DROP TABLE IF EXISTS staging.device_clock_offset;
WITH fp AS (
    SELECT device_id, emp_id, CAST(punch_time AS DATE) AS d, MIN(punch_time) AS first_punch
    FROM staging.punches_typed WHERE emp_id IS NOT NULL
    GROUP BY device_id, emp_id, CAST(punch_time AS DATE)
), j AS (
    SELECT fp.device_id,
           DATEDIFF(MINUTE, DATEADD(MINUTE, s.start_min, CAST(fp.d AS DATETIME2)), fp.first_punch) AS diff_min
    FROM fp
    JOIN staging.shift_roster r ON r.emp_id = fp.emp_id
         AND fp.d BETWEEN r.week_start AND DATEADD(DAY, 6, r.week_start)
    JOIN staging.shifts s ON s.shift_code = r.shift_code
    WHERE s.crosses_midnight = 0
), a AS (
    SELECT device_id, COUNT(*) AS n, AVG(diff_min * 1.0) AS avg_min
    FROM j WHERE diff_min BETWEEN -240 AND 240 GROUP BY device_id
), b AS (
    SELECT *, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_min) OVER () AS med FROM a
)
SELECT device_id, n, avg_min, med,
       CASE WHEN ABS(avg_min - med) >= 30
            THEN -CAST(ROUND((avg_min - med) / 30.0, 0) * 30 AS INT) ELSE 0 END AS offset_min
INTO staging.device_clock_offset FROM b;
GO
SELECT * FROM staging.device_clock_offset ORDER BY device_id;
GO

DROP TABLE IF EXISTS staging.rejected_punches;
SELECT punch_id, device_id, device_user_id, punch_time,
       'no mapping for device_id + device_user_id (contractor/visitor)' AS reason
INTO staging.rejected_punches
FROM staging.punches_typed WHERE emp_id IS NULL;
GO

DROP TABLE IF EXISTS staging.punches_fixed;
SELECT p.punch_id, p.device_id, p.emp_id,
       DATEADD(MINUTE, ISNULL(o.offset_min, 0), p.punch_time) AS punch_time,
       ISNULL(o.offset_min, 0) AS clock_offset_min
INTO staging.punches_fixed
FROM staging.punches_typed p
LEFT JOIN staging.device_clock_offset o ON o.device_id = p.device_id
WHERE p.emp_id IS NOT NULL;
GO

DROP TABLE IF EXISTS staging._punch_flag;
SELECT *, LAG(punch_time) OVER (PARTITION BY emp_id ORDER BY punch_time, punch_id) AS prev_time
INTO staging._punch_flag FROM staging.punches_fixed;
GO
DROP TABLE IF EXISTS staging.punches_clean;
SELECT punch_id, device_id, emp_id, punch_time, clock_offset_min
INTO staging.punches_clean FROM staging._punch_flag
WHERE prev_time IS NULL OR DATEDIFF(SECOND, prev_time, punch_time) > 120;
GO
DROP TABLE IF EXISTS staging.duplicate_punches;
SELECT punch_id, device_id, emp_id, punch_time, prev_time,
       'within 2 minutes of previous punch of same employee' AS reason
INTO staging.duplicate_punches FROM staging._punch_flag
WHERE prev_time IS NOT NULL AND DATEDIFF(SECOND, prev_time, punch_time) <= 120;
GO

DROP TABLE IF EXISTS staging.calendar;
WITH c AS (
    SELECT CAST('2026-01-01' AS DATE) AS d
    UNION ALL SELECT DATEADD(DAY, 1, d) FROM c WHERE d < '2026-12-31'
)
SELECT d INTO staging.calendar FROM c OPTION (MAXRECURSION 500);
GO
DROP TABLE IF EXISTS staging.plant_holidays;
SELECT DISTINCT p.plant, h.holiday_date, h.holiday_name
INTO staging.plant_holidays
FROM staging.holidays h
JOIN (VALUES ('Head Office','HO'),('Korangi Plant','KOR'),('SITE Plant','SITE'),('Faisalabad Plant','FSD')) p(plant, code)
  ON h.scope = 'ALL' OR h.scope = p.code;
GO

DROP TABLE IF EXISTS staging.leave_approval_steps;
SELECT JSON_VALUE(l.payload,'$.request_id') AS request_id,
       a.step, LTRIM(RTRIM(a.approver_role)) AS approver_role, a.approver_id,
       LTRIM(RTRIM(a.action)) AS action, TRY_CONVERT(DATETIME2, a.acted_at) AS acted_at
INTO staging.leave_approval_steps
FROM raw.leave_requests l
CROSS APPLY OPENJSON(l.payload, '$.approvals')
  WITH (step INT '$.step', approver_role NVARCHAR(30) '$.approver_role',
        approver_id NVARCHAR(30) '$.approver_id', action NVARCHAR(30) '$.action',
        acted_at NVARCHAR(40) '$.acted_at') a;
GO
DROP TABLE IF EXISTS staging.leave_requests;
SELECT JSON_VALUE(payload,'$.request_id') AS request_id,
       JSON_VALUE(payload,'$.employee.emp_id') AS emp_id,
       JSON_VALUE(payload,'$.employee.plant') AS plant,
       JSON_VALUE(payload,'$.leave.type') AS leave_type,
       staging.parse_date(JSON_VALUE(payload,'$.leave.from')) AS from_date,
       staging.parse_date(JSON_VALUE(payload,'$.leave.to')) AS to_date,
       TRY_CAST(JSON_VALUE(payload,'$.leave.days_requested') AS INT) AS days_requested,
       TRY_CONVERT(DATETIME2, JSON_VALUE(payload,'$.submitted_at')) AS submitted_at,
       TRY_CONVERT(DATETIME2, NULLIF(JSON_VALUE(payload,'$.cancelled_at'),'')) AS cancelled_at
INTO staging.leave_requests FROM raw.leave_requests;
GO
ALTER TABLE staging.leave_requests ADD is_valid BIT NULL;
GO
UPDATE r SET is_valid = CASE WHEN r.cancelled_at IS NULL
    AND EXISTS (SELECT 1 FROM staging.leave_approval_steps s WHERE s.request_id = r.request_id
                AND UPPER(s.approver_role)='MANAGER' AND UPPER(s.action)='APPROVED')
    AND EXISTS (SELECT 1 FROM staging.leave_approval_steps s WHERE s.request_id = r.request_id
                AND UPPER(s.approver_role)='HR' AND UPPER(s.action)='APPROVED')
    THEN 1 ELSE 0 END
FROM staging.leave_requests r;
GO

DROP TABLE IF EXISTS staging.leave_days;
SELECT r.request_id, r.emp_id, r.leave_type, c.d AS leave_date
INTO staging.leave_days
FROM staging.leave_requests r
JOIN staging.calendar c ON c.d BETWEEN r.from_date AND r.to_date
WHERE r.is_valid = 1
  AND (DATEDIFF(DAY, '19000107', c.d) % 7) <> 0
  AND NOT EXISTS (SELECT 1 FROM staging.plant_holidays h WHERE h.plant = r.plant AND h.holiday_date = c.d);
GO

SELECT 'punches raw' AS item, COUNT(*) AS n FROM raw.biometric_punches
UNION ALL SELECT 'punches clean', COUNT(*) FROM staging.punches_clean
UNION ALL SELECT 'punches rejected', COUNT(*) FROM staging.rejected_punches
UNION ALL SELECT 'punches duplicate', COUNT(*) FROM staging.duplicate_punches
UNION ALL SELECT 'clean+rejected+dup', (SELECT COUNT(*) FROM staging.punches_clean)
     + (SELECT COUNT(*) FROM staging.rejected_punches) + (SELECT COUNT(*) FROM staging.duplicate_punches)
UNION ALL SELECT 'leave raw', COUNT(*) FROM raw.leave_requests
UNION ALL SELECT 'leave staging', COUNT(*) FROM staging.leave_requests
UNION ALL SELECT 'leave valid', COUNT(*) FROM staging.leave_requests WHERE is_valid = 1
UNION ALL SELECT 'approval steps', COUNT(*) FROM staging.leave_approval_steps
UNION ALL SELECT 'leave days', COUNT(*) FROM staging.leave_days;
GO
