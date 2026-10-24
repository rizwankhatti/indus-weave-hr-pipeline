# Indus Weave HR Pipeline & Data Warehouse
**PeopleOps Data Hackathon — End-to-End HR Analytics Pipeline**

---

## 📌 Executive Summary
**Indus Weave Textiles** operates with ~1,200 employees across a head office and three manufacturing plants. Following a cloud migration to Polarapt HCM, overtime costs escalated steadily over six months. Due to discrepancies across isolated HCM modules (Core HR, Biometric Gateway, Leave, Overtime, and Payroll), operational numbers lacked cross-functional trust.

This project implements an end-to-end Python and SQL Data Engineering pipeline that ingests raw, messy HCM exports, standardizes operational records, builds an enterprise dimensional star-schema Data Warehouse, executes CFO business intelligence queries, and enforces automated Data Quality (DQ) checks.

---

## 📁 Repository Structure

indus-weave-hr-pipeline/
├── README.md                           # Setup, execution instructions, & architecture
├── requirements.txt                    # Project Python dependencies
├── run_pipeline.py                     # Master orchestration script
├── ingestion/                          # Stage 1: Raw data ingestion scripts
├── profiling/                          # Stage 2: Data profiling reports & utilities
│   ├── profile_files.py
│   └── profile_report.txt
├── transform/                          # Stage 2 & 3: Staging transformations & business logic
│   ├── 01_staging_basic.sql
│   ├── 02_staging_punches_leave.sql
│   ├── 03_attendance_daily.sql
│   └── run_sql.py                      # SQL script execution utility
├── warehouse/                          # Stage 4: Star Schema Data Warehouse
│   └── ddl/
│       ├── 01_create_warehouse.sql     # Warehouse DDL (Schemas, PK/FKs, SCD2)
│       └── 02_populate_warehouse.sql   # Data loading from staging to warehouse
├── presentation/                       # Stage 5: Business Intelligence & CFO Queries
│   └── 01_business_questions.sql       # SQL queries for headcount, late arrivals, leaves, etc.
└── quality/                            # Stage 6: Automated Data Quality Framework
    ├── 03_create_dq_results.sql        # DQ audit log table DDL
    └── dq_checks.py                    # Automated validation test suite

---

## ⚙️ Architecture & Pipeline Stages

The pipeline follows a multi-tiered architecture passing through four isolated database schemas (raw ➔ staging ➔ warehouse ➔ quality).

[Raw HCM Exports] ➔ [raw Schema] ➔ [staging Schema] ➔ [warehouse Schema] ➔ [CFO Analytics]
                                                               📊
                                                [quality.dq_results Audit]

### 🔹 Stage 1: Raw Data Ingestion (raw Schema)
* **Objective:** Ingest 12 untouched raw source files (CSV and nested JSON) across 5 HCM modules into SQL Server.
* **Metadata & Idempotence:** Enriched each raw table with operational metadata columns (`_source_file`, `_loaded_at`, `_row_hash`) to guarantee idempotent loads without duplication.

### 🔹 Stage 2: Data Cleansing & Standardization (staging Schema)
* **Data Profiling:** Automated profiling (`profiling/profile_files.py`) to detect missing values, date anomalies, and structural issues.
* **Employee Deduplication:** Resolved duplicated employee records and merged effective-dated job histories.
* **Biometric Gateway Cleansing:** Mapped device user IDs to employee IDs, quarantined unmapped punches into `staging.rejected_punches`, and removed duplicate punches within a 2-minute window using `LAG()` window functions.
* **Nested JSON Handling:** Flattened `leave_requests.json` into normalized request and approval steps, expanding approved leaves into daily rows.

### 🔹 Stage 3: Business Logic & Attendance Rollup
* **Attendance Consolidation:** Built `staging.attendance_daily` rolled up to one record per employee per scheduled working day.
* **Night Shift Handling:** Offset night shift biometric punches back to their scheduled shift start date before pairing check-ins and check-outs.
* **Metric Computations:** Calculated exact worked minutes, late arrival minutes (>10 mins grace), early departure minutes, and assigned daily statuses (`Present`, `Absent`, `On Leave`, `Holiday`, `Weekly Off`, `Missing Punch`).

### 🔹 Stage 4: Enterprise Data Warehouse (warehouse Schema)
Designed and deployed an optimized Star Schema with strict primary key and foreign key integrity constraints.
* **Dimension Tables:**
  * `warehouse.dim_date`: Complete calendar dimension.
  * `warehouse.dim_department`: Departmental structure, plant mappings, and cost centers.
  * `warehouse.dim_shift`: Shift definitions, start/end times, and grace thresholds.
  * `warehouse.dim_employee`: **SCD Type 2** dimension tracking historical position, grade, plant, and salary changes (`valid_from`, `valid_to`, `is_current`).
* **Fact Tables:**
  * `warehouse.fact_attendance_daily`: Daily work performance, check-in/out timestamps, and late metrics.
  * `warehouse.fact_leave_day`: Granular leave utilization breakdown by leave type.

### 🔹 Stage 5: Business Intelligence & CFO Analytics (presentation Schema)
Executed analytical SQL queries (`presentation/01_business_questions.sql`) leveraging CTEs and window functions to address core workforce challenges:
1. **Department Headcount & Attendance:** Active workforce distribution and attendance volume across manufacturing plants.
2. **Attendance Status Distribution:** Percentage breakdown of present, absent, and leave days.
3. **Punctuality Ranking:** Identification of Top 10 employees with highest cumulative late minutes.
4. **Leave Overuse:** Leave tracking per department and type to identify annual entitlement overruns.

### 🔹 Stage 6: Automated Data Quality Framework (quality Schema)
Implemented an automated Python verification engine (`quality/dq_checks.py`) logging audit results into `quality.dq_results`.
* **Primary Key Integrity:** Verified 100% uniqueness and zero NULL values on `dim_employee` keys.
* **Referential Integrity:** Confirmed orphan-free foreign key joins between fact tables and dimensions (`dim_date`).
* **Business Sanity Controls:** Flagged operational anomalies such as invalid work durations (`work_minutes < 0` or `work_minutes > 960`) and overlapping SCD Type 2 ranges.
* **Domain Validation:** Validated categorical status fields against authorized workforce domain values.

---

## 🛠️ Tech Stack & Prerequisites

* **Language:** Python 3.10+
* **Database Management System:** Microsoft SQL Server (17.0 / 2022)
* **Database Driver:** ODBC Driver 18 for SQL Server
* **Libraries:** `pyodbc`, `python-dotenv`, `pandas`

---

## 🚀 Installation & Execution Guide

### 1. Database Setup
Ensure Microsoft SQL Server is running and target database `IndusWeave` is initialized.

### 2. Environment Configuration
Verify connection settings in Python scripts or set environment variables:
```powershell
DB_SERVER="DESKTOP-4U7MJ1G"
DB_NAME="IndusWeave"
