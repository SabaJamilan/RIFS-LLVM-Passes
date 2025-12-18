import pandas as pd
import os
import argparse


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--app", default="swaptions",
                   help="App name key to use in the apps dict (default: swaptions)")

    # Option A: pass directory containing the standard CSV names
    p.add_argument("--data-dir", default=None,
                   help="Directory containing cfg_summary_all.csv, opcode_attr_for_all_opts_new.csv, perf_results_with_speedup.csv")

    # Option B: pass explicit CSV paths
    p.add_argument("--cfg", default=None, help="Path to cfg_summary_all.csv")
    p.add_argument("--opcode", default=None, help="Path to opcode_attr_for_all_opts_new.csv")
    p.add_argument("--perf", default=None, help="Path to perf_results_with_speedup.csv")

    return p.parse_args()

def build_apps_from_args(args):
    # If user gave --data-dir, infer filenames
    if args.data_dir:
        data_dir = args.data_dir
        cfg    = os.path.join(data_dir, "cfg_summary_all.csv")
        opcode = os.path.join(data_dir, "opcode_attr_for_all_opts_new.csv")
        perf   = os.path.join(data_dir, "perf_results_with_speedup.csv")
    else:
        # Otherwise require explicit paths
        missing = [k for k in ["cfg", "opcode", "perf"] if getattr(args, k) is None]
        if missing:
            raise SystemExit(
                f"Missing inputs: {missing}. Provide --data-dir OR provide --cfg --opcode --perf."
            )
        cfg, opcode, perf = args.cfg, args.opcode, args.perf

    apps = {
        args.app: {
            "cfg": cfg,
            "opcode": opcode,
            "perf": perf,
        }
    }
    return apps

def load_app_data(cfg_path, opcode_path, perf_path, app_name):
    # Load CSVs
    cfg_df = pd.read_csv(cfg_path)
    opcode_df = pd.read_csv(opcode_path)
    perf_df = pd.read_csv(perf_path)

    # Normalize IR column names
    cfg_df = cfg_df.rename(columns={"OptIR": "IR"})
    opcode_df = opcode_df.rename(columns={"OPT_IR_Name": "IR"})
    perf_df = perf_df.rename(columns={"ir_name": "IR"})

    # Merge perf with cfg
    merged = perf_df.merge(cfg_df, on="IR", how="left")

    # Merge with opcode
    merged = merged.merge(opcode_df, on="IR", how="left")

    # Add app name column for traceability
    merged["AppName"] = app_name

    return merged


if __name__ == "__main__":
    args = parse_args()
    apps = build_apps_from_args(args)

    # Example: access paths
    print(apps)

    # Combine all app data
    all_dataframes = []
    for app_name, paths in apps.items():
        df = load_app_data(paths["cfg"], paths["opcode"], paths["perf"], app_name)
        all_dataframes.append(df)

    # Concatenate and write out
    full_dataset = pd.concat(all_dataframes, ignore_index=True)
    output_path = f"full_dataset_raw_{list(apps.keys())[0]}.csv"
    full_dataset.to_csv(output_path, index=False)

    print(f"Saved to: {output_path}")

