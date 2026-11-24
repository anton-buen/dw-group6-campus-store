-- SESSION 1, task 3: Load the dimensions FIRST                 Lead: ETL Engineer
-- Load shared.dim_term, shared.dim_date, mart.dim_branch, mart.dim_product, mart.dim_customer.
-- The tables already exist (sql/00_setup/02_star_schema.sql). Surrogate keys are made by the
-- warehouse, never copied from the source.
-- Remember the special rows: term_key -1 (no term) and customer_key -1 (unknown buyer).
-- dim_date must cover every day from 2025-08-01 to 2026-07-31.
--
-- Evidence: row count per dimension, and 5 sample rows of each.

\set ON_ERROR_STOP on

BEGIN;

-- 1. shared.dim_term (including -1 = No Term)
INSERT INTO shared.dim_term (term_key, term_code, academic_year, term_name, start_date, end_date)
VALUES (-1, 'NO-TERM', 'N/A', 'No Term', NULL, NULL)
ON CONFLICT (term_key) DO NOTHING;

INSERT INTO shared.dim_term (term_key, term_code, academic_year, term_name, start_date, end_date)
SELECT
    REPLACE(TRIM(term_code), '-', '')::integer AS term_key,
    TRIM(term_code)                            AS term_code,
    TRIM(academic_year)                        AS academic_year,
    TRIM(term_name)                            AS term_name,
    TRIM(start_date)::date                     AS start_date,
    TRIM(end_date)::date                       AS end_date
FROM stg.stg_academic_calendar
ON CONFLICT (term_key) DO UPDATE
SET term_code     = EXCLUDED.term_code,
    academic_year = EXCLUDED.academic_year,
    term_name     = EXCLUDED.term_name,
    start_date    = EXCLUDED.start_date,
    end_date      = EXCLUDED.end_date;

-- 2. shared.dim_date (2025-08-01 to 2026-07-31, with exam weeks and term_key)
WITH cal AS (
    SELECT
        REPLACE(TRIM(term_code), '-', '')::integer            AS term_key,
        TRIM(start_date)::date                                AS start_date,
        TRIM(end_date)::date                                  AS end_date,
        NULLIF(TRIM(prelim_exam_start), '')::date             AS prelim_start,
        NULLIF(TRIM(prelim_exam_end), '')::date               AS prelim_end,
        NULLIF(TRIM(final_exam_start), '')::date              AS final_start,
        NULLIF(TRIM(final_exam_end), '')::date                AS final_end
    FROM stg.stg_academic_calendar
),
dates AS (
    SELECT d::date AS full_date
    FROM generate_series(DATE '2025-08-01', DATE '2026-07-31', INTERVAL '1 day') AS d
)
INSERT INTO shared.dim_date (
    date_key, full_date, day_name, day_of_week, week_of_year,
    month_no, month_name, year_month, quarter_no, year_no,
    is_weekend, is_exam_week, term_key
)
SELECT
    TO_CHAR(d.full_date, 'YYYYMMDD')::integer               AS date_key,
    d.full_date,
    TRIM(TO_CHAR(d.full_date, 'Day'))                       AS day_name,
    EXTRACT(ISODOW FROM d.full_date)::smallint              AS day_of_week,
    EXTRACT(WEEK FROM d.full_date)::smallint                AS week_of_year,
    EXTRACT(MONTH FROM d.full_date)::smallint               AS month_no,
    TRIM(TO_CHAR(d.full_date, 'Month'))                     AS month_name,
    TO_CHAR(d.full_date, 'YYYY-MM')                         AS year_month,
    EXTRACT(QUARTER FROM d.full_date)::smallint             AS quarter_no,
    EXTRACT(YEAR FROM d.full_date)::smallint                AS year_no,
    (EXTRACT(ISODOW FROM d.full_date) IN (6, 7))            AS is_weekend,
    COALESCE(
        (d.full_date BETWEEN c.prelim_start AND c.prelim_end)
        OR (d.full_date BETWEEN c.final_start AND c.final_end),
        false
    )                                                       AS is_exam_week,
    COALESCE(c.term_key, -1)                                AS term_key
FROM dates d
LEFT JOIN cal c
  ON d.full_date BETWEEN c.start_date AND c.end_date
ON CONFLICT (date_key) DO UPDATE
SET is_exam_week = EXCLUDED.is_exam_week,
    term_key     = EXCLUDED.term_key;

-- 3. mart.dim_branch (Type 1)
INSERT INTO mart.dim_branch (branch_code, branch_name, branch_type, building)
SELECT branch_code, branch_name, branch_type, building
FROM int.int_branches
ON CONFLICT (branch_code) DO UPDATE
SET branch_name = EXCLUDED.branch_name,
    branch_type = EXCLUDED.branch_type,
    building    = EXCLUDED.building;

-- 4. mart.dim_product (Type 2 on unit_price; initial load valid from 1900-01-01)
INSERT INTO mart.dim_product (
    product_code, product_name, category, unit_price, valid_from, valid_to, is_current
)
SELECT
    product_code,
    product_name,
    category,
    unit_price,
    TIMESTAMP '1900-01-01',
    TIMESTAMP '9999-12-31',
    true
FROM int.int_products
ON CONFLICT (product_code, valid_from) DO UPDATE
SET product_name = EXCLUDED.product_name,
    category     = EXCLUDED.category,
    unit_price   = EXCLUDED.unit_price;

-- 5. mart.dim_customer (including -1 = Unknown Buyer)
INSERT INTO mart.dim_customer (customer_key, customer_id, customer_type, student_id, staff_no)
VALUES (-1, 'UNKNOWN', 'UNKNOWN', NULL, NULL)
ON CONFLICT (customer_key) DO NOTHING;

INSERT INTO mart.dim_customer (customer_id, customer_type, student_id, staff_no)
SELECT
    customer_id,
    customer_type,
    CASE WHEN customer_type = 'STUDENT' THEN id_number ELSE NULL END AS student_id,
    CASE WHEN customer_type = 'STAFF'   THEN id_number ELSE NULL END AS staff_no
FROM int.int_customers
ON CONFLICT (customer_id) DO UPDATE
SET customer_type = EXCLUDED.customer_type,
    student_id    = EXCLUDED.student_id,
    staff_no      = EXCLUDED.staff_no;

COMMIT;

-- Evidence 1.3: Dimension row counts & special -1 rows
SELECT 'shared.dim_term'   AS dimension_table, COUNT(*) AS row_count FROM shared.dim_term
UNION ALL SELECT 'shared.dim_date',   COUNT(*) FROM shared.dim_date
UNION ALL SELECT 'mart.dim_branch',   COUNT(*) FROM mart.dim_branch
UNION ALL SELECT 'mart.dim_product',  COUNT(*) FROM mart.dim_product
UNION ALL SELECT 'mart.dim_customer', COUNT(*) FROM mart.dim_customer;

SELECT * FROM shared.dim_term WHERE term_key = -1;
SELECT * FROM mart.dim_customer WHERE customer_key = -1;