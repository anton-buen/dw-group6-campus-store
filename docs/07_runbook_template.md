# Runbook: Campus Store Warehouse

| Field | Value |
| :--- | :--- |
| **Database** | PostgreSQL 16 (`campus_store`) |
| **Repository** | `https://github.com/anton-buen/dw-group6-campus-store` |
| **Owner of each part** | Data Architect (`Buenafe, Antonio III B.`): schemas, shared dims, ADRs · ETL Engineer (`Pangan, Marc Stephen S.`): staging, cleaning, CDC, backfill · Data Steward (`Fian, Althea Kate P.`): DQ tests, rejects, RLS · Query Analyst (`Cupalao, Andrei Jonathan E.`): governed metric, Q1–Q6, dashboard · Performance Tuner (`Ilano, Dwayne Anthony E.`): query plans, summary MV, backup/restore |

## 1. Load (first time)
Run the initial build in order (~5 seconds total):

```powershell
psql -d campus_store -f sql/00_setup/01_schemas.sql
psql -d campus_store -f sql/00_setup/02_star_schema.sql
psql -d campus_store -f source/01_initial_load.sql
psql -d campus_store -f source/02_enrollment_extract.sql
psql -d campus_store -f sql/01_staging/01_stage_source.sql
psql -d campus_store -f sql/02_intermediate/02_clean_dimensions.sql
psql -d campus_store -f sql/02_intermediate/01_clean_sales.sql
psql -d campus_store -f sql/02_intermediate/03_clean_enrollment.sql
psql -d campus_store -f sql/03_marts/03_shared_dimensions.sql
psql -d campus_store -f sql/03_marts/01_load_dimensions.sql
psql -d campus_store -f sql/03_marts/02_load_fct_sales.sql
psql -d campus_store -f sql/03_marts/04_metric_net_sales.sql
psql -d campus_store -f sql/04_tests/01_data_quality_tests.sql
psql -d campus_store -f sql/04_tests/02_audit_totals.sql
psql -d campus_store -f sql/07_security/01_row_level_security.sql
```

**Success check:** Every test in `audit.dq_test_results` reports `PASS` (`0` failed rows) and `02_audit_totals.sql` reports `0` unexplained rows (`0.00` pesos). After applying all Session 2 increments, `mart.v_net_sales` holds **`9,359`** rows and **`₱1,541,459.50`** in net sales.

## 2. Load new data (daily)
Run incremental CDC scripts and refresh the executive summary view:

```powershell
psql -d campus_store -f sql/05_cdc/01_watermark_load.sql
psql -d campus_store -f sql/05_cdc/02_change_log_load.sql
psql -d campus_store -f sql/05_cdc/03_scd2_product_price.sql
psql -d campus_store -c "REFRESH MATERIALIZED VIEW mart.mv_net_sales_branch_term;"
```

* **Watermark location:** `audit.etl_watermark` (`pipeline_name = 'fct_sales'`).
* **Last LSN location:** `audit.cdc_state` (voided/deleted keys are tombstoned in `audit.deleted_sales_keys`).

## 3. Run again / backfill a day
```powershell
psql -d campus_store -f sql/05_cdc/05_rerun_and_backfill.sql
```

* **Why it is safe to run twice:** Fact loads upsert on natural key `(receipt_no, line_no)` (`ON CONFLICT DO UPDATE`), change-log deletes stay excluded via `audit.deleted_sales_keys`, and point-in-time joins (`sold_at >= valid_from AND sold_at < valid_to`) preserve historical SCD Type 2 prices.
* **Backfilling one past day:** Load the day's re-extract file (e.g., `psql -d campus_store -f source/06_reextract_2026-03-17.sql`), then run the deduplicated upsert procedure in `05_rerun_and_backfill.sql`. Existing rows update cleanly, missing branch rows insert, and all other days remain untouched.

## 4. Back up
Run daily after the ETL finishes and before business hours (stored in `sql/08_ops/` and copied to off-machine storage):

```powershell
pg_dump -Fc -d campus_store -f sql/08_ops/campus_store.dump
pg_dumpall --roles-only -f sql/08_ops/roles.sql
```

*Drill benchmark: **`1,088.55 KB`** (`1,114,674` bytes) in **`0.799 s`**.*

## 5. Restore
```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS campus_store WITH (FORCE);" -c "CREATE DATABASE campus_store;"
pg_restore -d campus_store sql/08_ops/campus_store.dump
psql -d campus_store -c "ANALYZE;" -c "REFRESH MATERIALIZED VIEW mart.mv_net_sales_branch_term;"
```

* **Drill restore time:** **`1.047 s`**.
* **Post-restore checks & fixes:** Run `ANALYZE` (planner stats are not saved in dumps), refresh `mart.mv_net_sales_branch_term`, verify `mart.v_net_sales` equals **`9,359`** rows / **`₱1,541,459.50`**, confirm `pg_policies` contains `rls_fct_sales_branch_only`, and test `SET ROLE mgr_bks_main` (`1,915` rows / `₱615,484.50`). On a brand-new server, restore `roles.sql` (or re-run `sql/07_security/01_row_level_security.sql`) before running `pg_restore`.

## 6. When a test fails or data is stale
1. **Who looks first:** The **Data Steward** checks `audit.dq_test_results`, queries `rej.rej_sales` grouped by `reject_reason`, and runs `psql -d campus_store -f sql/04_tests/03_freshness_alert.sql`.
2. **When to continue:** Isolated bad source rows (math mismatch, invalid date, unknown code) are automatically quarantined in `rej.rej_sales`; valid rows load normally.
3. **When to stop:** Duplicate `(receipt_no, line_no)` keys in `mart.fct_sales`, unresolved surrogate keys, an unexplained audit difference, or a branch feed stale by >2 days. Pause the MV/dashboard refresh, notify the **ETL Engineer** and **Store Manager**, and re-run after receiving a clean source re-extract.