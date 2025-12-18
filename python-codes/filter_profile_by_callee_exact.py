#!/usr/bin/env python3
import sys, re, csv

"""
Usage:
  python3 filter_profile_by_callee_exact.py <input_csv> <callee_name> <output_csv>

Example:
  python3 filter_profile_by_callee_exact.py profile.txt update_tree update_tree.csv
"""

def split_records(body: str):
    """
    Split a blob of CSV text into record-like chunks without altering content.
    We split *before* any token that looks like a C/C++ filename followed by a comma.
      e.g. 'psimplex.c, ...' or 'spec_qsort/spec_qsort.c, ...'
    """
    # Normalize newlines but do not touch characters
    body = body.replace("\r\n", "\n").replace("\r", "\n")

    # Keep header line (first line) separate; process rest as one blob
    if "\n" in body:
        header_line, rest = body.split("\n", 1)
    else:
        header_line, rest = body, ""

    # Split BEFORE each filename token; lookahead so nothing is consumed/changed
    # This handles concatenated rows like '... 10.2458psimplex.c, primal_net_simplex, ...'
    pat = re.compile(r'(?=\b[A-Za-z0-9_./-]+\.(?:c|cc|cpp)\s*,)')
    chunks = [c for c in pat.split(rest) if c.strip()]

    return header_line, chunks

def parse_csv_line(line: str):
    # Use csv.reader for a single line; allow spaces after commas
    for row in csv.reader([line], skipinitialspace=True):
        return [c.strip() for c in row]
    return None

def main():
    if len(sys.argv) != 4:
        print("usage: filter_profile_by_callee_exact.py <input_csv> <callee_name> <output_csv>", file=sys.stderr)
        sys.exit(1)

    inp, callee, outp = sys.argv[1], sys.argv[2], sys.argv[3]

    text = open(inp, "r", encoding="utf-8", errors="ignore").read()
    header_line, chunks = split_records(text)

    # Detect/ensure header
    header_row = parse_csv_line(header_line) or []
    if not any(h.strip().lower() == "callee" for h in header_row):
        # Fallback header if file has none
        header_row = ["FileName","Caller","Callee","Line","Col","CallFreq",
                      "ArgIndex","ArgVal","ArgValFreq","ArgValPred"]

    out_rows = []
    for ck in chunks:
        row = parse_csv_line(ck)
        if not row or len(row) < 3:
            continue
        if row[2] == callee:             # exact match; change to .lower() for case-insensitive
            out_rows.append(row)

    with open(outp, "w", encoding="utf-8", newline="") as g:
        w = csv.writer(g)
        w.writerow(header_row)
        w.writerows(out_rows)

    print(f"Wrote {len(out_rows)} rows to {outp}")

if __name__ == "__main__":
    main()
