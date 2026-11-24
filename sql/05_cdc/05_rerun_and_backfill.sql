-- SESSION 2, task 4: Rerun and backfill                        Lead: ETL Engineer + Data Steward
-- a) RERUN. Run your whole load again from the start of the source. Totals must not change.
--    Check the rows that the change log deleted: did they come back?
-- b) BACKFILL. Run source/06_reextract_2026-03-17.sql. It re-sends ONE past day for all branches.
--    Most rows are already loaded; one branch's rows are new. Load the day. Then load it again.
--
-- Evidence: totals before the rerun and after it (equal); totals for 2026-03-17 before the
-- backfill, after it, and after loading it a second time; totals of every other day unchanged.
\set ON_ERROR_STOP on

-- Ensure tombstone and schema-evolved columns exist
ALTER TABLE src.sales       ADD COLUMN IF NOT EXISTS order_channel text;
ALTER TABLE stg.stg_sales   ADD COLUMN IF NOT EXISTS order_channel text;
ALTER TABLE rej.rej_sales   ADD COLUMN IF NOT EXISTS order_channel text;
ALTER TABLE mart.fct_sales  ADD COLUMN IF NOT EXISTS order_channel text NOT NULL DEFAULT 'UNKNOWN';

CREATE TABLE IF NOT EXISTS audit.deleted_sales_keys (
    receipt_no      text NOT NULL,
    line_no         integer NOT NULL,
    deleted_lsn     bigint NOT NULL,
    deleted_at      timestamp,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (receipt_no, line_no)
);

-- PART A: FULL RERUN FROM SOURCE (must preserve totals & keep deletes gone)
CREATE TEMP TABLE tmp_before_rerun_totals AS
SELECT
    COUNT(*)         AS fct_rows,
    SUM(line_amount) AS fct_pesos
FROM mart.fct_sales;

BEGIN;

-- Re-stage src.sales cleanly
DROP TABLE IF EXISTS stg.stg_sales;
CREATE TABLE stg.stg_sales AS
SELECT *, 'S2_RERUN'::text AS batch_id, now() AS staged_at
FROM src.sales;

-- Deduplicate and clean full src.sales set (excluding rows deleted by change log)
CREATE TEMP TABLE tmp_rerun_ranked AS
SELECT
    s.*,
    ROW_NUMBER() OVER (
        PARTITION BY TRIM(s.receipt_no), TRIM(s.line_no)
        ORDER BY s.updated_at::timestamp DESC, s.ctid DESC
    ) AS rn
FROM src.sales s;

CREATE TEMP TABLE tmp_rerun_eval AS
WITH parsed AS (
    SELECT
        r.receipt_no                                                  AS raw_receipt_no,
        r.line_no                                                     AS raw_line_no,
        r.sold_at                                                     AS raw_sold_at,
        r.branch_code                                                 AS raw_branch_code,
        r.product_code                                                AS raw_product_code,
        r.customer_id                                                 AS raw_customer_id,
        r.txn_type                                                    AS raw_txn_type,
        r.quantity                                                    AS raw_quantity,
        r.unit_price                                                  AS raw_unit_price,
        r.discount                                                    AS raw_discount,
        r.line_total                                                  AS raw_line_total,
        r.payment_method                                              AS raw_payment_method,
        r.updated_at                                                  AS raw_updated_at,
        r.order_channel                                               AS raw_order_channel,

        TRIM(r.receipt_no)                                            AS receipt_no,
        CASE WHEN TRIM(r.line_no) ~ '^[1-9][0-9]*$'
             THEN TRIM(r.line_no)::integer END                        AS line_no,
        int.try_parse_timestamp(r.sold_at)                            AS sold_at,
        UPPER(TRIM(r.branch_code))                                    AS branch_code,
        UPPER(TRIM(r.product_code))                                   AS product_code,
        NULLIF(UPPER(TRIM(r.customer_id)), '')                        AS customer_id,
        UPPER(TRIM(r.txn_type))                                       AS txn_type,
        CASE WHEN TRIM(r.quantity) ~ '^[1-9][0-9]*$'
             THEN TRIM(r.quantity)::integer END                       AS quantity,
        CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(r.unit_price), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(r.unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS unit_price,
        CASE WHEN NULLIF(TRIM(r.discount), '') IS NULL THEN 0.00
             WHEN REPLACE(REPLACE(REPLACE(TRIM(r.discount), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(r.discount), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS discount_amount,
        CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(r.line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(r.line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2) END AS line_amount,
        UPPER(TRIM(r.payment_method))                                 AS payment_method,
        NULLIF(UPPER(TRIM(r.order_channel)), '')                      AS parsed_order_channel,
        r.updated_at::timestamp                                       AS source_updated_at
    FROM tmp_rerun_ranked r
    WHERE r.rn = 1
)
SELECT
    p.*,
    CASE
        WHEN p.sold_at IS NULL                                                   THEN 'INVALID_SOLD_AT_DATE'
        WHEN p.quantity IS NULL OR p.quantity <= 0                               THEN 'INVALID_QUANTITY'
        WHEN p.txn_type NOT IN ('SALE', 'REFUND')                                THEN 'INVALID_TXN_TYPE'
        WHEN b.branch_code IS NULL                                               THEN 'UNKNOWN_BRANCH'
        WHEN pr.product_code IS NULL                                             THEN 'UNKNOWN_PRODUCT'
        WHEN p.unit_price IS NULL OR p.line_amount IS NULL
          OR ROUND(p.quantity * p.unit_price - p.discount_amount, 2) <> ROUND(p.line_amount, 2)
                                                                                 THEN 'LINE_TOTAL_MATH_MISMATCH'
        ELSE NULL
    END AS reject_reason
FROM parsed p
LEFT JOIN mart.dim_branch b   ON p.branch_code = b.branch_code
LEFT JOIN mart.dim_product pr ON p.product_code = pr.product_code
                             AND p.sold_at >= pr.valid_from
                             AND p.sold_at <  pr.valid_to;

INSERT INTO mart.fct_sales (
    receipt_no, line_no, date_key, term_key, branch_key, product_key, customer_key,
    txn_type, payment_method, order_channel, quantity, unit_price, discount_amount,
    line_amount, sold_at, source_updated_at
)
SELECT
    s.receipt_no,
    s.line_no,
    d.date_key,
    d.term_key,
    b.branch_key,
    p.product_key,
    COALESCE(c.customer_key, -1) AS customer_key,
    s.txn_type,
    s.payment_method,
    COALESCE(s.parsed_order_channel, 'UNKNOWN'),
    s.quantity,
    s.unit_price,
    s.discount_amount,
    s.line_amount,
    s.sold_at,
    s.source_updated_at
FROM tmp_rerun_eval s
JOIN shared.dim_date d   ON s.sold_at::date = d.full_date
JOIN mart.dim_branch b   ON s.branch_code = b.branch_code
JOIN mart.dim_product p  ON s.product_code = p.product_code
                        AND s.sold_at >= p.valid_from
                        AND s.sold_at <  p.valid_to
LEFT JOIN mart.dim_customer c ON s.customer_id = c.customer_id
WHERE s.reject_reason IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM audit.deleted_sales_keys del
      WHERE del.receipt_no = s.receipt_no
        AND del.line_no    = s.line_no
  )
ON CONFLICT (receipt_no, line_no) DO UPDATE
SET date_key          = EXCLUDED.date_key,
    term_key          = EXCLUDED.term_key,
    branch_key        = EXCLUDED.branch_key,
    product_key       = EXCLUDED.product_key,
    customer_key      = EXCLUDED.customer_key,
    txn_type          = EXCLUDED.txn_type,
    payment_method    = EXCLUDED.payment_method,
    order_channel     = COALESCE(NULLIF(EXCLUDED.order_channel, 'UNKNOWN'), mart.fct_sales.order_channel),
    quantity          = EXCLUDED.quantity,
    unit_price        = EXCLUDED.unit_price,
    discount_amount   = EXCLUDED.discount_amount,
    line_amount       = EXCLUDED.line_amount,
    sold_at           = EXCLUDED.sold_at,
    source_updated_at = EXCLUDED.source_updated_at,
    loaded_at         = now();

COMMIT;

-- Rerun comparison: before vs after
SELECT
    'BEFORE_RERUN' AS stage,
    fct_rows,
    fct_pesos
FROM tmp_before_rerun_totals
UNION ALL
SELECT
    'AFTER_RERUN'  AS stage,
    COUNT(*),
    SUM(line_amount)
FROM mart.fct_sales;

-- Verify change-log deleted rows did NOT come back
SELECT
    d.receipt_no,
    d.line_no,
    d.deleted_lsn,
    CASE WHEN f.sales_key IS NULL THEN 'GONE (still deleted)' ELSE 'RESURRECTED' END AS status_after_rerun
FROM audit.deleted_sales_keys d
LEFT JOIN mart.fct_sales f
  ON d.receipt_no = f.receipt_no
 AND d.line_no    = f.line_no
ORDER BY d.deleted_lsn;

-- PART B: BACKFILL OF 2026-03-17 RE-EXTRACT (applied twice for idempotency)
CREATE TEMP TABLE tmp_mar17_before AS
SELECT
    COUNT(*)         AS mar17_rows,
    SUM(line_amount) AS mar17_pesos
FROM mart.fct_sales
WHERE sold_at::date = DATE '2026-03-17';

CREATE TEMP TABLE tmp_other_days_before AS
SELECT
    COUNT(*)         AS other_rows,
    SUM(line_amount) AS other_pesos
FROM mart.fct_sales
WHERE sold_at::date <> DATE '2026-03-17';

-- Reusable helper block to upsert src.sales_reextract_20260317 idempotently
CREATE OR REPLACE PROCEDURE int.apply_reextract_20260317()
LANGUAGE plpgsql
AS $$
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS tmp_reextract_ranked (
        receipt_no text, line_no text, sold_at text, branch_code text, product_code text,
        customer_id text, txn_type text, quantity text, unit_price text, discount text,
        line_total text, payment_method text, updated_at text, rn integer
    );
    TRUNCATE tmp_reextract_ranked;

    INSERT INTO tmp_reextract_ranked
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(r.receipt_no), TRIM(r.line_no)
            ORDER BY r.updated_at::timestamp DESC, r.ctid DESC
        ) AS rn
    FROM src.sales_reextract_20260317 r;

    INSERT INTO int.int_sales_dedup_removed (
        receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
        txn_type, quantity, unit_price, discount, line_total, payment_method, updated_at
    )
    SELECT
        r.receipt_no, r.line_no, r.sold_at, r.branch_code, r.product_code, r.customer_id,
        r.txn_type, r.quantity, r.unit_price, r.discount, r.line_total, r.payment_method, r.updated_at
    FROM tmp_reextract_ranked r
    WHERE r.rn > 1
      AND NOT EXISTS (
          SELECT 1 FROM int.int_sales_dedup_removed d
          WHERE TRIM(d.receipt_no) = TRIM(r.receipt_no)
            AND TRIM(d.line_no)    = TRIM(r.line_no)
            AND TRIM(d.updated_at) = TRIM(r.updated_at)
      );

    WITH parsed AS (
        SELECT
            TRIM(r.receipt_no)                                           AS receipt_no,
            CASE WHEN TRIM(r.line_no) ~ '^[1-9][0-9]*$'
                 THEN TRIM(r.line_no)::integer END                       AS line_no,
            int.try_parse_timestamp(r.sold_at)                           AS sold_at,
            UPPER(TRIM(r.branch_code))                                   AS branch_code,
            UPPER(TRIM(r.product_code))                                  AS product_code,
            NULLIF(UPPER(TRIM(r.customer_id)), '')                       AS customer_id,
            UPPER(TRIM(r.txn_type))                                      AS txn_type,
            CASE WHEN TRIM(r.quantity) ~ '^[1-9][0-9]*$'
                 THEN TRIM(r.quantity)::integer END                      AS quantity,
            CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(r.unit_price), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
                 THEN REPLACE(REPLACE(REPLACE(TRIM(r.unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS unit_price,
            CASE WHEN NULLIF(TRIM(r.discount), '') IS NULL THEN 0.00
                 WHEN REPLACE(REPLACE(REPLACE(TRIM(r.discount), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
                 THEN REPLACE(REPLACE(REPLACE(TRIM(r.discount), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS discount_amount,
            CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(r.line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                 THEN REPLACE(REPLACE(REPLACE(TRIM(r.line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2) END AS line_amount,
            UPPER(TRIM(r.payment_method))                                AS payment_method,
            r.updated_at::timestamp                                      AS source_updated_at
        FROM tmp_reextract_ranked r
        WHERE r.rn = 1
    ),
    valid_rows AS (
        SELECT p.*
        FROM parsed p
        JOIN mart.dim_branch b   ON p.branch_code = b.branch_code
        JOIN mart.dim_product pr ON p.product_code = pr.product_code
                                 AND p.sold_at >= pr.valid_from
                                 AND p.sold_at <  pr.valid_to
        WHERE p.sold_at IS NOT NULL
          AND p.quantity IS NOT NULL AND p.quantity > 0
          AND p.txn_type IN ('SALE', 'REFUND')
          AND p.unit_price IS NOT NULL AND p.line_amount IS NOT NULL
          AND ROUND(p.quantity * p.unit_price - p.discount_amount, 2) = ROUND(p.line_amount, 2)
          AND NOT EXISTS (
              SELECT 1 FROM audit.deleted_sales_keys del
              WHERE del.receipt_no = p.receipt_no
                AND del.line_no    = p.line_no
          )
    )
    INSERT INTO mart.fct_sales (
        receipt_no, line_no, date_key, term_key, branch_key, product_key, customer_key,
        txn_type, payment_method, order_channel, quantity, unit_price, discount_amount,
        line_amount, sold_at, source_updated_at
    )
    SELECT
        s.receipt_no,
        s.line_no,
        d.date_key,
        d.term_key,
        b.branch_key,
        p.product_key,
        COALESCE(c.customer_key, -1) AS customer_key,
        s.txn_type,
        s.payment_method,
        'UNKNOWN',
        s.quantity,
        s.unit_price,
        s.discount_amount,
        s.line_amount,
        s.sold_at,
        s.source_updated_at
    FROM valid_rows s
    JOIN shared.dim_date d   ON s.sold_at::date = d.full_date
    JOIN mart.dim_branch b   ON s.branch_code = b.branch_code
    JOIN mart.dim_product p  ON s.product_code = p.product_code
                            AND s.sold_at >= p.valid_from
                            AND s.sold_at <  p.valid_to
    LEFT JOIN mart.dim_customer c ON s.customer_id = c.customer_id
    ON CONFLICT (receipt_no, line_no) DO UPDATE
    SET date_key          = EXCLUDED.date_key,
        term_key          = EXCLUDED.term_key,
        branch_key        = EXCLUDED.branch_key,
        product_key       = EXCLUDED.product_key,
        customer_key      = EXCLUDED.customer_key,
        txn_type          = EXCLUDED.txn_type,
        payment_method    = EXCLUDED.payment_method,
        quantity          = EXCLUDED.quantity,
        unit_price        = EXCLUDED.unit_price,
        discount_amount   = EXCLUDED.discount_amount,
        line_amount       = EXCLUDED.line_amount,
        sold_at           = EXCLUDED.sold_at,
        source_updated_at = EXCLUDED.source_updated_at,
        loaded_at         = now();
END;
$$;

-- Load 1 of 2026-03-17 backfill
BEGIN;
CALL int.apply_reextract_20260317();
COMMIT;

CREATE TEMP TABLE tmp_mar17_after_load1 AS
SELECT
    COUNT(*)         AS mar17_rows,
    SUM(line_amount) AS mar17_pesos
FROM mart.fct_sales
WHERE sold_at::date = DATE '2026-03-17';

-- Load 2 of 2026-03-17 backfill (proves idempotency on second load)
BEGIN;
CALL int.apply_reextract_20260317();
COMMIT;

CREATE TEMP TABLE tmp_mar17_after_load2 AS
SELECT
    COUNT(*)         AS mar17_rows,
    SUM(line_amount) AS mar17_pesos
FROM mart.fct_sales
WHERE sold_at::date = DATE '2026-03-17';

-- 2026-03-17 totals: BEFORE, AFTER LOAD 1, AFTER LOAD 2
SELECT '1_MAR17_BEFORE_BACKFILL' AS step, mar17_rows, mar17_pesos FROM tmp_mar17_before
UNION ALL
SELECT '2_MAR17_AFTER_LOAD_1'    AS step, mar17_rows, mar17_pesos FROM tmp_mar17_after_load1
UNION ALL
SELECT '3_MAR17_AFTER_LOAD_2'    AS step, mar17_rows, mar17_pesos FROM tmp_mar17_after_load2;

-- All other days unchanged: BEFORE vs AFTER backfill
SELECT
    'OTHER_DAYS_BEFORE' AS step,
    other_rows          AS row_count,
    other_pesos         AS peso_total
FROM tmp_other_days_before
UNION ALL
SELECT
    'OTHER_DAYS_AFTER'  AS step,
    COUNT(*),
    SUM(line_amount)
FROM mart.fct_sales
WHERE sold_at::date <> DATE '2026-03-17';