CREATE OR ALTER FUNCTION staging.parse_date(@x NVARCHAR(50))
RETURNS DATE
AS
BEGIN
    SET @x = LTRIM(RTRIM(@x));
    RETURN COALESCE(
        CASE WHEN @x LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%' THEN TRY_CONVERT(DATE, LEFT(@x,10), 23) END,
        CASE WHEN @x LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, @x, 103) END,
        CASE WHEN @x LIKE '[0-9][0-9]-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9][0-9][0-9]'
             THEN TRY_CONVERT(DATE, REPLACE(@x,'-',' '), 106) END
    );
END
GO

DROP TABLE IF EXISTS staging.departments;
SELECT LTRIM(RTRIM(dept_id)) AS dept_id, LTRIM(RTRIM(dept_name)) AS dept_name,
       LTRIM(RTRIM(plant)) AS plant, LTRIM(RTRIM(cost_center)) AS cost_center,
       LTRIM(RTRIM(previous_name)) AS previous_name, staging.parse_date(renamed_on) AS renamed_on
INTO staging.departments FROM raw.departments;
GO

DROP TABLE IF EXISTS staging.shifts;
SELECT JSON_VALUE(payload,'$.shift_code') AS shift_code,
       JSON_VALUE(payload,'$.name') AS shift_name,
       TRY_CONVERT(TIME, JSON_VALUE(payload,'$.start_time')) AS start_time,
       TRY_CONVERT(TIME, JSON_VALUE(payload,'$.end_time')) AS end_time,
       DATEDIFF(MINUTE, CAST('00:00' AS TIME), TRY_CONVERT(TIME, JSON_VALUE(payload,'$.start_time'))) AS start_min,
       DATEDIFF(MINUTE, CAST('00:00' AS TIME), TRY_CONVERT(TIME, JSON_VALUE(payload,'$.end_time'))) AS end_min,
       CASE JSON_VALUE(payload,'$.crosses_midnight') WHEN 'true' THEN 1 ELSE 0 END AS crosses_midnight,
       TRY_CAST(JSON_VALUE(payload,'$.grace_minutes') AS INT) AS grace_minutes
INTO staging.shifts FROM raw.shifts;
GO

DROP TABLE IF EXISTS staging.shift_roster;
SELECT LTRIM(RTRIM(emp_id)) AS emp_id, staging.parse_date(week_start) AS week_start,
       UPPER(LTRIM(RTRIM(shift_code))) AS shift_code
INTO staging.shift_roster FROM raw.shift_roster;
GO
DROP TABLE IF EXISTS staging.holidays;
SELECT staging.parse_date(holiday_date) AS holiday_date, LTRIM(RTRIM(holiday_name)) AS holiday_name,
       UPPER(LTRIM(RTRIM(scope))) AS scope
INTO staging.holidays FROM raw.holidays;
GO
DROP TABLE IF EXISTS staging.device_mapping;
SELECT LTRIM(RTRIM(device_id)) AS device_id, LTRIM(RTRIM(device_user_id)) AS device_user_id,
       LTRIM(RTRIM(emp_id)) AS emp_id, staging.parse_date(enrolled_on) AS enrolled_on
INTO staging.device_mapping FROM raw.device_mapping;
GO

DROP TABLE IF EXISTS staging._emp_ranked;
WITH t AS (
    SELECT LTRIM(RTRIM(emp_id)) AS emp_id, LTRIM(RTRIM(full_name)) AS full_name,
           UPPER(LTRIM(RTRIM(gender))) AS gender,
           staging.parse_date(date_of_birth) AS date_of_birth,
           LOWER(LTRIM(RTRIM(email))) AS email, LTRIM(RTRIM(phone)) AS phone,
           LTRIM(RTRIM(plant)) AS plant,
           LOWER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(department,'  ',' '),'  ',' '),'  ',' ')))) AS dept_norm,
           LTRIM(RTRIM(designation)) AS designation, UPPER(LTRIM(RTRIM(grade))) AS grade,
           LTRIM(RTRIM(employment_type)) AS employment_type,
           staging.parse_date(hire_date) AS hire_date,
           staging.parse_date(separation_date) AS separation_date,
           LTRIM(RTRIM(status)) AS status,
           TRY_CAST(annual_leave_entitlement AS INT) AS annual_leave_entitlement,
           TRY_CONVERT(DATETIME2, updated_at) AS updated_at, _row_hash
    FROM raw.employees
)
SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC, _row_hash) AS rn
INTO staging._emp_ranked FROM t;
GO

DROP TABLE IF EXISTS staging.employees;
SELECT r.emp_id, r.full_name, r.gender, r.date_of_birth, r.email, r.phone, r.plant,
       d.dept_id, d.dept_name AS department, r.designation, r.grade, r.employment_type,
       r.hire_date, r.separation_date, r.status, r.annual_leave_entitlement, r.updated_at
INTO staging.employees
FROM staging._emp_ranked r
LEFT JOIN staging.departments d
  ON d.plant = r.plant AND (LOWER(d.dept_name) = r.dept_norm OR LOWER(d.previous_name) = r.dept_norm)
WHERE r.rn = 1;
GO

DROP TABLE IF EXISTS staging.employee_merge_log;
SELECT x.emp_id, x._row_hash AS dropped_row_hash, x.updated_at AS dropped_updated_at,
       k.updated_at AS kept_updated_at,
       'duplicate emp_id: older updated_at dropped, latest kept' AS reason
INTO staging.employee_merge_log
FROM staging._emp_ranked x
JOIN staging._emp_ranked k ON k.emp_id = x.emp_id AND k.rn = 1
WHERE x.rn > 1;
GO

DROP TABLE IF EXISTS staging.employment_history;
WITH t AS (
    SELECT LTRIM(RTRIM(emp_id)) AS emp_id, staging.parse_date(effective_from) AS valid_from,
           LTRIM(RTRIM(dept_id)) AS dept_id, LTRIM(RTRIM(designation)) AS designation,
           UPPER(LTRIM(RTRIM(grade))) AS grade, TRY_CAST(basic_salary AS DECIMAL(12,2)) AS basic_salary,
           LTRIM(RTRIM(change_reason)) AS change_reason
    FROM raw.employment_history
)
SELECT *,
       COALESCE(DATEADD(DAY, -1, LEAD(valid_from) OVER (PARTITION BY emp_id ORDER BY valid_from)),
                CAST('9999-12-31' AS DATE)) AS valid_to,
       CASE WHEN LEAD(valid_from) OVER (PARTITION BY emp_id ORDER BY valid_from) IS NULL THEN 1 ELSE 0 END AS is_current
INTO staging.employment_history FROM t;
GO

DROP TABLE IF EXISTS staging.punches_typed;
SELECT p.punch_id, LTRIM(RTRIM(p.device_id)) AS device_id, LTRIM(RTRIM(p.device_user_id)) AS device_user_id,
       TRY_CONVERT(DATETIME2(0), p.punch_time) AS punch_time, m.emp_id
INTO staging.punches_typed
FROM raw.biometric_punches p
LEFT JOIN staging.device_mapping m
  ON m.device_id = LTRIM(RTRIM(p.device_id)) AND m.device_user_id = LTRIM(RTRIM(p.device_user_id));
GO

SELECT 'employees raw' AS item, COUNT(*) AS n FROM raw.employees
UNION ALL SELECT 'employees staging', COUNT(*) FROM staging.employees
UNION ALL SELECT 'employees merged', COUNT(*) FROM staging.employee_merge_log
UNION ALL SELECT 'employees dept unmatched', COUNT(*) FROM staging.employees WHERE dept_id IS NULL
UNION ALL SELECT 'dates failed (hire)', COUNT(*) FROM staging.employees WHERE hire_date IS NULL
UNION ALL SELECT 'history rows', COUNT(*) FROM staging.employment_history
UNION ALL SELECT 'history bad range', COUNT(*) FROM staging.employment_history WHERE valid_to < valid_from
UNION ALL SELECT 'punches raw', COUNT(*) FROM raw.biometric_punches
UNION ALL SELECT 'punches mapped', COUNT(*) FROM staging.punches_typed WHERE emp_id IS NOT NULL
UNION ALL SELECT 'punches unmapped', COUNT(*) FROM staging.punches_typed WHERE emp_id IS NULL;
GO
