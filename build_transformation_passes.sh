#!/usr/bin/env bash
set -euo pipefail
JOBS="${JOBS:-40}"
# Path to your llvm-project checkout (override by env if needed)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLVM_ROOT="$ROOT_DIR/llvm-project"
LLVM_20_build_ART="$ROOT_DIR/build"
LLVM_20_install_ART="$ROOT_DIR/install"
CMAKE_FILE="$LLVM_ROOT/llvm/lib/Transforms/CMakeLists.txt"


cp -r PrintArgsPass $LLVM_ROOT/llvm/lib/Transforms
cp -r FuncSpecPassIRSwitchCaseV3 $LLVM_ROOT/llvm/lib/Transforms

[[ -f "$CMAKE_FILE" ]] || { echo "ERROR: not found: $CMAKE_FILE"; exit 1; }

add_line_if_missing() {
  local line="$1"
  local file="$2"

  if grep -Fqx "$line" "$file"; then
    echo "[=] Already present: $line"
  else
    echo "[+] Adding: $line"
    printf "\n%s\n" "$line" >> "$file"
  fi
}

add_line_if_missing 'add_subdirectory(PrintArgsPass)' "$CMAKE_FILE"
add_line_if_missing 'add_subdirectory(FuncSpecPassIRSwitchCaseV3)' "$CMAKE_FILE"

echo "[OK] Updated: $CMAKE_FILE"


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

