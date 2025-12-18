#!/usr/bin/env bash
set -euo pipefail

# Run from your artifact root (or anywhere; it installs relative to this script)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WLLVM_REPO="${WLLVM_REPO:-https://github.com/travitch/whole-program-llvm.git}"
WLLVM_REF="${WLLVM_REF:-master}"

WLLVM_DIR="${WLLVM_DIR:-$ROOT_DIR/whole-program-llvm}"
WLLVM_VENV="${WLLVM_VENV:-$ROOT_DIR/venv_wllvm}"

# If you already built LLVM and generated env_llvm20.sh, this is useful:
LLVM_20_install="${LLVM_20_install_ART:-$ROOT_DIR/install}"

echo "[+] ROOT_DIR       = $ROOT_DIR"
echo "[+] WLLVM_REPO     = $WLLVM_REPO"
echo "[+] WLLVM_REF      = $WLLVM_REF"
echo "[+] WLLVM_DIR      = $WLLVM_DIR"
echo "[+] WLLVM_VENV     = $WLLVM_VENV"
echo "[+] LLVM_20_install_ART= $LLVM_20_install_ART"
echo

# --- deps checks ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'"; exit 1; }; }
need git
need python3

# --- clone/update repo ---
if [[ ! -d "$WLLVM_DIR/.git" ]]; then
  echo "[+] Cloning whole-program-llvm..."
  git clone "$WLLVM_REPO" "$WLLVM_DIR"
else
  echo "[+] Updating existing repo..."
  git -C "$WLLVM_DIR" fetch --all --tags
fi

echo "[+] Checking out $WLLVM_REF"
git -C "$WLLVM_DIR" checkout "$WLLVM_REF"

# --- venv + install ---
echo "[+] Creating venv: $WLLVM_VENV"
python3 -m venv "$WLLVM_VENV"

echo "[+] Installing wllvm (editable) into venv..."
"$WLLVM_VENV/bin/python" -m pip install --upgrade pip
"$WLLVM_VENV/bin/python" -m pip install -e "$WLLVM_DIR"

# --- verify tools exist ---
echo "[+] Verifying wllvm tools..."
"$WLLVM_VENV/bin/wllvm" --help >/dev/null
"$WLLVM_VENV/bin/extract-bc" --help >/dev/null

# --- write env file ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/env_wllvm.sh"
#ENV_FILE="$ROOT_DIR/env_wllvm.sh"
cat > "$ENV_FILE" <<EOF
# Source this to enable wllvm:
export WLLVM_DIR="$WLLVM_DIR"
export WLLVM_VENV="$WLLVM_VENV"
export PATH="\$WLLVM_VENV/bin:\$PATH"

# wllvm uses clang underneath. Recommended settings:
# - LLVM_COMPILER is usually set to 'clang' (not an absolute path). :contentReference[oaicite:1]{index=1}
export LLVM_COMPILER=clang

# Make sure wllvm can find the LLVM tools (clang, llvm-link, etc.)
# If you built LLVM with your script, this should exist:
if [ -d "$LLVM_20_install_ART/bin" ]; then
  export LLVM_COMPILER_PATH="$LLVM_20_install_ART/bin"
  export PATH="\$LLVM_COMPILER_PATH:\$PATH"
fi

# Convenience: use wllvm wrappers as compilers
export CC=wllvm
export CXX=wllvm++
EOF

echo "[+] Installed wllvm into: $WLLVM_VENV"
echo "[+] Wrote: $ENV_FILE"
echo "    Activate with: source \"$ENV_FILE\""
echo
echo "[+] Quick sanity check:"
echo "    source \"$ENV_FILE\" && wllvm --help && extract-bc --help"
