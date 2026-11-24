-- SESSION 1, task 3: Surrogate key lookup and fact load        Lead: ETL Engineer
-- For each clean sales row, look up date_key, term_key, branch_key, product_key, customer_key,
-- then insert into mart.fct_sales. One row per receipt line (receipt_no + line_no).
-- Write this load so that running it twice does NOT add rows twice. You will need that in Session 2.
--
-- Evidence: count of fct_sales rows, and a query that shows no fact row has a missing key.
-- Performance Tuner: EXPLAIN (ANALYZE, BUFFERS) of the load's lookup query, with a one-line reading.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO mart.fct_sales (
    receipt_no, line_no, date_key, term_key, branch_key, product_key, customer_key,
    txn_type, payment_method, quantity, unit_price, discount_amount, line_amount,
    sold_at, source_updated_at
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
    s.quantity,
    s.unit_price,
    s.discount_amount,
    s.line_amount,
    s.sold_at,
    s.source_updated_at
FROM int.int_sales s
JOIN shared.dim_date d
  ON s.sold_at::date = d.full_date
JOIN mart.dim_branch b
  ON s.branch_code = b.branch_code
JOIN mart.dim_product p
  ON s.product_code = p.product_code
 AND s.sold_at >= p.valid_from
 AND s.sold_at <  p.valid_to
LEFT JOIN mart.dim_customer c
  ON s.customer_id = c.customer_id
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

COMMIT;

-- Evidence 1.4: Row count & proof that no fact row has a missing/invalid surrogate key
SELECT COUNT(*) AS fct_sales_rows FROM mart.fct_sales;

SELECT
    COUNT(*) FILTER (WHERE d.date_key IS NULL)     AS missing_date_key,
    COUNT(*) FILTER (WHERE t.term_key IS NULL)     AS missing_term_key,
    COUNT(*) FILTER (WHERE b.branch_key IS NULL)   AS missing_branch_key,
    COUNT(*) FILTER (WHERE p.product_key IS NULL)  AS missing_product_key,
    COUNT(*) FILTER (WHERE c.customer_key IS NULL) AS missing_customer_key
FROM mart.fct_sales f
LEFT JOIN shared.dim_date d     ON f.date_key     = d.date_key
LEFT JOIN shared.dim_term t     ON f.term_key     = t.term_key
LEFT JOIN mart.dim_branch b     ON f.branch_key   = b.branch_key
LEFT JOIN mart.dim_product p    ON f.product_key  = p.product_key
LEFT JOIN mart.dim_customer c   ON f.customer_key = c.customer_key;

-- Evidence 1.10: EXPLAIN (ANALYZE, BUFFERS) of the fact load lookup query
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    s.receipt_no, s.line_no, d.date_key, d.term_key, b.branch_key, p.product_key,
    COALESCE(c.customer_key, -1) AS customer_key, s.line_amount
FROM int.int_sales s
JOIN shared.dim_date d   ON s.sold_at::date = d.full_date
JOIN mart.dim_branch b   ON s.branch_code = b.branch_code
JOIN mart.dim_product p  ON s.product_code = p.product_code
                        AND s.sold_at >= p.valid_from AND s.sold_at < p.valid_to
LEFT JOIN mart.dim_customer c ON s.customer_id = c.customer_id;