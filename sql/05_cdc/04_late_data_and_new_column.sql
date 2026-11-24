-- SESSION 2, task 3: Late and changed data                     Lead: ETL Engineer
-- Run source/05_late_sales_and_new_column_may19.sql.
--   a) src.sales has a NEW COLUMN. Your staging load must not break, and old rows must stay valid.
--      Decide where the new column goes in the star schema and record it in your ADR.
--   b) Some sales arrive LATE: they were sold days ago, before the price change.
--      Check which dim_product row they point to.
--
-- Evidence: the new column in staging and in the mart, and the late sales joined to
-- dim_product showing the price that was true on the day of the sale.
\set ON_ERROR_STOP on

BEGIN;

-- 1. Schema evolution: add order_channel to fact, reject, and staging tables safely
ALTER TABLE stg.stg_sales   ADD COLUMN IF NOT EXISTS order_channel text;
ALTER TABLE rej.rej_sales   ADD COLUMN IF NOT EXISTS order_channel text;
ALTER TABLE mart.fct_sales  ADD COLUMN IF NOT EXISTS order_channel text NOT NULL DEFAULT 'UNKNOWN';

-- 2. Re-stage src.sales so stg.stg_sales captures the new order_channel column without breaking
DROP TABLE IF EXISTS stg.stg_sales;
CREATE TABLE stg.stg_sales AS
SELECT *, 'S2_MAY19'::text AS batch_id, now() AS staged_at
FROM src.sales;

COMMIT;

-- 3. Load May 18-19 sales + late-arriving handheld sales via the unified watermark pipeline
\i sql/05_cdc/01_watermark_load.sql

-- EVIDENCE 2.4: Late-arriving sales joined to mart.dim_product
-- Proves late sales bind to the historical SCD2 row (is_current = false) carrying the price that was true on the day of the sale (85.00 and 20.00, NOT 95.00/25.00)
SELECT
    f.receipt_no,
    f.sold_at,
    f.source_updated_at AS arrived_at,
    p.product_code,
    f.product_key,
    f.unit_price        AS fact_sale_price,
    p.unit_price        AS dim_price_on_sale_day,
    p.valid_from,
    p.valid_to,
    p.is_current        AS is_current_dim_row,
    f.order_channel
FROM mart.fct_sales f
JOIN mart.dim_product p ON f.product_key = p.product_key
WHERE f.source_updated_at::date >= DATE '2026-05-18'
  AND f.sold_at < TIMESTAMP '2026-05-15 06:00:00'
ORDER BY f.sold_at;

-- EVIDENCE 2.5a: New column (order_channel) in stg.stg_sales
SELECT
    COALESCE(order_channel, '[NULL - pre-May 18]') AS stg_order_channel,
    COUNT(*) AS stg_row_count
FROM stg.stg_sales
GROUP BY 1
ORDER BY 1;

-- EVIDENCE 2.5b: New column (order_channel) in mart.fct_sales (old rows valid as UNKNOWN)
SELECT
    order_channel,
    COUNT(*)         AS fact_row_count,
    MIN(sold_at)     AS earliest_sale,
    MAX(sold_at)     AS latest_sale,
    SUM(line_amount) AS total_pesos
FROM mart.fct_sales
GROUP BY order_channel
ORDER BY order_channel;