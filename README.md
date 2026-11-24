# UST Campus Store Warehouse: Starting Kit

CSELEC1C Data Warehousing · Final Case Study (Group) · 100 points

This is the starting kit named in the assignment. Make a new GitHub repository for your group,
copy everything in this folder into it, and work there.

The data is practice data made for this course. It is not real store, student or staff data.

## What you are given, and what you build

There is **no pre-made mart**. You get the design and the raw data. Your group builds and loads the mart.

| Given in this kit | Where |
|---|---|
| The business questions | `docs/01_business_questions.md` |
| The grain and the star schema | `docs/02_grain_and_star_schema.md`, empty tables in `sql/00_setup/02_star_schema.sql` |
| The architecture decision record (ADR) | `docs/03_ADR-001_architecture.md` |
| The raw source files | `source/` (SQL files for `psql`, and the same data as CSV in `source/csv/`) |
| What each source column means and what counts as valid | `docs/04_source_data_dictionary.md` |
| The repository skeleton | `sql/`, `dashboard/`, `evidence/` — files with the task and a `TODO` |
| What to put in your PDF | `docs/05_evidence_checklist.md` |
| Templates | `docs/06_lineage_template.md`, `docs/07_runbook_template.md` |

Everything marked `TODO` is your work: staging, cleaning rules, loads, tests, CDC, history, queries,
the metric, the dashboard, security, the recovery drill and the runbook.

## Set up (10 minutes)

You need PostgreSQL 16 with `psql`. Load the source the same way you loaded `lecture7_db.sql`.
In a terminal, inside this folder (not inside `psql`):

```
createdb campus_store
psql -d campus_store -f source/01_campus_store_source.sql
psql -d campus_store -f sql/00_setup/01_schemas.sql
psql -d campus_store -f sql/00_setup/02_star_schema.sql
psql -d campus_store
```

The first file prints the row counts of the source. `src.sales` should have 8,815 rows.
To start over at any time: `dropdb campus_store`, then run the four commands again.

**Rules for the source.** Schema `src` is the store's system. Read from it, never edit it by hand.
Only the numbered files in `source/` change it. Run each of those files **once**, in order, and only
when the task tells you to.

If your group uses dbt or Python instead of plain SQL, keep the same layers and table names. The CSV
copies in `source/csv/` hold the same rows as the SQL files.

## What happens in the source, and when

| File | What happened at the store | You use it in |
|---|---|---|
| `01_campus_store_source.sql` | Sales from Aug 4, 2025 to Apr 30, 2026; products, branches, customers, the academic calendar; the three enrollment extracts | Session 1 |
| `02_source_changes_to_may07.sql` | The store kept selling (May 2 to 7). A few older rows were corrected. | Session 2, CDC with a watermark |
| `03_change_log_may08_to_14.sql` | The POS vendor sent a change log for May 8 to 14 instead of table access | Session 2, CDC with a change log |
| `04_price_change_may15.sql` | Prices changed on May 15 and new products were added. Sales of May 15 and 16. | Session 2, SCD Type 2 |
| `05_late_sales_and_new_column_may19.sql` | The POS was upgraded: a new column. Sales of May 18 and 19, and some late sales. | Session 2, late and changed data |
| `06_reextract_2026-03-17.sql` | One past day is sent again because a branch's sales were missing | Session 2, rerun and backfill |

## The three sessions

Each member leads the tasks of the role they will own in the Course Project. In a 4-member group the
Data Architect also covers the Data Steward. Everyone must be able to explain every part.

### Session 1: Initial load and data quality (35 points)

| # | Task | Your code goes in | Lead |
|---|---|---|---|
| 1 | Staging: load the source into `stg_` tables, unchanged | `sql/01_staging/` | ETL Engineer |
| 2 | Cleaning rules: trim and fix codes, standardize dates, remove exact duplicates | `sql/02_intermediate/` | ETL Engineer |
| 3 | Surrogate keys: load dimensions first, then look up keys and load `fct_sales` | `sql/03_marts/01_…`, `02_…` | ETL Engineer |
| 4 | Audit totals: row counts and peso totals of source and warehouse match | `sql/04_tests/02_audit_totals.sql` | Data Steward |
| 5 | Shared tables: student, term, college, program from the enrollment extracts | `sql/02_intermediate/03_…`, `sql/03_marts/03_…` | Data Architect |
| 6 | Data-quality tests, reject table, alert | `sql/04_tests/01_…`, `03_…` | Data Steward |

### Session 2: Change handling and analytics (35 points)

| # | Task | Your code goes in | Lead |
|---|---|---|---|
| 1 | CDC load: with a watermark, then with a change log | `sql/05_cdc/01_…`, `02_…` | ETL Engineer |
| 2 | SCD Type 2: a product price changes, old sales keep the old price | `sql/05_cdc/03_…` | Data Architect, ETL Engineer |
| 3 | Late and changed data: a late sale and a new source column | `sql/05_cdc/04_…` | ETL Engineer |
| 4 | Rerun and backfill: totals do not change | `sql/05_cdc/05_…` | ETL Engineer, Data Steward |
| 5 | Layered model: staging, intermediate, mart | the folder layout of `sql/` | Data Architect |
| 6 | Analytical SQL: ROLLUP or CUBE and window functions, with checked totals | `sql/06_analytics/` | Query Analyst |
| 7 | One governed metric, "net sales", and a small dashboard | `sql/03_marts/04_…`, `dashboard/` | Query Analyst |

The Performance Tuner shows `EXPLAIN (ANALYZE, BUFFERS)` for the fact load lookup (Session 1) and for
one business question before and after an index or summary table (Session 2), read the way you read
plans in the Joins, Sorting and Memory lab.

### Session 3: Governance and recovery (30 points)

| # | Task | Your work goes in | Lead |
|---|---|---|---|
| 1 | Row-level security: a branch manager sees only its own branch, tested as that role | `sql/07_security/` | Data Steward |
| 2 | Lineage: how data flows from the source files to the dashboard | `docs/06_lineage_template.md` | Data Steward |
| 3 | Backup and recovery: back up, break a table on purpose, restore, record the time | `sql/08_ops/` | Performance Tuner |
| 4 | Runbook: one page | `docs/07_runbook_template.md` | ETL Engineer, all |
| 5 | Demo: the whole flow in 5 minutes | live | all |

## How you know your numbers are right

You are not given the expected totals. Your proof is your own audit query: source rows = loaded rows
+ rejected rows + duplicates removed, and every peso of difference is explained. Run it after every
load. Your teacher has the expected totals for each step and will compare.

## What you submit

One member submits for the group:

1. The link to your GitHub repository.
2. One PDF named `GroupName_CampusStore.pdf` with the evidence for each session. Follow `docs/05_evidence_checklist.md`.

Your README must let someone run the whole thing on a fresh laptop: the commands, in order.
