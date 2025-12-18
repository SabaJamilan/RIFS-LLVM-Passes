#!/usr/bin/env bash
# Usage:
#   ./run_all_bfi_cfg_parallel.sh \
#     --opt /path/to/opt \
#     --baseline /path/to/baseline.ll \
#     --opt-dir OPT_IRs_O3_dir \
#     --out output_res_dir \
#     --manifest output_res_dir/manifest_callees.csv \
#     --emitter ./emit_bfi_csv.sh \
#     --compare /path/to/compare_cfgs.py \
#     [--parallel 8]
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
rootS="${SCRIPT_DIR}"  # change this if you want a different base than the script dir
RUN_BFI_CALLER_CALLEE_SH="${rootS}/run_bfi_caller_callee.sh"
#RUN_CFG_CALLEE_SH="${rootS}/run_cfg_callees.sh"
RUN_CFG_CALLEE_PAR_SH="${rootS}/run_cfg_callees_parallel.sh"


OPT_BIN=""
BASELINE=""
OPT_DIR=""
OUT_DIR=""
MANIFEST=""
EMITTER=""
COMPARE_CFGS_PY=""
PARALLEL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --opt)       OPT_BIN="$2"; shift 2;;
    --baseline)  BASELINE="$2"; shift 2;;
    --opt-dir)   OPT_DIR="$2"; shift 2;;
    --out)       OUT_DIR="$2"; shift 2;;
    --manifest)  MANIFEST="$2"; shift 2;;
    --emitter)   EMITTER="$2"; shift 2;;
    --compare)   COMPARE_CFGS_PY="$2"; shift 2;;
    --parallel)  PARALLEL="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -x "${OPT_BIN:-}"          ]] || { echo "[run-all] ERROR: --opt not executable"; exit 1; }
[[ -f "${BASELINE:-}"         ]] || { echo "[run-all] ERROR: --baseline not found"; exit 1; }
[[ -d "${OPT_DIR:-}"          ]] || { echo "[run-all] ERROR: --opt-dir not a dir"; exit 1; }
[[ -n "${OUT_DIR:-}"          ]] || { echo "[run-all] ERROR: --out required"; exit 1; }
[[ -f "${MANIFEST:-}"         ]] || { echo "[run-all] ERROR: --manifest not found"; exit 1; }
[[ -x "${EMITTER:-}"          ]] || { echo "[run-all] ERROR: --emitter not executable"; exit 1; }
[[ -f "${COMPARE_CFGS_PY:-}"  ]] || { echo "[run-all] ERROR: --compare not found"; exit 1; }
(( PARALLEL >= 1 )) || PARALLEL=1

mkdir -p "$OUT_DIR"

# Collect IRs we’ll process
shopt -s nullglob
IR_LIST=( "$OPT_DIR"/*.ll "$OPT_DIR"/*.bc )
shopt -u nullglob
if (( ${#IR_LIST[@]} == 0 )); then
  echo "[run-all] WARNING: no *.ll or *.bc in $OPT_DIR"
fi

if (( PARALLEL == 1 || ${#IR_LIST[@]} <= 1 )); then
  echo "[run-all] Step 1/2 (serial): Emit BFI for baseline + optimized IRs"
  $RUN_BFI_CALLER_CALLEE_SH \
    --opt "$OPT_BIN" \
    --baseline "$BASELINE" \
    --opt-dir "$OPT_DIR" \
    --out "$OUT_DIR" \
    --emitter "$EMITTER"
else
  echo "[run-all] Step 1/2 (parallel x$PARALLEL): Emit BFI for baseline + optimized IRs"
  # Make chunk dirs with symlinks, to avoid modifying your inner scripts.
  CHUNK_ROOT="$(mktemp -d "${OUT_DIR%/}/.bfi_chunks.XXXXXX")"
  trap 'rm -rf "$CHUNK_ROOT"' EXIT

  # Split IR_LIST into PARALLEL roughly-equal chunks
  chunks=( )
  for ((i=0;i<PARALLEL;i++)); do
    cdir="$CHUNK_ROOT/chunk_$i"
    mkdir -p "$cdir"
    chunks+=( "$cdir" )
  done
  for ((i=0;i<${#IR_LIST[@]};i++)); do
    tgt="${chunks[$(( i % PARALLEL ))]}"
    ln -sf "${IR_LIST[$i]}" "$tgt/$(basename "${IR_LIST[$i]}")"
  done

  # Run emitter for each chunk in parallel; baseline is the same for all.
  pids=()
  for cdir in "${chunks[@]}"; do
    (
      echo "[run-all]  -> chunk $(basename "$cdir") ($(ls -1 "$cdir" | wc -l) IRs)"
      $RUN_BFI_CALLER_CALLEE_SH \
        --opt "$OPT_BIN" \
        --baseline "$BASELINE" \
        --opt-dir "$cdir" \
        --out "$OUT_DIR" \
        --emitter "$EMITTER"
    ) &
    pids+=( $! )
  done

  # Wait for all chunk workers
  fail=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then fail=1; fi
  done
  (( fail == 0 )) || { echo "[run-all] ERROR: at least one BFI worker failed"; exit 1; }
fi

echo "[run-all] Step 2/2: CFG callee summaries (with BFI merge if available)"
#$RUN_CFG_CALLEE_SH \
$RUN_CFG_CALLEE_PAR_SH \
  --baseline "$BASELINE" \
  --opt-dir "$OPT_DIR" \
  --manifest "$MANIFEST" \
  --out "$OUT_DIR" \
  --compare "$COMPARE_CFGS_PY" \
  --parallel  60
echo "[run-all] done"
