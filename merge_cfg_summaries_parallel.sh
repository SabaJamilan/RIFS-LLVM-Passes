#!/usr/bin/env bash

# Merge per-opt CFG summaries (callers + callees) into tidy CSVs, in parallel.
#
# Usage:
#   ./merge_cfg_summaries_parallel.sh --out output_res_dir [--parallel 8]
#
# Expected layout:
#   $OUT/cfg_callees/<OptIR>/*.cfg_summary.csv
#   $OUT/cfg_callers/<OptIR>/*.cfg_summary.csv   (optional)
#
# Writes:
#   $OUT/cfg_merged/cfg_summary_callees_merged.csv
#   $OUT/cfg_merged/cfg_summary_callers_merged.csv
#   $OUT/cfg_merged/cfg_summary_all.csv

OUT_DIR=""
PARALLEL=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)      OUT_DIR="$2"; shift 2;;
    --parallel) PARALLEL="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "${OUT_DIR:-}" ]] || { echo "[merge] ERROR: --out required"; exit 1; }
(( PARALLEL >= 1 )) || PARALLEL=1

CALLEES_ROOT="$OUT_DIR/cfg_callees"
CALLERS_ROOT="$OUT_DIR/cfg_callers"
OUT_MERGE_DIR="$OUT_DIR/cfg_merged"
mkdir -p "$OUT_MERGE_DIR"

MERGED_CALLEES="$OUT_MERGE_DIR/cfg_summary_callees_merged.csv"
MERGED_CALLERS="$OUT_MERGE_DIR/cfg_summary_callers_merged.csv"
MERGED_ALL="$OUT_MERGE_DIR/cfg_summary_all.csv"

_trim(){ sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ; }

write_block_parallel () {
  # $1 = ROLE  ("callee" or "caller")
  # $2 = ROOT  (e.g., OUT_DIR/cfg_callees or cfg_callers)
  # $3 = OUTFILE
  # $4 = PARALLEL
  local ROLE="$1" ROOT="$2" OUTFILE="$3" P="$4"

  [[ -d "$ROOT" ]] || { echo "[merge] NOTE: dir missing: $ROOT"; : > "$OUTFILE"; return; }

  # Collect CSVs (sorted for deterministic order)
  mapfile -t CSVS < <(find "$ROOT" -type f -name '*.cfg_summary.csv' | sort)
  echo "csv count: ${#CSVS[@]}"

  if (( ${#CSVS[@]} == 0 )); then
    # Sensible empty header
    echo "OptIR,Role,Function,V_base,E_base,V_after,E_after,dV,dE,avg_out_base,avg_out_after,density_base,density_after,maxW_base,meanW_base,ge75_base,ge50_base,ge25_base,maxW_after,meanW_after,ge75_after,ge50_after,ge25_after" > "$OUTFILE"
    return
  fi

  # Header from first file
  local header; header="$(head -n1 "${CSVS[0]}")"
  echo "OptIR,Role,$header" > "$OUTFILE"

  # Temp parts dir for parallel bodies
  local PARTS; PARTS="$(mktemp -d "${OUTFILE}.parts.XXXXXXXX")"
  # Clean up parts on exit
  trap 'rm -rf "$PARTS"' EXIT

  local i job_count=0
  for i in "${!CSVS[@]}"; do
    (
      csv="${CSVS[$i]}"
      # OptIR name = first directory under ROOT; fallback to file stem
      rel="${csv#$ROOT/}"
      optdir="${rel%%/*}"
      if [[ "$optdir" == "$rel" ]]; then
        filebase="$(basename "$csv")"
        optdir="${filebase%.cfg_summary.csv}"
      fi
      optdir="$(_trim <<<"$optdir")"

      # Write body lines with prefixed columns into a numbered .part
      # Number to preserve stable order without sorting the whole output.
      printf -v idx "%06d" "$i"
      tail -n +2 "$csv" \
        | awk -v O="$optdir" -v R="$ROLE" 'BEGIN{FS=OFS=","} {print O,R,$0}' \
        > "$PARTS/${idx}__$(basename "$csv").part"
    ) &
    ((job_count++))
    if (( job_count >= P )); then
      wait
      job_count=0
    fi
  done
  wait

  # Concatenate in the same deterministic order
  # (the files are already numbered 000000.. so 'ls' is fine)
  #if compgen -G "$PARTS/"'*.part' > /dev/null; then
   # cat "$PARTS/"*.part >> "$OUTFILE"
  #fi
  # Concatenate robustly (avoid ARG_MAX), preserving numeric order
  if compgen -G "$PARTS/"'*.part' > /dev/null; then
    LC_ALL=C printf '%s\0' "$PARTS/"*.part \
      | sort -z \
      | while IFS= read -r -d '' f; do
          cat "$f" >> "$OUTFILE"
        done
  fi
}

# Build role-specific merged files (parallel)
write_block_parallel "callee" "$CALLEES_ROOT" "$MERGED_CALLEES" "$PARALLEL"
if [[ -d "$CALLERS_ROOT" ]]; then
  write_block_parallel "caller" "$CALLERS_ROOT" "$MERGED_CALLERS" "$PARALLEL"
else
  echo "[merge] NOTE: callers root missing: $CALLERS_ROOT"
  echo "OptIR,Role,Function,V_base,E_base,V_after,E_after,dV,dE,avg_out_base,avg_out_after,density_base,density_after,maxW_base,meanW_base,ge75_base,ge50_base,ge25_base,maxW_after,meanW_after,ge75_after,ge50_after,ge25_after" > "$MERGED_CALLERS"
fi

# Join into ALL
if [[ -s "$MERGED_CALLEES" && -s "$MERGED_CALLERS" ]]; then
  head -n1 "$MERGED_CALLEES" > "$MERGED_ALL"
  tail -n +2 "$MERGED_CALLEES" >> "$MERGED_ALL"
  tail -n +2 "$MERGED_CALLERS" >> "$MERGED_ALL"
elif [[ -s "$MERGED_CALLEES" ]]; then
  cp -f "$MERGED_CALLEES" "$MERGED_ALL"
else
  cp -f "$MERGED_CALLERS" "$MERGED_ALL"
fi

# Stats
rows_callees=$(( $(wc -l < "$MERGED_CALLEES") - 1 ))
rows_callers=$(( $(wc -l < "$MERGED_CALLERS") - 1 ))
rows_all=$(( $(wc -l < "$MERGED_ALL") - 1 ))

echo "[merge] wrote:"
echo "  $MERGED_CALLEES  (rows: $rows_callees)"
echo "  $MERGED_CALLERS  (rows: $rows_callers)"
echo "  $MERGED_ALL      (rows: $rows_all)"
