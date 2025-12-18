#!/usr/bin/env bash
#set -euo pipefail
IFS=$'\n\t'

# ---- Where this script lives (absolute, no symlinks issues) ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
pin_tools_path="$SCRIPT_DIR/pin_tools"
# ---- Args ----
app="${1:?usage: $0 <app> <cores>}"
cores=${2:-}

python_codes="$SCRIPT_DIR/python-codes"

export LD_LIBRARY_PATH="$LLVM_20_build_ART/lib:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$LLVM_20_build_ART/lib:${LIBRARY_PATH:-}"

# ---- LLVM toolchain ----
: "${LLVM_20_build:?env LLVM_20_build must point to your LLVM bin dir root}"
CLANG="$LLVM_20_build_ART/bin/clang"
CLANGXX="$LLVM_20_build_ART/bin/clang++"
OPT="$LLVM_20_build_ART/bin/opt"
LLD="$LLVM_20_build_ART/bin/ld.lld"   # not strictly used here
LLDIS="$LLVM_20_build_ART/bin/llvm-dis"
LLVMDIS="$LLVM_20_build_ART/bin/llvm-dis"
LLVMPROFDATA="$LLVM_20_build_ART/bin/llvm-profdata"
LLVMCONFIG="$LLVM_20_build_ART/bin/llvm-config"
# ---- Env echo ----
PID=$$
echo "==============================="
echo "PID: $PID"
echo "==============================="
main_path="$(pwd)"
# ---- Output dirs ----
DIRECTORY="${app}-${PID}"
mkdir -p "$DIRECTORY"

SPEC_DIRECTORY="spec2017-wllvm-gdb"
mkdir -p "$SPEC_DIRECTORY"
all_benchmarks_dir_path="$main_path/$SPEC_DIRECTORY"

# ---- Frontend flags ----
# Use arrays with one flag per element (NO big quoted strings)
SPEC_DEBUG_FLAGS_O3=( "-O3 -g -fdebug-info-for-profiling -fno-discard-value-names -no-pie ")
DEBUG_CFLAGS_O3=(
  -O3
  -g
  -fdebug-info-for-profiling
  -fno-discard-value-names
  -no-pie
)
# ---- SPEC 505.mcf_r (C) example wiring ----
is_spec_bench=0

if [[ "$app" == "mcf_r_base.mytest-m64" ]]; then
  benchmark_path="cpu2017"
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
  INPUTS=(inp.in)
  INPUTS_Perf="inp.in"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  inputName="inp.in"
  compilerType="c++"
fi

if [[ "$app" == "perlbench_r_base.mytest-m64" ]]; then
  benchmark_path="cpu2017"
  SPECid="500"
  dirname="500.perlbench_r"
  compiler="clang++"  # C benchmark → use clang
  # host C flags used by SPEC when building from source:
  compileFlags1=(-std=c99   -m64  -DSPEC -DNDEBUG -DPERL_CORE -I"cpu2017/benchspec/CPU/500.perlbench_r/src" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/dist/IO" -I"cpan/Time-HiRes" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/cpan/HTML-Parser" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/ext/re" -I"cpu2017/benchspec/CPU/500.perlbench_r/src/specrand" -DDOUBLE_SLASHES_SPECIAL=0 -DSPEC_AUTO_SUPPRESS_OPENMP -D_LARGE_FILES -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64  -march=native -fno-unsafe-math-optimizations  -fcommon        -DSPEC_LINUX_X64    -fno-strict-aliasing -fgnu89-inline   -DSPEC_LP64 -Wno-implicit-function-declaration)
  compileFlags2=(-std=c99   -m64 -march=native -fno-unsafe-math-optimizations -no-pie -fcommon     -DSPEC_LINUX_X64    -fno-strict-aliasing -fgnu89-inline)
  compileFlags3=(-lm)
  INPUTS=(-Ilib diffmail.pl 4 800 10 17 19 300)
  INPUTS_Perf="-Ilib diffmail.pl 4 800 10 17 19 300"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "deepsjeng_r_base.mytest-m64" ]]; then
  benchmark_path="cpu2017"
  SPECid="531"
  dirname="531.deepsjeng_r"
  compiler="clang++"
  compileFlags1=(-std=c++03 -m64 -DSPEC -DNDEBUG -DSMALL_MEMORY -DSPEC_AUTO_SUPPRESS_OPENMP  -march=native -fno-unsafe-math-optimizations  -fcommon  -DSPEC_LP64)
  compileFlags2=(-std=c++03 -m64 -march=native -fno-unsafe-math-optimizations -fcommon)
  compileFlags3=()
  INPUTS=(train.txt)
  INPUTS_Perf="train.txt"
  inputName="train.txt"
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  is_spec_bench=1
  compilerType="c++"
fi
if [[ "$app" == "imagick_r_base.mytest-m64" ]]; then
  benchmark_path="cpu2017"
  SPECid="538"
  dirname="538.imagick_r"
  compiler="clang++"
  compileFlags1=(-std=c99   -m64 -DSPEC -DNDEBUG -I"cpu2017/benchspec/CPU/538.imagick_r/src" -DSPEC_AUTO_SUPPRESS_OPENMP  -march=native -fno-unsafe-math-optimizations  -fcommon  -DSPEC_LP64)
  compileFlags2=(-std=c99   -m64 -march=native -fno-unsafe-math-optimizations -fcommon )
  compileFlags3=(-lm)
  input_path=$main_path/$SPEC_DIRECTORY/$SPECid"-train."$PID/"baseline-gline"/"benchspec"/"CPU"/$dirname/"run"/"run_base_train_mytest-m64.0000"
  inputName="train_input.tga"
  INPUTS=(-limit disk 0 train_input.tga -resize 320x240 -shear 31 -edge 140 -negate -flop -resize 900x900 -edge 10 train_output.tga)
  INPUTS_Perf="-limit disk 0 train_input.tga -resize 320x240 -shear 31 -edge 140 -negate -flop -resize 900x900 -edge 10 train_output.tga"
  is_spec_bench=1
  compilerType="c++"
fi

if [[ "$app" == "x264_r_base.mytest-m64" ]]; then
  benchmark_path="cpu2017"
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
  benchmark_path="cpu2017"
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
  benchmark_path="cpu2017"
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
  benchmark_path="benchmarks/parsec3.0/parsec-benchmark/pkgs/apps/swaptions/src"
  SPECid="swaptions"
  dirname="cortex"
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
  benchmark_path="benchmarks/parsec3.0/parsec-benchmark/pkgs/apps/freqmine/src"
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
  inputs=""
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
  INPUTS=(large/audio.raw language_model/HUB4/)
  INPUTS_Perf="large/audio.raw language_model/HUB4/"
  input_path=""
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
  inputs=""
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
  INPUTS_perf="512 8 800 power_512x8 temp_512x8 output.out"
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
  INPUTS_perf="-i kdd_cup_synth.txt"
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
  extract-bc -l "$LLVM_20_build/bin/llvm-link" "$app"
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
  echo" Write one file per process (and include the executable name). Absolute path avoids CWD surprises."
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


VALUE_PROFILE_WITH_PIN_SO () {
  local BIN_TO_PROFILE="$1" IR_TO_PROFILE="$2" PGO_PROFILE_O3="$3"
  local lang=$compilerType
  local CL=$(pick_clang "$lang")

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

  if [ "${app}" = 'mcf_r_base.mytest-m64' ]; then
    echo "yes app is mcf!"
    cp $input_path/$INPUTS .
  fi

  cur_path=`pwd`
  echo "***** :cur_path: "  $cur_path
  $PIN_ROOT/pin -t $pin_tools_path/CountFuncCalls.so  -p 1 -po "CallsFreq-"$BIN_TO_PROFILE".csv" -- ./$BIN_TO_PROFILE ${INPUTS[@]}
  
  echo "1"  
  python3 $python_codes/dec2hex-CallFreq.py "CallsFreq-"$BIN_TO_PROFILE".csv" "CallsFreq-"$BIN_TO_PROFILE"-hex.csv"
  
  echo "2"  
  mv "TotalNumCalls.out" "TotalNumCalls_"$BIN_TO_PROFILE"."$PID".txt"
  mv "NumDiffCalls.out" "NumDiffCalls_"$BIN_TO_PROFILE"."$PID".txt"
  
  echo "3"  
  $PIN_ROOT/pin -t $pin_tools_path/proccount.so -- ./$BIN_TO_PROFILE ${INPUTS[@]}
  
  echo "4"  
  TotalNumCalls=$(head -n 1 "TotalNumCalls_"$BIN_TO_PROFILE"."$PID".txt")
  NumDiffCalls=$(head -n 1 "NumDiffCalls_"$BIN_TO_PROFILE"."$PID".txt")
  
  echo "5"  
  echo ""
  echo "Total Number of Executed Call instructions= " $TotalNumCalls
  echo "Number of different Call instructions= " $NumDiffCalls

  head -n 1 "TotalNumCalls_"$BIN_TO_PROFILE"."$PID".txt" >> "OverallResults_"$BIN_TO_PROFILE"."$PID"-100.csv"
  head -n 1 "NumDiffCalls_"$BIN_TO_PROFILE"."$PID".txt" >> "OverallResults_"$BIN_TO_PROFILE"."$PID"-100.csv"

  echo "6"  
  echo "Run pin tool for profiling int/float args values for funcCalls .... "
  gdb -x $python_codes/gdb_funcSig_all.py --args ./$BIN_TO_PROFILE ${INPUTS[@]}

  echo "pin path:"
  pwd
  echo ""
  echo "7"  

  j=0;
  
  filelen=$(wc -l < func_sig_all.csv)
  echo "filelen = " $filelen

  if [[ $filelen -le $num_cores ]]; then
    echo "8"  
    echo "Number of Functions to profile is less than $num_cores!!"
    m=$(( $filelen / $cores ))
    num_cores=$filelen
    echo "num_cores:  " $cores
  fi


  if [[ $filelen -gt $cores ]]; then
    echo "Number of Functions to profile  >= $cores!!"
    echo "9"  
    m=$(( $filelen / $cores ))
  fi

  i=0
  num_func=$(( $m + 1 ))
  n=$(( $num_func-1 ))


  echo "10"  
  echo "num_func_per_chunck: " $num_func  "  n: " $n
  while [[ $i -le $filelen ]]; do
    echo "11"  
    sed -n "s/\r//;$i,$(($i+$n))p;$(($i+$num_func))q;" func_sig_all.csv > func_sig_all.$j.csv;
    ((i+=$num_func));
    ((j+=1));
  done

  echo "Number of chuncks = " $j " exe: " $BIN_TO_PROFILE
  echo ""
  
  k=0
  start=`date +%s.%N`
  if [ "${app}" = 'mcf_r_base.mytest-m64' ]; then
    echo "12"  
    echo "yes app is mcf!"
    cp $input_path/$INPUTS .
  fi


  for k in $(seq 0 $(($j-1)));
  do
    echo "13"  
    func_name=$(cut -d "," -f1 func_sig_all.$k.csv)
    if [ "$func_name" != "RanUnif" ]; then
      echo "chunck #" $k "   Function Name:  " $func_name
      $PIN_ROOT/pin -t $pin_tools_path/traceAllArgsForFuncCalls-v2.so  -p 1 -i func_sig_all.$k.csv  -d $k -- ./$BIN_TO_PROFILE ${INPUTS[@]} &
    fi
  done
  wait
  echo "All done"

  end=`date +%s.%N`
  runtime=$( echo "$end - $start" | bc -l )
  echo "runtime:  "$runtime
  echo "runtime:  "$runtime >> "total-runtime-"$BIN_TO_PROFILE"."$PID".txt"
  echo "func_file_id, #Calls, CallPC, target, CallSiteName, CalleeName, CallFreq, #totalArgs, #IntArgs, #floatArgs, #PointerArgs, ArgIndex, ArgType, ArgVal, ArgValFreq, ArgValPred" >> $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID".csv"
  find *.CallArgsValueStatistics -exec cat {} + >> $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID".csv"

  python3 $python_codes/summarize_value_profile.py --out $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-summary.csv" $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID".csv"

  echo "133"  
  mkdir $CallArgsValueStatistics_files
  mv *.CallArgsValueStatistics $CallArgsValueStatistics_files
  mkdir $func_sig_files
  mv func_sig* $func_sig_files
  mv gdb_output*  $func_sig_files

  mv "tracedFuncsName.out" "TracedFuncsName_"$BIN_TO_PROFILE"."$PID".txt"
  echo $filelen >> "OverallResults_"$BIN_TO_PROFILE"."$PID"-100.csv"
  head -n 1 "NumDiffCalls_"$BIN_TO_PROFILE"."$PID".txt" >> "OverallResults_"$BIN_TO_PROFILE"."$PID"-100.csv"
  
  echo ""
  echo "pwd after profiling: "
  pwd
  echo ""

  echo "Apply analysis ......"
  mkdir  $BIN_TO_PROFILE"_coverage_analysis_results"

  python3 $python_codes/convert-to-hex-pcs.py $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID".csv" $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-hex.csv"
  
  python3 $python_codes/filter-pointerTypes-For-funcPass.py $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-hex.csv" $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-intTypes.csv"
  
  python3 $python_codes/FuncSpec_per_CallSite.py $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-intTypes.csv" $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-intTypes-callsite-analysis.csv" $BIN_TO_PROFILE"_final_CallArgsValueStatistics."$PID"-intTypes-funcSpec-per-Callsite.csv"
  
}

NON_SPEC_benchmark_compile_With_O3_PGO() {
  local lang=$compilerType
  local CL=$(pick_clang "$lang")

  cd "$all_benchmarks_dir_path"
  mkdir -p "${SPECid}-train.${PID}"
  
  if [ $dirname = "cortex" ]; then
    echo "########################## BASELINE -gline-tables-only ########################################"
    echo "1)   Generate baseline IR by using -gline-tables-only flag FOR CortexSuite ... "
    echo "###################################################################################"
    cd $benchmark_path
    rm $app-*
    rm *.profdata
    rm perf.data*
    rm *-perfstats.txt

    python3 "$python_codes/config_changer_baseline.py" "${SPEC_DEBUG_FLAGS_O3[@]}" $benchmark_path/Makefile-baseline-raw $benchmark_path/Makefile
    make clean
    make
    input_path=`pwd`

    echo "[*] Extracting bitcode from: $app"
    extract-bc -l "$LLVM_20_build/bin/llvm-link" "$app"
    have_file "${app}.bc" || die "failed to extract ${app}.bc"
    "$LLDIS" "${app}.bc" -o "${app}_baseline_O3.ll"
    SRC_LL="${app}_baseline_O3.ll"

    cp "$SRC_LL" $main_path/$DIRECTORY
    cp $INPUTS $main_path/$DIRECTORY
    cp $input_path/$INPUTS $main_path/$DIRECTORY
    cd $main_path/$DIRECTORY


    # 1) Instrument the IR at IR level
    "$OPT" -passes='pgo-instr-gen' "$SRC_LL" -o "${app}_baseline_O3_gen_opt.ll"

  
    "$CL" "${DEBUG_CFLAGS_O3[@]}" "${compileFlags1[@]}" -fprofile-instr-generate "${app}_baseline_O3_gen_opt.ll" \
      -o "${app}_baseline_O3_gen_opt"

    echo "[*] Running instrumented binary to collect profile…"
    echo " Put profiles in a dedicated dir and use a unique pattern to avoid mixing old runs."
  
    profdir="${PWD}/profraw.${app}.$$"

    if [ "${app}" = 'bfs' ]; then
      cp benchmarks/rodinia_3.1/openmp/bfs/graph4K_deg8.txt .
    fi

    if [ "${app}" = 'kmeans' ]; then
      cp benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/kdd_cup_synth.txt .
      rm benchmarks/rodinia_3.1/openmp/kmeans/kmeans_serial/*.o
    fi

    if [ "${app}" = 'euler3d_cpu' ]; then
      cp benchmarks/rodinia_3.1/data/cfd/fvcorr.domn.097K .
  
    fi
 

    if [ "${app}" = 'hotspot' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot/temp_1024 .
      cp benchmarks/rodinia_3.1/data/hotspot/power_1024 .
    fi
 
    if [ "${app}" = 'hotspot3D' ]; then
      cp benchmarks/rodinia_3.1/data/hotspot3D/temp_512x8 .
      cp benchmarks/rodinia_3.1/data/hotspot3D/power_512x8 .
    fi

    mkdir -p "$profdir"
    echo" Write one file per process (and include the executable name). Absolute path avoids CWD surprises."
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
    #list_profile_functions pgo_ir_profile.profdata funcs.txt summary.txt
    # Confirm the file exists and is non-empty
    if [[ ! -s pgo_ir_profile.profdata ]]; then
      echo "error: failed to create non-empty pgo_ir_profile.profdata" >&2
    fi
  
    # 5) Apply the profile to the ORIGINAL (uninstrumented) IR
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

  echo ""
  echo "---- 1) value profile with PIN Tool (-O3 + PGO)----"
  VALUE_PROFILE_WITH_PIN_SO $CUR_O3_PGO_BIN $CUR_O3_PGO $PGO_PROFILE
  echo ""
  echo "---- 2) value profile with PIN Tool (-O3) ----"
  cd "$main_path/$DIRECTORY"
  VALUE_PROFILE_WITH_PIN_SO $CUR_O3_BIN $CUR_O3 $PGO_PROFILE
  echo ""

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
  VALUE_PROFILE_WITH_PIN_SO $CUR_O3_PGO_BIN $CUR_O3_PGO $PGO_PROFILE
  echo ""
  echo "---- 2) value profile with PIN Tool (-O3) ----"
  cd "$main_path/$DIRECTORY"
  VALUE_PROFILE_WITH_PIN_SO $CUR_O3_BIN $CUR_O3 $PGO_PROFILE
  echo ""

fi


