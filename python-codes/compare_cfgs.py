#!/usr/bin/env python3
import argparse, csv, pathlib, re, sys
from typing import Tuple, Set, Dict, List

# ---------- DOT parsing ----------
_RE_NODE = re.compile(r'^\s*"([^"]+)"\s*;\s*$')
_RE_EDGE = re.compile(r'^\s*"([^"]+)"\s*->\s*"([^"]+)"\s*;')

def parse_dot(dot_path: str) -> Tuple[Set[str], Set[Tuple[str,str]]]:
    nodes, edges = set(), set()
    with open(dot_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("digraph") or s.startswith("node "):
                continue
            m = _RE_EDGE.match(s)
            if m:
                a, b = m.group(1), m.group(2)
                edges.add((a, b)); nodes.add(a); nodes.add(b)
                continue
            m = _RE_NODE.match(s)
            if m:
                nodes.add(m.group(1))
    return nodes, edges

def cfg_stats_from_dot(dot_path: str):
    Ns, Es = parse_dot(dot_path)
    V, E = len(Ns), len(Es)
    avg_out = (E / V) if V else 0.0
    density = (E / (V * (V - 1))) if V > 1 else 0.0
    return {"V": V, "E": E, "avg_out": avg_out, "density": density}

# ---------- BFI CSV helpers ----------
def read_bfi(csv_path: str):
    """
    Returns:
      func_to_bb: Dict[str, Dict[bb, weight]]
      func_list : List[str]  (unique function names seen, order of first appearance)
    """
    func_to_bb: Dict[str, Dict[str, float]] = {}
    func_seen_order: List[str] = []

    if not csv_path:
        return func_to_bb, func_seen_order
    try:
        with open(csv_path, newline="") as f:
            r = csv.DictReader(f)
            if "Function" not in r.fieldnames or "BB" not in r.fieldnames or "Weight" not in r.fieldnames:
                # Not the expected schema; give up gracefully.
                return {}, []
            for row in r:
                fn = (row.get("Function") or "").strip()
                bb = (row.get("BB") or "").strip()
                wt_s = (row.get("Weight") or "0").strip()
                try:
                    wt = float(wt_s)
                except:
                    wt = 0.0
                if not fn or not bb:
                    continue
                if fn not in func_to_bb:
                    func_to_bb[fn] = {}
                    func_seen_order.append(fn)
                func_to_bb[fn][bb] = wt
    except FileNotFoundError:
        return {}, []
    return func_to_bb, func_seen_order

def resolve_bfi_function(requested: str, funcs: List[str], debug=False, side="base", csv_path=""):
    """
    Pick a function name from BFI CSV to use.
    Priority:
      1) exact match
      2) name that contains requested
      3) name contained in requested
      4) if only one function exists, use it
      5) return '' (no match)
    """
    if not funcs:
        if debug:
            print(f"[bfi:{side}] {csv_path}: no functions present", file=sys.stderr)
        return ""
    # Exact
    for fn in funcs:
        if fn == requested:
            if debug:
                print(f"[bfi:{side}] matched EXACT: {fn}", file=sys.stderr)
            return fn
    # contains
    for fn in funcs:
        if requested and (requested in fn):
            if debug:
                print(f"[bfi:{side}] matched CONTAINS: want='{requested}' using='{fn}'", file=sys.stderr)
            return fn
    # contained in
    for fn in funcs:
        if fn and (fn in requested):
            if debug:
                print(f"[bfi:{side}] matched CONTAINED-IN: want='{requested}' using='{fn}'", file=sys.stderr)
            return fn
    # single function fallback
    if len(funcs) == 1:
        if debug:
            print(f"[bfi:{side}] single-function CSV; using '{funcs[0]}'", file=sys.stderr)
        return funcs[0]
    if debug:
        samp = ", ".join(funcs[:6])
        print(f"[bfi:{side}] no match for '{requested}'. Available: {samp}{' ...' if len(funcs)>6 else ''}", file=sys.stderr)
    return ""

def hotness_stats(weights: Dict[str,float]):
    if not weights:
        return dict(maxW=0.0, meanW=0.0, ge75=0, ge50=0, ge25=0)
    vals = list(weights.values())
    maxW = max(vals)
    meanW = sum(vals)/len(vals) if vals else 0.0
    if maxW <= 0.0:
        return dict(maxW=0.0, meanW=meanW, ge75=0, ge50=0, ge25=0)
    t75, t50, t25 = 0.75*maxW, 0.5*maxW, 0.25*maxW
    ge75 = sum(1 for v in vals if v >= t75)
    ge50 = sum(1 for v in vals if v >= t50)
    ge25 = sum(1 for v in vals if v >= t25)
    return dict(maxW=maxW, meanW=meanW, ge75=ge75, ge50=ge50, ge25=ge25)

# ---------- CSV fields ----------
FIELDS = [
    "Function",
    "V_base","E_base","V_after","E_after",
    "dV","dE",
    "avg_out_base","avg_out_after",
    "density_base","density_after",
    "maxW_base","meanW_base","ge75_base","ge50_base","ge25_base",
    "maxW_after","meanW_after","ge75_after","ge50_after","ge25_after",
]

def write_row(out_csv: pathlib.Path, row: dict):
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    header_needed = not out_csv.exists() or out_csv.stat().st_size == 0
    with out_csv.open("a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if header_needed:
            w.writeheader()
        w.writerow({k: row.get(k, "") for k in FIELDS})

# ---------- main ----------
def main():
    ap = argparse.ArgumentParser("Compare two CFG DOTs with optional BFI merge")
    ap.add_argument("--baseline-dot", required=True)
    ap.add_argument("--after-dot",    required=True)
    ap.add_argument("--fn-name",      required=True, help="Label for CSV output")

    # Separate names for BFI lookup
    ap.add_argument("--fn-base-name",  default="", help="Name to look up in baseline BFI CSV (default: --fn-name)")
    ap.add_argument("--fn-after-name", default="", help="Name to look up in after BFI CSV (default: --fn-name)")

    ap.add_argument("--out-csv",      required=True)
    ap.add_argument("--bfi-base-csv",  default="", help="Optional: baseline BFI CSV")
    ap.add_argument("--bfi-after-csv", default="", help="Optional: after BFI CSV")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    base = cfg_stats_from_dot(args.baseline_dot)
    aft  = cfg_stats_from_dot(args.after_dot)

    # Resolve BFI names
    fn_base_req  = args.fn_base_name if args.fn_base_name else args.fn_name
    fn_after_req = args.fn_after_name if args.fn_after_name else args.fn_name

    hb = dict(maxW=0.0, meanW=0.0, ge75=0, ge50=0, ge25=0)
    ha = dict(maxW=0.0, meanW=0.0, ge75=0, ge50=0, ge25=0)

    # Baseline BFI
    if args.bfi_base_csv:
        fb, fb_order = read_bfi(args.bfi_base_csv)
        if args.debug:
            print(f"[bfi:base] csv={args.bfi_base_csv} fn_req='{fn_base_req}' funcs={len(fb_order)}", file=sys.stderr)
        if fb:
            use_fn_b = resolve_bfi_function(fn_base_req, fb_order, debug=args.debug, side="base", csv_path=args.bfi_base_csv)
            if use_fn_b and use_fn_b in fb:
                hb = hotness_stats(fb[use_fn_b])
                if args.debug:
                    print(f"[bfi:base] using '{use_fn_b}' with {len(fb[use_fn_b])} BB rows", file=sys.stderr)
            else:
                if args.debug:
                    print(f"[bfi:base] no match -> hotness=0", file=sys.stderr)

    # After BFI
    if args.bfi_after_csv:
        fa, fa_order = read_bfi(args.bfi_after_csv)
        if args.debug:
            print(f"[bfi:after] csv={args.bfi_after_csv} fn_req='{fn_after_req}' funcs={len(fa_order)}", file=sys.stderr)
        if fa:
            use_fn_a = resolve_bfi_function(fn_after_req, fa_order, debug=args.debug, side="after", csv_path=args.bfi_after_csv)
            if use_fn_a and use_fn_a in fa:
                ha = hotness_stats(fa[use_fn_a])
                if args.debug:
                    print(f"[bfi:after] using '{use_fn_a}' with {len(fa[use_fn_a])} BB rows", file=sys.stderr)
            else:
                if args.debug:
                    print(f"[bfi:after] no match -> hotness=0", file=sys.stderr)

    row = {
        "Function": args.fn_name,
        "V_base": base["V"], "E_base": base["E"],
        "V_after": aft["V"], "E_after": aft["E"],
        "dV": aft["V"] - base["V"], "dE": aft["E"] - base["E"],
        "avg_out_base": f"{base['avg_out']:.6f}",
        "avg_out_after": f"{aft['avg_out']:.6f}",
        "density_base": f"{base['density']:.6f}",
        "density_after": f"{aft['density']:.6f}",
        "maxW_base": f"{hb['maxW']:.6f}",
        "meanW_base": f"{hb['meanW']:.6f}",
        "ge75_base": hb["ge75"], "ge50_base": hb["ge50"], "ge25_base": hb["ge25"],
        "maxW_after": f"{ha['maxW']:.6f}",
        "meanW_after": f"{ha['meanW']:.6f}",
        "ge75_after": ha["ge75"], "ge50_after": ha["ge50"], "ge25_after": ha["ge25"],
    }

    outp = pathlib.Path(args.out_csv)
    write_row(outp, row)

    # Console summary
    print("=== CFG Comparison ===")
    print(f"Function: {args.fn_name}")
    print(f"Baseline: V={base['V']} E={base['E']} | avg_out={base['avg_out']:.2f}, density={base['density']:.4f} | "
          f"maxW={row['maxW_base']} meanW={row['meanW_base']}")
    print(f"After   : V={aft['V']} E={aft['E']} | avg_out={aft['avg_out']:.2f}, density={aft['density']:.4f} | "
          f"maxW={row['maxW_after']} meanW={row['meanW_after']}")
    print(f"ΔV={row['dV']} ΔE={row['dE']}")
    print(f"[compare_cfgs] wrote: {args.out_csv}")

if __name__ == "__main__":
    main()
