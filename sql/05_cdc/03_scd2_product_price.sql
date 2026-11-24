-- SESSION 2, task 2: SCD Type 2 on product price               Lead: Data Architect + ETL Engineer
-- Run source/04_price_change_may15.sql. Prices changed and new products appeared.
-- The source keeps only the current price. Your warehouse must keep history:
--   keep the old price row, close it (valid_to, is_current), add the new row.
-- Then load the new sales with your watermark load.
--
-- Evidence: both rows of one changed product in mart.dim_product, and a query showing that
-- sales before the change point to the old row and sales after it point to the new row.
\set ON_ERROR_STOP on

BEGIN;

-- 1. Parse current source products cleanly
CREATE TEMP TABLE tmp_src_products AS
SELECT DISTINCT ON (UPPER(TRIM(product_code)))
    UPPER(TRIM(product_code))                                   AS product_code,
    TRIM(REGEXP_REPLACE(product_name, '\s+', ' ', 'g'))         AS product_name,
    INITCAP(LOWER(TRIM(category)))                              AS category,
    REPLACE(REPLACE(REPLACE(TRIM(unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) AS unit_price,
    updated_at::timestamp                                       AS effective_at
FROM src.products
WHERE NULLIF(TRIM(product_code), '') IS NOT NULL
ORDER BY UPPER(TRIM(product_code)), updated_at::timestamp DESC;

-- 2. Identify existing current products whose price changed
CREATE TEMP TABLE tmp_price_changes AS
SELECT
    s.product_code,
    s.product_name,
    s.category,
    d.product_key   AS old_product_key,
    d.unit_price    AS old_price,
    s.unit_price    AS new_price,
    s.effective_at
FROM tmp_src_products s
JOIN mart.dim_product d
  ON s.product_code = d.product_code
 AND d.is_current   = true
WHERE s.unit_price <> d.unit_price;

-- 3. Expire (close) the old SCD Type 2 rows in mart.dim_product
UPDATE mart.dim_product d
SET valid_to   = c.effective_at,
    is_current = false
FROM tmp_price_changes c
WHERE d.product_key = c.old_product_key;

-- 4. Insert the new SCD Type 2 version rows for price-changed products
INSERT INTO mart.dim_product (
    product_code, product_name, category, unit_price, valid_from, valid_to, is_current
)
SELECT
    c.product_code,
    c.product_name,
    c.category,
    c.new_price,
    c.effective_at,
    TIMESTAMP '9999-12-31 00:00:00',
    true
FROM tmp_price_changes c;

-- 5. Insert brand-new products that do not yet exist in mart.dim_product
INSERT INTO mart.dim_product (
    product_code, product_name, category, unit_price, valid_from, valid_to, is_current
)
SELECT
    s.product_code,
    s.product_name,
    s.category,
    s.unit_price,
    s.effective_at,
    TIMESTAMP '9999-12-31 00:00:00',
    true
FROM tmp_src_products s
LEFT JOIN mart.dim_product d
  ON s.product_code = d.product_code
WHERE d.product_code IS NULL;

COMMIT;

-- 6. Run the watermark load to pick up May 15-16 sales against the updated SCD2 dimension
\i sql/05_cdc/01_watermark_load.sql

-- EVIDENCE 2.3a: Both rows of changed products in mart.dim_product (specifically CN-0001, CN-0012, BK-0003)
SELECT
    product_key,
    product_code,
    product_name,
    unit_price,
    valid_from,
    valid_to,
    is_current
FROM mart.dim_product
WHERE product_code IN ('CN-0001', 'CN-0012', 'BK-0003', 'CN-0021', 'BK-0021')
ORDER BY product_code, valid_from;

-- EVIDENCE 2.3b: Summary proving all sales of changed products before May 15 pointto the old product_key (is_current = false) and sales on/after May 15 point to the new row (is_current = true)
SELECT
    p.product_code,
    p.product_key,
    p.unit_price       AS dim_unit_price,
    p.is_current,
    COUNT(f.sales_key) AS sales_count,
    MIN(f.sold_at)     AS earliest_sale,
    MAX(f.sold_at)     AS latest_sale,
    MIN(f.unit_price)  AS min_fact_price,
    MAX(f.unit_price)  AS max_fact_price
FROM mart.dim_product p
JOIN mart.fct_sales f ON p.product_key = f.product_key
WHERE p.product_code IN ('CN-0001', 'CN-0012', 'BK-0003')
GROUP BY p.product_code, p.product_key, p.unit_price, p.is_current, p.valid_from
ORDER BY p.product_code, p.valid_from;

-- Sample individual sales of CN-0001 right before and right after the May 15 price change
(
    SELECT
        'BEFORE_CHANGE' AS period,
        f.receipt_no,
        f.sold_at,
        p.product_code,
        f.product_key,
        p.unit_price AS dim_price,
        f.unit_price AS sale_price,
        p.is_current
    FROM mart.fct_sales f
    JOIN mart.dim_product p ON f.product_key = p.product_key
    WHERE p.product_code = 'CN-0001' AND f.sold_at < TIMESTAMP '2026-05-15 06:00:00'
    ORDER BY f.sold_at DESC
    LIMIT 3
)
UNION ALL
(
    SELECT
        'AFTER_CHANGE' AS period,
        f.receipt_no,
        f.sold_at,
        p.product_code,
        f.product_key,
        p.unit_price AS dim_price,
        f.unit_price AS sale_price,
        p.is_current
    FROM mart.fct_sales f
    JOIN mart.dim_product p ON f.product_key = p.product_key
    WHERE p.product_code = 'CN-0001' AND f.sold_at >= TIMESTAMP '2026-05-15 06:00:00'
    ORDER BY f.sold_at ASC
    LIMIT 3
);