"""Shared settings and SQL Server connection for every stage."""
from pathlib import Path
import pyodbc

ROOT = Path(__file__).resolve().parent
RAW_DIR = ROOT / "data" / "raw"

SERVER = r"DESKTOP-4U7MJ1G"
DATABASE = "IndusWeave"
SCHEMAS = ["raw", "staging", "warehouse"]


def _driver():
    names = [d for d in pyodbc.drivers() if "SQL Server" in d]
    for pref in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if pref in names:
            return pref
    if names:
        return names[-1]
    raise RuntimeError("No SQL Server ODBC driver found. Install ODBC Driver 17.")


def _conn_str(database):
    return (f"DRIVER={{{_driver()}}};SERVER={SERVER};DATABASE={database};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;Encrypt=optional;")


def ensure_database():
    """Create the database and the 3 schemas if they do not exist."""
    con = pyodbc.connect(_conn_str("master"), autocommit=True)
    con.execute(f"IF DB_ID('{DATABASE}') IS NULL CREATE DATABASE [{DATABASE}]")
    con.close()
    con = pyodbc.connect(_conn_str(DATABASE), autocommit=True)
    for s in SCHEMAS:
        con.execute(f"IF SCHEMA_ID('{s}') IS NULL EXEC('CREATE SCHEMA [{s}]')")
    con.close()


def get_connection():
    ensure_database()
    return pyodbc.connect(_conn_str(DATABASE))
