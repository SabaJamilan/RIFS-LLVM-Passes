#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run_bfi_caller_callee.sh \
#     --opt /path/to/opt \
#     --baseline /path/to/baseline.ll \
#     --opt-dir OPT_IRs_O3_dir \
#     --out output_res_dir \
#     --emitter ./emit_bfi_csv.sh
#
# Emits: out/bfi/<stem>.bfi.csv for baseline + each .ll in opt-dir

OPT_BIN=""
BASELINE=""
OPT_DIR=""
OUT_DIR=""
EMITTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --opt)       OPT_BIN="$2"; shift 2;;
    --baseline)  BASELINE="$2"; shift 2;;
    --opt-dir)   OPT_DIR="$2"; shift 2;;
    --out)       OUT_DIR="$2"; shift 2;;
    --emitter)   EMITTER="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

echo "EMITTER: " $EMITTER




[[ -x "${OPT_BIN:-}" ]] || { echo "[bfi-run] ERROR: --opt not executable"; exit 1; }
[[ -f "${BASELINE:-}" ]] || { echo "[bfi-run] ERROR: --baseline not found"; exit 1; }
[[ -d "${OPT_DIR:-}"  ]] || { echo "[bfi-run] ERROR: --opt-dir not a dir"; exit 1; }
[[ -n "${OUT_DIR:-}"  ]] || { echo "[bfi-run] ERROR: --out is required"; exit 1; }
[[ -x "${EMITTER:-}"  ]] || { echo "[bfi-run] ERROR: --emitter not executable"; exit 1; }

mkdir -p "$OUT_DIR/bfi"

echo "[bfi-run] baseline: $BASELINE"
"$EMITTER" "$OPT_BIN" "$BASELINE" "$OUT_DIR"

shopt -s nullglob
for ir in "$OPT_DIR"/*.ll; do
  echo "[bfi-run] opt IR: $ir"
  "$EMITTER" "$OPT_BIN" "$ir" "$OUT_DIR"
done

echo "[bfi-run] done (BFI CSVs in $OUT_DIR/bfi)"
