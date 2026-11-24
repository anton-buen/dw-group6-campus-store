-- SESSION 1, task 2: Cleaning rules for sales                  Lead: ETL Engineer
-- Turn stg.stg_sales into clean, typed rows. The rules for what is valid are in
-- docs/04_source_data_dictionary.md. For each rule decide: FIX it, or REJECT the row.
--   - trim and fix codes (letter case, spaces)
--   - standardize dates (sold_at comes in more than one format)
--   - remove exact duplicates
--   - when the same receipt line comes twice with different values, keep the right one
-- Every rejected row gets a reason. Never drop a row without a record.
--
-- Evidence: your list of cleaning rules, and a count of rows fixed by each rule.

\set ON_ERROR_STOP on

BEGIN;
CREATE OR REPLACE FUNCTION int.try_parse_timestamp(raw_val text)
RETURNS timestamp
LANGUAGE plpgsql
AS $$
DECLARE
    v text := TRIM(raw_val);
BEGIN
    IF v IS NULL OR v = '' THEN
        RETURN NULL;
    ELSIF v ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN
        RETURN v::timestamp;
    ELSIF v ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN
        RETURN to_timestamp(v, 'MM/DD/YYYY HH24:MI:SS')::timestamp;
    ELSIF v ~ '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN
        RETURN to_timestamp(v, 'DD-Mon-YYYY HH24:MI:SS')::timestamp;
    ELSE
        RETURN NULL;
    END IF;
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RETURN NULL;
END;
$$;

-- 1. Reject table (keeps raw row + reason + timestamp)
CREATE TABLE IF NOT EXISTS rej.rej_sales (
    reject_id       serial PRIMARY KEY,
    receipt_no      text,
    line_no         text,
    sold_at         text,
    branch_code     text,
    product_code    text,
    customer_id     text,
    txn_type        text,
    quantity        text,
    unit_price      text,
    discount        text,
    line_total      text,
    payment_method  text,
    updated_at      text,
    batch_id        text,
    reject_reason   text NOT NULL,
    rejected_at     timestamptz NOT NULL DEFAULT now()
);

TRUNCATE TABLE rej.rej_sales RESTART IDENTITY;

-- 2. Deduplicate stg_sales on (receipt_no, line_no), keeping newest updated_at
DROP TABLE IF EXISTS int.int_sales_dedup_removed;
CREATE TABLE int.int_sales_dedup_removed AS
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(receipt_no), TRIM(line_no)
            ORDER BY TRIM(updated_at)::timestamp DESC, ctid DESC
        ) AS rn,
        MIN(TRIM(updated_at)) OVER (
            PARTITION BY TRIM(receipt_no), TRIM(line_no)
        ) AS min_upd,
        MAX(TRIM(updated_at)) OVER (
            PARTITION BY TRIM(receipt_no), TRIM(line_no)
        ) AS max_upd
    FROM stg.stg_sales
)
SELECT
    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
    txn_type, quantity, unit_price, discount, line_total, payment_method,
    updated_at, batch_id,
    CASE WHEN min_upd <> max_upd THEN 'DUPLICATE_SUPERSEDED' ELSE 'DUPLICATE_EXACT' END AS removal_reason
FROM ranked
WHERE rn > 1;

-- 3. Parse, standardize, and classify all deduplicated rows
DROP TABLE IF EXISTS int.int_sales_evaluated;
CREATE TABLE int.int_sales_evaluated AS
WITH deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(receipt_no), TRIM(line_no)
            ORDER BY TRIM(updated_at)::timestamp DESC, ctid DESC
        ) AS rn
    FROM stg.stg_sales
),
parsed AS (
    SELECT
        -- Raw copies for reject table and rule counting
        s.receipt_no     AS raw_receipt_no,
        s.line_no        AS raw_line_no,
        s.sold_at        AS raw_sold_at,
        s.branch_code    AS raw_branch_code,
        s.product_code   AS raw_product_code,
        s.customer_id    AS raw_customer_id,
        s.txn_type       AS raw_txn_type,
        s.quantity       AS raw_quantity,
        s.unit_price     AS raw_unit_price,
        s.discount       AS raw_discount,
        s.line_total     AS raw_line_total,
        s.payment_method AS raw_payment_method,
        s.updated_at     AS raw_updated_at,
        s.batch_id,

        -- Cleaned values
        TRIM(s.receipt_no)                                        AS receipt_no,
        CASE WHEN TRIM(s.line_no) ~ '^[1-9][0-9]*$' THEN TRIM(s.line_no)::integer END AS line_no,
        int.try_parse_timestamp(s.sold_at)                        AS sold_at,
        UPPER(TRIM(s.branch_code))                                AS branch_code,
        UPPER(TRIM(s.product_code))                               AS product_code,
        NULLIF(UPPER(TRIM(s.customer_id)), '')                    AS customer_id,
        UPPER(TRIM(s.txn_type))                                   AS txn_type,
        CASE WHEN TRIM(s.quantity) ~ '^[1-9][0-9]*$' THEN TRIM(s.quantity)::integer END AS quantity,
        CASE
            WHEN REPLACE(REPLACE(REPLACE(TRIM(s.unit_price), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
            THEN REPLACE(REPLACE(REPLACE(TRIM(s.unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2)
        END                                                       AS unit_price,
        CASE
            WHEN NULLIF(TRIM(s.discount), '') IS NULL THEN 0.00::numeric(10,2)
            WHEN REPLACE(REPLACE(REPLACE(TRIM(s.discount), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
            THEN REPLACE(REPLACE(REPLACE(TRIM(s.discount), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2)
        END                                                       AS discount_amount,
        CASE
            WHEN REPLACE(REPLACE(REPLACE(TRIM(s.line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
            THEN REPLACE(REPLACE(REPLACE(TRIM(s.line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2)
        END                                                       AS line_amount,
        UPPER(TRIM(s.payment_method))                             AS payment_method,
        TRIM(s.updated_at)::timestamp                             AS source_updated_at
    FROM deduped s
    WHERE s.rn = 1
)
SELECT
    p.*,
    CASE
        WHEN p.receipt_no IS NULL OR p.receipt_no = '' OR p.line_no IS NULL THEN 'INVALID_RECEIPT_OR_LINE'
        WHEN p.sold_at IS NULL                                              THEN 'INVALID_SOLD_AT_DATE'
        WHEN b.branch_code IS NULL                                          THEN 'UNKNOWN_BRANCH'
        WHEN pr.product_code IS NULL                                        THEN 'UNKNOWN_PRODUCT'
        WHEN p.txn_type NOT IN ('SALE', 'REFUND')                           THEN 'INVALID_TXN_TYPE'
        WHEN p.quantity IS NULL OR p.quantity <= 0                          THEN 'INVALID_QUANTITY'
        WHEN p.unit_price IS NULL OR p.discount_amount IS NULL OR p.line_amount IS NULL THEN 'INVALID_AMOUNT_FORMAT'
        WHEN ROUND(p.quantity * p.unit_price - p.discount_amount, 2) <> ROUND(p.line_amount, 2) THEN 'LINE_TOTAL_MATH_MISMATCH'
        ELSE 'VALID'
    END AS status_code
FROM parsed p
LEFT JOIN int.int_branches b  ON p.branch_code  = b.branch_code
LEFT JOIN int.int_products pr ON p.product_code = pr.product_code;

-- 4. Route rejected rows to rej.rej_sales
INSERT INTO rej.rej_sales (
    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
    txn_type, quantity, unit_price, discount, line_total, payment_method,
    updated_at, batch_id, reject_reason
)
SELECT
    raw_receipt_no, raw_line_no, raw_sold_at, raw_branch_code, raw_product_code, raw_customer_id,
    raw_txn_type, raw_quantity, raw_unit_price, raw_discount, raw_line_total, raw_payment_method,
    raw_updated_at, batch_id, status_code
FROM int.int_sales_evaluated
WHERE status_code <> 'VALID';

-- 5. Materialize clean sales in int.int_sales
DROP TABLE IF EXISTS int.int_sales;
CREATE TABLE int.int_sales AS
SELECT
    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
    txn_type, quantity, unit_price, discount_amount, line_amount,
    payment_method, source_updated_at, batch_id
FROM int.int_sales_evaluated
WHERE status_code = 'VALID';

COMMIT;

-- 6. Evidence 1.2: Cleaning rules summary (problem, action, rows touched)
SELECT rule_name, action, rows_touched FROM (
    SELECT 1 AS ord, 'Exact duplicate receipt lines'                  AS rule_name, 'FIX (deduplicate)' AS action, COUNT(*) AS rows_touched FROM int.int_sales_dedup_removed WHERE removal_reason = 'DUPLICATE_EXACT'
    UNION ALL SELECT 2, 'Conflicting duplicate lines (kept newest updated_at)', 'FIX (deduplicate)', COUNT(*) FROM int.int_sales_dedup_removed WHERE removal_reason = 'DUPLICATE_SUPERSEDED'
    UNION ALL SELECT 3, 'Trim/uppercase branch_code',                  'FIX', COUNT(*) FROM int.int_sales_evaluated WHERE raw_branch_code <> branch_code
    UNION ALL SELECT 4, 'Trim/uppercase txn_type',                     'FIX', COUNT(*) FROM int.int_sales_evaluated WHERE raw_txn_type <> txn_type
    UNION ALL SELECT 5, 'Standardize non-ISO sold_at date formats',    'FIX', COUNT(*) FROM int.int_sales_evaluated WHERE sold_at IS NOT NULL AND TRIM(raw_sold_at) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} '
    UNION ALL SELECT 6, 'Strip PHP/commas from unit_price',            'FIX', COUNT(*) FROM int.int_sales_evaluated WHERE raw_unit_price ~ '(PHP|,)'
    UNION ALL SELECT 7, 'Default empty/NULL discount to 0.00',         'FIX', COUNT(*) FROM int.int_sales_evaluated WHERE NULLIF(TRIM(raw_discount), '') IS NULL
    UNION ALL SELECT 8, 'Blank product category -> Uncategorized',     'FIX', COUNT(*) FROM stg.stg_products WHERE NULLIF(TRIM(category), '') IS NULL
    UNION ALL SELECT 9, 'Reject: ' || reject_reason,                   'REJECT', COUNT(*) FROM rej.rej_sales GROUP BY reject_reason
) r
ORDER BY ord, rule_name;

SELECT
    (SELECT COUNT(*) FROM stg.stg_sales)               AS stg_rows,
    (SELECT COUNT(*) FROM int.int_sales)               AS clean_rows,
    (SELECT COUNT(*) FROM rej.rej_sales)               AS rejected_rows,
    (SELECT COUNT(*) FROM int.int_sales_dedup_removed) AS dupes_removed;