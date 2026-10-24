USE IndusWeave;
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'warehouse')
BEGIN
    EXEC('CREATE SCHEMA warehouse');
END
GO

DROP TABLE IF EXISTS warehouse.fact_payroll_line;
DROP TABLE IF EXISTS warehouse.fact_overtime_approved;
DROP TABLE IF EXISTS warehouse.fact_leave_day;
DROP TABLE IF EXISTS warehouse.fact_attendance_daily;
DROP TABLE IF EXISTS warehouse.dim_employee;
DROP TABLE IF EXISTS warehouse.dim_department;
DROP TABLE IF EXISTS warehouse.dim_shift;
DROP TABLE IF EXISTS warehouse.dim_date;

CREATE TABLE warehouse.dim_date (
    date_key DATE PRIMARY KEY,
    year INT,
    quarter INT,
    month INT,
    month_name VARCHAR(20),
    day_of_week INT,
    day_name VARCHAR(20),
    is_weekend BIT
);

CREATE TABLE warehouse.dim_department (
    dept_id VARCHAR(50) PRIMARY KEY,
    dept_name VARCHAR(100),
    plant VARCHAR(50),
    cost_center VARCHAR(50)
);

CREATE TABLE warehouse.dim_shift (
    shift_code VARCHAR(20) PRIMARY KEY,
    shift_name VARCHAR(100),
    start_time TIME,
    end_time TIME,
    crosses_midnight INT,
    grace_minutes INT
);

CREATE TABLE warehouse.dim_employee (
    emp_key INT IDENTITY(1,1) PRIMARY KEY,
    emp_id VARCHAR(50),
    full_name VARCHAR(150),
    gender VARCHAR(20),
    date_of_birth DATE,
    email VARCHAR(150),
    phone VARCHAR(50),
    plant VARCHAR(50),
    designation VARCHAR(100),
    grade VARCHAR(20),
    employment_type VARCHAR(50),
    hire_date DATE,
    separation_date DATE,
    status VARCHAR(50),
    annual_leave_entitlement INT,
    dept_id VARCHAR(50),
    basic_salary DECIMAL(12,2),
    valid_from DATE,
    valid_to DATE,
    is_current BIT
);

CREATE TABLE warehouse.fact_attendance_daily (
    attendance_id INT IDENTITY(1,1) PRIMARY KEY,
    emp_id VARCHAR(50),
    attendance_date DATE,
    shift_code VARCHAR(20),
    check_in DATETIME2,
    check_out DATETIME2,
    work_minutes INT,
    late_minutes INT,
    status VARCHAR(50),
    FOREIGN KEY (attendance_date) REFERENCES warehouse.dim_date(date_key)
);

CREATE TABLE warehouse.fact_leave_day (
    leave_day_id INT IDENTITY(1,1) PRIMARY KEY,
    request_id VARCHAR(50),
    emp_id VARCHAR(50),
    leave_type VARCHAR(50),
    leave_date DATE,
    FOREIGN KEY (leave_date) REFERENCES warehouse.dim_date(date_key)
);
GO
