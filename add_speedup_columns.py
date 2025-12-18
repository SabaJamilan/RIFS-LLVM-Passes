#!/usr/bin/env python3
import sys
import pandas as pd

def add_speedup_columns(perf_csv_path, baseline_name, output_csv_path, agg_baseline="mean"):
    df = pd.read_csv(perf_csv_path)

    # assume columns:
    #   bin_name, elapsed_s, user_s, ...
    # we pick the baseline rows
    base_rows = df[df["bin_name"] == baseline_name]

    if agg_baseline == "mean":
        base_elapsed = base_rows["elapsed_s"].astype(float).mean()
        base_user    = base_rows["user_s"].astype(float).mean()
    else:  # "first"
        base_elapsed = float(base_rows["elapsed_s"].iloc[0])
        base_user    = float(base_rows["user_s"].iloc[0])

    # compute speedup and % improvement
    def safe_ratio(b, x):
        if x == 0: return 0.0
        return b / x
    def safe_improve(b, x):
        if b == 0: return 0.0
        return (b - x) / b * 100.0

    df["speedup_elapsed"] = df["elapsed_s"].astype(float).apply(lambda x: safe_ratio(base_elapsed, x))
    df["speedup_user"]    = df["user_s"].astype(float).apply(lambda x: safe_ratio(base_user, x))

    df["improvement_elapsed_pct"] = df["elapsed_s"].astype(float).apply(lambda x: safe_improve(base_elapsed, x))
    df["improvement_user_pct"]    = df["user_s"].astype(float).apply(lambda x: safe_improve(base_user, x))

    df.to_csv(output_csv_path, index=False)
    return df

if __name__ == "__main__":
    # CLI usage:
    #   ./add_speedup_columns.py perf.csv baseline_bin_name output.csv [mean|first]
    perf_csv      = sys.argv[1]
    baseline_name = sys.argv[2]
    out_csv       = sys.argv[3]
    agg_mode      = sys.argv[4] if len(sys.argv) > 4 else "mean"

    add_speedup_columns(
        perf_csv_path=perf_csv,
        baseline_name=baseline_name,
        output_csv_path=out_csv,
        agg_baseline=agg_mode,
    )
