import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from config import get_connection


def run_file(path):
    sql = Path(path).read_text(encoding="utf-8")
    batches = [b.strip() for b in re.split(r"^\s*GO\s*$", sql, flags=re.I | re.M) if b.strip()]
    con = get_connection()
    con.autocommit = True
    cur = con.cursor()
    for b in batches:
        cur.execute(b)
        while True:
            if cur.description:
                print(" | ".join(c[0] for c in cur.description))
                for r in cur.fetchall():
                    print(" | ".join("" if v is None else str(v) for v in r))
                print()
            if not cur.nextset():
                break
    print(f"OK: {path} ({len(batches)} batches)")
    con.close()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        run_file(p)
