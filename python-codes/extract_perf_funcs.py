import sys
import re
import os

LINE_RE = re.compile(
    r'^\s*(?P<pct>\d+(?:\.\d+)?)%\s+\S+\s+(?P<dso>\S+)\s+\[\.\]\s+(?P<symbol>.+)$'
)

def clean_func_name(symbol: str) -> str:
    # strip arguments if present
    name = symbol.split('(')[0].strip()

    # strip templates <...> recursively
    while '<' in name and '>' in name:
        name = re.sub(r'<[^<>]*>', '', name)

    # keep only the last identifier after :: (remove namespaces/classes)
    if '::' in name:
        name = name.split('::')[-1]

    return name

def parse_perf_stdio(path, main_binary):
    results = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            pct = m.group("pct")
            dso = os.path.basename(m.group("dso"))
            symbol = m.group("symbol").strip()
            if dso == main_binary:  # only keep from main binary
                func = clean_func_name(symbol)
                results.append((pct, func))
    return results

if __name__ == "__main__":
    path = sys.argv[1]          
    main_binary = sys.argv[2] 
    out_file = sys.argv[3]
    rows = parse_perf_stdio(path, main_binary)
    with open(out_file, "w", encoding="utf-8") as f:
        for pct, func in rows:
            print(f"{pct}  {func}")
            f.write(f"{pct}  {func}\n")
    print(f"Saved {len(rows)} functions to {out_file}")

