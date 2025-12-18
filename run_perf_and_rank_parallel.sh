#!/usr/bin/env bash

# Run perf stat for baseline + all optimized binaries from a build manifest,
# compute runtime improvements over baseline, and write rankings (elapsed + user).
#
# Usage:
#   ./run_perf_and_rank.sh \
#     --bin-dir bin_out \
#     --manifest bin_out/build_bins_manifest.csv \
#     --input "/abs/path/to/input/file/or/args" \
#     [--events "<perf events...>"] \
#     [--runs 3] \
#     [--taskset "1"] \
#     [--rank-by elapsed|user] \
#     [--out bin_out/perf_runs]
#
# Manifest header (CSV):
#   bin_name,ir_name,type
#
# Notes:
# - We parse the *last* occurrence of the lines:
#       "seconds time elapsed"
#       "seconds user"
#   which is the aggregate when -r is used. LC_ALL=C enforced for stability.

BIN_DIR=""
MANIFEST=""
INPUT_ARGS=""
EVENTS=""
RUNS=3
TASKSET_CORES="1"
RANK_BY="elapsed"
OUT_DIR=""
PARALLEL=1
CPU_LIST=""          # NEW: pin each job to its own CPU when parallel

DEFAULT_EVENTS=(
  L1-dcache-loads
  L1-dcache-load-misses
  LLC-loads
  LLC-load-misses
  br_inst_retired.all_branches
  baclears.any
  br_misp_retired.all_branches
  instructions
  cycles
  task-clock
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin-dir)   BIN_DIR="$2"; shift 2;;
    --manifest)  MANIFEST="$2"; shift 2;;
    --input)     INPUT_ARGS="$2"; shift 2;;
    --events)    EVENTS="$2"; shift 2;;
    --runs)      RUNS="$2"; shift 2;;
    --taskset)   TASKSET_CORES="$2"; shift 2;;
    --rank-by)   RANK_BY="$2"; shift 2;;
    --out)       OUT_DIR="$2"; shift 2;;
    --parallel)  PARALLEL="$2"; shift 2;;
    --cpu-list)  CPU_LIST="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -d "${BIN_DIR:-}"    ]] || { echo "[perf] ERROR: --bin-dir not a dir"; exit 1; }
[[ -f "${MANIFEST:-}"   ]] || { echo "[perf] ERROR: --manifest not found"; exit 1; }
[[ "$RANK_BY" == "elapsed" || "$RANK_BY" == "user" ]] || { echo "[perf] ERROR: --rank-by must be 'elapsed' or 'user'"; exit 1; }
[[ -n "${OUT_DIR:-}"    ]] || OUT_DIR="$BIN_DIR/perf_runs"
mkdir -p "$OUT_DIR/logs"

# Build events string
if [[ -z "${EVENTS:-}" ]]; then
  EVENTS_STR=""
  for e in "${DEFAULT_EVENTS[@]}"; do EVENTS_STR+=" -e $e"; done
else
  EVENTS_STR="$EVENTS"
  if [[ "$EVENTS_STR" != *"-e"* ]]; then
    TMP=""
    for e in $EVENTS_STR; do TMP+=" -e $e"; done
    EVENTS_STR="$TMP"
  fi
fi

_trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ; }

mapfile -t ROWS < <(tail -n +2 "$MANIFEST")

BASE_BIN=""
declare -a OPT_BINS=()
declare -A TYPE_OF
for row in "${ROWS[@]}"; do
  IFS=, read -r bin_name ir_name type <<< "$row"
  bin_name="$(printf '%s' "$bin_name" | _trim)"
  ir_name="$(printf '%s' "$ir_name" | _trim)"
  type="$(printf '%s' "$type" | _trim)"
  [[ -z "$bin_name" ]] && continue
  full="$BIN_DIR/$bin_name"
  [[ -x "$full" ]] || { echo "[perf] WARN: not executable: $full"; continue; }
  TYPE_OF["$full"]="$type"
  if [[ "$type" == "baseline" ]]; then
    BASE_BIN="$full"
  else
    OPT_BINS+=("$full")
  fi
done

[[ -n "${BASE_BIN:-}" ]] || { echo "[perf] ERROR: baseline row not found in manifest"; exit 1; }

echo "[perf] Baseline: $BASE_BIN"
echo "[perf] Optimized: ${#OPT_BINS[@]} binaries"
echo "[perf] Events: $EVENTS_STR"
echo "[perf] Runs: $RUNS"
echo "[perf] Taskset cores base: $TASKSET_CORES"
echo "[perf] Rank-by: $RANK_BY"
echo "[perf] Input args: ${INPUT_ARGS:-<none>}"
echo


run_perf_one_new() {
  local BIN="$1"
  local CORE="$2"   # e.g., "7" or "0,2"
  local STEM="${BIN##*/}"
  local OUT_TXT="$OUT_DIR/${STEM}-perf-stats.txt"

  LC_ALL=C taskset -c "$CORE" \
      perf stat -r "$RUNS" $EVENTS_STR \
      -x, -o "$OUT_TXT" --no-big-num -- \
      "$BIN" ${INPUT_ARGS:-} >/dev/null 2>&1 || true

  # Parse aggregate wall and user times from CSV
  # CSV columns: <value>,<unit>,<name>,<run>,...
  local ELAPSED="NA" USERSEC="NA"
  ELAPSED="$(awk -F, '$3=="duration_time"{v=$1} END{print (v=="")?"NA":v}' "$OUT_TXT")"
  USERSEC="$(awk -F,   '$3=="user_time"    {v=$1} END{print (v=="")?"NA":v}' "$OUT_TXT")"

  # Fallback: if user_time missing, use task-clock (msec) / 1000
  if [[ "$USERSEC" == "NA" ]]; then
    USERSEC="$(awk -F, '$3=="task-clock"{v=$1/1000} END{print (v=="")?"NA":v}' "$OUT_TXT")"
  fi

  printf '%s,%s' "$ELAPSED" "$USERSEC"
}





run_perf_one() {
  local BIN="$1"
  local CORE="$2"   # e.g., "7" or "0,2"
  local STEM="${BIN##*/}"
  local OUT_TXT="$OUT_DIR/${STEM}-perf-stats.txt"

  LC_ALL=C taskset -c "$CORE" \
    perf stat -r "$RUNS" $EVENTS_STR -o "$OUT_TXT" --no-big-num -- \
      "$BIN" ${INPUT_ARGS:-} >/dev/null 2>&1 || true

  # Extract last 'seconds time elapsed' and 'seconds user'
  local ELAPSED="NA" USERSEC="NA" INSTR="NA"
  if grep -q "seconds time elapsed" "$OUT_TXT"; then
    ELAPSED="$(awk '/seconds time elapsed/ {t=$1} END{if(t=="") t="NA"; print t}' "$OUT_TXT")"
  fi
  if grep -q "seconds user" "$OUT_TXT"; then
    USERSEC="$(awk '/seconds user/ {t=$1} END{if(t=="") t="NA"; print t}' "$OUT_TXT")"
  fi
  # instructions line looks like: "<count>  instructions  # ..."; grab field 1 from the last match
  if grep -qE '[[:digit:]]+[[:space:]]+instructions(\>|[[:space:]#])' "$OUT_TXT" 2>/dev/null; then
    INSTR="$(awk '/[[:space:]]instructions([[:space:]#]|$)/ {v=$1} END{print (v=="")?"NA":v}' "$OUT_TXT")"
  else
    # generic fallback: last line containing ' instructions'
    INSTR="$(awk '/instructions/ {v=$1} END{print (v=="")?"NA":v}' "$OUT_TXT")"
  fi
  
  printf '%s,%s,%s' "$ELAPSED" "$USERSEC" "$INSTR"
}

BASE_TIMES="$(run_perf_one "$BASE_BIN" "$TASKSET_CORES")"
#BASE_TIMES="$(run_perf_one_new "$BASE_BIN" "$TASKSET_CORES")"
BASE_T="$(printf '%s' "$BASE_TIMES" | cut -d, -f1)"
BASE_U="$(printf '%s' "$BASE_TIMES" | cut -d, -f2)"
Instr="$(printf '%s' "$BASE_TIMES" | cut -d, -f3)"

if [[ "$BASE_T" == "NA" || "$BASE_U" == "NA" ]]; then
  echo "[perf] ERROR: could not parse baseline elapsed/user time. See: $OUT_DIR/$(basename "$BASE_BIN")-perf-stats.txt" >&2
  exit 1
fi

echo "[perf] Baseline elapsed: $BASE_T s"
echo "[perf] Baseline user   : $BASE_U s"

RESULTS_CSV="$OUT_DIR/perf_results.csv"
#echo "bin_name,ir_name,type,elapsed_s,user_s,improvement_elapsed_pct,speedup_elapsed,improvement_user_pct,speedup_user" > "$RESULTS_CSV"
echo "bin_name,ir_name,type,elapsed_s,user_s,instructions" > "$RESULTS_CSV"

# Baseline row
#echo "$(basename "$BASE_BIN"),$(basename "$BASE_BIN"),baseline,$BASE_T,$BASE_U,0.0,1.0,0.0,1.0" >> "$RESULTS_CSV"
echo "$(basename "$BASE_BIN"),$(basename "$BASE_BIN"),baseline,$BASE_T,$BASE_U,$Instr" >> "$RESULTS_CSV"

# before the loop: build a CPU list (or leave empty if PARALLEL<=1)
# (works with set -u)
declare -a CPU_LIST=()

if (( PARALLEL > 1 )); then
  if [[ -n "${CPU_LIST_SPEC:-}" ]]; then
    # expand "0-3,6,8-9" to an array
    IFS=',' read -r -a _parts <<< "$CPU_LIST_SPEC"
    for part in "${_parts[@]}"; do
      if [[ "$part" == *-* ]]; then
        IFS='-' read -r a b <<< "$part"
        for ((i=a; i<=b; i++)); do CPU_LIST+=("$i"); done
      else
        CPU_LIST+=("$part")
      fi
    done
  else
    # default: first PARALLEL online CPUs
    online=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
    for ((i=0; i<online && i<PARALLEL; i++)); do CPU_LIST+=("$i"); done
  fi
fi



#echo "PARALLEL=$PARALLEL"
#echo "Built CPU_LIST (${#CPU_LIST[@]}): ${CPU_LIST[*]}"
#for i in "${!CPU_LIST[@]}"; do echo "  [$i]=${CPU_LIST[$i]}"; done
#for i in "${!OPT_BINS[@]}"; do
 # printf 'OPT_BINS[%d]=%s\n' "$i" "${OPT_BINS[$i]}"
#done


OPT_BINS=("$BASE_BIN" "${OPT_BINS[@]}")

# Optimized rows
job_count=0
idx_core=0
if [ -d "$BIN_DIR" ]; then
  for BIN in "${OPT_BINS[@]}"; do
    (
       echo "OPT BIN: " $BIN
       STEM="$(basename "$BIN")"
       echo "  STEM: " $STEM
       # pick a core safely (or empty when not pinning)
       CORE="${CPU_LIST[$(( idx_core % ${#CPU_LIST[@]} ))]}"
    
       echo "CORE: " $CORE
       TIMES="$(run_perf_one "$BIN" "$CORE")"
       #TIMES="$(run_perf_one_new "$BIN" "$CORE")"
       T="$(printf '%s' "$TIMES" | cut -d, -f1)"
       U="$(printf '%s' "$TIMES" | cut -d, -f2)"
       I="$(printf '%s' "$TIMES" | cut -d, -f3)"
       if [[ "$T" == "NA" || "$U" == "NA" ]]; then
         echo "[perf] WARN: cannot parse elapsed/user for $STEM (see $OUT_DIR/${STEM}-perf-stats.txt)"
         continue
       fi

       imp_t=$(awk -v b="$BASE_T" -v t="$T" 'BEGIN{ if(t<=0||b<=0) print 0.0; else printf("%.6f", (b-t)/b*100.0) }')
       spd_t=$(awk -v b="$BASE_T" -v t="$T" 'BEGIN{ if(t<=0) print 0.0; else printf("%.6f", b/t) }')
       imp_u=$(awk -v b="$BASE_U" -v u="$U" 'BEGIN{ if(u<=0||b<=0) print 0.0; else printf("%.6f", (b-u)/b*100.0) }')
       spd_u=$(awk -v b="$BASE_U" -v u="$U" 'BEGIN{ if(u<=0) print 0.0; else printf("%.6f", b/u) }')
    #   echo "$STEM,$STEM,optimized,$T,$U,$imp_t,$spd_t,$imp_u,$spd_u" >> "$RESULTS_CSV"
       echo "$STEM,$STEM,optimized,$T,$U,$I" >> "$RESULTS_CSV"
    ) &
    
    ((job_count++))
    ((idx_core++))
  
    if (( job_count >= PARALLEL )); then
      wait  
      job_count=0
    fi
  done
  wait
  else
    echo "Directory '$BIN_DIR' does not exist!"
fi


# Rankings
RANK_ELAPSED_TXT="$OUT_DIR/ranking_by_elapsed.txt"
RANK_USER_TXT="$OUT_DIR/ranking_by_user.txt"

# Elapsed ranking
{
  echo "# Ranked by improvement (elapsed) over baseline (higher is better)"
  echo "# rank, optimizedIR_Name, BenefitScoreElapsed(%), speedupElapsed, elapsed_s"
  awk -F',' 'NR>1 && $3=="optimized" {print $2","$6","$7","$4}' "$RESULTS_CSV" \
    | sort -t',' -k2,2nr \
    | nl -w2 -s'. ' \
    | awk -F'[ \t]*[.] ' '{
        rank=$1; rest=$2; split(rest,a,",");
        printf("%2d. %s  BenefitScoreElapsed=%.3f%%  speedup=%.3fx  elapsed=%ss\n",
               rank, a[1], a[2], a[3], a[4]);
      }'
} > "$RANK_ELAPSED_TXT"

# User ranking
{
  echo "# Ranked by improvement (user) over baseline (higher is better)"
  echo "# rank, optimizedIR_Name, BenefitScoreUser(%), speedupUser, user_s"
  awk -F',' 'NR>1 && $3=="optimized" {print $2","$8","$9","$5}' "$RESULTS_CSV" \
    | sort -t',' -k2,2nr \
    | nl -w2 -s'. ' \
    | awk -F'[ \t]*[.] ' '{
        rank=$1; rest=$2; split(rest,a,",");
        printf("%2d. %s  BenefitScoreUser=%.3f%%  speedup=%.3fx  user=%ss\n",
               rank, a[1], a[2], a[3], a[4]);
      }'
} > "$RANK_USER_TXT"

# Preferred ranking symlink/copy
if [[ "$RANK_BY" == "user" ]]; then
  cp -f "$RANK_USER_TXT" "$OUT_DIR/ranking.txt"
else
  cp -f "$RANK_ELAPSED_TXT" "$OUT_DIR/ranking.txt"
fi

echo
echo "[perf] Results:"
echo "  CSV               : $RESULTS_CSV"
echo "  Rank (elapsed)    : $RANK_ELAPSED_TXT"
echo "  Rank (user)       : $RANK_USER_TXT"
echo "  Rank (preferred)  : $OUT_DIR/ranking.txt  (by $RANK_BY)"
echo
echo "[perf] Done."


