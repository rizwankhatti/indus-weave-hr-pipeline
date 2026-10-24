import os
import pyodbc

# Database connection parameters
SERVER = os.getenv("DB_SERVER", "DESKTOP-4U7MJ1G")
DATABASE = os.getenv("DB_NAME", "IndusWeave")
DRIVER = "{ODBC Driver 18 for SQL Server}"

def get_connection():
    conn_str = (
        f"DRIVER={DRIVER};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)

def log_result(cursor, check_name, check_category, table_name, status, records_failed, error_message):
    sql = """
        INSERT INTO quality.dq_results (check_name, check_category, table_name, status, records_failed, error_message)
        VALUES (?, ?, ?, ?, ?, ?)
    """
    cursor.execute(sql, (check_name, check_category, table_name, status, records_failed, error_message))
    print(f"[{status}] {check_category} - {check_name} on {table_name} (Failed rows: {records_failed})")

def run_dq_checks():
    conn = get_connection()
    conn.autocommit = True
    cursor = conn.cursor()

    print("--- STARTING AUTOMATED DATA QUALITY CHECKS ---")

    # Ensure schema and table exist
    cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'quality') EXEC('CREATE SCHEMA quality');
        IF NOT EXISTS (SELECT * FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'quality' AND t.name = 'dq_results')
        BEGIN
            CREATE TABLE quality.dq_results (
                check_id INT IDENTITY(1,1) PRIMARY KEY,
                check_name VARCHAR(150),
                check_category VARCHAR(50),
                table_name VARCHAR(100),
                status VARCHAR(20),
                records_failed INT,
                error_message VARCHAR(500),
                executed_at DATETIME2 DEFAULT SYSDATETIME()
            )
        END
    """)

    # 1. Uniqueness & Not-Null Check on Primary Keys
    try:
        cursor.execute("SELECT COUNT(*) FROM warehouse.dim_employee WHERE emp_key IS NULL")
        nulls = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM (SELECT emp_key, COUNT(*) as cnt FROM warehouse.dim_employee GROUP BY emp_key HAVING COUNT(*) > 1) x")
        dupes = cursor.fetchone()[0]
        
        total_failed = nulls + dupes
        status = "FAIL" if total_failed > 0 else "PASS"
        log_result(cursor, "PK Uniqueness & Not-Null", "Uniqueness", "warehouse.dim_employee", status, total_failed, f"Nulls: {nulls}, Dupes: {dupes}")
    except Exception as e:
        print(f"Error in PK check: {e}")

    # 2. Referential Integrity Check
    try:
        cursor.execute("""
            SELECT COUNT(*) FROM warehouse.fact_attendance_daily f
            LEFT JOIN warehouse.dim_date d ON f.attendance_date = d.date_key
            WHERE d.date_key IS NULL
        """)
        orphans = cursor.fetchone()[0]
        status = "FAIL" if orphans > 0 else "PASS"
        log_result(cursor, "Fact Attendance Date FK Check", "Referential", "warehouse.fact_attendance_daily", status, orphans, f"Orphan records: {orphans}")
    except Exception as e:
        print(f"Error in Referential check: {e}")

    # 3. Business Sanity: Worked Minutes Check
    try:
        cursor.execute("""
            SELECT COUNT(*) FROM warehouse.fact_attendance_daily
            WHERE work_minutes < 0 OR work_minutes > 960
        """)
        sanity_fails = cursor.fetchone()[0]
        status = "FAIL" if sanity_fails > 0 else "PASS"
        log_result(cursor, "Worked Hours Sanity Check", "Business Sanity", "warehouse.fact_attendance_daily", status, sanity_fails, f"Invalid worked minutes: {sanity_fails}")
    except Exception as e:
        print(f"Error in Business Sanity check: {e}")

    # 4. Business Sanity: SCD2 Overlapping Ranges
    try:
        cursor.execute("""
            SELECT COUNT(*) FROM warehouse.dim_employee e1
            JOIN warehouse.dim_employee e2 ON e1.emp_id = e2.emp_id AND e1.emp_key <> e2.emp_key
            WHERE e1.valid_from <= ISNULL(e2.valid_to, '9999-12-31') 
              AND ISNULL(e1.valid_to, '9999-12-31') >= e2.valid_from
        """)
        overlaps = cursor.fetchone()[0]
        status = "FAIL" if overlaps > 0 else "PASS"
        log_result(cursor, "SCD2 Overlapping Range Check", "Business Sanity", "warehouse.dim_employee", status, overlaps, f"Overlapping ranges: {overlaps}")
    except Exception as e:
        print(f"Error in SCD2 check: {e}")

    # 5. Accepted Values Check
    try:
        cursor.execute("""
            SELECT COUNT(*) FROM warehouse.fact_attendance_daily
            WHERE status NOT IN ('Present', 'Absent', 'Leave', 'Half-Day', 'Late', 'Off')
        """)
        invalid_vals = cursor.fetchone()[0]
        status = "FAIL" if invalid_vals > 0 else "PASS"
        log_result(cursor, "Accepted Values Attendance Status", "Domain", "warehouse.fact_attendance_daily", status, invalid_vals, f"Invalid status count: {invalid_vals}")
    except Exception as e:
        print(f"Error in Accepted Values check: {e}")

    print("--- DATA QUALITY CHECKS COMPLETED SUCCESSFULLY ---")
    cursor.close()
    conn.close()

if __name__ == "__main__":
    run_dq_checks()
