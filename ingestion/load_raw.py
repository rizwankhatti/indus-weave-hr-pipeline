"""
Stage 1 - Ingest (SQL Server).
All 12 raw files -> [raw] schema exactly as delivered:
  * every column NVARCHAR (text), JSON not flattened (one row per object)
  * metadata: _source_file, _loaded_at, _row_hash (MD5)
  * idempotent: tables are dropped and rebuilt on every run
  * row counts file vs table logged to raw.load_log
"""
import csv
import hashlib
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pandas as pd
from config import RAW_DIR, get_connection

CSV_TABLES = {
    "employees.csv": ("employees", 1316),
    "employment_history.csv": ("employment_history", 3686),
    "departments.csv": ("departments", 25),
    "shift_roster.csv": ("shift_roster", 36402),
    "device_mapping.csv": ("device_mapping", 1260),
    "biometric_punches.csv": ("biometric_punches", 345280),
    "holidays.csv": ("holidays", 12),
    "overtime_requests.csv": ("overtime_requests", 22098),
    "payroll_lines.csv": ("payroll_lines", 53617),
    "applications.csv": ("applications", 3835),
}
JSON_TABLES = {
    "shifts.json": ("shifts", "shifts", 4),
    "leave_requests.json": ("leave_requests", None, 5372),
}
META = ["_source_file", "_loaded_at", "_row_hash"]
SEP = "\x1f"


def row_hash(values):
    text = SEP.join("" if v is None else str(v) for v in values)
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def count_csv_rows(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def write_table(con, table, columns, rows, source_file, loaded_at, big_text=False):
    cur = con.cursor()
    cur.execute(f"DROP TABLE IF EXISTS [raw].[{table}]")
    defs = []
    for c in columns:
        defs.append(f"[{c}] NVARCHAR(MAX) NULL" if big_text else f"[{c}] NVARCHAR(500) NULL")
    defs += ["[_source_file] NVARCHAR(100)", "[_loaded_at] NVARCHAR(30)", "[_row_hash] CHAR(32)"]
    cur.execute(f"CREATE TABLE [raw].[{table}] ({', '.join(defs)})")
    n = len(columns) + len(META)
    sql = f"INSERT INTO [raw].[{table}] VALUES ({','.join('?' * n)})"
    cur.fast_executemany = not big_text
    batch = []
    for r in rows:
        batch.append(tuple(r) + (source_file, loaded_at, row_hash(r)))
        if len(batch) >= 20000:
            cur.executemany(sql, batch)
            batch = []
    if batch:
        cur.executemany(sql, batch)
    con.commit()


def log_result(con, source_file, table, file_rows, table_rows, loaded_at):
    cur = con.cursor()
    cur.execute("""IF OBJECT_ID('raw.load_log') IS NULL
        CREATE TABLE raw.load_log (
            source_file NVARCHAR(100) PRIMARY KEY, table_name NVARCHAR(100),
            file_rows INT, table_rows INT, status NVARCHAR(20), loaded_at NVARCHAR(30))""")
    status = "MATCH" if file_rows == table_rows else "MISMATCH"
    cur.execute("DELETE FROM raw.load_log WHERE source_file = ?", source_file)
    cur.execute("INSERT INTO raw.load_log VALUES (?,?,?,?,?,?)",
                source_file, table, file_rows, table_rows, status, loaded_at)
    con.commit()
    return status


def main():
    con = get_connection()
    loaded_at = datetime.now().isoformat(timespec="seconds")
    problems = 0
    print(f"{'file':26}{'file_rows':>10}{'table_rows':>12}{'expected':>10}  status")

    for fname, (table, expected) in CSV_TABLES.items():
        path = RAW_DIR / fname
        file_rows = count_csv_rows(path)
        df = pd.read_csv(path, dtype=str, keep_default_na=False,
                         na_values=[""], encoding="utf-8-sig")
        df = df.astype(object).where(df.notna(), None)
        write_table(con, table, list(df.columns),
                    df.itertuples(index=False, name=None), fname, loaded_at)
        table_rows = con.execute(f"SELECT COUNT(*) FROM [raw].[{table}]").fetchone()[0]
        status = log_result(con, fname, table, file_rows, table_rows, loaded_at)
        if status != "MATCH" or table_rows != expected:
            problems += 1
        print(f"{fname:26}{file_rows:>10}{table_rows:>12}{expected:>10}  {status}")

    for fname, (table, key, expected) in JSON_TABLES.items():
        with open(RAW_DIR / fname, encoding="utf-8") as f:
            data = json.load(f)
        items = data[key] if key else data
        rows = [(json.dumps(item, ensure_ascii=False),) for item in items]
        write_table(con, table, ["payload"], rows, fname, loaded_at, big_text=True)
        table_rows = con.execute(f"SELECT COUNT(*) FROM [raw].[{table}]").fetchone()[0]
        status = log_result(con, fname, table, len(items), table_rows, loaded_at)
        if status != "MATCH" or table_rows != expected:
            problems += 1
        print(f"{fname:26}{len(items):>10}{table_rows:>12}{expected:>10}  {status}")

    con.close()
    print("\nALL OK" if problems == 0 else f"\n{problems} PROBLEM(S) - check above")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
