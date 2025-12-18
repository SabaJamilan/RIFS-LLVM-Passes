#!/usr/bin/env bash
# build_opcode_attr_parallel.sh  (fast, same structure/CLI)
# Usage:
#   ./build_opcode_attr_parallel.sh \
#     --manifest /path/to/manifest_funcs_with_callers.csv \
#     --baseline /path/to/baseline.ll \
#     --optimized_dir /path/to/OPT_IRs_O3_dir \
#     --bfi_dir /path/to/profile_bfi_dir \
#     --out /path/to/opcode_attr_for_all_opts.csv \
#     --jobs 60

ts() { date +"%F %T"; }
log() { echo "[$(ts)] $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 2; }

MANIFEST=""
BASELINE=""
OPT_DIR=""
BFI_DIR=""
OUT="opcode_attr_for_all_opts.csv"
JOBS=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)      MANIFEST="$2"; shift 2;;
    --baseline)      BASELINE="$2"; shift 2;;
    --optimized_dir) OPT_DIR="$2"; shift 2;;
    --bfi_dir)       BFI_DIR="$2"; shift 2;;
    --out)           OUT="$2"; shift 2;;
    --jobs|-j)       JOBS="$2"; shift 2;;
    -h|--help) sed -n '1,120p' "$0"; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -f "$MANIFEST" ]] || die "--manifest not found: $MANIFEST"
[[ -f "$BASELINE"  ]] || die "--baseline not found: $BASELINE"
[[ -d "$OPT_DIR"   ]] || die "--optimized_dir not found: $OPT_DIR"
[[ -d "$BFI_DIR"   ]] || die "--bfi_dir not found: $BFI_DIR"

log "[setup] manifest=$MANIFEST"
log "[setup] baseline=$BASELINE"
log "[setup] optimized_dir=$OPT_DIR"
log "[setup] bfi_dir=$BFI_DIR"
log "[setup] out=$OUT  jobs=$JOBS"

mkdir -p "$(dirname "$OUT")"

# ----- Embedded (faster) Python worker -----
WORKER="$(mktemp -t opcode_worker_py.XXXXXX)"
trap 'rm -f "$WORKER" "$IR_LIST_FILE"' EXIT

cat > "$WORKER" <<'PYCODE'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os, re, csv, sys, io, glob, fcntl
from collections import defaultdict, Counter
from typing import Dict, Tuple, List, Optional, Set

def log(msg): sys.stderr.write(msg+"\n")

LABEL_RE       = re.compile(r'^\s*([A-Za-z0-9_.\-]+):\s*(?:$|;)')
DEF_NAME_RE    = re.compile(r'^\s*define\b[^\n@]*@([^\s(]+)\(')
OPCODE_RE      = re.compile(r'^\s*(?:;.*)?\s*([a-z][a-z0-9_.-]*)\b')
ASSIGN_RE      = re.compile(r'^\s*(?P<lhs>%[A-Za-z0-9_.\-]+)\s*=\s*(?P<op>[a-z][a-z0-9_.-]*)\b')
TERM_RE        = re.compile(r'^\s*(?P<op>br|ret|switch|indirectbr|invoke|resume|unreachable)\b')
VAL_USE_RE     = re.compile(r'(%[A-Za-z0-9_.\-]+)')
INTRIN_SKIP_RE = re.compile(r'^llvm\.lifetime\.(start|end)\b')

def normalize_opcode(op: str) -> str:
    if op.endswith('call'):
        return 'call'
    if op == 'truncate':
        return 'trunc'
    return op

class IRFunction:
    __slots__ = ("name","blocks","block_order","insts_by_lhs","op_by_line")
    def __init__(self, name: str):
        self.name = name
        self.blocks: Dict[str, List[str]] = defaultdict(list)
        self.block_order: List[str] = []
        self.insts_by_lhs: Dict[str, Tuple[str,str]] = {}
        self.op_by_line: List[Tuple[str,str]] = []

def parse_all_functions(ir_text: str):
    """Single-pass parse of the entire IR into {name: IRFunction} and IR-wide opcode counts."""
    functions: Dict[str, IRFunction] = {}
    irwide = Counter()

    lines = ir_text.splitlines()
    n = len(lines)
    i = 0
    while i < n:
        line = lines[i]
        m = DEF_NAME_RE.match(line)
        if not m:
            i += 1
            continue
        fn_name = m.group(1)
        fn = IRFunction(fn_name)

        # find opening '{'
        depth = 0
        # current line may already contain '{'
        if '{' in line:
            depth += line.count('{') - line.count('}')
        else:
            i += 1
            while i < n and '{' not in lines[i]:
                i += 1
            if i < n:
                depth += lines[i].count('{') - lines[i].count('}')
        curbb = ""

        # read body
        i += 1
        while i < n and depth > 0:
            raw = lines[i]
            depth += raw.count('{') - raw.count('}')
            # label?
            ml = LABEL_RE.match(raw)
            if ml:
                curbb = ml.group(1)
                if curbb not in fn.blocks:
                    fn.blocks[curbb] = []
                    fn.block_order.append(curbb)
                i += 1
                continue
            code = raw.split(';',1)[0].strip()
            if code:
                if not curbb:
                    curbb = "entry"
                    if curbb not in fn.blocks:
                        fn.blocks[curbb] = []
                        fn.block_order.append(curbb)
                fn.blocks[curbb].append(code)

                mA = ASSIGN_RE.match(code)
                if mA:
                    op = normalize_opcode(mA.group('op'))
                    if not INTRIN_SKIP_RE.match(op):
                        fn.insts_by_lhs[mA.group('lhs')] = (op, curbb)
                        fn.op_by_line.append((op, curbb))
                        irwide[op] += 1
                else:
                    mT = TERM_RE.match(code)
                    if mT:
                        op = normalize_opcode(mT.group('op'))
                        if not INTRIN_SKIP_RE.match(op):
                            fn.op_by_line.append((op, curbb))
                            irwide[op] += 1
                    else:
                        if ' call ' in code:
                            op = 'call'
                            fn.op_by_line.append((op, curbb))
                            irwide[op] += 1
                        else:
                            mO = OPCODE_RE.match(code)
                            if mO:
                                op = normalize_opcode(mO.group(1))
                                if not INTRIN_SKIP_RE.match(op):
                                    fn.op_by_line.append((op, curbb))
                                    irwide[op] += 1
            i += 1

        functions[fn_name] = fn
        # Note: i already at first line after body
    return functions, irwide

def load_text(p: str) -> str:
    with open(p, 'r', encoding='utf-8', errors='ignore') as f:
        return f.read()

def opcode_counts(fn: IRFunction) -> Counter:
    c = Counter()
    for op,_ in fn.op_by_line:
        c[op] += 1
    return c

def propagate_taint(fn: IRFunction, arg_idx: int):
    seeds = {f"%{arg_idx}", f"%arg{arg_idx}"}
    tainted_vals: Set[str] = set(seeds)
    tainted_insts_blocks: Dict[str,str] = {}
    changed = True
    # compact representation of block lines to avoid repeated scans
    block_concat = {b: "\n".join(fn.blocks[b]) for b in fn.block_order}
    while changed:
        changed = False
        for lhs, (_op, blk) in fn.insts_by_lhs.items():
            # locate defining line quickly (string find on the block blob)
            # pattern like "%x =" to reduce false positives
            blob = block_concat.get(blk, "")
            idx = blob.find(lhs + " =")
            if idx == -1:  # fallback (rare)
                # mild linear scan only in this block
                def_line = next((l for l in fn.blocks[blk] if l.strip().startswith(lhs+" =")), None)
            else:
                # slice around the found position to the line end
                end = blob.find("\n", idx)
                def_line = blob[idx:end] if end != -1 else blob[idx:]

            if not def_line: continue
            uses = set(VAL_USE_RE.findall(def_line))
            if (uses & tainted_vals) and lhs not in tainted_vals:
                tainted_vals.add(lhs)
                tainted_insts_blocks[lhs] = blk
                changed = True
    return tainted_vals, tainted_insts_blocks

def dep_counts(fn: IRFunction, tainted_insts_blocks: Dict[str,str]) -> Counter:
    c = Counter()
    for lhs, (op,_blk) in fn.insts_by_lhs.items():
        if lhs in tainted_insts_blocks:
            c[op] += 1
    return c

def load_bfi_csv(path: str) -> Dict[Tuple[str,str], float]:
    if not os.path.exists(path): return {}
    out: Dict[Tuple[str,str], float] = {}
    with open(path, newline='') as f:
        r = csv.DictReader(f)
        cols = { (c or "").strip().lower(): c for c in (r.fieldnames or []) }
        fn_key   = cols.get('function') or cols.get('fn') or cols.get('func')
        bb_key   = cols.get('bb') or cols.get('block') or cols.get('label')
        freq_key = cols.get('weight') or cols.get('freqint') or cols.get('frequency') or cols.get('count') or cols.get('freq')
        if not (fn_key and bb_key and freq_key): return {}
        for row in r:
            fn = (row.get(fn_key) or "").strip()
            bb = (row.get(bb_key) or "").strip()
            if not fn or not bb: continue
            try:
                freq = float((row.get(freq_key) or "0").replace("nan","0"))
            except Exception:
                freq = 0.0
            out[(fn,bb)] = out.get((fn,bb), 0.0) + freq
    return out

def resolve_bfi(stem: str, bfi_dir: str) -> Dict[Tuple[str,str], float]:
    cand = os.path.join(bfi_dir, f"{stem}.bfi.csv")
    if os.path.isfile(cand): return load_bfi_csv(cand)
    folder = os.path.join(bfi_dir, f"{stem}.bfi.csv")
    if os.path.isdir(folder):
        inner = os.path.join(folder, "bfi.csv")
        if os.path.isfile(inner): return load_bfi_csv(inner)
    hits = sorted(glob.glob(os.path.join(bfi_dir, f"{stem}*.csv")))
    for h in hits:
        if os.path.isfile(h): return load_bfi_csv(h)
    return {}

def sum_bfi_for_optype(fn: IRFunction, bfi: Dict[Tuple[str,str], float],
                       optype: str, tainted_insts_blocks=None) -> float:
    blocks = set()
    for lhs,(op,blk) in fn.insts_by_lhs.items():
        if op != optype: continue
        if tainted_insts_blocks is not None and lhs not in tainted_insts_blocks: continue
        blocks.add(blk)
    return sum(bfi.get((fn.name, b), 0.0) for b in blocks)

FIELDS = [
    "OPT_IR_Name","Role","Func_Base","Func_Opt","Arg_Index","OpcodeType",
    "Base_Count","Opt_Count","RemovedCount","IncreasedCount",
    "DepTypeToArg","RemovedCountByArg","AllDepToArg","AllRemovedByArg",
    "Sum_BFI_Func_Base","Sum_BFI_Func_OPT","Sum_BFI_Func_Reduction","Sum_BFI_Func_Removed_by_Arg",
    "Count_Base_IR","Count_OPT_IR","Count_Reduction_IR"
]

def norm(h: str) -> str:
    return (h or "").strip().lower().replace(" ","").replace("\t","").replace("-","_")

def append_rows(out_path: str, rows):
    with open(out_path, 'a', newline='') as outf:
        fcntl.flock(outf.fileno(), fcntl.LOCK_EX)
        w = csv.writer(outf)
        w.writerows(rows)
        fcntl.flock(outf.fileno(), fcntl.LOCK_UN)

def main():
    if len(sys.argv) != 7:
        sys.stderr.write("usage: worker.py BASELINE OPT_DIR BFI_DIR MANIFEST OUT OPT_IR\n")
        sys.exit(2)
    baseline, opt_dir, bfi_dir, manifest, out, opt_ir = sys.argv[1:7]
    stem = os.path.splitext(os.path.basename(opt_ir))[0]
    log(f"[start] {opt_ir}")

    # Read manifest rows for this opt_ir
    with open(manifest, newline='') as f:
        first = f.readline()
        if first.startswith('\ufeff'): first = first.lstrip('\ufeff')
        rest = f.read()
    r = csv.DictReader(io.StringIO(first+rest))
    if not r.fieldnames:
        log("[warn] empty manifest headers")
        return
    nmap = {norm(h): h for h in r.fieldnames}
    req = ["baselineir","optimizedir","fn_caller","fn_callee_base","fn_callee_opt","arg_index"]
    for key in req:
        if key not in nmap:
            log(f"[ERR] manifest missing column: {key}")
            return

    rows_for_ir = []
    baseline_path_in_manifest = None
    for row in r:
        if (row.get(nmap["optimizedir"]) or "").strip() == opt_ir:
            rows_for_ir.append(row)
            if baseline_path_in_manifest is None:
                baseline_path_in_manifest = (row.get(nmap["baselineir"]) or "").strip()
    if not rows_for_ir:
        log(f"[skip] no manifest rows for {opt_ir}")
        return

    # Load texts (baseline is single shared file)
    base_text = load_text(baseline)
    opt_path = os.path.join(opt_dir, opt_ir)
    if not os.path.isfile(opt_path):
        hits = sorted(glob.glob(os.path.join(opt_dir, f"{stem}*.ll")))
        if hits: opt_path = hits[0]
    if not os.path.isfile(opt_path):
        log(f"[warn] optimized IR not found: {opt_path}")
        return
    opt_text = load_text(opt_path)

    # One-pass parse per IR
    base_funcs, counts_base_ir = parse_all_functions(base_text)
    opt_funcs,  counts_opt_ir  = parse_all_functions(opt_text)
    bfi = resolve_bfi(stem, bfi_dir)

    appended = 0
    for row in rows_for_ir:
        caller = (row.get(nmap["fn_caller"]) or "").strip()
        cbase  = (row.get(nmap["fn_callee_base"]) or "").strip()
        copt   = (row.get(nmap["fn_callee_opt"]) or "").strip()
        try:
            argi = int((row.get(nmap["arg_index"]) or "0").strip())
        except Exception:
            argi = 0

        def build_pair(role: str, base_fn: IRFunction, opt_fn: IRFunction):
            out_rows = []
            base_counts = opcode_counts(base_fn)
            opt_counts  = opcode_counts(opt_fn)

            _, tbase = propagate_taint(base_fn, argi)
            _, topt  = propagate_taint(opt_fn,  argi)
            dep_base = dep_counts(base_fn, tbase)
            dep_opt  = dep_counts(opt_fn,  topt)
            all_dep_base = sum(dep_base.values())
            all_dep_opt  = sum(dep_opt.values())
            all_removed_by_arg = max(0, all_dep_base - all_dep_opt)

            all_ops = sorted(set(base_counts)|set(opt_counts)|set(counts_base_ir)|set(counts_opt_ir))
            for op in all_ops:
                b = base_counts.get(op,0); a = opt_counts.get(op,0)
                removed   = b-a if b>a else 0
                increased = a-b if a>b else 0
                dep_b = dep_base.get(op,0); dep_a = dep_opt.get(op,0)
                removed_by_arg = dep_b - dep_a if dep_b>dep_a else 0

                sum_bfi_base = sum_bfi_for_optype(base_fn, bfi, op, None)
                sum_bfi_opt  = sum_bfi_for_optype(opt_fn,  bfi, op, None)
                sum_bfi_red  = sum_bfi_base - sum_bfi_opt
                if role == "caller":
                    sum_bfi_removed = sum_bfi_for_optype(opt_fn, bfi, op, topt) if removed>0 else 0.0
                else:
                    sum_bfi_removed = sum_bfi_for_optype(base_fn, bfi, op, tbase) if removed>0 else 0.0

                cbir = counts_base_ir.get(op,0)
                coir = counts_opt_ir.get(op,0)
                cred = cbir - coir

                out_rows.append([
                    stem, role, base_fn.name, opt_fn.name, argi, op,
                    int(b), int(a), int(removed), int(increased),
                    int(dep_b), int(removed_by_arg),
                    int(all_dep_base), int(all_removed_by_arg),
                    float(sum_bfi_base), float(sum_bfi_opt), float(sum_bfi_red), float(sum_bfi_removed),
                    int(cbir), int(coir), int(cred)
                ])
            return out_rows

        # callee (base vs specialized)
        if cbase and cbase in base_funcs:
            base_fn = base_funcs[cbase]
            if copt and copt.lower() == "inlined":
                opt_fn = IRFunction(f"{cbase}.inlined")
            else:
                name_opt = copt or cbase
                opt_fn = opt_funcs.get(name_opt)
                if opt_fn is None:
                    # if the specialized name isn't present, skip callee rows but continue callers
                    opt_fn = None
            if opt_fn is not None:
                rows = build_pair("callee", base_fn, opt_fn)
                if rows:
                    append_rows(out, rows)
                    appended += len(rows)

        # caller (same symbol name baseline vs optimized)
        if caller and (caller in base_funcs) and (caller in opt_funcs):
            rows = build_pair("caller", base_funcs[caller], opt_funcs[caller])
            if rows:
                append_rows(out, rows)
                appended += len(rows)

    log(f"[done ] {opt_ir} +{appended} rows")

if __name__ == "__main__":
    main()
PYCODE

chmod +x "$WORKER"

# ----- write header once -----
python3 - "$OUT" <<'PYH'
import csv, os, sys
FIELDS = [
    "OPT_IR_Name","Role","Func_Base","Func_Opt","Arg_Index","OpcodeType",
    "Base_Count","Opt_Count","RemovedCount","IncreasedCount",
    "DepTypeToArg","RemovedCountByArg","AllDepToArg","AllRemovedByArg",
    "Sum_BFI_Func_Base","Sum_BFI_Func_OPT","Sum_BFI_Func_Reduction","Sum_BFI_Func_Removed_by_Arg",
    "Count_Base_IR","Count_OPT_IR","Count_Reduction_IR"
]
out = sys.argv[1]
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
if (not os.path.exists(out)) or os.stat(out).st_size == 0:
    with open(out, 'w', newline='') as f:
        csv.writer(f).writerow(FIELDS)
PYH

# ----- extract unique optimized IR names -----
IR_LIST_FILE="$(mktemp -t ir_list.XXXXXX)"

python3 - "$MANIFEST" > "$IR_LIST_FILE" <<'PYLIST'
import sys,csv,io
p=sys.argv[1]
with open(p,newline='') as f:
    first=f.readline()
    if first.startswith('\ufeff'): first=first.lstrip('\ufeff')
    rest=f.read()
r=csv.DictReader(io.StringIO(first+rest))
if not r.fieldnames: sys.exit(0)
def norm(h): return (h or "").strip().lower().replace(" ","").replace("\t","").replace("-","_")
n={norm(h):h for h in r.fieldnames}
col=n.get("optimizedir") or n.get("optimized_ir") or n.get("optimizedir_name")
seen=set()
for row in r:
    v=(row.get(col) or "").strip()
    if v and v not in seen:
        print(v); seen.add(v)
PYLIST

COUNT=$(wc -l < "$IR_LIST_FILE" | tr -d '[:space:]')
[[ "$COUNT" -gt 0 ]] || die "no optimized IR names found in manifest"

# ----- runner (same structure) -----
run_one() {
  local opt_ir="$1"
  echo "[$(ts)] [start] IR=$opt_ir" >&2
  # -OO removes asserts & docstrings; faster startup footprint
  python3 -OO "$WORKER" "$BASELINE" "$OPT_DIR" "$BFI_DIR" "$MANIFEST" "$OUT" "$opt_ir"
  local rc=$?
  echo "[$(ts)] [done ] IR=$opt_ir rc=$rc" >&2
  return $rc
}
export -f run_one
export WORKER BASELINE OPT_DIR BFI_DIR MANIFEST OUT

# Pick a GNU-parallel binary if one exists
PARALLEL_BIN=""
for p in $(type -ap parallel 2>/dev/null); do
  if "$p" --version 2>/dev/null | head -n 1 | grep -qi "GNU parallel"; then
    PARALLEL_BIN="$p"
    break
  fi
done

if [[ -n "$PARALLEL_BIN" ]]; then
  log "[run] GNU parallel ($PARALLEL_BIN) -j $JOBS"
  # If run_one is a bash function, export it:
  export -f run_one 2>/dev/null || true

  "$PARALLEL_BIN" --halt soon,fail=1 -j "$JOBS" \
    --joblog "$(dirname "$OUT")/parallel.joblog" \
    run_one :::: "$IR_LIST_FILE"
else
  log "[run] GNU parallel not found; using xargs -P $JOBS"
  xargs -I{} -P "$JOBS" bash -lc 'run_one "$@"' _ {} < "$IR_LIST_FILE"
fi

: '
if command -v parallel >/dev/null 2>&1; then
  log "[run] GNU parallel -j $JOBS"
  parallel --halt soon,fail=1 -j "$JOBS" --joblog "$(dirname "$OUT")/parallel.joblog" run_one :::: "$IR_LIST_FILE"
else
  log "[run] xargs -P $JOBS"
  xargs -I{} -P "$JOBS" bash -lc ''run_one "$@"' '_ {} < "$IR_LIST_FILE"
fi
'



log "[all done] -> $OUT"
