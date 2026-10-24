INSERT INTO warehouse.dim_date (date_key, year, quarter, month, month_name, day_of_week, day_name, is_weekend)
SELECT 
    d, YEAR(d), DATEPART(QUARTER, d), MONTH(d), DATENAME(MONTH, d),
    DATEPART(WEEKDAY, d), DATENAME(WEEKDAY, d),
    CASE WHEN (DATEDIFF(DAY, '19000107', d) % 7) = 0 THEN 1 ELSE 0 END
FROM staging.calendar
WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_date WHERE date_key = d);

INSERT INTO warehouse.dim_department (dept_id, dept_name, plant, cost_center)
SELECT dept_id, dept_name, plant, cost_center
FROM staging.departments
WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_department WHERE dim_department.dept_id = staging.departments.dept_id);

INSERT INTO warehouse.dim_shift (shift_code, shift_name, start_time, end_time, crosses_midnight, grace_minutes)
SELECT shift_code, shift_name, start_time, end_time, crosses_midnight, grace_minutes
FROM staging.shifts
WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_shift WHERE dim_shift.shift_code = staging.shifts.shift_code);

INSERT INTO warehouse.dim_employee (emp_id, full_name, gender, date_of_birth, email, phone, plant, designation, grade, employment_type, hire_date, separation_date, status, annual_leave_entitlement, dept_id, basic_salary, valid_from, valid_to, is_current)
SELECT 
    e.emp_id, e.full_name, e.gender, e.date_of_birth, e.email, e.phone, e.plant,
    h.designation, h.grade, e.employment_type, e.hire_date, e.separation_date, e.status, e.annual_leave_entitlement,
    h.dept_id, h.basic_salary, h.valid_from, h.valid_to, h.is_current
FROM staging.employees e
JOIN staging.employment_history h ON h.emp_id = e.emp_id;

INSERT INTO warehouse.fact_attendance_daily (emp_id, attendance_date, shift_code, check_in, check_out, work_minutes, late_minutes, status)
SELECT emp_id, attendance_date, shift_code, check_in, check_out, work_minutes, late_minutes, status
FROM staging.attendance_daily;

INSERT INTO warehouse.fact_leave_day (request_id, emp_id, leave_type, leave_date)
SELECT request_id, emp_id, leave_type, leave_date
FROM staging.leave_days;
GO
