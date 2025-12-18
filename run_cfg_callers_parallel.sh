#!/usr/bin/env bash

# Usage:
#   ./run_cfg_callers_parallel.sh \
#     --baseline  /abs/path/to/baseline.ll \
#     --opt-dir   OPT_IRs_O3_dir \
#     --manifest  output_res_dir/manifest_callees.csv \
#     --out       output_res_dir \
#     --compare   /abs/path/to/compare_cfgs.py \
#     [--parallel 8]
#
# Manifest header (exact):
#   baselineIR,optimizedIR,fn_caller,fn_callee_base,fn_callee_opt,arg_index

BASELINE=""; OPT_DIR=""; MANIFEST=""; OUT_DIR=""; COMPARE_CFGS_PY=""
PARALLEL=8

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2;;
    --opt-dir)  OPT_DIR="$2"; shift 2;;
    --manifest) MANIFEST="$2"; shift 2;;
    --out)      OUT_DIR="$2"; shift 2;;
    --compare)  COMPARE_CFGS_PY="$2"; shift 2;;
    --parallel) PARALLEL="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -f "${BASELINE:-}"        ]] || { echo "[caller-cfg] ERROR: --baseline not found"; exit 1; }
[[ -d "${OPT_DIR:-}"         ]] || { echo "[caller-cfg] ERROR: --opt-dir not a dir"; exit 1; }
[[ -f "${MANIFEST:-}"        ]] || { echo "[caller-cfg] ERROR: --manifest not found"; exit 1; }
[[ -n "${OUT_DIR:-}"         ]] || { echo "[caller-cfg] ERROR: --out required"; exit 1; }
[[ -f "${COMPARE_CFGS_PY:-}" ]] || { echo "[caller-cfg] ERROR: --compare not found"; exit 1; }
(( PARALLEL >= 1 )) || PARALLEL=1

mkdir -p "$OUT_DIR/cfg_callers" "$OUT_DIR/logs" "$OUT_DIR/bfi"

# ---------- IR → DOT (no opt dependency) ----------
_emit_cfg_dot_from_ir() {
  local IR="$1" FN="$2" OUT="$3"
  awk -v FN="$FN" '
    BEGIN{infn=0;depth=0;curbb=""}
    function addN(n){ if(n!=""){N[n]=1} }
    function addE(a,b){ if(a!="" && b!=""){E[a SUBSEP b]=1} }
    $0 ~ ("define[ \t].*@" FN "\\(") && /\{/ {
      infn=1; curbb="";
      oc=gsub(/\{/,"{"); cc=gsub(/\}/,"}"); depth+=oc-cc; next
    }
    !infn{next}
    { oc=gsub(/\{/,"{"); cc=gsub(/\}/,"}"); depth+=oc-cc; if (depth<=0){infn=0; next} }
    /^[ \t]*[A-Za-z0-9_.-]+:[ \t]*($|;)/ {
      match($0,/^[ \t]*([A-Za-z0-9_.-]+):/,m); curbb=m[1]; addN(curbb); next
    }
    {
      line=$0; sub(/;.*$/,"",line)
      if (curbb=="" && line ~ /[^ \t]/) {curbb="entry"; addN(curbb)}
      if (match(line,/(^|[^A-Za-z0-9_])br[ \t]+label[ \t]+%([A-Za-z0-9_.-]+)/,m1)){addE(curbb,m1[2]); next}
      if (match(line,/(^|[^A-Za-z0-9_])br[ \t]+i1[ \t]+%[A-Za-z0-9_.-][^,]*,[ \t]*label[ \t]+%([A-Za-z0-9_.-]+)[ \t]*,[ \t]*label[ \t]+%([A-Za-z0-9_.-]+)/,m2)){addE(curbb,m2[2]); addE(curbb,m2[3]); next}
      if (match(line,/(^|[^A-Za-z0-9_])switch[ \t]+[A-Za-z0-9_ *]+,[ \t]*label[ \t]+%([A-Za-z0-9_.-]+)/,ms)){
        defl=ms[2]; addE(curbb,defl); buf=line
        while (buf !~ /\]/ && (getline more)>0){sub(/;.*$/,"",more); buf=buf "\n" more}
        while (match(buf,/label[ \t]+%([A-Za-z0-9_.-]+)/,mm)){addE(curbb,mm[1]); buf=substr(buf,RSTART+RLENGTH)}
        next
      }
      if (match(line,/(^|[^A-Za-z0-9_])indirectbr[ \t]+[^,]+,[ \t]*\[/,mi)){
        buf=line
        while (buf !~ /\]/ && (getline more2)>0){sub(/;.*$/,"",more2); buf=buf "\n" more2}
        while (match(buf,/label[ \t]+%([A-Za-z0-9_.-]+)/,mm2)){addE(curbb,mm2[1]); buf=substr(buf,RSTART+RLENGTH)}
        next
      }
    }
    END{
      print "digraph \"" FN "\" {"
      print "  node [shape=box];"
      for(n in N) print "  \"" n "\";"
      for(k in E){ split(k,a,SUBSEP); print "  \"" a[1] "\" -> \"" a[2] "\";" }
      print "}"
    }
  ' "$IR" > "$OUT"
  [[ -s "$OUT" ]]
}

_trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ; }

# ---------- Build unique (optimizedIR, fn_caller) worklist ----------
mapfile -t TASKS < <(
  awk -F',' '
    NR==1 { next }  # skip header
    {
      for (i=1;i<=6;i++){ gsub(/^[ \t]+|[ \t]+$/,"",$i) }
      # need optimizedIR (2) and fn_caller (3)
      if ($2!="" && $3!="") {
        k=$2 "\t" $3
        if (!seen[k]++) print k
      }
    }
  ' "$MANIFEST"
)
echo "[caller-cfg] tasks: ${#TASKS[@]} (deduplicated)"

# ---------- Simple semaphore ----------
sem_open()  { local n="$1" f; f="$(mktemp -u)"; mkfifo "$f"; exec 9<>"$f"; rm -f "$f"; for ((i=0;i<n;i++)); do printf . >&9; done; }
sem_take()  { read -r -u 9 -n 1 _t; }
sem_give()  { printf . >&9; }
sem_close() { exec 9>&- 9<&-; }

sem_open "$PARALLEL"

fail=0
for row in "${TASKS[@]}"; do
  sem_take
  {
    IFS=$'\t' read -r optimizedIR fn_caller <<< "$row"

    opt_path="$OPT_DIR/$optimizedIR"
    if [[ ! -f "$opt_path" ]]; then
      echo "[caller-cfg] WARN: missing opt IR $opt_path" >&2
      sem_give; exit 0
    fi

    opt_stem="${optimizedIR%.*}"
    out_sub="$OUT_DIR/cfg_callers/$opt_stem"
    mkdir -p "$out_sub"

    base_dot="$out_sub/${fn_caller}.cfg.baseline.dot"
    after_dot="$out_sub/${fn_caller}.cfg.after.dot"

    if ! _emit_cfg_dot_from_ir "$BASELINE" "$fn_caller" "$base_dot"; then
      echo "[caller-cfg] WARN: baseline DOT failed for $fn_caller" >&2
      sem_give; exit 0
    fi
    if ! _emit_cfg_dot_from_ir "$opt_path" "$fn_caller" "$after_dot"; then
      echo "[caller-cfg] WARN: after DOT failed for $fn_caller in $optimizedIR" >&2
      sem_give; exit 0
    fi

    BFI_BASE_CSV="$OUT_DIR/bfi/$(basename "${BASELINE%.*}").bfi.csv"
    BFI_AFTER_CSV="$OUT_DIR/bfi/${opt_stem}.bfi.csv"

    out_csv="$out_sub/${fn_caller}.cfg_summary.csv"
    logf="$OUT_DIR/logs/${opt_stem}__caller__${fn_caller}.log"

    echo "[caller-cfg] compare caller=$fn_caller optIR=$optimizedIR"

    if [[ -f "$BFI_BASE_CSV" && -f "$BFI_AFTER_CSV" ]]; then
      python3 "$COMPARE_CFGS_PY" \
        --baseline-dot "$base_dot" \
        --after-dot    "$after_dot" \
        --fn-name      "$fn_caller" \
        --out-csv      "$out_csv" \
        --bfi-base-csv "$BFI_BASE_CSV" \
        --bfi-after-csv "$BFI_AFTER_CSV" \
        > "$logf" 2>&1 || echo "[caller-cfg] WARN: compare_cfgs failed for $fn_caller ($optimizedIR)"
    else
      python3 "$COMPARE_CFGS_PY" \
        --baseline-dot "$base_dot" \
        --after-dot    "$after_dot" \
        --fn-name      "$fn_caller" \
        --out-csv      "$out_csv" \
        > "$logf" 2>&1 || echo "[caller-cfg] WARN: compare_cfgs failed for $fn_caller ($optimizedIR)"
    fi

    sem_give
  } &
done

set +e
wait
rc=$?
set -e
sem_close

(( rc == 0 )) || echo "[caller-cfg] NOTE: some tasks reported warnings/failures (see logs)."
echo "[caller-cfg] done (caller summaries in $OUT_DIR/cfg_callers)"
