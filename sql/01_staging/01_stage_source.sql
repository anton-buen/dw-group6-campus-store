-- SESSION 1, task 1: Staging                                   Lead: ETL Engineer
-- Copy every src table into a stg_ table WITHOUT changing it (same columns, all text).
-- Add only load details if you want them (batch id, loaded_at).
-- Save your starting watermark here: the largest src.sales.updated_at you staged.
--
-- Evidence: row counts of src.* next to stg.* (they must be equal).

\set ON_ERROR_STOP on

BEGIN;

-- 1. Drop and recreate staging tables as exact copies of src.* plus load metadata
DROP TABLE IF EXISTS stg.stg_sales;
CREATE TABLE stg.stg_sales AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.sales;

DROP TABLE IF EXISTS stg.stg_products;
CREATE TABLE stg.stg_products AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.products;

DROP TABLE IF EXISTS stg.stg_branches;
CREATE TABLE stg.stg_branches AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.branches;

DROP TABLE IF EXISTS stg.stg_customers;
CREATE TABLE stg.stg_customers AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.customers;

DROP TABLE IF EXISTS stg.stg_academic_calendar;
CREATE TABLE stg.stg_academic_calendar AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.academic_calendar;

DROP TABLE IF EXISTS stg.stg_enroll_students;
CREATE TABLE stg.stg_enroll_students AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.enroll_students;

DROP TABLE IF EXISTS stg.stg_enroll_courses;
CREATE TABLE stg.stg_enroll_courses AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.enroll_courses;

DROP TABLE IF EXISTS stg.stg_enroll_enrollments;
CREATE TABLE stg.stg_enroll_enrollments AS
SELECT *, 'S1_INITIAL'::text AS batch_id, now() AS staged_at
FROM src.enroll_enrollments;

-- 2. Initialize audit.watermarks and save the starting sales watermark
CREATE TABLE IF NOT EXISTS audit.watermarks (
    stream_name     text PRIMARY KEY,
    last_watermark  timestamp NOT NULL,
    last_lsn        bigint,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

INSERT INTO audit.watermarks (stream_name, last_watermark, updated_at)
SELECT 'sales', MAX(updated_at::timestamp), now()
FROM stg.stg_sales
ON CONFLICT (stream_name) DO UPDATE
SET last_watermark = EXCLUDED.last_watermark,
    updated_at     = EXCLUDED.updated_at;

COMMIT;

-- 3. Evidence 1.1: Row counts of each src table next to its stg_ table
SELECT table_name, src_rows, stg_rows, (src_rows = stg_rows) AS counts_match
FROM (
    SELECT 'sales'              AS table_name, (SELECT COUNT(*) FROM src.sales)              AS src_rows, (SELECT COUNT(*) FROM stg.stg_sales)              AS stg_rows
    UNION ALL SELECT 'products',           (SELECT COUNT(*) FROM src.products),           (SELECT COUNT(*) FROM stg.stg_products)
    UNION ALL SELECT 'branches',           (SELECT COUNT(*) FROM src.branches),           (SELECT COUNT(*) FROM stg.stg_branches)
    UNION ALL SELECT 'customers',          (SELECT COUNT(*) FROM src.customers),          (SELECT COUNT(*) FROM stg.stg_customers)
    UNION ALL SELECT 'academic_calendar',  (SELECT COUNT(*) FROM src.academic_calendar),  (SELECT COUNT(*) FROM stg.stg_academic_calendar)
    UNION ALL SELECT 'enroll_students',    (SELECT COUNT(*) FROM src.enroll_students),    (SELECT COUNT(*) FROM stg.stg_enroll_students)
    UNION ALL SELECT 'enroll_courses',     (SELECT COUNT(*) FROM src.enroll_courses),     (SELECT COUNT(*) FROM stg.stg_enroll_courses)
    UNION ALL SELECT 'enroll_enrollments', (SELECT COUNT(*) FROM src.enroll_enrollments), (SELECT COUNT(*) FROM stg.stg_enroll_enrollments)
) t
ORDER BY table_name;

SELECT * FROM audit.watermarks;

