-- SESSION 1, task 6: Freshness test and a simple alert         Lead: Data Steward
-- Rule (from the store): every branch sells Monday to Saturday. A branch is STALE when its
-- newest sale is more than 2 days older than the load date.
-- The Session 1 load date is 2026-05-01. Use that date, not today's date.
-- Alert = something a person will see: a row in an audit.alert table and a clear message
-- (RAISE WARNING, or a non-zero exit code in your run script) when a test fails or data is stale.
--
-- Evidence: the alert firing. Say which branch is stale and for how many days.
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS audit.alert (
    alert_id        serial PRIMARY KEY,
    alert_type      text NOT NULL,
    branch_code     text NOT NULL,
    load_date       date NOT NULL,
    newest_sale     date NOT NULL,
    days_stale      integer NOT NULL,
    message         text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Clear prior alert for this load_date if re-running idempotently
DELETE FROM audit.alert WHERE alert_type = 'FRESHNESS_STALE' AND load_date = DATE '2026-05-01';

DO $$
DECLARE
    v_load_date CONSTANT date := DATE '2026-05-01';
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            b.branch_code,
            MAX(f.sold_at)::date AS newest_sale,
            (v_load_date - MAX(f.sold_at)::date) AS days_stale
        FROM mart.fct_sales f
        JOIN mart.dim_branch b ON f.branch_key = b.branch_key
        GROUP BY b.branch_code
        HAVING (v_load_date - MAX(f.sold_at)::date) > 2
        ORDER BY b.branch_code
    LOOP
        INSERT INTO audit.alert (alert_type, branch_code, load_date, newest_sale, days_stale, message)
        VALUES (
            'FRESHNESS_STALE',
            rec.branch_code,
            v_load_date,
            rec.newest_sale,
            rec.days_stale,
            format('ALERT: Branch %s is STALE by %s days (newest sale: %s, load date: %s)',
                   rec.branch_code, rec.days_stale, rec.newest_sale, v_load_date)
        );

        RAISE WARNING 'FRESHNESS ALERT: Branch % is STALE by % days (newest sale: %, load date: %)',
            rec.branch_code, rec.days_stale, rec.newest_sale, v_load_date;
    END LOOP;
END;
$$;

COMMIT;

-- Evidence 1.9: Branch freshness status + audit.alert table
SELECT
    b.branch_code,
    MAX(f.sold_at)::date                       AS newest_sale_date,
    DATE '2026-05-01'                          AS load_date,
    (DATE '2026-05-01' - MAX(f.sold_at)::date) AS days_stale,
    CASE
        WHEN (DATE '2026-05-01' - MAX(f.sold_at)::date) > 2 THEN 'STALE'
        ELSE 'OK'
    END                                        AS freshness_status
FROM mart.fct_sales f
JOIN mart.dim_branch b ON f.branch_key = b.branch_key
GROUP BY b.branch_code
ORDER BY b.branch_code;

SELECT alert_id, alert_type, branch_code, newest_sale, days_stale, message
FROM audit.alert
ORDER BY alert_id;