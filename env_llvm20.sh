# Source this to use LLVM 20 built in this folder:
export LLVM_ROOT_ART="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact-codes/llvm-project"
export LLVM_20_build_ART="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact-codes/build"
export LLVM_20_install_ART="/soe/sjamilan/LLVM16-vp/llvm-project/my-llvm-tutorial/rifs-sum/test-costModel/rifs-artifact-codes/install"
export PATH="$LLVM_20_install_ART/bin:$PATH"
export LD_LIBRARY_PATH_ART="$LLVM_20_install_ART/lib:${LD_LIBRARY_PATH_ART:-}"
