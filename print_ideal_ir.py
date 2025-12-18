#!/usr/bin/env python3
import argparse
import pandas as pd

def _try_read_no_header(path):
    # Expect: IR_NAME,SPEEDUP (no header)
    df = pd.read_csv(path, header=None, names=["ir", "speedup"], low_memory=False)
    return df

def _try_read_with_header(path):
    # Expect: header exists; take first two columns (any names)
    df = pd.read_csv(path, header=0, low_memory=False)
    if df.shape[1] < 2:
        raise ValueError("CSV has header but fewer than 2 columns")
    df = df.iloc[:, :2].copy()
    df.columns = ["ir", "speedup"]
    return df

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="inp", default="swaptions-best-speedup.csv",
                   help="Input CSV (default: swaptions-best-speedup.csv)")
    args = p.parse_args()

    # First try "no header" mode; if speedup isn't numeric, retry "with header".
    df = _try_read_no_header(args.inp)

    if df.empty:
        raise SystemExit(f"ERROR: {args.inp} is empty")

    # If first speedup is not convertible, it likely means we accidentally read the header as data.
    try:
        ir = str(df.loc[0, "ir"]).strip()
        speedup = float(str(df.loc[0, "speedup"]).strip())
    except Exception:
        df = _try_read_with_header(args.inp)
        if df.empty:
            raise SystemExit(f"ERROR: {args.inp} has a header but no data rows")
        ir = str(df.loc[0, "ir"]).strip()
        speedup = float(str(df.loc[0, "speedup"]).strip())

    print("--------------------------------------------")
    print("IDEAL IR with FunctionSpecialization:\n")
    print(ir)
    print(f"Speedup Over baseline:  {speedup}")
    print("--------------------------------------------")

if __name__ == "__main__":
    main()
