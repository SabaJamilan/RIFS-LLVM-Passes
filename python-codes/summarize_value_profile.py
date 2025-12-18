#!/usr/bin/env python3
import argparse
import sys
import pandas as pd
import numpy as np

def classify_kind(argtype: str) -> str:
    if not isinstance(argtype, str):
        return "INT"
    t = argtype.strip().lower()
    if "*" in t:
        return "PTR"
    if "float" in t or "double" in t:
        return "FLOAT"
    return "INT"

def load_and_normalize(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path, engine="python")
    df.columns = [c.strip() for c in df.columns]

    # Coerce numerics where present
    num_cols = ["func_file_id", "#Calls", "CallPC", "target", "CallFreq",
                "#totalArgs", "#IntArgs", "#floatArgs", "#PointerArgs",
                "ArgIndex", "ArgVal", "ArgValFreq", "ArgValPred"]
    for c in num_cols:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="ignore")

    if "ArgType" in df.columns:
        df["Kind"] = df["ArgType"].apply(classify_kind)
    else:
        df["Kind"] = "INT"

    if "CallPC" not in df.columns or "target" not in df.columns:
        raise ValueError("Input must contain 'CallPC' and 'target' columns.")
    df["CallKey"] = list(zip(df["CallPC"], df["target"]))
    return df

def compute_denominator(df: pd.DataFrame):
    # one CallFreq per site; if duplicated rows exist for a site, take max
    site_freq = df.groupby("CallKey", sort=False)["CallFreq"].max(min_count=1)
    site_freq = site_freq.fillna(0)

    sum_callfreq_over_sites = int(site_freq.sum())
    max_numcalls_col = int(df["#Calls"].max()) if "#Calls" in df.columns and pd.api.types.is_numeric_dtype(df["#Calls"]) else 0
    total_dynamic_calls = max(sum_callfreq_over_sites, max_numcalls_col)
    num_call_sites = int(site_freq.shape[0])
    return sum_callfreq_over_sites, max_numcalls_col, total_dynamic_calls, num_call_sites, site_freq

def site_level_masks(df: pd.DataFrame, site_index: pd.Index):
    grp = df.groupby("CallKey", sort=False)

    # ANY-kind fully/semi
    site_fully_any = grp["ArgValPred"].apply(lambda s: bool(np.any(s == 100)))
    site_semi_any  = grp["ArgValPred"].apply(lambda s: bool(np.any((s > 10) & (s < 100))))
    site_fully_any = site_fully_any.reindex(site_index).fillna(False)
    site_semi_any  = site_semi_any.reindex(site_index).fillna(False)
    semi_only_any  = site_semi_any & (~site_fully_any)

    # By-type flags (per site)
    flags_fully = {}
    flags_semi  = {}
    for kind in ["INT", "PTR", "FLOAT"]:
        mask_f = (df["Kind"] == kind) & (df["ArgValPred"] == 100)
        m = grp["ArgValPred"].apply(lambda s, mk=mask_f: bool(np.any(mk.loc[s.index])))
        flags_fully[kind] = m.reindex(site_index).fillna(False)

        mask_s = (df["Kind"] == kind) & (df["ArgValPred"] > 10) & (df["ArgValPred"] < 100)
        m2 = grp["ArgValPred"].apply(lambda s, mk=mask_s: bool(np.any(mk.loc[s.index])))
        flags_semi[kind] = m2.reindex(site_index).fillna(False)

    return site_fully_any, semi_only_any, flags_fully, flags_semi

def exclusive_buckets(precedence, flags_dict, base_mask):
    """flags_dict keys: 'INT','PTR','FLOAT'. base_mask: eligible sites (bool Series)."""
    assigned = pd.Series(False, index=base_mask.index)
    buckets = {}
    for k in precedence:
        cand = base_mask & (~assigned) & flags_dict[k]
        buckets[k] = cand
        assigned = assigned | cand
    return buckets

def arg_slot_stability(df: pd.DataFrame, kind_filter=None):
    sub = df if kind_filter is None else df[df["Kind"] == kind_filter]
    if sub.empty:
        return 0, 0, 0
    slot_grp = sub.groupby(["CallKey", "ArgIndex"], sort=False)
    slot_fully = slot_grp["ArgValPred"].apply(lambda s: bool(np.any(s == 100)))
    slot_semi  = slot_grp["ArgValPred"].apply(lambda s: bool(np.any((s > 10) & (s < 100))))
    slot_fully = slot_fully.fillna(False)
    slot_semi  = (slot_semi.fillna(False)) & (~slot_fully)
    total_slots = int(slot_grp.ngroups)
    fully_count = int(slot_fully.sum())
    semi_count  = int(slot_semi.sum())
    return total_slots, fully_count, semi_count

def main():
    ap = argparse.ArgumentParser(description="Summarize value-profile CSV.")
    ap.add_argument("csv", help="Input value-profile CSV")
    ap.add_argument("--out", help="Write the text summary here (optional)")
    args = ap.parse_args()

    df = load_and_normalize(args.csv)
    sum_callfreq, max_numcalls, total_calls, num_call_sites, site_freq = compute_denominator(df)
    site_index = site_freq.index

    num_functions = int(df["func_file_id"].max()) if "func_file_id" in df.columns and pd.api.types.is_numeric_dtype(df["func_file_id"]) else 0

    site_fully_any, semi_only_any, flags_fully, flags_semi = site_level_masks(df, site_index)

    # ANY-kind site-level counts (each site counted once)
    fully_dyn = int(site_freq[site_fully_any].sum())
    semi_dyn  = int(site_freq[semi_only_any].sum())

    # Exclusive type precedence: INT > PTR > FLOAT
    precedence = ["INT", "PTR", "FLOAT"]
    fully_bkts = exclusive_buckets(precedence, flags_fully, site_fully_any)
    semi_bkts  = exclusive_buckets(precedence, flags_semi,  semi_only_any)

    fully_int_dyn   = int(site_freq[fully_bkts["INT"]].sum())
    fully_ptr_dyn   = int(site_freq[fully_bkts["PTR"]].sum())
    fully_float_dyn = int(site_freq[fully_bkts["FLOAT"]].sum())

    semi_int_dyn    = int(site_freq[semi_bkts["INT"]].sum())
    semi_ptr_dyn    = int(site_freq[semi_bkts["PTR"]].sum())
    semi_float_dyn  = int(site_freq[semi_bkts["FLOAT"]].sum())

    # Argument-slot stability
    tot_slots_all, fully_slots_all, semi_slots_all = arg_slot_stability(df, None)
    tot_slots_int, fully_slots_int, semi_slots_int = arg_slot_stability(df, "INT")

    # INT-only site-level view
    int_fully_sites = flags_fully["INT"]
    int_semi_sites  = flags_semi["INT"] & (~int_fully_sites)
    int_fully_dyn   = int(site_freq[int_fully_sites].sum())
    int_semi_dyn    = int(site_freq[int_semi_sites].sum())

    def pct(x): return (100.0 * x / total_calls) if total_calls > 0 else 0.0

    lines = []
    lines.append("==== Summary ====")
    lines.append(f"NumFunctions (max func_file_id)  : {num_functions}")
    lines.append("Denominator components:")
    lines.append(f"  Sum_CallFreq_over_sites        : {sum_callfreq}")
    lines.append(f"  Max_of_NumCalls_column         : {max_numcalls}")
    lines.append(f"  NumCallSites (unique pairs)    : {num_call_sites}")
    lines.append(f"Total_Dynamic_Calls (used max)   : {total_calls}")
    lines.append("")
    lines.append("Calls with invariant behavior (ANY arg kind):")
    lines.append(f"  FullyInv_Call_DynCount         : {fully_dyn}")
    lines.append(f"  Pct_FullyInv_Calls             : {pct(fully_dyn):.2f}%")
    lines.append(f"  SemiInv_Call_DynCount          : {semi_dyn}")
    lines.append(f"  Pct_SemiInv_Calls              : {pct(semi_dyn):.2f}%")
    lines.append("  (SemiInv excludes fully-invariant calls.)")
    lines.append("")
    lines.append("Type breakdown for FULLY invariant-call slots (exclusive, INT>PTR>FLOAT):")
    lines.append(f"  FullyInv_Call_IntDyn           : {fully_int_dyn}")
    lines.append(f"  FullyInv_Call_PtrDyn           : {fully_ptr_dyn}")
    lines.append(f"  FullyInv_Call_FloatDyn         : {fully_float_dyn}")
    lines.append(f"  Pct_FullyInv_IntCalls          : {pct(fully_int_dyn):.2f}%")
    lines.append(f"  Pct_FullyInv_PtrCalls          : {pct(fully_ptr_dyn):.2f}%")
    lines.append(f"  Pct_FullyInv_FloatCalls        : {pct(fully_float_dyn):.2f}%")
    lines.append("")
    lines.append("Type breakdown for SEMI invariant-call slots (exclusive, INT>PTR>FLOAT):")
    lines.append(f"  SemiInv_Call_IntDyn            : {semi_int_dyn}")
    lines.append(f"  SemiInv_Call_PtrDyn            : {semi_ptr_dyn}")
    lines.append(f"  SemiInv_Call_FloatDyn          : {semi_float_dyn}")
    lines.append(f"  Pct_SemiInv_IntCalls           : {pct(semi_int_dyn):.2f}%")
    lines.append(f"  Pct_SemiInv_PtrCalls           : {pct(semi_ptr_dyn):.2f}%")
    lines.append(f"  Pct_SemiInv_FloatCalls         : {pct(semi_float_dyn):.2f}%")
    lines.append("")
    lines.append("Argument-level stability (unique arg slots) — ALL kinds:")
    lines.append(f"  Total_Arg_Obs                  : {tot_slots_all}")
    lines.append(f"  FullyInv_Arg_Obs               : {fully_slots_all}")
    lines.append(f"  Pct_FullyInv_Args              : {(100.0*fully_slots_all/tot_slots_all if tot_slots_all>0 else 0.0):.2f}%")
    lines.append(f"  SemiInv_Arg_Obs                : {semi_slots_all}")
    lines.append(f"  Pct_SemiInv_Args               : {(100.0*semi_slots_all/tot_slots_all if tot_slots_all>0 else 0.0):.2f}%")
    lines.append("  (SemiInv_Arg_Obs excludes fully-invariant slots.)")
    lines.append("")
    lines.append("Unique argument slots by invariance class:")
    lines.append(f"  Num_FullyInv_ArgSlots          : {fully_slots_all}")
    lines.append(f"  Num_SemiInv_ArgSlots           : {semi_slots_all}")
    lines.append("  (Each slot = (CallKey, ArgIndex). Fully and Semi are disjoint.)")
    lines.append("")
    lines.append("Argument-level stability (unique arg slots) — INT-only:")
    lines.append(f"  Total_Arg_Obs                  : {tot_slots_int}")
    lines.append(f"  FullyInv_Arg_Obs               : {fully_slots_int}")
    lines.append(f"  Pct_FullyInv_Args              : {(100.0*fully_slots_int/tot_slots_int if tot_slots_int>0 else 0.0):.2f}%")
    lines.append(f"  SemiInv_Arg_Obs                : {semi_slots_int}")
    lines.append(f"  Pct_SemiInv_Args               : {(100.0*semi_slots_int/tot_slots_int if tot_slots_int>0 else 0.0):.2f}%")
    lines.append("  (SemiInv_Arg_Obs excludes fully-invariant slots.)")
    lines.append("")
    lines.append("Unique argument slots by invariance class:")
    lines.append(f"  Num_FullyInv_ArgSlots          : {fully_slots_int}")
    lines.append(f"  Num_SemiInv_ArgSlots           : {semi_slots_int}")
    lines.append("  (Each slot = (CallKey, ArgIndex). Fully and Semi are disjoint.)")
    lines.append("INT-only view (only integer-looking args, ignore PTR/FLOAT):")
    lines.append(f"  INT_FullyInv_Call_DynCount     : {int_fully_dyn}")
    lines.append(f"  INT_Pct_FullyInv_Calls         : { (100.0*int_fully_dyn/total_calls if total_calls>0 else 0.0):.2f}%")
    lines.append(f"  INT_SemiInv_Call_DynCount      : {int_semi_dyn}")
    lines.append(f"  INT_Pct_SemiInv_Calls          : { (100.0*int_semi_dyn/total_calls if total_calls>0 else 0.0):.2f}%")
    lines.append("  (SemiInv excludes fully-invariant INT slots.)")
    lines.append("=============================================")

    out = "\n".join(lines)
    print(out)
    if args.out:
        with open(args.out, "w") as f:
            f.write(out + "\n")

if __name__ == "__main__":
    pd.set_option("mode.copy_on_write", True)
    try:
        main()
    except Exception as e:
        print(f"[error] {e}", file=sys.stderr)
        sys.exit(1)
