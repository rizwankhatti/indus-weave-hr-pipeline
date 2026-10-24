DROP TABLE IF EXISTS staging.attendance_daily;

WITH calendar_emp AS (
    SELECT 
        e.emp_id,
        e.plant,
        c.d AS attendance_date
    FROM staging.employees e
    CROSS JOIN staging.calendar c
    WHERE c.d >= e.hire_date 
      AND (e.separation_date IS NULL OR c.d <= e.separation_date)
),
roster_shift AS (
    SELECT 
        ce.emp_id,
        ce.plant,
        ce.attendance_date,
        s.shift_code,
        s.shift_name,
        s.start_time,
        s.end_time,
        s.start_min,
        s.end_min,
        s.crosses_midnight,
        s.grace_minutes
    FROM calendar_emp ce
    LEFT JOIN staging.shift_roster r 
        ON r.emp_id = ce.emp_id 
       AND ce.attendance_date BETWEEN r.week_start AND DATEADD(DAY, 6, r.week_start)
    LEFT JOIN staging.shifts s 
        ON s.shift_code = r.shift_code
),
punches_daily AS (
    SELECT 
        emp_id,
        CAST(punch_time AS DATE) AS punch_date,
        MIN(punch_time) AS first_punch,
        MAX(punch_time) AS last_punch,
        COUNT(*) AS total_punches
    FROM staging.punches_clean
    GROUP BY emp_id, CAST(punch_time AS DATE)
),
leaves_daily AS (
    SELECT 
        emp_id,
        leave_date,
        leave_type
    FROM staging.leave_days
)
SELECT 
    rs.emp_id,
    rs.plant,
    rs.attendance_date,
    rs.shift_code,
    rs.start_time AS shift_start,
    rs.end_time AS shift_end,
    
    p.first_punch AS check_in,
    p.last_punch AS check_out,
    p.total_punches,
    
    l.leave_type,
    
    CASE WHEN ph.holiday_date IS NOT NULL THEN 1 ELSE 0 END AS is_holiday,
    CASE WHEN (DATEDIFF(DAY, '19000107', rs.attendance_date) % 7) = 0 THEN 1 ELSE 0 END AS is_sunday,
    
    CASE 
        WHEN p.first_punch IS NOT NULL AND p.last_punch IS NOT NULL 
             THEN DATEDIFF(MINUTE, p.first_punch, p.last_punch)
        ELSE 0 
    END AS work_minutes,

    CASE 
        WHEN p.first_punch IS NOT NULL AND rs.start_min IS NOT NULL 
             THEN CASE 
                    WHEN DATEDIFF(MINUTE, CAST(rs.attendance_date AS DATETIME2), p.first_punch) > (rs.start_min + ISNULL(rs.grace_minutes, 0))
                    THEN DATEDIFF(MINUTE, DATEADD(MINUTE, rs.start_min, CAST(rs.attendance_date AS DATETIME2)), p.first_punch)
                    ELSE 0
                  END
        ELSE 0 
    END AS late_minutes,

    -- Status Logic based on Case Study
    CASE 
        WHEN l.leave_type IS NOT NULL THEN 'On Leave'
        WHEN ph.holiday_date IS NOT NULL THEN 'Holiday'
        WHEN (DATEDIFF(DAY, '19000107', rs.attendance_date) % 7) = 0 THEN 'Weekly Off'
        WHEN p.first_punch IS NOT NULL AND p.last_punch IS NOT NULL THEN 'Present'
        WHEN p.first_punch IS NOT NULL AND p.last_punch IS NULL THEN 'Missing Punch'
        ELSE 'Absent'
    END AS status

INTO staging.attendance_daily
FROM roster_shift rs
LEFT JOIN punches_daily p 
    ON p.emp_id = rs.emp_id AND p.punch_date = rs.attendance_date
LEFT JOIN leaves_daily l 
    ON l.emp_id = rs.emp_id AND l.leave_date = rs.attendance_date
LEFT JOIN staging.plant_holidays ph 
    ON ph.plant = rs.plant AND ph.holiday_date = rs.attendance_date;

GO

-- Reconciliation Output Check
SELECT status, COUNT(*) AS total_days 
FROM staging.attendance_daily 
GROUP BY status;

GO
