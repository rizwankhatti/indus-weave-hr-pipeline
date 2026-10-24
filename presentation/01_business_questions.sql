-- ====================================================================
-- STAGE 5: BUSINESS ANALYTICS & QUESTIONS (Warehouse Queries)
-- ====================================================================

USE IndusWeave;
GO

-- 1. Department-wise Attendance & Employee Count
SELECT 
    d.dept_name,
    d.plant,
    COUNT(DISTINCT e.emp_id) AS total_employees,
    COUNT(f.attendance_id) AS total_attendance_records
FROM warehouse.dim_department d
JOIN warehouse.dim_employee e ON e.dept_id = d.dept_id
JOIN warehouse.fact_attendance_daily f ON f.emp_id = e.emp_id
WHERE e.is_current = 1
GROUP BY d.dept_name, d.plant
ORDER BY total_employees DESC;

GO

-- 2. Attendance Status Breakdown (Present, Absent, Leave, etc.)
SELECT 
    status,
    COUNT(*) AS total_days_count,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM warehouse.fact_attendance_daily) AS DECIMAL(5,2)) AS percentage
FROM warehouse.fact_attendance_daily
GROUP BY status
ORDER BY total_days_count DESC;

GO

-- 3. Top 10 Employees with Highest Late Minutes
SELECT TOP 10
    e.emp_id,
    e.full_name,
    d.dept_name,
    SUM(f.late_minutes) AS total_late_minutes,
    COUNT(CASE WHEN f.late_minutes > 0 THEN 1 END) AS times_late
FROM warehouse.fact_attendance_daily f
JOIN warehouse.dim_employee e ON e.emp_id = f.emp_id
JOIN warehouse.dim_department d ON d.dept_id = e.dept_id
WHERE e.is_current = 1
GROUP BY e.emp_id, e.full_name, d.dept_name
ORDER BY total_late_minutes DESC;

GO
