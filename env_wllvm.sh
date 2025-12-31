# ---- wllvm / venv locations ----
export WLLVM_DIR="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/whole-program-llvm"
export WLLVM_VENV="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/venv_wllvm"
export PATH="$WLLVM_VENV/bin:$PATH"

# ---- LLVM install prefix (MUST be the *install* tree, not build) ----
: "${LLVM_20_install_ART:=/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact/install}"
LLVM_BIN="$LLVM_20_install_ART/bin"

# Fail early if clang is missing
if [[ ! -x "$LLVM_BIN/clang" ]]; then
  echo "[ERROR] clang not found at: $LLVM_BIN/clang"
  echo "[HINT] Ensure LLVM_20_install_ART points to your LLVM install prefix."
  return 1 2>/dev/null || exit 1
fi

# Some installs may not provide clang++ as a separate file (rare). Ensure it exists.
if [[ ! -x "$LLVM_BIN/clang++" ]]; then
  ln -sf "$LLVM_BIN/clang" "$LLVM_BIN/clang++"
fi

# Put the installed LLVM tools first on PATH
export PATH="$LLVM_BIN:$PATH"
hash -r

# ---- Tell wllvm to use this LLVM/Clang toolchain ----
export LLVM_COMPILER=clang
export LLVM_COMPILER_PATH="$LLVM_BIN"

# Optional but helps many Makefiles/toolchains pick LLVM utilities consistently:
export AR="$LLVM_BIN/llvm-ar"
export RANLIB="$LLVM_BIN/llvm-ranlib"
export NM="$LLVM_BIN/llvm-nm"
export STRIP="$LLVM_BIN/llvm-strip"
export LD="$LLVM_BIN/ld.lld"

# ---- Use wllvm wrappers as compilers (recommended) ----
export CC=wllvm
export CXX=wllvm++

# ---- Sanity prints (optional) ----
echo "[INFO] Using LLVM_BIN=$LLVM_BIN"
echo "[INFO] wllvm=$(command -v wllvm || echo MISSING)"
echo "[INFO] wllvm++=$(command -v wllvm++ || echo MISSING)"
echo "[INFO] clang=$(command -v clang)"
echo "[INFO] clang resource dir: $("$LLVM_BIN/clang" --print-resource-dir)"
