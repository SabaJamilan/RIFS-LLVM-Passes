# Source this to enable wllvm:
export WLLVM_DIR="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/whole-program-llvm"
export WLLVM_VENV="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/venv_wllvm"
export PATH="$WLLVM_VENV/bin:$PATH"

# wllvm uses clang underneath. Recommended settings:
# - LLVM_COMPILER is usually set to 'clang' (not an absolute path). :contentReference[oaicite:1]{index=1}
export LLVM_COMPILER=clang

# Make sure wllvm can find the LLVM tools (clang, llvm-link, etc.)
# If you built LLVM with your script, this should exist:
if [ -d "/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact/install/bin" ]; then
  export LLVM_COMPILER_PATH="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact/install/bin"
  export PATH="$LLVM_COMPILER_PATH:$PATH"
fi

# Convenience: use wllvm wrappers as compilers
export CC=wllvm
export CXX=wllvm++
