#!/usr/bin/env python3
# python3 train_rank_lambdamart_5folds_safe.py --input full_dataset_raw_swaptions.csv --app swaptions --folds 5
import os
import re
import math
import argparse
import numpy as np
import pandas as pd
from sklearn.model_selection import KFold
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    roc_auc_score, average_precision_score,
    classification_report, confusion_matrix
)
import lightgbm as lgb

# ---------- Ranking metric helpers ----------
def _dcg(rels):
    return sum(((2.0**r - 1.0) / math.log2(i + 2)) for i, r in enumerate(rels))

def _ndcg_at_k_binary(labels_sorted, k):
    rels = labels_sorted[:k]
    dcg_k = _dcg(rels)
    ideal = sorted(labels_sorted, reverse=True)[:k]
    idcg_k = _dcg(ideal) if ideal else 0.0
    return 0.0 if idcg_k == 0 else dcg_k / idcg_k

def _ndcg_at_k_real(gains_sorted, k):
    gains = gains_sorted[:k]
    dcg_k = _dcg(gains)
    ideal = sorted(gains_sorted, reverse=True)[:k]
    idcg_k = _dcg(ideal) if ideal else 0.0
    return 0.0 if idcg_k == 0 else dcg_k / idcg_k

def _precision_at_k(labels_sorted, k):
    k = min(k, len(labels_sorted))
    if k == 0: return 0.0
    return float(sum(labels_sorted[:k])) / k

def _recall_at_k(labels_sorted, k):
    pos = sum(labels_sorted)
    if pos == 0: return 0.0
    return float(sum(labels_sorted[:k])) / pos

def _map(labels_sorted):
    pos = sum(labels_sorted)
    if pos == 0: return 0.0
    hits = 0
    ap_sum = 0.0
    for i, y in enumerate(labels_sorted, start=1):
        if y == 1:
            hits += 1
            ap_sum += hits / i
    return ap_sum / pos

def evaluate_fold_metrics(out_df, app_name, fold_idx, summary_path):
    """
    out_df: columns = IR_ID, prob_speedup, speedup_user
    """
    df = out_df.sort_values("prob_speedup", ascending=False).reset_index(drop=True)
    labels = (df["speedup_user"] > 1.0).astype(int).tolist()
    scores = df["prob_speedup"].values
    speedups = df["speedup_user"].values

    metrics = {}
    for k in [1, 5, 10]:
        metrics[f"hit@{k}"] = 1.0 if sum(labels[:k]) > 0 else 0.0
        metrics[f"precision@{k}"] = _precision_at_k(labels, k)
        metrics[f"recall@{k}"] = _recall_at_k(labels, k)
        metrics[f"ndcg@{k}"] = _ndcg_at_k_binary(labels, k)
        metrics[f"ndcg_speedup@{k}"] = _ndcg_at_k_real(speedups.tolist(), k)

    metrics["map"] = _map(labels)
    try:
        metrics["roc_auc"] = roc_auc_score(labels, scores) if len(set(labels)) > 1 else float("nan")
    except Exception:
        metrics["roc_auc"] = float("nan")
    try:
        metrics["pr_auc"] = average_precision_score(labels, scores) if sum(labels) > 0 else float("nan")
    except Exception:
        metrics["pr_auc"] = float("nan")

    per_fold_path = f"{app_name}-metrics_fold{fold_idx}.csv"
    pd.Series(metrics, name="value").to_csv(per_fold_path, header=True)

    row = {"fold": fold_idx, **metrics}
    if not os.path.exists(summary_path):
        pd.DataFrame([row]).to_csv(summary_path, index=False)
    else:
        pd.concat([pd.read_csv(summary_path), pd.DataFrame([row])], ignore_index=True)\
          .to_csv(summary_path, index=False)

    print(f"[Fold {fold_idx}] Metrics → {per_fold_path}")

# ---------- Utilities ----------
def infer_ir_column(df):
    for cand in ["IR", "ir_name", "IR_ID", "IR_KEY"]:
        if cand in df.columns:
            return cand
    raise KeyError("IR column not found. Tried: IR, ir_name, IR_ID, IR_KEY.")

def infer_app_name(app_arg, input_path):
    if app_arg: return app_arg
    base = os.path.basename(input_path)
    m = re.search(r"full_dataset_raw_(.*)\.csv", base)
    return m.group(1) if m else os.path.splitext(base)[0]

def best_speedup_file(df, ir_col, app_name):
    max_per_ir = df.groupby(ir_col, as_index=False)["speedup_user"].max()
    gmax = max_per_ir["speedup_user"].max()
    winners = max_per_ir[max_per_ir["speedup_user"] == gmax]\
              .rename(columns={ir_col: "IR_ID", "speedup_user": "max_speedup_user"})
    out_path = f"{app_name}-best-speedup.csv"
    winners.to_csv(out_path, index=False)
    print(f"[BEST] Wrote: {out_path}")

def aggregate_per_ir(df, ir_col, forbidden_cols):
    # Coerce all but ir_col to numeric
    tmp = df.copy()
    cols = [c for c in tmp.columns if c != ir_col]
    tmp[cols] = tmp[cols].apply(pd.to_numeric, errors="coerce")

    # Mean aggregate numeric features per IR
    num_cols = tmp.select_dtypes(include=[np.number]).columns.tolist()
    agg_map = {c: "mean" for c in num_cols}
    grp = tmp.groupby(ir_col, as_index=False).agg(agg_map)

    # Attach target: max(speedup_user) per IR from original df
    max_speed = df.groupby(ir_col, as_index=False)["speedup_user"].max()\
                  .rename(columns={"speedup_user": "speedup_user_max"})
    grp = grp.merge(max_speed, on=ir_col, how="left")

    # Binary label for reporting
    grp["label"] = (grp["speedup_user_max"] > 1.0).astype(int)

    # Feature set: numeric minus forbidden + targets
    feature_cols = [c for c in grp.select_dtypes(include=[np.number]).columns
                    if c not in set(forbidden_cols) | {"speedup_user_max", "label"}]
    return grp, feature_cols

# ---------- Main ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Path to full_dataset_raw_*.csv")
    ap.add_argument("--app", default="", help="App name tag for output files")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--random_state", type=int, default=42)
    args = ap.parse_args()

    df = pd.read_csv(args.input, low_memory=False)
    print(f"Original shape: {df.shape}")

    if "speedup_user" not in df.columns:
        raise ValueError("Input must contain 'speedup_user'.")

    ir_col = infer_ir_column(df)
    app_name = infer_app_name(args.app, args.input)

    # Global best-speedup IRs (raw)
    best_speedup_file(df, ir_col, app_name)

    # Optional: encode AppName if present and non-numeric
    if "AppName" in df.columns and df["AppName"].dtype == object:
        df["AppName"] = LabelEncoder().fit_transform(df["AppName"].astype(str))

    # Forbidden training features
    forbidden = {"speedup_user", "improvement_user_pct", "elapsed_s", "user_s", "instructions"}

    # Aggregate to IR-level
    grp, feature_cols = aggregate_per_ir(df, ir_col, forbidden)
    grp = grp.rename(columns={ir_col: "IR_ID"})
    print(f"IRs after aggregation: {len(grp)}")

    # Build X / y / ids
    X = grp[feature_cols].copy()

    # Drop any all-NaN features
    all_nan = [c for c in X.columns if X[c].isna().all()]
    if all_nan:
        X = X.drop(columns=all_nan)
        feature_cols = [c for c in feature_cols if c not in all_nan]
    X = X.fillna(0.0)

    y = grp["label"].astype(int).values                     # relevance for training/reporting
    ir_ids = grp["IR_ID"].astype(str).values               # IR names/keys
    spmax = grp["speedup_user_max"].values                 # ground-truth max speedup per IR

    print(f"[Features used ({len(feature_cols)})]:")
    for c in feature_cols:
        print(f" - {c}")

    # KFold on IRs
    kf = KFold(n_splits=args.folds, shuffle=True, random_state=args.random_state)

    # Summary metrics file
    summary_path = f"{app_name}-metrics_summary.csv"
    if os.path.exists(summary_path):
        os.remove(summary_path)

    for fold_idx, (tr, te) in enumerate(kf.split(X), start=1):
        X_tr, X_te = X.iloc[tr], X.iloc[te]
        y_tr, y_te = y[tr], y[te]
        ir_te = ir_ids[te]
        sp_te = spmax[te]

        # LambdaMART ranker — single training group (whole training split)
        train_group = np.array([len(tr)], dtype=np.int32)
        print(f"\n[Fold {fold_idx}] Train={len(tr)}  Test={len(te)}  Pos/Neg in Train: {int((y_tr==1).sum())}/{int((y_tr==0).sum())}")

        ranker = lgb.LGBMRanker(
            objective="lambdarank",
            learning_rate=0.05,
            n_estimators=500,
            max_depth=-1,
            num_leaves=63,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=args.random_state,
            metric="ndcg",
        )
        # Train with binary relevance (y_tr) as the gain signal
        ranker.fit(X_tr, y_tr, group=train_group)

        # Predict scores for test IRs — higher is better (call it prob_speedup for convenience)
        scores = ranker.predict(X_te)

        # ---- Save classification-ish evaluation to text file
        y_hat = (scores >= np.median(scores)).astype(int)  # quick threshold for diagnostics only
        eval_txt = []
        eval_txt.append(f"[Fold {fold_idx}] Classification-ish report (threshold at test-score median)\n")
        try:
            eval_txt.append(classification_report(y_te, y_hat, digits=3))
            eval_txt.append("Confusion Matrix (TEST):")
            eval_txt.append(str(confusion_matrix(y_te, y_hat)))
        except Exception:
            eval_txt.append("Classification report unavailable (single-class test set).")
        eval_path = f"{app_name}-eval_fold{fold_idx}.txt"
        with open(eval_path, "w") as f:
            f.write("\n".join(eval_txt))
        print(f"[Fold {fold_idx}] Eval text → {eval_path}")

        # ---- Feature importance
        fi = pd.Series(ranker.feature_importances_, index=X.columns).sort_values(ascending=False)
        fi_path = f"{app_name}-feature_importance_lambdamart_fold{fold_idx}.csv"
        fi.to_csv(fi_path, header=["importance"])
        print(f"[Fold {fold_idx}] Feature importance → {fi_path}")

        # ---- Full ranking (exact columns requested)
        out = pd.DataFrame({
            "IR_ID": ir_te,
            "prob_speedup": scores,
            "speedup_user": sp_te
        }).sort_values("prob_speedup", ascending=False)

        rank_path = f"{app_name}-ranker_lambdamart_ir_rankings_fold{fold_idx}.csv"
        out.to_csv(rank_path, index=False)
        print(f"[Fold {fold_idx}] Rankings → {rank_path}")

        # ---- Top IR(s) for this fold (ties included)
        top_score = out["prob_speedup"].max()
        top_df = out[out["prob_speedup"] == top_score]
        top_path = f"{app_name}-topIR_fold{fold_idx}.csv"
        top_df.to_csv(top_path, index=False)
        print(f"[Fold {fold_idx}] Top IR(s) → {top_path}")

        # ---- Ranking metrics for this fold
        evaluate_fold_metrics(out_df=out, app_name=app_name, fold_idx=fold_idx, summary_path=summary_path)

    print(f"\n[Done] Summary metrics → {summary_path}")
    print("Generated per fold:")
    print("  - <app>-ranker_lambdamart_ir_rankings_foldK.csv")
    print("  - <app>-feature_importance_lambdamart_foldK.csv")
    print("  - <app>-metrics_foldK.csv")
    print("  - <app>-topIR_foldK.csv")
    print("  - <app>-eval_foldK.txt")
    print("Also:")
    print("  - <app>-best-speedup.csv")
    print("  - <app>-metrics_summary.csv")

if __name__ == "__main__":
    main()
