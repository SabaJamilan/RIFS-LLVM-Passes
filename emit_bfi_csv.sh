#!/usr/bin/env bash
set -euo pipefail

# Usage: emit_bfi_csv.sh /path/to/opt /path/to/IR.ll /out/dir
OPT_BIN="${1:?need /path/to/opt}"
IR="${2:?need /path/to/IR.ll}"
OUTDIR="${3:?need /out/dir}"

if [[ ! -x "$OPT_BIN" ]]; then
  echo "[bfi] ERROR: opt not executable: $OPT_BIN" >&2; exit 1
fi
if [[ ! -f "$IR" ]]; then
  echo "[bfi] ERROR: IR not found: $IR" >&2; exit 1
fi

base="$(basename "$IR")"
stem="${base%.*}"
mkdir -p "$OUTDIR/bfi"
OUT_CSV="$OUTDIR/bfi/${stem}.bfi.csv"

echo "[bfi] opt : $OPT_BIN"
echo "[bfi] ir  : $IR"
echo "[bfi] out : $OUT_CSV"

RAW="$(mktemp -t bfi_raw_XXXX.log)"

# Some LLVM builds print to stderr; capture BOTH.
if ! "$OPT_BIN" -passes='print<block-freq>' -disable-output "$IR" &> "$RAW"; then
  echo "[bfi] ERROR: opt failed. Showing first 40 lines" >&2
  sed -n '1,40p' "$RAW" | sed 's/^/  | /' >&2
  exit 1
fi

awk -v OFS=',' '
function strip_bar(s){ sub(/^[ \t]*\|[ \t]*/, "", s); return s }
function ltrim(s){ sub(/^[ \t]+/,"",s); return s }
function rtrim(s){ sub(/[ \t]+$/,"",s); return s }

BEGIN{
  print "Function","BB","Weight","FreqInt","Count"
  fn=""; entry_int=0; entry_w=0.0
}

{
  line=$0
  line=strip_bar(line)
}

# Header style 1: Printing analysis results of BFI for function 'NAME':
index(line, "Printing analysis results of BFI for function") {
  # extract between first pair of single quotes
  q1 = index(line, "'\''")
  if (q1 > 0) {
    rest = substr(line, q1+1)
    q2 = index(rest, "'\''")
    if (q2 > 0) fn = substr(rest, 1, q2-1)
  }
  entry_int=0; entry_w=0.0
  next
}

# Header style 2: block-frequency-info: NAME
line ~ /^[ \t]*block-frequency-info:[ \t]+/ {
  tmp=line
  sub(/^[ \t]*block-frequency-info:[ \t]+/, "", tmp)
  sub(/[ \t:,]+$/, "", tmp)
  fn=tmp
  entry_int=0; entry_w=0.0
  next
}

# Data lines:  - label: float = X, int = Y, count = Z
(fn != "") && (line ~ /^[ \t-]*-[ \t]*[A-Za-z0-9_.-]+[ \t]*:/) {
  tmp=line
  sub(/^[ \t-]*-[ \t]*/, "", tmp)
  lbl=tmp
  sub(/:.*/, "", lbl)
  lbl=rtrim(ltrim(lbl))

  have_w = match(line, /float[ \t]*=[ \t]*([-+0-9.eE]+)/, mw)
  have_i = match(line, /int[ \t]*=[ \t]*([0-9]+)/, mi)
  have_c = match(line, /count[ \t]*=[ \t]*([0-9]+)/, mc)

  w  = (have_w ? mw[1] : "")
  ii = (have_i ? mi[1] : "")
  cc = (have_c ? mc[1] : "")

  # Remember entry block scalars for fallback normalization
  if (lbl=="entry") {
    if (have_i) entry_int = ii + 0
    if (have_w) entry_w = w + 0.0
  }

  # Compute weight:
  # Prefer printed float; otherwise normalize int by entry_int if available.
  if (w == "" || w == 0) {
    if (have_i && entry_int > 0) {
      w = (ii + 0.0) / entry_int
    } else if (lbl=="entry") {
      w = 1.0
    } else {
      w = 0.0
    }
  }

  # Emit row
  print fn, lbl, sprintf("%.6f", w), (ii==""?0:ii), (cc==""?0:cc)
  next
}
' "$RAW" > "$OUT_CSV"

rows=$(( $(wc -l < "$OUT_CSV") - 1 ))
if (( rows <= 0 )); then
  echo "[bfi] WARNING: parsed 0 rows. First 120 lines of combined opt output for debugging:" >&2
  sed -n '1,120p' "$RAW" | sed 's/^/  | /' >&2
else
  echo "[bfi] wrote $rows rows -> $OUT_CSV"
fi
