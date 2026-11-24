-- SESSION 2, task 6: Analytical SQL                            Lead: Query Analyst
-- Answer the business questions in docs/01_business_questions.md.
-- Use ROLLUP or CUBE where a question asks for subtotals, and window functions where it asks
-- for a rank, a running total, a moving average or a change from the previous period.
-- Read net sales from your one governed metric (sql/03_marts/04_metric_net_sales.sql).
-- For every ROLLUP / CUBE answer, add a check that the subtotals add up to the grand total.
--
-- Performance Tuner: EXPLAIN (ANALYZE, BUFFERS) for one of these queries, before and after
-- one index or summary table. Say what changed in the plan.
\set ON_ERROR_STOP on

-- Q1: Net sales per branch type, branch, and term (ROLLUP + subtotal check)
SELECT
    CASE WHEN GROUPING(b.branch_type) = 1 THEN 'ALL BRANCH TYPES' ELSE b.branch_type END AS branch_type,
    CASE WHEN GROUPING(b.branch_name) = 1 THEN 'ALL BRANCHES'     ELSE b.branch_name END AS branch_name,
    CASE WHEN GROUPING(t.term_code)   = 1 THEN 'ALL TERMS'        ELSE t.term_code   END AS term_code,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_branch b ON v.branch_key = b.branch_key
JOIN shared.dim_term t ON v.term_key   = t.term_key
GROUP BY ROLLUP (b.branch_type, b.branch_name, t.term_code)
ORDER BY
    GROUPING(b.branch_type), b.branch_type,
    GROUPING(b.branch_name), b.branch_name,
    GROUPING(t.term_code),   t.term_code;

-- Q1 Subtotal Check: verify each ROLLUP level sums to the exact grand total
WITH q1 AS (
    SELECT
        GROUPING(b.branch_type) AS g_type,
        GROUPING(b.branch_name) AS g_branch,
        GROUPING(t.term_code)   AS g_term,
        SUM(v.net_sales)        AS net_sales
    FROM mart.v_net_sales v
    JOIN mart.dim_branch b ON v.branch_key = b.branch_key
    JOIN shared.dim_term t ON v.term_key   = t.term_key
    GROUP BY ROLLUP (b.branch_type, b.branch_name, t.term_code)
)
SELECT
    SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 0 AND g_term = 0) AS detail_sum,
    SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 0 AND g_term = 1) AS branch_subtotal_sum,
    SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 1 AND g_term = 1) AS branch_type_subtotal_sum,
    SUM(net_sales) FILTER (WHERE g_type = 1 AND g_branch = 1 AND g_term = 1) AS grand_total,
    (
        SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 0 AND g_term = 0) =
        SUM(net_sales) FILTER (WHERE g_type = 1 AND g_branch = 1 AND g_term = 1)
        AND
        SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 0 AND g_term = 1) =
        SUM(net_sales) FILTER (WHERE g_type = 1 AND g_branch = 1 AND g_term = 1)
        AND
        SUM(net_sales) FILTER (WHERE g_type = 0 AND g_branch = 1 AND g_term = 1) =
        SUM(net_sales) FILTER (WHERE g_type = 1 AND g_branch = 1 AND g_term = 1)
    ) AS all_levels_match_grand_total
FROM q1;

-- Q2: Net sales by product category and customer type (CUBE + subtotal check)
SELECT
    CASE WHEN GROUPING(p.category)      = 1 THEN 'ALL CATEGORIES'     ELSE p.category      END AS product_category,
    CASE WHEN GROUPING(c.customer_type) = 1 THEN 'ALL CUSTOMER TYPES' ELSE c.customer_type END AS customer_type,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_product p  ON v.product_key  = p.product_key
JOIN mart.dim_customer c ON v.customer_key = c.customer_key
GROUP BY CUBE (p.category, c.customer_type)
ORDER BY
    GROUPING(p.category),      p.category,
    GROUPING(c.customer_type), c.customer_type;

-- Q2 Subtotal Check: verify category subtotals and customer_type subtotals match grand total
WITH q2 AS (
    SELECT
        GROUPING(p.category)      AS g_cat,
        GROUPING(c.customer_type) AS g_cust,
        SUM(v.net_sales)          AS net_sales
    FROM mart.v_net_sales v
    JOIN mart.dim_product p  ON v.product_key  = p.product_key
    JOIN mart.dim_customer c ON v.customer_key = c.customer_key
    GROUP BY CUBE (p.category, c.customer_type)
)
SELECT
    SUM(net_sales) FILTER (WHERE g_cat = 0 AND g_cust = 0) AS detail_sum,
    SUM(net_sales) FILTER (WHERE g_cat = 0 AND g_cust = 1) AS category_subtotal_sum,
    SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 0) AS customer_type_subtotal_sum,
    SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 1) AS grand_total,
    (
        SUM(net_sales) FILTER (WHERE g_cat = 0 AND g_cust = 0) =
        SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 1)
        AND
        SUM(net_sales) FILTER (WHERE g_cat = 0 AND g_cust = 1) =
        SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 1)
        AND
        SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 0) =
        SUM(net_sales) FILTER (WHERE g_cat = 1 AND g_cust = 1)
    ) AS all_subtotals_match_grand_total
FROM q2;

-- Q3: Top 5 products of each branch in each term, by net sales
WITH ranked AS (
    SELECT
        b.branch_name,
        t.term_code,
        p.product_code,
        p.product_name,
        SUM(v.net_sales) AS net_sales,
        RANK() OVER (
            PARTITION BY b.branch_name, t.term_code
            ORDER BY SUM(v.net_sales) DESC
        ) AS sales_rank
    FROM mart.v_net_sales v
    JOIN mart.dim_branch b  ON v.branch_key  = b.branch_key
    JOIN shared.dim_term t  ON v.term_key    = t.term_key
    JOIN mart.dim_product p ON v.product_key = p.product_key
    GROUP BY b.branch_name, t.term_code, p.product_code, p.product_name
)
SELECT branch_name, term_code, sales_rank, product_code, product_name, net_sales
FROM ranked
WHERE sales_rank <= 5
ORDER BY branch_name, term_code, sales_rank;

-- Q4a: Monthly net sales per branch, MoM change (LAG), and term running total
WITH monthly AS (
    SELECT
        b.branch_name,
        t.term_code,
        d.year_month,
        SUM(v.net_sales) AS monthly_net_sales
    FROM mart.v_net_sales v
    JOIN mart.dim_branch b ON v.branch_key = b.branch_key
    JOIN shared.dim_date d ON v.date_key   = d.date_key
    JOIN shared.dim_term t ON v.term_key   = t.term_key
    GROUP BY b.branch_name, t.term_code, d.year_month
)
SELECT
    branch_name,
    term_code,
    year_month,
    monthly_net_sales,
    monthly_net_sales - LAG(monthly_net_sales) OVER (
        PARTITION BY branch_name ORDER BY year_month
    ) AS mom_change,
    SUM(monthly_net_sales) OVER (
        PARTITION BY branch_name, term_code
        ORDER BY year_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS term_running_total
FROM monthly
ORDER BY branch_name, year_month;

-- Q4b: Canteens 7-day moving average of daily net sales (latest 14 days shown)
WITH daily_canteen AS (
    SELECT
        b.branch_name,
        d.full_date,
        SUM(v.net_sales) AS daily_net_sales
    FROM mart.v_net_sales v
    JOIN mart.dim_branch b ON v.branch_key = b.branch_key
    JOIN shared.dim_date d ON v.date_key   = d.date_key
    WHERE b.branch_type = 'CANTEEN'
    GROUP BY b.branch_name, d.full_date
),
moving AS (
    SELECT
        branch_name,
        full_date,
        daily_net_sales,
        ROUND(AVG(daily_net_sales) OVER (
            PARTITION BY branch_name
            ORDER BY full_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2) AS moving_avg_7d,
        ROW_NUMBER() OVER (PARTITION BY branch_name ORDER BY full_date DESC) AS rn_recent
    FROM daily_canteen
)
SELECT branch_name, full_date, daily_net_sales, moving_avg_7d
FROM moving
WHERE rn_recent <= 7
ORDER BY branch_name, full_date;

-- Q5a: Canteen average daily net sales — exam weeks vs other weeks
WITH daily_canteen AS (
    SELECT
        d.full_date,
        d.is_exam_week,
        SUM(v.net_sales) AS daily_net_sales
    FROM mart.v_net_sales v
    JOIN mart.dim_branch b ON v.branch_key = b.branch_key
    JOIN shared.dim_date d ON v.date_key   = d.date_key
    WHERE b.branch_type = 'CANTEEN'
    GROUP BY d.full_date, d.is_exam_week
)
SELECT
    CASE WHEN is_exam_week THEN 'Exam Week' ELSE 'Regular Week' END AS week_type,
    COUNT(*)                      AS active_days,
    ROUND(AVG(daily_net_sales), 2) AS avg_daily_net_sales,
    SUM(daily_net_sales)          AS total_net_sales
FROM daily_canteen
GROUP BY is_exam_week
ORDER BY is_exam_week DESC;

-- Q5b: Student spend per buyer by college (joined via shared dimensions)
SELECT
    col.college_code,
    col.college_name,
    COUNT(DISTINCT c.customer_key)                                        AS student_buyers,
    SUM(v.net_sales)                                                      AS total_net_sales,
    ROUND(SUM(v.net_sales) / NULLIF(COUNT(DISTINCT c.customer_key), 0), 2) AS spend_per_buyer
FROM mart.v_net_sales v
JOIN mart.dim_customer c   ON v.customer_key = c.customer_key
JOIN shared.dim_student s  ON c.student_id   = s.student_id AND s.is_current = true
JOIN shared.dim_program pr ON s.program_key  = pr.program_key
JOIN shared.dim_college col ON pr.college_key = col.college_key
WHERE c.customer_type = 'STUDENT'
GROUP BY col.college_code, col.college_name
ORDER BY spend_per_buyer DESC;

-- Q6: Price-changed products — units sold & net sales at old vs new price
WITH changed_products AS (
    SELECT product_code
    FROM mart.dim_product
    GROUP BY product_code
    HAVING COUNT(*) > 1
)
SELECT
    p.product_code,
    p.product_name,
    CASE WHEN p.is_current THEN 'NEW_PRICE' ELSE 'OLD_PRICE' END AS price_period,
    p.unit_price     AS dim_unit_price,
    p.valid_from,
    p.valid_to,
    SUM(v.net_units) AS units_sold,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_product p      ON v.product_key  = p.product_key
JOIN changed_products cp     ON p.product_code = cp.product_code
GROUP BY p.product_code, p.product_name, p.is_current, p.unit_price, p.valid_from, p.valid_to
ORDER BY p.product_code, p.valid_from;
