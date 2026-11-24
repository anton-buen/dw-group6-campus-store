-- SESSION 2, task 1a: CDC with a watermark                     Lead: ETL Engineer
-- 1. Write down your current watermark (largest updated_at you have loaded).
-- 2. Run source/02_source_changes_to_may07.sql   (the store kept selling)
-- 3. Load ONLY the rows with updated_at newer than your watermark. Some are new, some are
--    older rows that were corrected. Then move the watermark forward.
--
-- Evidence: watermark before and after, rows picked up, rows inserted vs rows updated,
-- one corrected row shown before and after, and the audit totals query again.
\set ON_ERROR_STOP on

BEGIN;

-- 0. Ensure schema evolution & tombstone tables exist safely across any run order
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

-- 1. Create and seed watermark table from current mart.fct_sales max updated_at
CREATE TABLE IF NOT EXISTS audit.etl_watermark (
    pipeline_name     text PRIMARY KEY,
    last_updated_at   timestamp NOT NULL,
    updated_on        timestamptz NOT NULL DEFAULT now()
);

INSERT INTO audit.etl_watermark (pipeline_name, last_updated_at)
SELECT 'fct_sales', MAX(source_updated_at)
FROM mart.fct_sales
ON CONFLICT (pipeline_name) DO NOTHING;

-- Capture watermark BEFORE load (drop temp tables first so \i can run multiple times per session)
DROP TABLE IF EXISTS tmp_wm_before, tmp_delta_ranked, tmp_delta_eval, tmp_corrected_before, tmp_upsert_stats;

CREATE TEMP TABLE tmp_wm_before AS
SELECT last_updated_at AS watermark_before
FROM audit.etl_watermark
WHERE pipeline_name = 'fct_sales';

-- 2. Extract ONLY rows newer than the watermark from src.sales, and rank duplicates
CREATE TEMP TABLE tmp_delta_ranked AS
SELECT
    s.*,
    ROW_NUMBER() OVER (
        PARTITION BY TRIM(s.receipt_no), TRIM(s.line_no)
        ORDER BY s.updated_at::timestamp DESC, s.ctid DESC
    ) AS rn
FROM src.sales s
CROSS JOIN tmp_wm_before w
WHERE s.updated_at::timestamp > w.watermark_before;

-- Log removed duplicates from this delta batch (idempotent check prevents double-logging)
INSERT INTO int.int_sales_dedup_removed (
    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
    txn_type, quantity, unit_price, discount, line_total, payment_method, updated_at
)
SELECT
    r.receipt_no, r.line_no, r.sold_at, r.branch_code, r.product_code, r.customer_id,
    r.txn_type, r.quantity, r.unit_price, r.discount, r.line_total, r.payment_method, r.updated_at
FROM tmp_delta_ranked r
WHERE r.rn > 1
  AND NOT EXISTS (
      SELECT 1 FROM int.int_sales_dedup_removed d
      WHERE TRIM(d.receipt_no) = TRIM(r.receipt_no)
        AND TRIM(d.line_no)    = TRIM(r.line_no)
        AND TRIM(d.updated_at) = TRIM(r.updated_at)
  );

-- 3. Parse and evaluate deduplicated delta rows against Session 1 quality rules
CREATE TEMP TABLE tmp_delta_eval AS
WITH parsed AS (
    SELECT
        s.receipt_no                                                  AS raw_receipt_no,
        s.line_no                                                     AS raw_line_no,
        s.sold_at                                                     AS raw_sold_at,
        s.branch_code                                                 AS raw_branch_code,
        s.product_code                                                AS raw_product_code,
        s.customer_id                                                 AS raw_customer_id,
        s.txn_type                                                    AS raw_txn_type,
        s.quantity                                                    AS raw_quantity,
        s.unit_price                                                  AS raw_unit_price,
        s.discount                                                    AS raw_discount,
        s.line_total                                                  AS raw_line_total,
        s.payment_method                                              AS raw_payment_method,
        s.updated_at                                                  AS raw_updated_at,
        s.order_channel                                               AS raw_order_channel,

        TRIM(s.receipt_no)                                            AS receipt_no,
        CASE WHEN TRIM(s.line_no) ~ '^[1-9][0-9]*$'
             THEN TRIM(s.line_no)::integer END                        AS line_no,
        int.try_parse_timestamp(s.sold_at)                            AS sold_at,
        UPPER(TRIM(s.branch_code))                                    AS branch_code,
        UPPER(TRIM(s.product_code))                                   AS product_code,
        NULLIF(UPPER(TRIM(s.customer_id)), '')                        AS customer_id,
        UPPER(TRIM(s.txn_type))                                       AS txn_type,
        CASE WHEN TRIM(s.quantity) ~ '^[1-9][0-9]*$'
             THEN TRIM(s.quantity)::integer END                       AS quantity,
        CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(s.unit_price), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(s.unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS unit_price,
        CASE WHEN NULLIF(TRIM(s.discount), '') IS NULL THEN 0.00
             WHEN REPLACE(REPLACE(REPLACE(TRIM(s.discount), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(s.discount), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END AS discount_amount,
        CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(s.line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
             THEN REPLACE(REPLACE(REPLACE(TRIM(s.line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2) END AS line_amount,
        UPPER(TRIM(s.payment_method))                                 AS payment_method,
        COALESCE(NULLIF(UPPER(TRIM(s.order_channel)), ''), 'UNKNOWN') AS order_channel,
        s.updated_at::timestamp                                       AS source_updated_at
    FROM tmp_delta_ranked s
    WHERE s.rn = 1
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

-- 4. Route rejected delta rows to rej.rej_sales (idempotent guard)
INSERT INTO rej.rej_sales (
    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
    txn_type, quantity, unit_price, discount, line_total, payment_method,
    updated_at, order_channel, batch_id, reject_reason
)
SELECT
    e.raw_receipt_no, e.raw_line_no, e.raw_sold_at, e.raw_branch_code, e.raw_product_code, e.raw_customer_id,
    e.raw_txn_type, e.raw_quantity, e.raw_unit_price, e.raw_discount, e.raw_line_total, e.raw_payment_method,
    e.raw_updated_at, e.raw_order_channel, 'S2_WATERMARK_CDC', e.reject_reason
FROM tmp_delta_eval e
WHERE e.reject_reason IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM rej.rej_sales r
      WHERE TRIM(r.receipt_no) = TRIM(e.raw_receipt_no)
        AND TRIM(r.line_no)    = TRIM(e.raw_line_no)
        AND TRIM(r.updated_at) = TRIM(e.raw_updated_at)
  );

-- 5. Snapshot existing rows in mart.fct_sales that are about to be updated (corrected rows)
CREATE TEMP TABLE tmp_corrected_before AS
SELECT
    f.receipt_no,
    f.line_no,
    f.quantity          AS qty_before,
    f.discount_amount   AS disc_before,
    f.line_amount       AS amt_before,
    f.source_updated_at AS updated_at_before
FROM mart.fct_sales f
JOIN tmp_delta_eval d
  ON f.receipt_no = d.receipt_no
 AND f.line_no    = d.line_no
WHERE d.reject_reason IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM audit.deleted_sales_keys del
      WHERE del.receipt_no = d.receipt_no
        AND del.line_no    = d.line_no
        AND (del.deleted_at IS NULL OR d.source_updated_at <= del.deleted_at)
  );

-- 6. Upsert clean, non-tombstoned delta rows into mart.fct_sales
CREATE TEMP TABLE tmp_upsert_stats AS
WITH upserted AS (
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
        s.order_channel,
        s.quantity,
        s.unit_price,
        s.discount_amount,
        s.line_amount,
        s.sold_at,
        s.source_updated_at
    FROM tmp_delta_eval s
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
            AND (del.deleted_at IS NULL OR s.source_updated_at <= del.deleted_at)
      )
    ON CONFLICT (receipt_no, line_no) DO UPDATE
    SET date_key          = EXCLUDED.date_key,
        term_key          = EXCLUDED.term_key,
        branch_key        = EXCLUDED.branch_key,
        product_key       = EXCLUDED.product_key,
        customer_key      = EXCLUDED.customer_key,
        txn_type          = EXCLUDED.txn_type,
        payment_method    = EXCLUDED.payment_method,
        order_channel     = EXCLUDED.order_channel,
        quantity          = EXCLUDED.quantity,
        unit_price        = EXCLUDED.unit_price,
        discount_amount   = EXCLUDED.discount_amount,
        line_amount       = EXCLUDED.line_amount,
        sold_at           = EXCLUDED.sold_at,
        source_updated_at = EXCLUDED.source_updated_at,
        loaded_at         = now()
    RETURNING (xmax = 0) AS is_insert
)
SELECT
    (SELECT COUNT(*) FROM tmp_delta_ranked)                               AS rows_picked_up,
    COUNT(*) FILTER (WHERE is_insert)                                     AS rows_inserted,
    COUNT(*) FILTER (WHERE NOT is_insert)                                 AS rows_updated,
    (SELECT COUNT(*) FROM tmp_delta_eval WHERE reject_reason IS NOT NULL) AS rows_rejected,
    (SELECT COUNT(*) FROM tmp_delta_ranked WHERE rn > 1)                  AS dupes_removed
FROM upserted;

-- 7. Advance watermark in BOTH audit tables so staging & CDC stay synchronized
UPDATE audit.etl_watermark
SET last_updated_at = (SELECT MAX(source_updated_at) FROM tmp_delta_eval),
    updated_on      = now()
WHERE pipeline_name = 'fct_sales'
  AND EXISTS (SELECT 1 FROM tmp_delta_eval);

UPDATE audit.watermarks
SET last_watermark = (SELECT last_updated_at FROM audit.etl_watermark WHERE pipeline_name = 'fct_sales'),
    updated_at     = now()
WHERE stream_name = 'sales';

COMMIT;

-- Watermark summary + corrected rows
SELECT
    b.watermark_before,
    w.last_updated_at AS watermark_after,
    s.rows_picked_up,
    s.rows_inserted,
    s.rows_updated,
    s.rows_rejected,
    s.dupes_removed
FROM tmp_wm_before b
CROSS JOIN audit.etl_watermark w
CROSS JOIN tmp_upsert_stats s
WHERE w.pipeline_name = 'fct_sales';

SELECT
    cb.receipt_no,
    cb.line_no,
    cb.qty_before,        f.quantity          AS qty_after,
    cb.disc_before,       f.discount_amount   AS disc_after,
    cb.amt_before,        f.line_amount       AS amt_after,
    cb.updated_at_before, f.source_updated_at AS updated_at_after
FROM tmp_corrected_before cb
JOIN mart.fct_sales f
  ON cb.receipt_no = f.receipt_no
 AND cb.line_no    = f.line_no
ORDER BY cb.receipt_no, cb.line_no;