#!/usr/bin/env python3
import os
import sys
import glob
import argparse
import pandas as pd

def find_speedup_column(cols):
    """
    Pick a column that looks like 'speedup'. Prefer 'measured/true/real' if present.
    """
    cols_l = [c.lower() for c in cols]
    speedup_idxs = [i for i, c in enumerate(cols_l) if "speedup" in c]
    if not speedup_idxs:
        return None

    # Prefer columns that indicate measured/true speedup if multiple exist
    preferred_keywords = ["measured", "true", "real", "actual", "exec", "runtime", "perf"]
    for kw in preferred_keywords:
        for i in speedup_idxs:
            if kw in cols_l[i]:
                return cols[i]

    # Otherwise take the first "speedup*" column
    return cols[speedup_idxs[0]]

def find_ir_identifier_column(cols):
    """
    Try to pick a column that identifies the IR / candidate.
    """
    cols_l = [c.lower() for c in cols]
    candidates = []

    # Strong signals first
    for key in ["ir_path", "irfile", "ir_file", "ir", "ll", "bitcode", "candidate", "candidateid", "cand", "opt_ir"]:
        for c, cl in zip(cols, cols_l):
            if key in cl:
                candidates.append(c)

    if candidates:
        # Prefer paths/files over generic ids if available
        for prefer in ["path", "file", "ll", "bc"]:
            for c in candidates:
                if prefer in c.lower():
                    return c
        return candidates[0]

    return None

def read_top_ranked_row(csv_path):
    df = pd.read_csv(csv_path, low_memory=False)

    if df.empty:
        raise ValueError(f"{csv_path}: CSV is empty")

    # "first line is the ranked one" -> take first row (row 0)
    top = df.iloc[0].copy()
    return df, top

def parse_float(x):
    try:
        if pd.isna(x):
            return None
        return float(x)
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "files",
        nargs="*",
        help="Ranking CSVs (default: swaptions-ranker_lambdamart_ir_rankings_fold*.csv in current dir)",
    )
    args = ap.parse_args()

    files = args.files
    if not files:
        files = sorted(glob.glob("swaptions-ranker_lambdamart_ir_rankings_fold*.csv"))

    if not files:
        print("ERROR: No input files found.", file=sys.stderr)
        sys.exit(2)

    best = None  # (speedup, csv_path, speedup_col, ir_col, top_row_dict)

    for f in files:
        try:
            df, top = read_top_ranked_row(f)
        except Exception as e:
            print(f"[WARN] Skipping {f}: {e}", file=sys.stderr)
            continue

        speedup_col = find_speedup_column(df.columns)
        if speedup_col is None:
            print(f"[WARN] {f}: no column containing 'speedup' found; skipping", file=sys.stderr)
            continue

        sp = parse_float(top.get(speedup_col))
        if sp is None:
            print(f"[WARN] {f}: top row has non-numeric speedup in '{speedup_col}'; skipping", file=sys.stderr)
            continue

        ir_col = find_ir_identifier_column(df.columns)
        top_dict = top.to_dict()

        if best is None or sp > best[0]:
            best = (sp, f, speedup_col, ir_col, top_dict)

    if best is None:
        print("ERROR: Could not pick a best IR (no usable speedup column/values found).", file=sys.stderr)
        sys.exit(3)

    sp, f, speedup_col, ir_col, top_dict = best

    print("=== Suggested IR by cost model (max top-ranked speedup across folds) ===")
    print(f"Chosen file      : {os.path.basename(f)}")
    print(f"Speedup column   : {speedup_col}")
    print(f"Top-ranked speed : {sp}")

    if ir_col is not None:
        print(f"Suggested IR     : {top_dict.get(ir_col)}   (from column '{ir_col}')")
    else:
        print("Suggested IR     : (could not auto-detect an IR/candidate column)")
        print("                 Full top row printed below so you can see the identifier.")

    print("\n--- Top-ranked row (chosen fold) ---")
    for k, v in top_dict.items():
        print(f"{k}: {v}")

if __name__ == "__main__":
    main()
