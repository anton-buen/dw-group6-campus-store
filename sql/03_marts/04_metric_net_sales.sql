-- SESSION 2, task 7: One governed metric                       Lead: Query Analyst
-- Define "net sales" in ONE place (a view here, or a dbt metric / semantic model).
-- The business definition is in docs/01_business_questions.md.
-- Every analytical query and every dashboard chart must read net sales from this one place.
--
-- Evidence: the definition, and one query + one dashboard chart that show the same number.
\set ON_ERROR_STOP on

CREATE OR REPLACE VIEW mart.v_net_sales
WITH (security_invoker = true) AS
SELECT
    f.sales_key,
    f.receipt_no,
    f.line_no,
    f.date_key,
    f.term_key,
    f.branch_key,
    f.product_key,
    f.customer_key,
    f.txn_type,
    f.payment_method,
    f.order_channel,
    f.quantity,
    f.unit_price,
    f.discount_amount,
    f.line_amount,
    CASE
        WHEN f.txn_type = 'SALE'   THEN  f.line_amount
        WHEN f.txn_type = 'REFUND' THEN -f.line_amount
        ELSE 0::numeric(12,2)
    END AS net_sales,
    CASE
        WHEN f.txn_type = 'SALE'   THEN  f.quantity
        WHEN f.txn_type = 'REFUND' THEN -f.quantity
        ELSE 0
    END AS net_units,
    f.sold_at,
    f.source_updated_at
FROM mart.fct_sales f;

-- Verification: Total governed net sales across the entire warehouse
SELECT
    COUNT(*)        AS total_fact_lines,
    SUM(net_sales)  AS total_net_sales_pesos
FROM mart.v_net_sales;