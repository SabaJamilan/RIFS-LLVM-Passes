echo ""

echo "(1) ---- build LLVM 20 ----"
./build_llvm20.sh
echo ""

echo "(2) ---- set paths ----"
source ./env_llvm20.sh
echo "LLVM 20 path: " $LLVM_20_build_ART
echo ""
echo "      ---- clang + opt (version) ----"
echo ""
echo "           clang version: " $LLVM_20_build_ART
$LLVM_20_build_ART/bin/clang --version
echo ""
echo "      ---- opt version -----"
$LLVM_20_build_ART/bin/opt --version

echo ""

echo "(3) ---- download the applications ---"
./fetch_benchmarks.sh

echo ""
echo "(4) ---- download and install wllvm ---"
chmod +x env_wllvm.sh
./env_wllvm.sh


echo ""
echo "(5) ---- run PIN tools to do value profiling on all data types (int/float/pointer) ---"
./get_pin_3.31.sh
source ~/tools/env_pin.sh
./install_gdb.sh
./profile_with_pin_steps.sh swaptions 60

echo ""
echo "(6) ---- build LLVM passes for Value Profiling and Function Specialization ---"
./build_transformation_passes.sh

echo ""
echo "(7) ---- Perform Value Profiling and Function Specialization ---"
./do_specialization_run_cost_model.sh swaptions 60 1000 5
