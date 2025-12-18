#!/usr/bin/env bash
set -euo pipefail

# gen_profiles_singletons_plus_random.sh
# Create N singleton profile files (one per data row) + up to M random unique combo files (size >=2).
#
# Usage:
#   ./gen_profiles_singletons_plus_random.sh <input_csv> <out_dir> <M> [MAX_K]
#
# Args:
#   input_csv : value profile CSV (with header)
#   out_dir   : directory to write candidate profiles
#   M         : number of additional RANDOM unique combo files to generate
#               AND the maximum number of rows allowed in any random combo file
#               (i.e., per-file subset size cap)
#   MAX_K     : (optional) user cap for subset size (still capped by M). Default: DATA_COUNT
#
# Notes:
#   - Produces exactly N singleton files if there are N data rows:  profile_row_<i>.csv
#   - Then produces up to M random unique combo files (subset size in [2, CAP]),
#     where CAP = min(M, MAX_K, DATA_COUNT).
#   - Uniqueness is enforced across ALL outputs via md5 of file content.

die() { echo "ERROR: $*" >&2; exit 2; }
require() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

if [[ $# -lt 3 ]]; then
  echo "Usage: $(basename "$0") <input_csv> <out_dir> <M> [MAX_K]"
  exit 1
fi
app="$1"
INPUT="$2"
OUTDIR="$3"
M="$4"
MAX_K_USER="${5:-}"

require awk; require sed; require shuf; require md5sum
[[ -f "$INPUT" ]] || die "Input CSV not found: $INPUT"
[[ "$M" =~ ^[0-9]+$ ]] || die "M must be a non-negative integer"

mkdir -p "$OUTDIR"

# Read all lines
mapfile -t ALL_LINES < "$INPUT"
[[ ${#ALL_LINES[@]} -ge 2 ]] || die "CSV must have header + at least 1 data row"

HEADER="${ALL_LINES[0]}"
DATA_COUNT=$(( ${#ALL_LINES[@]} - 1 ))
(( DATA_COUNT >= 1 )) || die "No data rows"

# Determine MAX_K for random combos (user cap), then cap by M and DATA_COUNT
if [[ -n "$MAX_K_USER" ]]; then
  [[ "$MAX_K_USER" =~ ^[0-9]+$ ]] || die "MAX_K must be integer"
  MAX_K_BASE="$MAX_K_USER"
else
  MAX_K_BASE="$DATA_COUNT"
fi

# Effective cap: at most M rows per random file (and never exceed DATA_COUNT)
# If M==0 → we'll skip random combos entirely later.
if (( M > 0 )); then
  CAP=$MAX_K_BASE
  (( CAP > DATA_COUNT )) && CAP="$DATA_COUNT"
  (( CAP > M )) && CAP="$M"
else
  CAP=0
fi

echo "[gen] input     : $INPUT"
echo "[gen] outdir    : $OUTDIR"
echo "[gen] data rows : $DATA_COUNT"
echo "[gen] singletons: $DATA_COUNT (one per row)"
if (( M == 0 )); then
  echo "[gen] random    : disabled (M=0)"
else
  if (( CAP < 2 )); then
    echo "[gen] random    : requested M=$M but subset-size cap < 2 → no combos possible"
  else
    echo "[gen] random M  : $M  (up to $M files; subset size in [2,$CAP]; cap reason: min(M,MAX_K,DATA_COUNT))"
  fi
fi

declare -A SEEN=()

# Helper: write file with header + selected data-row indices (1..DATA_COUNT)
write_subset_file() {
  local outfile="$1"; shift
  local -a idxes=( "$@" )
  {
    echo "$HEADER"
    for idx in "${idxes[@]}"; do
      echo "${ALL_LINES[idx]}"
    done
  } > "$outfile"
}

# Helper: content hash for uniqueness
content_hash() {
  local tmp="$1"
  md5sum "$tmp" | awk '{print $1}'
}

# 1) Emit exactly N singleton files (one per row)
for ((i=1;i<=DATA_COUNT;i++)); do
  tmp="$(mktemp)"
  write_subset_file "$tmp" "$i"
  h=$(content_hash "$tmp")
  if [[ -n "${SEEN[$h]:-}" ]]; then
    rm -f "$tmp"
    continue
  fi
  SEEN[$h]=1
  OUT="$OUTDIR/${app}_profile_row_${i}.csv"
  mv "$tmp" "$OUT"
  echo "[gen] wrote $OUT (rows=1: [$i])"
done

# 2) Emit up to M random unique combo files (subset size in [2..CAP])
if (( M > 0 && CAP >= 2 )); then
  attempts=0
  created=0
  max_attempts=$(( M * 50 ))
  while (( created < M && attempts < max_attempts )); do
    attempts=$((attempts+1))
    # choose K in [2..CAP]
    K=$(shuf -i 2-"$CAP" -n 1)
    # choose K distinct rows in 1..DATA_COUNT
    mapfile -t idx < <(shuf -i 1-"$DATA_COUNT" -n "$K" | sort -n)

    tmp="$(mktemp)"
    write_subset_file "$tmp" "${idx[@]}"
    h=$(content_hash "$tmp")
    if [[ -n "${SEEN[$h]:-}" ]]; then
      rm -f "$tmp"
      continue
    fi
    SEEN[$h]=1
    created=$((created+1))
    OUT="$OUTDIR/${app}_profile_mix_${created}.csv"
    mv "$tmp" "$OUT"
    echo "[gen] wrote $OUT (rows=$K: [${idx[*]}])"
  done
  if (( created < M )); then
    echo "[gen] note: produced only $created / $M unique random combos (exhausted search)."
  fi
fi

echo "[gen] done."
