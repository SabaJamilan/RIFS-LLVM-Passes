#!/usr/bin/env bash
set -euo pipefail

# Build baseline + optimized IRs (.ll) into runnable binaries and emit a manifest.
#
# Usage:
#   cores=60 ./build_bins_from_irs.sh \
#     --clang  /abs/path/to/clang \
#     --baseline-ir  /abs/path/to/baseline.ll \
#     --opt-dir      /abs/path/to/OPT_IRs_O3_dir \
#     --bin-dir      /abs/path/to/bin_out \
#     [--extra-cflags "-std=c99 -m64 ..."] \
#     [--extra-ldflags "-lm"] \
#     [--pgo-profdata /abs/path/to/pgo_ir_profile.profdata]

CLANG=""
BASE_IR=""
OPT_DIR=""
BIN_DIR=""
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""
PGO_PROFDATA=""
CORES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clang)         CLANG="$2"; shift 2;;
    --baseline-ir)   BASE_IR="$2"; shift 2;;
    --opt-dir)       OPT_DIR="$2"; shift 2;;
    --bin-dir)       BIN_DIR="$2"; shift 2;;
    --extra-cflags)  EXTRA_CFLAGS="$2"; shift 2;;
    --extra-ldflags) EXTRA_LDFLAGS="$2"; shift 2;;
    --pgo-profdata)  PGO_PROFDATA="$2"; shift 2;;
    --num_cores)  CORES="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

echo "EXTRA_CFLAGS: $EXTRA_CFLAGS"

[[ -x "${CLANG:-}"   ]] || { echo "[build] ERROR: --clang not executable"; exit 1; }
[[ -f "${BASE_IR:-}" ]] || { echo "[build] ERROR: --baseline-ir not found"; exit 1; }
[[ -d "${OPT_DIR:-}" ]] || { echo "[build] ERROR: --opt-dir not a dir"; exit 1; }
[[ -n "${BIN_DIR:-}" ]] || { echo "[build] ERROR: --bin-dir required"; exit 1; }
mkdir -p "$BIN_DIR"

# parallelism (same job-counter style as you requested)
#: "${cores:=60}"
echo ""
echo "-------------------------------------"
echo "EXTRA_CFLAGS: " $EXTRA_CFLAGS
echo ""
echo "EXTRA_LDFLAGS: " $EXTRA_LDFLAGS
echo "-------------------------------------"
echo ""
# O3 + debug flags you specified
#DEBUG_CFLAGS_O3=( -O3 -gline-tables-only -fdebug-info-for-profiling -fno-discard-value-names -no-pie -fno-pie )

# Allow extra flags
read -r -a EXTRA_CFLAGS_ARR  <<< "${EXTRA_CFLAGS:-}"
read -r -a EXTRA_LDFLAGS_ARR <<< "${EXTRA_LDFLAGS:-}"

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
    "$CLANG" "${EXTRA_CFLAGS_ARR[@]}" \
      -fprofile-instr-use="${PGO_PROFDATA}" -c "$IR" -o "$OBJ"
  else
    "$CLANG" "${EXTRA_CFLAGS_ARR[@]}" \
      -c "$IR" -o "$OBJ"
  fi

  "$CLANG"  "${EXTRA_CFLAGS_ARR[@]}" "$OBJ" -o "$BIN" "${EXTRA_LDFLAGS_ARR[@]}"
  echo "$BIN"
}

: '
echo "[build] Baseline IR: $BASE_IR"
BASE_BIN="$(_compile_one "$BASE_IR")"
BASE_STEM="$(_stem "$BASE_IR")"
'

echo "[build] Optimized IRs from: $OPT_DIR"
#OPT_IRS=( "$OPT_DIR"/*.ll )
#echo "[build] Found ${#OPT_IRS[@]} optimized IRs."
# temp dir to collect manifest lines without races
#PARTS_DIR="$(mktemp -d "${BIN_DIR}/.manifest_parts.XXXXXX")"
find "$OPT_DIR" -maxdepth 1 -type f -name '*.ll' | wc -l

if [ -d "$OPT_DIR" ]; then
  for IR in "$OPT_DIR"/*".ll"; do
    echo "###IR: " $IR
  done
fi

job_count2=0
# Parallel loop: compile each IR to a binary
if [ -d "$OPT_DIR" ]; then
  for IR in "$OPT_DIR"/*".ll"; do
    (
      echo "IR: "$IR
      STEM="$(_stem "$IR")"
      echo "  STEM: " $STEM
      BIN_PATH="$(_compile_one "$IR" "$STEM")"
      echo "[build] OK  : $STEM"
    ) &
    ((job_count2++))
    if [[ "$job_count2" -ge "$CORES" ]]; then
      wait   # wait for all background jobs in this batch to finish
      job_count2=0
    fi
  done
  wait  # final wait for remaining jobs
else
  echo "[build] ERROR: directory '$OPT_DIR' does not exist!"
fi

echo "[build] Wrote manifest: $manifest"
echo "[build] Done."
