#!/usr/bin/env bash
set -euo pipefail

# --- defaults (CLI can override) ---
baseline="mcf_r_base.mytest-m64_baseline_O3_PGO.ll"
opt_irs_dir="OPT_IRs_O3_dir"
profiles_dir="candidate_profiles_dir"
out_dir="output_res_dir"
PARALLEL="${PARALLEL:-8}"   # set via env or leave default

# Optional CLI overrides: ./build_manifest_with_callers.sh [baseline] [opt_irs_dir] [profiles_dir] [out_dir] [parallel]
if [[ $# -ge 1 ]]; then baseline="$1"; fi
if [[ $# -ge 2 ]]; then opt_irs_dir="$2"; fi
if [[ $# -ge 3 ]]; then profiles_dir="$3"; fi
if [[ $# -ge 4 ]]; then out_dir="$4"; fi
if [[ $# -ge 5 ]]; then PARALLEL="$5"; fi

mkdir -p "$out_dir/parts"
out_csv="$out_dir/manifest_funcs_with_callers.csv"
tmp_header="$out_dir/.header.$$"
echo "baselineIR,optimizedIR,fn_caller,fn_callee_base,fn_callee_opt,arg_index" > "$tmp_header"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Grep function names from .ll (or auto-disassemble .bc if llvm-dis exists).
list_functions() {
  local ir="$1"
  if [[ "$ir" == *.bc && -x "$(command -v llvm-dis)" ]]; then
    local tmp="${ir%.bc}.ll"
    if [[ ! -f "$tmp" ]]; then llvm-dis -o "$tmp" "$ir" >/dev/null 2>&1 || true; fi
    ir="$tmp"
  fi
  # unique, sorted list of function names
  grep -Eo 'define[[:space:]][^{]*@[[:alnum:]_.$-]+' "$ir" \
    | sed 's/.*@//' | sed 's/[[:space:]]*$//' | sort -u
}

# Find the optimized IR file for a given profile stem
ir_for_profile() {
  local stem="$1" optdir="$2"
  local cand_ll="$optdir/${stem}.ll"
  local cand_bc="$optdir/${stem}.bc"
  if [[ -f "$cand_ll" ]]; then echo "$cand_ll"; return 0; fi
  if [[ -f "$cand_bc" ]]; then echo "$cand_bc"; return 0; fi
  local m; m=$(ls -t "$optdir"/*"$stem"* 2>/dev/null | head -n1 || true)
  [[ -n "$m" ]] && { echo "$m"; return 0; }
  return 1
}

# Choose specialized name for (callee, arg_index) from a list
choose_specialized_name() {
  local callee="$1"; local arg_index="$2"; shift 2
  local -a fnlist=( "$@" )
  local -a candidates=()

  for f in "${fnlist[@]}"; do
    [[ "$f" =~ ^${callee}.*(clone|special|arg) ]] || continue
    candidates+=( "$f" )
  done
  ((${#candidates[@]})) || return 1

  local -a arghits=()
  local pat="(^|[._-])arg${arg_index}([._-]|$)"
  for f in "${candidates[@]}"; do
    if [[ "$f" =~ $pat ]]; then arghits+=( "$f" ); fi
  done
  if ((${#arghits[@]})); then candidates=( "${arghits[@]}" ); fi

  local best="${candidates[0]}"
  for f in "${candidates[@]}"; do
    (( ${#f} > ${#best} )) && best="$f"
  done
  printf '%s' "$best"
}

base_name="$(basename "$baseline")"
shopt -s nullglob
mapfile -t PROFILES < <(printf '%s\n' "$profiles_dir"/*.csv)

# ---- simple semaphore using FD 9 ----
sem_open()  { local n="$1"; local fifo; fifo="$(mktemp -u)"; mkfifo "$fifo"; exec 9<>"$fifo"; rm -f "$fifo"; for ((_i=0; _i<n; _i++)); do printf . >&9; done; }
sem_take()  { read -r -u 9 -n 1 _tok; }
sem_give()  { printf . >&9; }
sem_close() { exec 9>&- 9<&-; }

# Open with PARALLEL tokens
(( PARALLEL < 1 )) && PARALLEL=1
sem_open "$PARALLEL"

# ---- launch one job per profile (up to PARALLEL at a time) ----
for prof in "${PROFILES[@]}"; do
  stem="$(basename "${prof%.csv}")"
  sem_take
  {
    # Each job writes to its own part
    part="$out_dir/parts/${stem}.part"
    : > "$part"  # truncate

    # Resolve optimized IR
    if ! opt_ir="$(ir_for_profile "$stem" "$opt_irs_dir")"; then
      echo "[warn] no optimized IR for $stem in $opt_irs_dir" >&2
      sem_give; exit 0
    fi
    opt_name="$(basename "$opt_ir")"

    # Cache function list from optimized IR once
    mapfile -t FUNS < <(list_functions "$opt_ir")

    # Unique (Caller,Callee) pairs from the profile CSV
    mapfile -t pairs < <(awk -F',' '
      NR==1 { next }
      {
        caller=$2; callee=$3;
        gsub(/^[ \t]+|[ \t]+$/,"",caller);
        gsub(/^[ \t]+|[ \t]+$/,"",callee);
        if (callee!="") print caller","callee
      }' "$prof" | sort -u )

    # For each pair, collect arg indices and emit rows
    for p in "${pairs[@]}"; do
      IFS=, read -r caller_raw callee_raw <<< "$p"
      caller="$(trim "$caller_raw")"
      callee="$(trim "$callee_raw")"
      [[ -z "$callee" ]] && continue

      # list of arg indexes for this (caller, callee)
      IFS=',' read -r -a ARGIDX <<< "$(
        awk -F',' -v C="$caller" -v E="$callee" '
          NR>1 {
            c=$2; e=$3; a=$7;
            gsub(/^[ \t]+|[ \t]+$/,"",c);
            gsub(/^[ \t]+|[ \t]+$/,"",e);
            gsub(/^[ \t]+|[ \t]+$/,"",a);
            if (c==C && e==E && a!="") print a
          }' "$prof" | sort -n | uniq | paste -sd',' -
      )"

      for ai in "${ARGIDX[@]}"; do
        ai="$(trim "${ai:-}")"
        [[ -z "$ai" ]] && continue

        fn_opt=""
        if ((${#FUNS[@]})); then
          fn_opt="$(choose_specialized_name "$callee" "$ai" "${FUNS[@]}" || true)"
        fi
        [[ -z "$fn_opt" ]] && fn_opt="Inlined"

        printf '%s,%s,%s,%s,%s,%s\n' \
          "$base_name" "$opt_name" "$caller" "$callee" "$fn_opt" "$ai" >> "$part"
      done
    done

    sem_give
  } &
done

wait
sem_close

# ---- merge header + parts deterministically ----
{
  cat "$tmp_header"
  # stable order: sort by part filename; adjust if you prefer natural numeric sort
  if compgen -G "$out_dir/parts/*.part" >/dev/null; then
    LC_ALL=C sort -t/ -k2,2 "$out_dir/parts/"*.part
  fi
} > "$out_csv"

rm -f "$tmp_header"
echo "[ok] wrote $out_csv"
