import pandas as pd
import json, glob, os

RAW = "data/raw"
out = open("profiling/profile_report.txt", "w", encoding="utf-8")

def log(*a):
    print(*a)
    print(*a, file=out)

for f in sorted(glob.glob(f"{RAW}/*.csv")):
    df = pd.read_csv(f, dtype=str)
    log("\n" + "=" * 70)
    log("FILE:", os.path.basename(f), "| shape:", df.shape)
    log("COLUMNS:", list(df.columns))
    log("\nHEAD(3):\n", df.head(3).to_string())
    log("\nNULLS:\n", df.isna().sum().to_string())
    log("\nUNIQUE COUNT:\n", df.nunique().to_string())
    log("\nFULL DUPLICATE ROWS:", df.duplicated().sum())

for f in sorted(glob.glob(f"{RAW}/*.json")):
    with open(f, encoding="utf-8") as fh:
        data = json.load(fh)
    log("\n" + "=" * 70)
    log("FILE:", os.path.basename(f), "| type:", type(data).__name__)
    if isinstance(data, dict):
        log("TOP KEYS:", list(data.keys()))
    items = data if isinstance(data, list) else next(
        (v for v in data.values() if isinstance(v, list)), [])
    log("ITEMS:", len(items))
    log("FIRST ITEM:\n", json.dumps(items[0], indent=2) if items else "empty")

out.close()
