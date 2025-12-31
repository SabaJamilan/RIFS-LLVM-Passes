#!/usr/bin/env bash
set -euo pipefail

LLVM_REPO="${LLVM_REPO:-https://github.com/llvm/llvm-project.git}"
LLVM_REF="${LLVM_REF:-release/20.x}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "ROOT_DIR: " $ROOT_DIR
LLVM_ROOT_ART="$ROOT_DIR/llvm-project"
LLVM_20_build_ART="$ROOT_DIR/build"
LLVM_20_install_ART="$ROOT_DIR/install"

JOBS="${JOBS:-40}"

echo "[+] ROOT_DIR        = $ROOT_DIR"
echo "[+] LLVM_REPO       = $LLVM_REPO"
echo "[+] LLVM_REF        = $LLVM_REF"
echo "[+] LLVM_ROOT_ART       = $LLVM_ROOT_ART"
echo "[+] LLVM_20_build_ART   = $LLVM_20_build_ART"
echo "[+] LLVM_20_install_ART = $LLVM_20_install_ART"
echo "[+] JOBS            = $JOBS"
echo

# ---- dependency checks ----
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing ''$1'' in PATH"; exit 1; }; }
need git
need cmake
need ninja
need python3

# ---- Clone LLVM if needed ----
if [[ ! -d "$LLVM_ROOT_ART/.git" ]]; then
  echo "[+] Cloning llvm-project..."
  git clone "$LLVM_REPO" "$LLVM_ROOT_ART"
else
  echo "[+] llvm-project already exists. Reusing: $LLVM_ROOT_ART"
fi

cd "$LLVM_ROOT_ART"
echo "[+] Fetching refs..."
git fetch --all --tags

echo "[+] Checking out: $LLVM_REF"
git checkout "$LLVM_REF"

cmake -S "$LLVM_ROOT_ART/llvm" -B "$LLVM_20_build_ART" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_20_install_ART" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
  -DCOMPILER_RT_BUILD_PROFILE=ON
ninja -C "$LLVM_20_build_ART" compiler-rt
ninja -C "$LLVM_20_build_ART" install
RES="$("$LLVM_20_install_ART/bin/clang" --print-resource-dir)"
ls -lah "$RES/lib/x86_64-unknown-linux-gnu" | grep -i profile || true
find "$RES" -name 'libclang_rt.profile.a' -o -name 'libclang_rt.profile*.a'




echo
echo "[+] LLVM build complete."
"$LLVM_20_install_ART/bin/clang" --version

# ---- Write an env file  ----
ENV_FILE="$ROOT_DIR/env_llvm20.sh"
cat > "$ENV_FILE" <<EOF
# Source this to use LLVM 20 built in this folder:
export LLVM_ROOT_ART="$LLVM_ROOT_ART"
export LLVM_20_build_ART="$LLVM_20_build_ART"
export LLVM_20_install_ART="$LLVM_20_install_ART"
export PATH="\$LLVM_20_install_ART/bin:\$PATH"
export LD_LIBRARY_PATH_ART="\$LLVM_20_install_ART/lib:\${LD_LIBRARY_PATH_ART:-}"
EOF
cd $ROOT_DIR
chmod +x env_llvm20.sh
echo "[+] Wrote: $ENV_FILE"
echo "    Activate with:  source \"$ENV_FILE\""
