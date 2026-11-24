-- SESSION 1, task 6: Data-quality tests                        Lead: Data Steward
-- Write at least one test for each kind:
--   completeness  (a value that must be there is there)
--   validity      (a value has the right type, format or range)
--   uniqueness    (the grain holds: no duplicate receipt line)
--   consistency   (values agree with each other, and every key finds its dimension row)
--   freshness     (see 03_freshness_alert.sql)
-- A test returns the failing rows. Zero rows = pass.
-- Failing source rows go to a reject table in schema rej, with the reason and the time.
-- Save each test run (test name, time, rows failed, pass/fail) in schema audit.
--
-- Evidence: the test results table, and the reject table grouped by reason.
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS audit.dq_test_results (
    run_id          serial PRIMARY KEY,
    batch_label     text NOT NULL,
    test_category   text NOT NULL,
    test_name       text NOT NULL,
    rows_failed     integer NOT NULL,
    status          text NOT NULL,
    run_at          timestamptz NOT NULL DEFAULT now()
);

-- Clear prior S1_INITIAL run if re-running idempotently
DELETE FROM audit.dq_test_results WHERE batch_label = 'S1_INITIAL';

-- 1. COMPLETENESS: Required columns in mart.fct_sales must not be NULL
INSERT INTO audit.dq_test_results (batch_label, test_category, test_name, rows_failed, status)
SELECT
    'S1_INITIAL',
    'completeness',
    'fct_sales_no_null_required_fields',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fct_sales
WHERE receipt_no IS NULL
   OR line_no IS NULL
   OR date_key IS NULL
   OR term_key IS NULL
   OR branch_key IS NULL
   OR product_key IS NULL
   OR customer_key IS NULL
   OR line_amount IS NULL;

-- 2. VALIDITY: Quantity > 0, unit_price >= 0, discount >= 0, valid txn_type
INSERT INTO audit.dq_test_results (batch_label, test_category, test_name, rows_failed, status)
SELECT
    'S1_INITIAL',
    'validity',
    'fct_sales_valid_ranges_and_txn_type',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fct_sales
WHERE quantity <= 0
   OR unit_price < 0
   OR discount_amount < 0
   OR txn_type NOT IN ('SALE', 'REFUND');

-- 3. UNIQUENESS: Grain holds (no duplicate receipt_no + line_no)
INSERT INTO audit.dq_test_results (batch_label, test_category, test_name, rows_failed, status)
SELECT
    'S1_INITIAL',
    'uniqueness',
    'fct_sales_unique_receipt_line_grain',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT receipt_no, line_no
    FROM mart.fct_sales
    GROUP BY receipt_no, line_no
    HAVING COUNT(*) > 1
) dupes;

-- 4. CONSISTENCY (Math): quantity * unit_price - discount_amount = line_amount
INSERT INTO audit.dq_test_results (batch_label, test_category, test_name, rows_failed, status)
SELECT
    'S1_INITIAL',
    'consistency',
    'fct_sales_line_amount_math_check',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fct_sales
WHERE ROUND(quantity * unit_price - discount_amount, 2) <> ROUND(line_amount, 2);

-- 5. CONSISTENCY (Referential Integrity): Every foreign key finds its dimension row
INSERT INTO audit.dq_test_results (batch_label, test_category, test_name, rows_failed, status)
SELECT
    'S1_INITIAL',
    'consistency',
    'fct_sales_all_dimension_keys_resolve',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fct_sales f
LEFT JOIN shared.dim_date d     ON f.date_key     = d.date_key
LEFT JOIN shared.dim_term t     ON f.term_key     = t.term_key
LEFT JOIN mart.dim_branch b     ON f.branch_key   = b.branch_key
LEFT JOIN mart.dim_product p    ON f.product_key  = p.product_key
LEFT JOIN mart.dim_customer c   ON f.customer_key = c.customer_key
WHERE d.date_key IS NULL
   OR t.term_key IS NULL
   OR b.branch_key IS NULL
   OR p.product_key IS NULL
   OR c.customer_key IS NULL;

COMMIT;

-- Evidence 1.7: Data-quality test results table
SELECT test_category, test_name, rows_failed, status, run_at
FROM audit.dq_test_results
WHERE batch_label = 'S1_INITIAL'
ORDER BY run_id;

-- Evidence 1.8: Reject table grouped by reason
SELECT reject_reason, COUNT(*) AS rejected_rows
FROM rej.rej_sales
GROUP BY reject_reason
ORDER BY rejected_rows DESC, reject_reason;