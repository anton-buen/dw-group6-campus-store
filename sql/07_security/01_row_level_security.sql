-- SESSION 3, task 1: Row-level security                        Lead: Data Steward
-- Make a branch manager role that can read the mart but sees ONLY its own branch's sales.
-- Do it in PostgreSQL (CREATE ROLE, GRANT, ENABLE ROW LEVEL SECURITY, CREATE POLICY).
-- Make it work for any branch without writing a new policy for each one.
-- Test it by connecting AS that role (psql -U ..., or SET ROLE). A table owner or superuser
-- skips the policy, so a test as yourself proves nothing.
--
-- Evidence: the same count query run as the manager role and as the owner, with different results.
-- Optional, not graded here but part of Module 7: hide customer id numbers from the manager
-- role (column masking), and log who reads the fact table (audit logging).
\set ON_ERROR_STOP on

BEGIN;

-- 1. Create group role and sample branch-manager login roles (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_branch_manager') THEN
        CREATE ROLE role_branch_manager NOLOGIN NOSUPERUSER NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mgr_bks_main') THEN
        CREATE ROLE mgr_bks_main LOGIN PASSWORD 'campus_mgr' NOSUPERUSER NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mgr_cnt_carp') THEN
        CREATE ROLE mgr_cnt_carp LOGIN PASSWORD 'campus_mgr' NOSUPERUSER NOBYPASSRLS;
    END IF;
END
$$;

GRANT role_branch_manager TO mgr_bks_main, mgr_cnt_carp;

-- 2. Role-to-branch mapping table (add any future branch manager here — no new policy needed)
CREATE TABLE IF NOT EXISTS audit.branch_manager_map (
    role_name   text PRIMARY KEY,
    branch_code text NOT NULL REFERENCES mart.dim_branch(branch_code),
    assigned_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO audit.branch_manager_map (role_name, branch_code)
VALUES
    ('mgr_bks_main', 'BKS-MAIN'),
    ('mgr_cnt_carp', 'CNT-CARP')
ON CONFLICT (role_name) DO UPDATE
SET branch_code = EXCLUDED.branch_code,
    assigned_at = now();

-- 3. Least-privilege grants (read-only on mart + shared dimensions + mapping table; no raw/stg/int/rej/MV access)
GRANT USAGE ON SCHEMA mart, shared, audit TO role_branch_manager;

GRANT SELECT ON
    mart.fct_sales,
    mart.v_net_sales,
    mart.dim_branch,
    mart.dim_product,
    mart.dim_customer
TO role_branch_manager;

GRANT SELECT ON
    shared.dim_date,
    shared.dim_term,
    shared.dim_student,
    shared.dim_program,
    shared.dim_college
TO role_branch_manager;

GRANT SELECT ON audit.branch_manager_map TO role_branch_manager;

-- Explicitly block pre-aggregated summary MV so managers cannot bypass RLS
REVOKE ALL ON mart.mv_net_sales_branch_term FROM PUBLIC, role_branch_manager;

-- 4. Enable RLS on mart.fct_sales and attach ONE dynamic policy for all branch managers
ALTER TABLE mart.fct_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_fct_sales_branch_only ON mart.fct_sales;

CREATE POLICY rls_fct_sales_branch_only
ON mart.fct_sales
FOR SELECT
TO role_branch_manager
USING (
    EXISTS (
        SELECT 1
        FROM audit.branch_manager_map m
        JOIN mart.dim_branch b ON m.branch_code = b.branch_code
        WHERE m.role_name = current_user
          AND b.branch_key = mart.fct_sales.branch_key
    )
);

COMMIT;

-- EVIDENCE 3.1a: Roles, mapping, grants, and active RLS policy metadata
SELECT role_name, branch_code
FROM audit.branch_manager_map
ORDER BY role_name;

SELECT schemaname, tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'mart'
  AND tablename  = 'fct_sales';

-- EVIDENCE 3.1b: Exact same query run as OWNER vs TWO DIFFERENT BRANCH MANAGERS

-- 1) Run as table OWNER (sees all 4 branches: 9,359 rows / 1,541,459.50 net sales)
SELECT
    current_user     AS running_as,
    b.branch_code,
    COUNT(*)         AS fact_rows,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_branch b ON v.branch_key = b.branch_key
GROUP BY ROLLUP (b.branch_code)
ORDER BY b.branch_code;

-- 2) Run as Bookstore Main manager (sees ONLY BKS-MAIN)
SET ROLE mgr_bks_main;
SELECT
    current_user     AS running_as,
    b.branch_code,
    COUNT(*)         AS fact_rows,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_branch b ON v.branch_key = b.branch_key
GROUP BY ROLLUP (b.branch_code)
ORDER BY b.branch_code;
RESET ROLE;

-- 3) Run as Carpark Canteen manager (sees ONLY CNT-CARP — proves 1 policy works for any branch)
SET ROLE mgr_cnt_carp;
SELECT
    current_user     AS running_as,
    b.branch_code,
    COUNT(*)         AS fact_rows,
    SUM(v.net_sales) AS net_sales
FROM mart.v_net_sales v
JOIN mart.dim_branch b ON v.branch_key = b.branch_key
GROUP BY ROLLUP (b.branch_code)
ORDER BY b.branch_code;
RESET ROLE;