-- SESSION 1, task 4: Audit totals                              Lead: Data Steward
-- Prove that nothing was lost or made up between the source and the warehouse:
--   rows:   source rows = loaded rows + rejected rows + duplicate rows removed
--   pesos:  explain every peso of difference between the source line_total and the warehouse line_amount
-- Write it as ONE query you can run again after every load in Session 2.
--
-- Evidence: the query and its output after the Session 1 load.

\set ON_ERROR_STOP on

-- Evidence 1.5: Row count and peso reconciliation
WITH src_agg AS (
    SELECT
        COUNT(*) AS row_cnt,
        COALESCE(SUM(
            CASE
                WHEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                THEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2)
                ELSE 0.00
            END
        ), 0.00) AS peso_total
    FROM src.sales
),
fct_agg AS (
    SELECT
        COUNT(*) AS row_cnt,
        COALESCE(SUM(line_amount), 0.00)::numeric(12,2) AS peso_total
    FROM mart.fct_sales
),
rej_agg AS (
    SELECT
        COUNT(*) AS row_cnt,
        COALESCE(SUM(
            CASE
                WHEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                THEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2)
                ELSE 0.00
            END
        ), 0.00) AS peso_total
    FROM rej.rej_sales
),
dup_agg AS (
    SELECT
        COUNT(*) AS row_cnt,
        COALESCE(SUM(
            CASE
                WHEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                THEN REPLACE(REPLACE(REPLACE(TRIM(line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2)
                ELSE 0.00
            END
        ), 0.00) AS peso_total
    FROM int.int_sales_dedup_removed
)
SELECT category, row_count, peso_total
FROM (
    SELECT 1 AS ord, '1. Source (src.sales)'                       AS category, s.row_cnt AS row_count, s.peso_total FROM src_agg s
    UNION ALL
    SELECT 2, '2. Loaded (mart.fct_sales)',                                     f.row_cnt, f.peso_total FROM fct_agg f
    UNION ALL
    SELECT 3, '3. Rejected (rej.rej_sales)',                                    r.row_cnt, r.peso_total FROM rej_agg r
    UNION ALL
    SELECT 4, '4. Duplicates removed (int.int_sales_dedup_removed)',            d.row_cnt, d.peso_total FROM dup_agg d
    UNION ALL
    SELECT 5, '5. Reconciled Total (Loaded + Rejected + Dupes)',
           (f.row_cnt + r.row_cnt + d.row_cnt),
           (f.peso_total + r.peso_total + d.peso_total)
    FROM fct_agg f, rej_agg r, dup_agg d
    UNION ALL
    SELECT 6, '6. Unexplained Difference (Source - Reconciled)',
           (s.row_cnt - (f.row_cnt + r.row_cnt + d.row_cnt)),
           (s.peso_total - (f.peso_total + r.peso_total + d.peso_total))
    FROM src_agg s, fct_agg f, rej_agg r, dup_agg d
) audit_summary
ORDER BY ord;