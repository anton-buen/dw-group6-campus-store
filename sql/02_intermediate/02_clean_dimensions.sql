-- SESSION 1, task 2: Cleaning rules for products, branches, customers
-- Same idea as sales: trim and fix codes, one row per real product / branch / customer.
\set ON_ERROR_STOP on

BEGIN;

-- 1. Clean Branches (trim, uppercase codes, deduplicate)
DROP TABLE IF EXISTS int.int_branches;
CREATE TABLE int.int_branches AS
WITH ranked AS (
    SELECT
        UPPER(TRIM(branch_code)) AS branch_code,
        TRIM(branch_name)        AS branch_name,
        UPPER(TRIM(branch_type)) AS branch_type,
        TRIM(building)           AS building,
        opened_on::date          AS opened_on,
        ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(branch_code)) ORDER BY opened_on DESC) AS rn
    FROM stg.stg_branches
)
SELECT branch_code, branch_name, branch_type, building, opened_on
FROM ranked
WHERE rn = 1;

-- 2. Clean Products (trim, uppercase codes, blank category -> 'Uncategorized', clean price, deduplicate)
DROP TABLE IF EXISTS int.int_products;
CREATE TABLE int.int_products AS
WITH ranked AS (
    SELECT
        UPPER(TRIM(product_code))                                                      AS product_code,
        TRIM(product_name)                                                             AS product_name,
        COALESCE(NULLIF(TRIM(category), ''), 'Uncategorized')                          AS category,
        REPLACE(REPLACE(REPLACE(TRIM(unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) AS unit_price,
        UPPER(TRIM(is_active))                                                         AS is_active,
        TRIM(updated_at)::timestamp                                                    AS updated_at,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(product_code))
            ORDER BY TRIM(updated_at)::timestamp DESC
        ) AS rn
    FROM stg.stg_products
)
SELECT product_code, product_name, category, unit_price, is_active, updated_at
FROM ranked
WHERE rn = 1;

-- 3. Clean Customers (trim, uppercase IDs & type, deduplicate 76 -> 75)
DROP TABLE IF EXISTS int.int_customers;
CREATE TABLE int.int_customers AS
WITH ranked AS (
    SELECT
        UPPER(TRIM(customer_id))   AS customer_id,
        UPPER(TRIM(customer_type)) AS customer_type,
        UPPER(TRIM(id_number))     AS id_number,
        TRIM(full_name)            AS full_name,
        TRIM(registered_on)::date  AS registered_on,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(customer_id))
            ORDER BY TRIM(registered_on)::date DESC, ctid DESC
        ) AS rn
    FROM stg.stg_customers
)
SELECT customer_id, customer_type, id_number, full_name, registered_on
FROM ranked
WHERE rn = 1;

COMMIT;

SELECT 'int_branches'  AS table_name, COUNT(*) AS row_count FROM int.int_branches
UNION ALL
SELECT 'int_products',  COUNT(*) FROM int.int_products
UNION ALL
SELECT 'int_customers', COUNT(*) FROM int.int_customers;
