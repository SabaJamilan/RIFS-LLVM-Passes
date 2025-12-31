#!/usr/bin/env bash
#set -euo pipefail
IFS=$'\n\t'
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ---- Where this script lives (absolute, no symlinks issues) ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
echo "SCRIPT_DIR: " $SCRIPT_DIR
# ---- Args ----
app="${1:?usage: $0 <app> <cores>}"
cores=${2:-}
NumberOfFiles=${3:-}
MAX_SIZE=${4:-}


BENCH_ROOT="$ROOT_DIR/benchmarks"
python_codes="$ROOT_DIR/python-codes"
cpp_files="$ROOT_DIR/cpp_files"
raw_MakeFile_dir="$ROOT_DIR/raw_MakeFile_dir"

# Require install prefix (preferred)
: "${LLVM_20_install_ART:?env LLVM_20_install_ART must point to your LLVM install prefix}"
TOOLBIN="$LLVM_20_install_ART/bin"

# Optionally keep these for compatibility
export LLVM_20_build="${LLVM_20_install_ART}"
export LLVM_20_build_ART="${LLVM_20_install_ART}"

CLANG="$TOOLBIN/clang"
CLANGXX="$TOOLBIN/clang++"
OPT="$TOOLBIN/opt"
LLD="$TOOLBIN/ld.lld"
LLDIS="$TOOLBIN/llvm-dis"
LLVMDIS="$TOOLBIN/llvm-dis"
LLVMPROFDATA="$TOOLBIN/llvm-profdata"
LLVMCONFIG="$TOOLBIN/llvm-config"

# Sanity checks (fail early)
[[ -x "$CLANG" ]] || { echo "[ERROR] Missing clang at $CLANG"; exit 1; }
[[ -x "$CLANGXX" ]] || { echo "[ERROR] Missing clang++ at $CLANGXX"; exit 1; }

echo "[INFO] Using clang:  $CLANG"
echo "[INFO] Resource dir: $("$CLANG" --print-resource-dir)"


RES="$("$LLVM_20_install_ART/bin/clang" --print-resource-dir)"
echo "RES=$RES"

find "$RES" -name 'libclang_rt.profile.a' -o -name 'libclang_rt.profile*.a'
PID=$$
echo "==============================="
echo "PID: $PID"
echo "==============================="

main_path="$(pwd)"
# ---- Output dirs ----
DIRECTORY="${app}-${PID}"
mkdir -p "$DIRECTORY"

SPEC_DIRECTORY="spec2017-build-benchs"
mkdir -p "$SPEC_DIRECTORY"
#all_benchmarks_dir_path="$main_path/$SPEC_DIRECTORY"

# ---- Frontend flags ----
# Use arrays with one flag per element (NO big quoted strings)
SPEC_DEBUG_FLAGS_O3=( "-O3 -gline-tables-only -fdebug-info-for-profiling -fno-discard-value-names -no-pie")
DEBUG_CFLAGS_O3=(
  -O3
  -gline-tables-only
  -fdebug-info-for-profiling
  -fno-discard-value-names
  -no-pie
)
# ---- SPEC 505.mcf_r (C) example wiring ----
is_spec_bench=0

if [[ "$app" == "mcf_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="505"
  dirname="505.mcf_r"
  compiler="clang++"  # C benchmark → use clang
  compileFlags1=(-std=c99 -m64 -DSPEC -DNDEBUG
                 -I"$benchmark_path/benchspec/CPU/505.mcf_r/src/spec_qsort"
                 -DSPEC_AUTO_SUPPRESS_OPENMP -march=native
                 -fno-unsafe-math-optimizations -fcommon
                 -Xclang -fopenmp -DSPEC_OPENMP -fno-strict-aliasing
                 -fgnu89-inline -DSPEC_LP64)
  compileFlags2=(-std=c99 -m64 -march=native -fno-unsafe-math-optimizations
                 -fcommon -Xclang -fopenmp -DSPEC_OPENMP -fno-strict-aliasing
                 -fgnu89-inline)
  compileFlags3=(-lm)
  INPUTS="inp.in"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "perlbench_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="500"
  dirname="500.perlbench_r"
  compiler="clang++"  # C benchmark → use clang
  compileFlags1=(-std=c99   -m64  -DSPEC -DNDEBUG -DPERL_CORE -I"cpu2017/benchspec/CPU/500.perlbench_r/src" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/dist/IO" -I"cpan/Time-HiRes" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/cpan/HTML-Parser" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/ext/re" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/specrand" -DDOUBLE_SLASHES_SPECIAL=0 -DSPEC_AUTO_SUPPRESS_OPENMP -D_LARGE_FILES -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64  -march=native -fno-unsafe-math-optimizations  -fcommon        -DSPEC_LINUX_X64    -fno-strict-aliasing -fgnu89-inline   -DSPEC_LP64 -Wno-implicit-function-declaration)
  compileFlags2=(-std=c99   -m64 -march=native -fno-unsafe-math-optimizations -no-pie -fcommon     -DSPEC_LINUX_X64    -fno-strict-aliasing -fgnu89-inline)
  compileFlags3=(-lm)
  INPUTS="-Ilib diffmail.pl 4 800 10 17 19 300"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "deepsjeng_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="531"
  dirname="531.deepsjeng_r"
  compiler="clang++"
  compileFlags1=(-std=c++03 -m64 -DSPEC -DNDEBUG -DSMALL_MEMORY -DSPEC_AUTO_SUPPRESS_OPENMP  -march=native -fno-unsafe-math-optimizations  -fcommon  -DSPEC_LP64)
  compileFlags2=(-std=c++03 -m64 -march=native -fno-unsafe-math-optimizations -fcommon)
  compileFlags3=()
  INPUTS="train.txt"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
fi
if [[ "$app" == "imagick_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="538"
  dirname="538.imagick_r"
  compiler="clang++"
  compileFlags1=(-std=c99   -m64 -DSPEC -DNDEBUG -I"cpu2017/benchspec/CPU/538.imagick_r/src" -DSPEC_AUTO_SUPPRESS_OPENMP  -march=native -fno-unsafe-math-optimizations  -fcommon  -DSPEC_LP64)
  compileFlags2=(-std=c99   -m64 -march=native -fno-unsafe-math-optimizations -fcommon )
  compileFlags3=(-lm)
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  inputName="train_input.tga"
  INPUTS="-limit disk 0 train_input.tga -resize 320x240 -shear 31 -edge 140 -negate -flop -resize 900x900 -edge 10 train_output.tga"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "x264_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="525"
  dirname="525.x264_r"
  compiler="clang++"
  compileFlags1=(-std=c99   -m64  -DSPEC -DNDEBUG -Icpu2017/benchspec/CPU/525.x264_r/src/ldecod_src/inc -Icpu2017/benchspec/CPU/525.x264_r/src/x264_src -Icpu2017/benchspec/CPU/525.x264_r/src/x264_src/extras -Icpu2017/benchspec/CPU/525.x264_r/src/x264_src/common -DSPEC_AUTO_SUPPRESS_OPENMP -DSPEC_AUTO_BYTEORDER=0x12345678  -march=native -fno-unsafe-math-optimizations -fcommon            -fno-strict-aliasing -fgnu89-inline   -DSPEC_LP64)
  compileFlags2=(-std=c99   -m64   -march=native -fno-unsafe-math-optimizations -no-pie -fcommon         -fno-strict-aliasing -fgnu89-inline)
  compileFlags3=(-lm)
  INPUTS=(--dumpyuv 50 --frames 142 -o BuckBunny_New.264 BuckBunny.yuv 1280x720)
  INPUTS_Perf="--dumpyuv 50 --frames 142 -o BuckBunny_New.264 BuckBunny.yuv 1280x720"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
  inputName="BuckBunny.yuv"
fi

if [[ "$app" == "xz_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="557"
  dirname="557.xz_r"
  compiler="clang++"
  compileFlags1=(-std=c99   -m64  -DSPEC -DNDEBUG -DSPEC_AUTO_BYTEORDER=0x12345678 -DHAVE_CONFIG_H=1 -DSPEC_MEM_IO -DSPEC_XZ -DSPEC_AUTO_SUPPRESS_OPENMP -Icpu2017/benchspec/CPU/557.xz_r/src -Icpu2017/benchspec/CPU/557.xz_r/src/spec_mem_io -Isha-2 -Icpu2017/benchspec/CPU/557.xz_r/src/common -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/api -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/lzma -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/common -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/check -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/simple -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/delta -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/lz -Icpu2017/benchspec/CPU/557.xz_r/src/liblzma/rangecoder -march=native -fno-unsafe-math-optimizations  -fcommon            -fno-strict-aliasing -fgnu89-inline   -DSPEC_LP64)
  compileFlags2=(-std=c99   -m64  -march=native -fno-unsafe-math-optimizations -fcommon -fno-strict-aliasing -fgnu89-inline)
  compileFlags3=()
  INPUTS=(input.combined.xz 40 a841f68f38572a49d86226b7ff5baeb31bd19dc637a922a972b2e6d1257a890f6a544ecab967c313e370478c74f760eb229d4eef8a8d2836d233d3e9dd1430bf 6356684 -1 8)
  INPUTS_Perf="input.combined.xz 40 a841f68f38572a49d86226b7ff5baeb31bd19dc637a922a972b2e6d1257a890f6a544ecab967c313e370478c74f760eb229d4eef8a8d2836d233d3e9dd1430bf 6356684 -1 8"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
  inputName="input.combined.xz"
fi

if [[ "$app" == "cpugcc_r_base.mytest-m64" ]]; then
  benchmark_path="$BENCH_ROOT/cpu2017"
  SPECid="502"
  dirname="502.gcc_r"
  compiler="clang++"
  compileFlags1=( -std=c99  -m64  -DSPEC -DNDEBUG -Icpu2017/benchspec/CPU/502.gcc_r/src -Icpu2017/benchspec/CPU/502.gcc_r/src/include -Icpu2017/benchspec/CPU/502.gcc_r/src/spec_qsort -DSPEC_502 -DSPEC_AUTO_SUPPRESS_OPENMP -DIN_GCC -DHAVE_CONFIG_H  -march=native -fno-unsafe-math-optimizations  -fcommon  -fno-strict-aliasing -fgnu89-inline   -DSPEC_LP64 )
  compileFlags2=(-std=c99   -m64  -march=native -fno-unsafe-math-optimizations -fcommon         -fno-strict-aliasing -fgnu89-inline )
  compileFlags3=(-lm)

  INPUTS=(200.c -O3 -finline-limit=50000 -o 200.opts-O3_-finline-limit_50000.s)
  INPUTS_Perf="200.c -O3 -finline-limit=50000 -o 200.opts-O3_-finline-limit_50000.s"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  inputName="200.c"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "swaptions" ]]; then
  is_spec_bench=0
  compilerType="c++"
  benchmark_path="$BENCH_ROOT/parsec-3.0/pkgs/apps/swaptions/src"
  SPECid="swaptions"
  dirname="non-spec"
  compiler="clang++"
  compileFlags1=(-Wno-register)
  compileFlags2=(-Wno-register)
  compileFlags3=()
  INPUTS=(-ns 20 -sm 800000 -nt 1 -sd 1000)
  INPUTS_Perf="-ns 20 -sm 800000 -nt 1 -sd 1000"
  input_path=""
  inputName=""
fi

if [[ "$app" == "freqmine" ]]; then
  is_spec_bench=0
  compilerType="c++"
  benchmark_path="$BENCH_ROOT/parsec-3.0/pkgs/apps/freqmine/src"
  SPECid="freqmine"
  dirname="cortex"
  compiler="clang++"
  compileFlags1=(-Wno-deprecated -Wno-register)
  compileFlags2=(-Wno-deprecated -Wno-register)
  compileFlags3=()
  INPUTS=($benchmark_path/kosarak_990k_2times_x.dat 790)
  INPUTS_Perf="$benchmark_path/kosarak_990k_2times_x.dat 790"
  input_path="$benchmark_path"
  inputName="kosarak_990k_2times_x.dat"
fi

if [[ "$app" == "spc-large" ]]; then
  benchmark_path="benchmarks/cortexsuite/cortex/clustering/spectral"
  is_spec_bench=0
  compilerType="c++"
  SPECid="spc-large"
  dirname="cortex"
  compiler="clang++"
  compileFlags1=(-Wno-implicit-function-declaration -Ibenchmarks/cortexsuite/cortex/clustering/spectral/includes -Ibenchmarks/cortexsuite/cortex/clustering/spectral )
  compileFlags2=(-Wno-implicit-function-declaration -Ibenchmarks/cortexsuite/cortex/clustering/spectral/includes -Ibenchmarks/cortexsuite/cortex/clustering/spectral )
  compileFlags3=(-lm)
  INPUTS=(benchmarks/cortexsuite/cortex/clustering/datasets/D31 2000 2 16 0.707 1)
  INPUTS_Perf="benchmarks/cortexsuite/cortex/clustering/datasets/D31 2000 2 16 0.707 1"
  input_path=""
  inputName=""
fi

if [[ "$app" == "me-large" ]]; then
  benchmark_path="benchmarks/cortexsuite/cortex/motion-estimation"
  is_spec_bench=0
  compilerType="c++"
  compiler="clang++"
  SPECid="me-large"
  dirname="cortex"
  compileFlags1=(-Ibenchmarks/cortexsuite/cortex/motion-estimation/includes -Ibenchmarks/cortexsuite/motion-estimation -DBOOKCASE)
  compileFlags2=(-Ibenchmarks/cortexsuite/cortex/motion-estimation/includes -Ibenchmarks/cortexsuite/motion-estimation -DBOOKCASE)
  compileFlags3=(-lm)
  INPUTS=()
  INPUTS_Perf=""
  input_path=""
fi
if [[ "$app" == "sphinx-large" ]]; then
  benchmark_path="benchmarks/cortexsuite/cortex/sphinx"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="sphinx-large"
  dirname="cortex"
  compileFlags1=(-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Ibenchmarks/cortexsuite/cortex/sphinx/includes)
  compileFlags2=(-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Ibenchmarks/cortexsuite/cortex/sphinx/includes)
  compileFlags3=(-lm)
  INPUTS=(benchmarks/cortexsuite/cortex/sphinx/large/audio.raw benchmarks/cortexsuite/cortex/sphinx/language_model/HUB4/)
  INPUTS_Perf="benchmarks/cortexsuite/cortex/sphinx/large/audio.raw benchmarks/cortexsuite/cortex/sphinx/language_model/HUB4/"
  input_path=""
  inputName=""
fi

if [[ "$app" == "kmeans" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="kmeans"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(-i kdd_cup_synth.txt)
  INPUTS_Perf="-i kdd_cup_synth.txt"
  input_path="$benchmark_path"
  inputName=""
fi



if [[ "$app" == "euler3d_cpu" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/cfd"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="kmeans"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(fvcorr.domn.097K)
  INPUTS_Perf="fvcorr.domn.097K"
  input_path="$benchmark_path"
  inputName=""
fi


if [[ "$app" == "pathfinder" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/pathfinder"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="kmeans"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(400000 400)
  INPUTS_Perf="400000 400"
  input_path="$benchmark_path"
  inputName=""
fi


if [[ "$app" == "hotspot" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/hotspot"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="hotspot"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(1024 1024 20000 1 temp_1024 power_1024 output.out)
  INPUTS_Perf="1024 1024 20000 1 temp_1024 power_1024 output.out"
  input_path="$benchmark_path"
  inputName=""
fi

if [[ "$app" == "hotspot3D" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/hotspot3D"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="hotspot3D"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(512 8 800 power_512x8 temp_512x8 output.out)
  INPUTS_Perf="512 8 800 power_512x8 temp_512x8 output.out"
  input_path="$benchmark_path"
  inputName=""
fi

if [[ "$app" == "srr-medium" ]]; then
  benchmark_path="benchmarks/cortexsuite/cortex/srr"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="srr-medium"
  dirname="cortex"
  compileFlags1=(-Ibenchmarks/cortexsuite/cortex/srr/includes -Ibenchmarks/cortexsuite/cortex/srr -DBOOKCASE)
  compileFlags2=(-Ibenchmarks/cortexsuite/cortex/srr/includes -Ibenchmarks/cortexsuite/cortex/srr -DBOOKCASE)
  compileFlags3=(-lm)
  INPUTS=()
  INPUTS_Perf=""
  input_path="$benchmark_path"
  inputName=""
fi


if [[ "$app" == "bfs" ]]; then
  benchmark_path="benchmarks/rodinia_3.1/openmp/bfs"
  compiler="clang++"
  compilerType="c++"
  is_spec_bench=0
  SPECid="bfs"
  dirname="cortex"
  compileFlags1=()
  compileFlags2=()
  compileFlags3=()
  INPUTS=(4 graph4K_deg8.txt)
  INPUTS_Perf="4 graph4K_deg8.txt"
  input_path="$benchmark_path"
  inputName=""
fi

die() { echo "error: $*" >&2; exit 2; }

have_file() { [[ -f "$1" ]]; }

# Decide clang front-end by language:
pick_clang() {
  # $1: expected language ("c" or "c++")
  case "$1" in
    c)   echo "$CLANG"  ;;
    c++) echo "$CLANGXX";;
    *)   echo "$CLANG";;
  esac
}

# ---- Main SPEC function ----
NON_SPEC_benchmark_compile_With_O3_PGO() {
  local lang=$compilerType
  local CL=$(pick_clang "$lang")

  cd "$all_benchmarks_dir_path"
  mkdir -p "${SPECid}-train.${PID}"

  if [ $dirname = "non-spec" ]; then
    echo "########################## BASELINE -gline-tables-only ########################################"
    echo "1)   Generate baseline IR by using -gline-tables-only flag FOR CortexSuite ... "
    echo "###################################################################################"
    cd $benchmark_path
    cp $raw_MakeFile_dir/$app-Makefile-baseline-raw $benchmark_path/Makefile-baseline-raw
    python3 "$python_codes/config_changer_baseline.py" "${SPEC_DEBUG_FLAGS_O3[@]}" $benchmark_path/Makefile-baseline-raw $benchmark_path/Makefile
    make clean
    make
    input_path=`pwd`

    echo "[*] Extracting bitcode from: $app"
    extract-bc -l "$LLVM_20_build_ART/bin/llvm-link" "$app"
    have_file "${app}.bc" || die "failed to extract ${app}.bc"
    "$LLDIS" "${app}.bc" -o "${app}_baseline_O3.ll"
    SRC_LL="${app}_baseline_O3.ll"
    echo "SRC_LL: " $SRC_LL
    cp "$SRC_LL" $main_path/$DIRECTORY

    if [[ -n "${inputName:-}" ]] && [[ -e "$input_path/$inputName" ]]; then
      mkdir -p "$main_path/$DIRECTORY"
      cp --update=none -- "$input_path/$inputName" "$main_path/$DIRECTORY/"
    fi
    
    cd $main_path/$DIRECTORY

    # 1) Instrument the IR at IR level
    "$OPT" -passes='pgo-instr-gen' "$SRC_LL" -o "${app}_baseline_O3_gen_opt.ll"

    if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
    fi
    if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
    fi
    if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
    fi
    if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
    fi
 
    if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
    fi
    if [ "${app}" = 'bfs' ]; then
      cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
    fi

    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-generate "${app}_baseline_O3_gen_opt.ll" \
      -o "${app}_baseline_O3_gen_opt"

    echo "[*] Running instrumented binary to collect profile…"
    echo " Put profiles in a dedicated dir and use a unique pattern to avoid mixing old runs."

    profdir="${PWD}/profraw.${app}.$$"

    mkdir -p "$profdir"
    export LLVM_PROFILE_FILE="${profdir}/pgo-%p-%m.profraw"
    echo "run ..."
    ./${app}"_baseline_O3_gen_opt" ${INPUTS[@]}

    echo "done"
    echo "[*] Merging *.profraw → pgo_ir_profile.profdata"
    shopt -s nullglob
    raws=( "$profdir"/*.profraw )
    shopt -u nullglob
    if (( ${#raws[@]} == 0 )); then
      echo "error: no .profraw files produced (did the run execute & hit code?)" >&2
    fi
    "$LLVMPROFDATA" merge -o pgo_ir_profile.profdata "${raws[@]}"


    have_file pgo_ir_profile.profdata || die "failed to create pgo_ir_profile.profdata"
    echo ""
    
    if [[ ! -s pgo_ir_profile.profdata ]]; then
      echo "error: failed to create non-empty pgo_ir_profile.profdata" >&2
    fi

    "$OPT" -S -passes='pgo-instr-use' \
      -pgo-test-profile-file=pgo_ir_profile.profdata \
      "$SRC_LL" -o "${app}_baseline_O3_PGO.ll"

    echo "Generate binary for O3 and O3+PGO ... "
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-use=pgo_ir_profile.profdata "${app}_baseline_O3_PGO.ll" -c
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-use=pgo_ir_profile.profdata "${app}_baseline_O3_PGO.o" -o "${app}_baseline_O3_PGO" "${compileFlags3[@]}"
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" "${app}_baseline_O3.ll" -c
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" "${app}_baseline_O3.o" -o "${app}_baseline_O3" "${compileFlags3[@]}"

  fi
}

SPEC2017_benchmark_compile_With_O3_PGO() {
  local lang=$compilerType     # 505.mcf_r is C; adjust if needed
  local CL=$(pick_clang "$lang")

  cd "$all_benchmarks_dir_path"
  mkdir -p "${SPECid}-train.${PID}"

  # Load SPEC env
  cd "$benchmark_path"
  # shellcheck disable=SC1091
  source shrc
  cd "$benchmark_path/config"

  # Generate config (your helper adjusts config flags)
  rm -f wllvm-spec2017.cfg
  python3 "$python_codes/config_changer_baseline.py" \
      "${SPEC_DEBUG_FLAGS_O3[@]}" "$benchmark_path/config/wllvm-spec2017-raw.cfg" \
      "$benchmark_path/config/wllvm-spec2017.cfg"

  # Build & run train (baseline O3 with wllvm)
  cd "$benchmark_path/benchspec/CPU"
  runcpu --configfile "$benchmark_path/config/wllvm-spec2017.cfg" \
         --tune base --action run --size train \
         --output_root "$all_benchmarks_dir_path/${SPECid}-train.${PID}/baseline-gline" \
         "$SPECid"
  cp "$benchmark_path/config/wllvm-spec2017.cfg" \
     "$all_benchmarks_dir_path/${SPECid}-train.${PID}/baseline-gline"

  # Enter the run dir
  cd $all_benchmarks_dir_path/$SPECid"-train."$PID/"baseline-gline"/benchspec/CPU/$dirname/run/run_base_train_mytest-m64.0000
  #run_dir="$(pwd)"

  # Extract IR from baseline app (wllvm)
  if ! command -v extract-bc >/dev/null 2>&1; then
    die "extract-bc not found in PATH"
  fi

  echo "[*] Extracting bitcode from: $app"
  extract-bc -l "$LLVM_20_build_ART/bin/llvm-link" "$app"
  have_file "${app}.bc" || die "failed to extract ${app}.bc"
  "$LLDIS" "${app}.bc" -o "${app}_baseline_O3.ll"
  SRC_LL="${app}_baseline_O3.ll"

  cp "$SRC_LL" $main_path/$DIRECTORY
  cp $INPUTS $main_path/$DIRECTORY
  cp $input_path/$INPUTS $main_path/$DIRECTORY
  cd $main_path/$DIRECTORY

  if [ "${app}" = 'perlbench_r_base.mytest-m64' ]; then
    echo "yes app is perl!"
    cp $input_path/diffmail.pl .
    cp -r $input_path/lib .
  fi

  if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
  fi 
  if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  fi
   
  if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
  fi
  if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
  fi
 
  if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
  fi
  if [ "${app}" = 'bfs' ]; then
    cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
  fi


  if [ "${app}" = 'mcf_r_base.mytest-m64' ]; then
    echo "yes app is mcf!"
    cp $input_path/$INPUTS .
  fi

  if [ "${app}" = 'deepsjeng_r_base.mytest-m64' ]; then
    echo "yes app is deep!"
    cp $input_path/$INPUTS .
  fi
  if [ "${app}" = 'imagick_r_base.mytest-m64' ]; then
    echo "yes app is imagick!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi
  
  if [ "${app}" = 'cpugcc_r_base.mytest-m64' ]; then
    echo "yes app is gcc!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi

  if [ "${app}" = 'x264_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'xz_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi



  # 1) Instrument the IR at IR level
  "$OPT" -passes='pgo-instr-gen' "$SRC_LL" -o "${app}_baseline_O3_gen_opt.ll"

  # 2) Build + link the instrumented IR. Use -fprofile-instr-generate at LINK
  #  (just to pull in the runtime library).

  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-generate "${app}_baseline_O3_gen_opt.ll" \
    -o "${app}_baseline_O3_gen_opt"

  echo "[*] Running instrumented binary to collect profile…"
  echo " Put profiles in a dedicated dir and use a unique pattern to avoid mixing old runs."
  profdir="${PWD}/profraw.${app}.$$"
  mkdir -p "$profdir"
  export LLVM_PROFILE_FILE="${profdir}/pgo-%p-%m.profraw"
  echo "run ..."
  #./${app}"_baseline_O3_gen_opt" $INPUTS
  ./${app}"_baseline_O3_gen_opt" ${INPUTS[@]}

  echo "done"
  # Merge profiles
  echo "[*] Merging *.profraw → pgo_ir_profile.profdata"
  shopt -s nullglob
  raws=( "$profdir"/*.profraw )
  shopt -u nullglob
  if (( ${#raws[@]} == 0 )); then
    echo "error: no .profraw files produced (did the run execute & hit code?)" >&2
  fi
  "$LLVMPROFDATA" merge -o pgo_ir_profile.profdata "${raws[@]}"

  have_file pgo_ir_profile.profdata || die "failed to create pgo_ir_profile.profdata"
  echo ""
  #list_profile_functions pgo_ir_profile.profdata funcs.txt summary.txt
  # Confirm the file exists and is non-empty
  if [[ ! -s pgo_ir_profile.profdata ]]; then
    echo "error: failed to create non-empty pgo_ir_profile.profdata" >&2
  fi

  # 5) Apply the profile to the ORIGINAL (uninstrumented) IR
  "$OPT" -S -passes='pgo-instr-use' \
  -pgo-test-profile-file=pgo_ir_profile.profdata \
  "$SRC_LL" -o "${app}_baseline_O3_PGO.ll"
: '
  echo ""
  echo "Check !prof insertion ... "
  grep -n ''!prof'' "${app}_baseline_O3_PGO.ll" | head
  echo ""
  echo "Check !branch_weights insertion ..."
  grep -n ''!"branch_weights"'' "${app}_baseline_O3_PGO.ll" | head
  echo ""
'
  echo "Generate binary for O3 and O3+PGO ... "
  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-use=pgo_ir_profile.profdata "${app}_baseline_O3_PGO.ll" -c
  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-use=pgo_ir_profile.profdata "${app}_baseline_O3_PGO.o" -o "${app}_baseline_O3_PGO" "${compileFlags3[@]}"
  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" "${app}_baseline_O3.ll" -c
  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" "${app}_baseline_O3.o" -o "${app}_baseline_O3" "${compileFlags3[@]}"


}


VALUE_PROFILE_AND_ATTACH_SO () {
  local BIN_TO_PROFILE="$1" IR_TO_PROFILE="$2" PGO_PROFILE_O3="$3"
  local lang=$compilerType
  local CL=$(pick_clang "$lang")
  echo "Capture Hot functions: "

  DIRECTORY_record="perfrecord-for-"$BIN_TO_PROFILE"-"$PID
  if [ ! -d "$DIRECTORY_record" ]; then
    mkdir $DIRECTORY_record
  fi
  if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
  fi
  if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  fi
  
  if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
  fi
  if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
  fi
 
  if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
  fi
  
  if [ "${app}" = 'bfs' ]; then
    cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
  fi


  if [ "${app}" = 'deepsjeng_r_base.mytest-m64' ]; then
    echo "yes app is deep!"
    cp $input_path/$INPUTS .
  fi

  if [ "${app}" = 'xz_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi
  if [ "${app}" = 'cpugcc_r_base.mytest-m64' ]; then
    echo "yes app is gcc!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'imagick_r_base.mytest-m64' ]; then
    echo "yes app is imagick!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
 
  fi

  if [ "${app}" = 'x264_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'perlbench_r_base.mytest-m64' ]; then
    cp $input_path/diffmail.pl .
    cp -r $input_path/lib .
  fi
  if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
  fi
  if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  fi
  
  if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
  fi
  if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
  fi
 
  if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
  fi
  
  if [ "${app}" = 'bfs' ]; then
    cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
  fi


  if [ "${app}" = 'mcf_r_base.mytest-m64' ]; then
    echo "yes app is mcf!"
    cp $input_path/$INPUTS .
  fi

  cur_path=`pwd`
  echo "cur_path: "  $cur_path

  echo ""
  echo "  1) run perf record ...."
  taskset -c 4 perf record -e cycles:u -- ./$BIN_TO_PROFILE ${INPUTS[@]}
  echo ""
  echo "  2) perf report --stdio ...."
  perf report --stdio > $BIN_TO_PROFILE"-perfReport.txt"
  echo ""
  echo "  3) Capture Functions that consume most of the cycles ..."
  python3 $python_codes/extract_perf_funcs.py $BIN_TO_PROFILE"-perfReport.txt" $BIN_TO_PROFILE $BIN_TO_PROFILE"-FuncPercentList.txt"
  echo ""
  echo "---------------------------------------------------------"
  echo "Capture the name of Hot functions: "
  python3 $python_codes/filterHotFuncs.py $BIN_TO_PROFILE"-FuncPercentList.txt" $BIN_TO_PROFILE"-HotFuncList.txt"
  mv perf.data $DIRECTORY_record
  mv $BIN_TO_PROFILE"-FuncPercentList.txt" $DIRECTORY_record
  mv $BIN_TO_PROFILE"-perfReport.txt" $DIRECTORY_record
  echo "---------------------------------------------------------"
  echo ""
  cur_path=`pwd`
  echo "cur_path: "  $cur_path
  if [ -f $BIN_TO_PROFILE"-HotFuncNamesToProfile.txt" ]; then
    echo "1) File: $BIN_TO_PROFILE-HotFuncNamesToProfile.txt exists!"
  else
    echo "File: $BIN_TO_PROFILE-HotFuncNamesToProfile.txt does not exist!"
    echo ""
    echo "---------------------------------------------------------"
    echo "1) Extract Hot function names and write them to the output file: $BIN_TO_PROFILE-HotFuncNamesToProfile.txt"
    echo "---------------------------------------------------------"
    awk ' { split($2, a, "("); print a[1] }' $BIN_TO_PROFILE"-HotFuncList.txt" > $BIN_TO_PROFILE"-HotFuncNamesToProfile.txt"
  fi
  
  echo ""
  echo "---------------------------------------------------------"
  echo "2) Start Value Profiling for Hot Functions in IR level .... "
  echo "---------------------------------------------------------"
  echo ""
  echo "  ---------------------------------------------------------"
  echo "  🔹 Compiling the external helper function..."
  echo "  ---------------------------------------------------------"
    "$CL" -std=c++20 -stdlib=libstdc++ -shared -fPIC -o external_prinArgVal.so $cpp_files/external_prinArgVal.cpp
  echo ""
  echo "  ---------------------------------------------------------"
  echo "  🔹 Compiling IR to creating executable..."
  echo "  ---------------------------------------------------------"
    "$OPT" -load-pass-plugin $LLVM_20_build_ART/lib/PrintArgsPass.so  -passes=print-args  --enable-value-profiling  -targetFunctionName=$BIN_TO_PROFILE"-HotFuncNamesToProfile.txt" -binaryName=$BIN_TO_PROFILE -S $IR_TO_PROFILE  -o $BIN_TO_PROFILE"-print-args.ll"
  echo "  ---------------------------------------------------------"
  echo "  🔹 Running LLVM Pass for Value Profiling on IR file..."
  echo "  ---------------------------------------------------------"
  echo "path before profiling : "
  pwd
  if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
  fi
  if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
  fi
 
  if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
  fi
  if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  fi
  
  if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
  fi 
  if [ "${app}" = 'bfs' ]; then
    cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
  fi


  if [ "${app}" = 'deepsjeng_r_base.mytest-m64' ]; then
    echo "yes app is deep!"
    cp $input_path/$INPUTS .
  fi
  if [ "${app}" = 'imagick_r_base.mytest-m64' ]; then
    echo "yes app is imagick!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
 
  fi
  if [ "${app}" = 'cpugcc_r_base.mytest-m64' ]; then
    echo "yes app is gcc!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'xz_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'x264_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
  fi


  if [ "${app}" = 'perlbench_r_base.mytest-m64' ]; then
    cp $input_path/diffmail.pl .
    cp -r $input_path/lib .
  fi

  if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
  fi
 
  if [ "${app}" = 'srr-medium' ]; then
      cp -r "benchmarks/cortexsuite/cortex/srr/"* .
  fi
  if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
  fi
 
  if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
  fi
  if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  fi
 
  if [ "${app}" = 'bfs' ]; then
    cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
  fi


  if [ "${app}" = 'mcf_r_base.mytest-m64' ]; then
    echo "yes app is mcf!"
    cp $input_path/$INPUTS .
  fi


  echo "path before profiling : "
  pwd
  read -r -a LLVM_FLAGS_ARR < <("$LLVM_20_build_ART/bin/llvm-config" --ldflags --system-libs --libs core)

  "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" "$BIN_TO_PROFILE"-print-args.ll ./external_prinArgVal.so -o $BIN_TO_PROFILE"-print-args"   "${LLVM_FLAGS_ARR[@]}"



  #./$BIN_TO_PROFILE"-print-args" $INPUTS
  ./$BIN_TO_PROFILE"-print-args" ${INPUTS[@]}
  echo "  ---------------------------------------------------------"
  echo "  🔹 Attach Value Profiles as a metadata ..."
  echo "  ---------------------------------------------------------"
  echo ""
  ATTACH_SO=LLVM20/llvm-project/build-bohr4/lib/AttachSpecKeys.so
  ATTACH_PASS=attach-spec-keys
  #NEXT="$BIN_TO_PROFILE"_00_baseline_AttachSpecKeys.ll

  VALUE_PROF="value_profile_"$BIN_TO_PROFILE".txt"

  in=$VALUE_PROF
  out="callees.txt"

  awk -F',' '
    BEGIN{ OFS="," }
    NR==1 { next }                       # skip header
    {
      callee=$3                          # 3rd column = Callee
      gsub(/^[ \t]+|[ \t]+$/, "", callee)  # trim spaces
      sub(/\r$/,"", callee)              # strip CR if file is CRLF
      if (callee != "" && !seen[callee]++) print callee
    }' "$in" > "$out"


  LIST_FILE="callees.txt"
  #echo " Read each line as a function name ... "
  while IFS= read -r name || [[ -n "$name" ]]; do
    name="${name%$'\r'}"
    # drop leading/trailing whitespace
    name="${name#"${name%%[![:space:]]*}"}"   # trim left
    name="${name%"${name##*[![:space:]]}"}"   # trim right
    # skip blanks and comments
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    # --- do something with "$name" ---
    python3 $python_codes/filter_profile_by_callee_exact.py $VALUE_PROF $name "func_"$name"_profiles.csv"
  done < "$LIST_FILE"

}

# ---- Entry ----
if [[ "${is_spec_bench}" == "1" ]]; then
#saba
  lang=$compilerType
  CL=$(pick_clang "$lang")
  cd "$main_path/$DIRECTORY"
  SPEC2017_benchmark_compile_With_O3_PGO
  echo
  echo "[OK] Outputs in: $main_path/$DIRECTORY"

  cd "$main_path/$DIRECTORY"
  CUR_O3=$app"_baseline_O3.ll"
  CUR_O3_BIN=$app"_baseline_O3"

  PGO_PROFILE="pgo_ir_profile.profdata"
  CUR_O3_PGO=$app"_baseline_O3_PGO.ll"
  CUR_O3_PGO_BIN=$app"_baseline_O3_PGO"
  echo ""

  echo "---- 1) Attach keys from your value profile ----"
  VALUE_PROFILE_AND_ATTACH_SO $CUR_O3_PGO_BIN $CUR_O3_PGO $PGO_PROFILE

else
  lang=$compilerType
  CL=$(pick_clang "$lang")
  cd "$main_path/$DIRECTORY"
  NON_SPEC_benchmark_compile_With_O3_PGO

  echo
  echo "[OK] Outputs in: $main_path/$DIRECTORY"
  cd "$main_path/$DIRECTORY"

  CUR_O3=$app"_baseline_O3.ll"
  CUR_O3_BIN=$app"_baseline_O3"

  PGO_PROFILE="pgo_ir_profile.profdata"
  CUR_O3_PGO=$app"_baseline_O3_PGO.ll"
  CUR_O3_PGO_BIN=$app"_baseline_O3_PGO"

  echo ""
  echo ""
  echo "---- 1) value profile with PIN Tool (-O3 + PGO)----"
  VALUE_PROFILE_AND_ATTACH_SO $CUR_O3_PGO_BIN $CUR_O3_PGO $PGO_PROFILE
fi



# ---- Where this script lives (absolute, no symlinks issues) ----
cd $main_path/$DIRECTORY
RES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
echo "SCRIPT_DIR: " $SCRIPT_DIR
echo "RES_DIR: " $RES_DIR


#---------- SET PATHs for BASELINE and VALUE profile file ---------
BASELINE=$main_path/$DIRECTORY/$app"_baseline_O3_PGO.ll"
input_csv=$main_path/$DIRECTORY/"value_profile_"$app"_baseline_O3_PGO.txt"


if [[ -z "${BASELINE}" || -z "${input_csv}" || -z "${NumberOfFiles}" ]]; then
  echo "Usage: $0 <BASELINE> <input_csv> <NumberOfFiles>" >&2
  exit 1
fi

# ---- Tooling: prefer LLVM_20_build_ART if set; fallback to PATH 'opt' ----
if [[ -n "${LLVM_20_build_ART:-}" && -x "${LLVM_20_build_ART}/bin/opt" ]]; then
  OPT_BIN="${LLVM_20_build_ART}/bin/opt"
else
  OPT_BIN="$(command -v opt || true)"
fi
if [[ -z "${OPT_BIN}" ]]; then
  echo "[error] Could not find 'opt'. Set LLVM_20_build_ART or add 'opt' to PATH." >&2
  exit 1
fi

# ---- Project-relative directories (all under the script folder) ----
rootS="${SCRIPT_DIR}"  # change this if you want a different base than the script dir
rootD="${RES_DIR}"  # change this if you want a different base than the script dir
PROFDIR="${rootD}/candidate_profiles_dir"
OUTDIR="${rootD}/OPT_IRs_dir"
BIN_DIR="${rootD}/bin_dir"
PERF_OUT="${rootD}/perf_out_dir"
OUTDIR_O3="${rootD}/OPT_IRs_O3_dir"
additional_files="${rootD}/other_files"
out_dir="${rootD}/output_res_dir"
COMPARE_CFGS_PY="${rootS}/python-codes/compare_cfgs.py"
CFG_caller_callee_dir="${rootD}/cfg_caller_callee_dir"
EMITTER_SH="${rootS}/emit_bfi_csv.sh"
GEN_PROF_SH="${rootS}/gen_profiles_singletons_plus_random_maxrow.sh"
BUILD_BIN_PAR_SH="${rootS}/build_bins_from_irs_parallel.sh"
RUN_PERF_PAR_SH="${rootS}/run_perf_and_rank_parallel.sh"
BUILD_MANIFEST_SH="${rootS}/build_manifests_for_profiles_parallel.sh"
RUN_ALL_BFI_CFG_SH="${rootS}/run_all_bfi_cfg_parallel.sh"
RUN_CFG_FOR_CALLER_PAR_SH="${rootS}/run_cfg_callers_parallel.sh"
MERGE_CFGs_PAR_SH="${rootS}/merge_cfg_summaries_parallel.sh"
MAKE_OPCODE_STATIC_PAR_FAST_SH="${rootS}/build_opcode_attr_parallel_fast.sh"

# ---- Create dirs if missing ----
mkdir -p \
  "${PROFDIR}" \
  "${OUTDIR}" \
  "${BIN_DIR}" \
  "${PERF_OUT}" \
  "${OUTDIR_O3}" \
  "${additional_files}" \
  "${out_dir}" \
  "${CFG_caller_callee_dir}"


# ---- Example echoes so you can see what resolved where ----
echo "[cfg] SCRIPT_DIR=${SCRIPT_DIR}"
echo "[cfg] OPT_BIN=${OPT_BIN}"
echo "[cfg] BASELINE=${BASELINE}"
echo "[cfg] input_csv=${input_csv}"
echo "[cfg] NumberOfFiles=${NumberOfFiles}"
echo "[cfg] OUTDIR=${OUTDIR}"
echo "[cfg] OUTDIR_O3=${OUTDIR_O3}"
echo "[cfg] PERF_OUT=${PERF_OUT}"
echo "[cfg] BIN_DIR=${BIN_DIR}"
echo "[cfg] PROFDIR=${PROFDIR}"
echo "[cfg] CFG_caller_callee_dir=${CFG_caller_callee_dir}"

generate_opt_irs_from_profiles() {
  [[ -f "$BASELINE" ]] || { echo "[opt-gen] ERROR: baseline IR not found: $BASELINE" >&2; return 2; }
  command -v "$OPT_BIN" >/dev/null 2>&1 || { echo "[opt-gen] ERROR: OPT_BIN not executable: $OPT_BIN" >&2; return 2; }
  [[ -d "$PROFDIR" ]] || { echo "[opt-gen] ERROR: profiles dir not found: $PROFDIR" >&2; return 2; }


  echo "BASELINE: " $BASELINE
  mkdir -p "$OUTDIR"/logs

  shopt -s nullglob
  local profiles=( "$PROFDIR"/*.csv )
  if (( ${#profiles[@]} == 0 )); then
    echo "[opt-gen] WARNING: no *.csv profiles in $PROFDIR"
    return 1
  fi

  echo "[opt-gen] profdir : $PROFDIR"
  echo "[opt-gen] outdir  : $OUTDIR"
  echo "[opt-gen] count   : ${#profiles[@]}"

  for prof in "${profiles[@]}"; do
    local base="$(basename "$prof")"
    local stem="${base%.csv}"
    local outIR="$OUTDIR/${stem}.ll"
    local outIR_O3="$OUTDIR_O3/${stem}_O3.ll"
    local log="$OUTDIR/logs/${stem}.log"
    local profnum="${stem##*_}"

    echo "prof: " $prof
    echo "[opt-gen] running: $base -> $(basename "$outIR_O3")"
    "$OPT_BIN" -load-pass-plugin $LLVM_20_build_ART/lib/FuncSpecPassIRSwitchCaseV3.so -passes=FuncSpecPassIRSwitchCaseV3 -input-file $prof -ValPredThreshold 10 -NumOFDepInstrThreshold 1 -benchmarkName $stem -profileNum $profnum -S $BASELINE -o "$outIR"
    "$OPT_BIN" -passes='default<O3>' -S "$outIR" -o "$outIR_O3"
    # collect matches safely
    files=( *ProfileInfo.txt *rect.txt )
    # if there is at least one match, move them
    if ((${#files[@]} > 0)); then
      mv -- "${files[@]}" "$additional_files"/
    else
      echo "No matching files to move."
    fi

  done
}



generate_opt_irs_from_profiles_jobcount() {

  job_count=0
  if [ -d "$PROFDIR" ]; then
    for prof in "$PROFDIR"/*".csv"; do
      (
        echo "Processing $prof"
        echo ""
        echo "1) Processing Profile: $prof"

        base="$(basename "$prof")"
        stem="${base%.csv}"
        profnum="${stem##*_}"
        outIR="$OUTDIR/${stem}.ll"
        outIR_O3="$OUTDIR_O3/${stem}_O3.ll"
        log="$OUTDIR/logs/${stem}.log"

        echo "File: $base → num: $profnum"
        echo ""
        echo "2) Applying the Function Specialization Pass based on the profile ... "

        "$OPT_BIN" \
            -load-pass-plugin $LLVM_20_build_ART/lib/FuncSpecPassIRSwitchCaseV3.so \
            -passes=FuncSpecPassIRSwitchCaseV3 \
            -input-file "$prof" \
            -ValPredThreshold 10 \
            -NumOFDepInstrThreshold 1 \
            -benchmarkName "$stem" \
            -profileNum "$profnum" \
            -S "$BASELINE" \
            -o "${stem}.ll"

        "$OPT_BIN" -passes='default<O3>' -S "${stem}.ll" -o "${stem}_O3.ll"

        mv -f -- "${stem}.ll"    "$outIR"
        mv -f -- "${stem}_O3.ll" "$outIR_O3"

        files=( *ProfileInfo.txt *rect.txt )
        # if there is at least one match, move them
        if ((${#files[@]} > 0)); then
          mv -- "${files[@]}" "$additional_files"/
        else
          echo "No matching files to move."
        fi

        if [[ -f "$outIR" ]]; then
          echo "[opt-gen] OK: $base -> $(basename "$outIR_O3")"
        else
          echo "[opt-gen] FAIL: $base (see $log)"
          # Optional: tail -n 20 "$log"
        fi
      ) &
      ((job_count++))
      if [[ "$job_count" -ge "$cores" ]]; then
        wait
        job_count=0
      fi
    done
    wait
  else
    echo "Directory '$PROFDIR' does not exist!"
  fi
}

if [[ "$compilerType" == "c" ]]; then
  CL=$CLANG
else
  CL=$CLANGXX
fi
echo "CL: " $CL


# Helpers
_stem() { local p="$1"; p="${p##*/}"; echo "${p%.ll}"; }

_compile_one() {
  # _compile_one IR [OUTPUT_STEM]
  local IR="${1:?IR required}"
  local STEM="${2:-}"
  if [[ -z "$STEM" ]]; then STEM="$(_stem "$IR")"; fi

  local OBJ="$BIN_DIR/${STEM}.o"
  local BIN="$BIN_DIR/${STEM}"
  echo "[build]  -> $STEM"

  if [[ -n "${PGO_PROFDATA:-}" ]]; then
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" \
      -fprofile-instr-use="${PGO_PROFDATA}" -c "$IR" -o "$OBJ"
  else
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" \
      -c "$IR" -o "$OBJ"
  fi

  "$CL"  "${DEBUG_CFLAGS_O3[@]}" "${compileFlags2[@]}" "$OBJ" -o "$BIN" "${compileFlags3[@]}"
  echo "$BIN"
}


build_bins_from_IRs_jobcount() {
  echo "[build] Baseline IR: $BASELINE"
  BASE_BIN="$(_compile_one "$BASELINE")"
  BASE_STEM="$(_stem "$BASELINE")"

  job_count2=0
  # Parallel loop: compile each IR to a binary
  if [ -d "$OUTDIR_O3" ]; then
    for IR in "$OUTDIR_O3"/*".ll"; do
      (
        echo "IR: "$IR
        STEM="$(_stem "$IR")"
        echo "  STEM: " $STEM
        BIN_PATH="$(_compile_one "$IR" "$STEM")"
        echo "[build] OK  : $STEM"
      ) &
      ((job_count2++))
      if [[ "$job_count2" -ge "$cores" ]]; then
        wait   # wait for all background jobs in this batch to finish
        job_count2=0
      fi
    done
    wait  # final wait for remaining jobs
  else
    echo "[build] ERROR: directory '$OUTDIR_O3' does not exist!"
  fi
}

run_perf_parallel (){

  local WORKDIR="$1"
  local BASE_BIN="$2"
  shift 2              # everything after this are the program args
  local -a ARGS=( "$@" )
  
  echo ""
  echo "WORKDIR : $WORKDIR"
  echo "BIN     : $BIN_NAME"
  echo "ARGS    : ${ARGS[*]}"
  echo ""

  cd $WORKDIR
  perf stat -- "./$BIN_NAME" "${ARGS[@]}"
}


echo ""
echo "Follow the STEPs to run the scripts : "

echo ""
echo "1) Generate Random profiles for IRs : "
$GEN_PROF_SH $app $input_csv $PROFDIR $NumberOfFiles $MAX_SIZE
echo ""


echo "2) Generate IRs from Random profiles : "
generate_opt_irs_from_profiles_jobcount
echo ""
cd $main_path/$DIRECTORY


echo "3) Generate Binaries from IRs : "
build_bins_from_IRs_jobcount
echo ""
cd $main_path/$DIRECTORY

if [[ "$compilerType" == "c" ]]; then
  CL=$CLANG
else
  CL=$CLANGXX
fi

echo "CL: " $CL

combined_c_flags=( "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" )
joined_C1="$(printf ''%q '' "${combined_c_flags[@]}")"
joined_C1="${joined_C1% }"
echo "joined_C3: " $joined_C1

combined_c3_flags=("${compileFlags3[@]}" )
joined_C3="$(printf ''%q' ' "${combined_c3_flags[@]}")"
joined_C3="${joined_C3% }"
echo "joined_C3: " $joined_C3


$BUILD_BIN_PAR_SH \
  --clang "$CL" \
  --baseline-ir "$BASELINE" \
  --opt-dir   "$OUTDIR_O3" \
  --bin-dir   "$BIN_DIR" \
  --extra-cflags "$joined_C1" \
  --extra-ldflags "${compileFlags3[@]}" \
  --pgo-profdata $main_path/$DIRECTORY/"pgo_ir_profile.profdata" \
  --num_cores "$cores"


echo ""
echo "4) Get Perf Stat results for Binaries in $BIN_DIR : "

BASE_BIN=$BIN_DIR/$app"_baseline_O3_PGO"
manifest="$BIN_DIR/build_bins_manifest.csv"
base_name="$(basename "$BASE_BIN")"

# list executables in BIN_DIR (non-recursive), sorted
mapfile -d '' bins < <(find "$BIN_DIR" -maxdepth 1 -type f -perm -u+x -printf '%f\0' | sort -z)

{
  echo "bin_name,ir_name,type"
  echo "${base_name},${base_name},baseline"
  for s in "${bins[@]}"; do
    [[ "$s" == "$base_name" ]] && continue
    echo "${s},${s},optimized"
  done
} > "$manifest"

echo "[manifest] wrote: $manifest"




cd "$BIN_DIR"
if [ "${app}" = 'perlbench_r_base.mytest-m64' ]; then
    cp $input_path/diffmail.pl .
    cp -r $input_path/lib .
fi
if [ "${app}" = 'imagick_r_base.mytest-m64' ]; then
    echo "yes app is imagick!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
 
fi
if [ "${app}" = 'cpugcc_r_base.mytest-m64' ]; then
    echo "yes app is gcc!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
fi


if [ "${app}" = 'xz_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
fi


if [ "${app}" = 'x264_r_base.mytest-m64' ]; then
    echo "yes app is x264!"
    cp $input_path/$inputName .
    cp $input_path/* .
    cp -r $input_path/* .
fi

 
if [ "${app}" = 'srr-medium' ]; then
  cp -r "benchmarks/cortexsuite/cortex/srr/"* .
fi
if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
fi
 
if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
fi
if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
fi
 
if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
fi
if [ "${app}" = 'bfs' ]; then
  cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
fi


if [ "${app}" = 'deepsjeng_r_base.mytest-m64' ]; then
  echo "yes app is deep!"
  cp $input_path/$INPUTS .
fi

  #--input "$INPUTS" 

cd $main_path/$DIRECTORY
BASE_BIN=$app"_baseline_O3_PGO"

$RUN_PERF_PAR_SH \
  --bin-dir "$BIN_DIR" \
  --manifest "$BIN_DIR"/build_bins_manifest.csv \
  --input "$INPUTS_Perf"  --runs 1 \
  --taskset 1 \
  --rank-by user \
  --parallel 30 \
  --cpu-list "1-31" \
  --out "$PERF_OUT"




cd $main_path/$DIRECTORY
echo ""
echo " 5) Get the manifests csv file"
$BUILD_MANIFEST_SH \
  "$BASELINE" \
  "$OUTDIR_O3" \
  "$PROFDIR"\
  "$out_dir" \
  60



MANIFEST=$out_dir/"manifest_funcs_with_callers.csv"


echo ""
echo " 6) Get the BFI and CFG data for caller and callee from IRs"

$RUN_ALL_BFI_CFG_SH \
  --opt "$OPT_BIN" \
  --baseline "$BASELINE" \
  --opt-dir "$OUTDIR_O3" \
  --out "$out_dir" \
  --manifest "$MANIFEST" \
  --emitter "$EMITTER_SH" \
  --compare "$COMPARE_CFGS_PY" \
  --parallel 60


$RUN_CFG_FOR_CALLER_PAR_SH \
  --baseline  "$BASELINE" \
  --opt-dir   "$OUTDIR_O3" \
  --manifest  "$MANIFEST" \
  --out       "$out_dir" \
  --compare   "$COMPARE_CFGS_PY" \
  --parallel  60



echo ""
echo " 7) Get the BFI and CFG data for caller and callee from IRs"
$MERGE_CFGs_PAR_SH --out "$out_dir"


echo ""
echo " 8) Get the static data for opcode Types from the IRs"


MANIFEST=$out_dir/"manifest_funcs_with_callers.csv"

$MAKE_OPCODE_STATIC_PAR_FAST_SH \
  --manifest "$MANIFEST" \
  --baseline "$BASELINE" \
  --optimized_dir "$OUTDIR_O3" \
  --bfi_dir "$out_dir"/bfi \
  --out "$out_dir"/opcode_attr_for_all_opts_new.csv \
  --jobs 60 
  #--verbose

echo "[ok] Paths configured relative to ${SCRIPT_DIR}"

echo "######### add speedup compared to baseline to perf results #############"
cd $SCRIPT_DIR

perf_path="$PERF_OUT/perf_results.csv"       # e.g. perf_out_dir/perf_results.csv
echo "perf_path: " $perf_path
baseline_name=$app"_baseline_O3_PGO"   # e.g. perlbench_r_base.mytest-m64_baseline_O3_PGO
output_path="$PERF_OUT/perf_results_with_speedup.csv"      # e.g. perf_out_dir/perf_results_with_speedup.csv
agg_mode="${4:-mean}" # optional 4th arg (default mean)


python3 ./add_speedup_columns.py "$perf_path" "$baseline_name" "$output_path" "$agg_mode"
echo "###### generate the full data set #######"
python3 ./generate_full_dataset_raw.py \
  --app $app \
  --cfg "$out_dir/cfg_merged/cfg_summary_all.csv" \
  --opcode "$out_dir/opcode_attr_for_all_opts_new.csv" \
  --perf "$output_path"
echo "###### train the model and rank the candidates #######"
python3 ./train_rank_lambdamart_5folds_safe.py --input full_dataset_raw_$app.csv --app $app --folds 5

echo ""
echo "BEST: "
python ./print_ideal_ir.py --in $app-best-speedup.csv
echo ""
echo "COST-MODEL: "
python3 ./pick_best_ranked_ir_by_speedup.py
echo ""


mv full_dataset_raw_$app.csv $rootD 
mv $app-metrics* $rootD
mv $app-ranker* $rootD
mv $app-eval* $rootD
mv $app-feature* $rootD
mv $app-topIR* $rootD
mv $app-best-speedup.csv $rootD


