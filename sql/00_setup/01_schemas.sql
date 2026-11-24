-- Given. Run once after you load the source.
--   psql -d campus_store -f sql/00_setup/01_schemas.sql
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS stg;     -- staging: copies of the source, unchanged (stg_ tables)
CREATE SCHEMA IF NOT EXISTS int;     -- intermediate: cleaned and conformed data (int_ tables or views)
CREATE SCHEMA IF NOT EXISTS mart;    -- the Campus Store data mart (dim_ and fct_ tables)
CREATE SCHEMA IF NOT EXISTS shared;  -- dimensions the whole class will share in the course project
CREATE SCHEMA IF NOT EXISTS rej;     -- rows that failed a data-quality rule
CREATE SCHEMA IF NOT EXISTS audit;   -- load log, watermarks, test results, audit totals
