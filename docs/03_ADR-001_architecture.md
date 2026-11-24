# ADR-001: Architecture of the Campus Store mart

**Status:** Accepted (given). **Date:** November 2026. **Decided by:** the course, for all groups.

## Context

The store's point-of-sale (POS) system keeps only current data and exports it with problems:
mixed date formats, repeated rows, codes typed in different ways. The manager needs trusted sales
numbers by branch, product, term and buyer type, and a history of prices. The team is 4 to 5 students,
on laptops, with free tools, for three lab sessions. The same patterns will be reused in the Course Project,
where six marts must join through shared dimensions.

## Decision

1. **Kimball dimensional mart.** One star schema for one business process (retail sales), at the grain of one receipt line.
2. **ELT inside PostgreSQL 16.** Load the source as it is, then clean and transform with SQL in the database. dbt is allowed; the layers stay the same.
3. **Three layers.** `stg` (source copy, unchanged) → `int` (cleaned, typed, conformed) → `mart` (dimensions and facts). Rejected rows go to `rej`. Load logs, watermarks and test results go to `audit`.
4. **Conformed dimensions in their own schema.** `shared.dim_date`, `dim_term`, `dim_student`, `dim_program`, `dim_college` are built once and reused by every mart.
5. **Type 2 history for product price.** The source overwrites prices; the warehouse keeps each price period.
6. **Loads can be run again safely.** A fact row is identified by `receipt_no` + `line_no`. Loading the same data twice must give the same result.
7. **Bad rows are rejected, not dropped and not guessed.** Every rejected row is kept with a reason.
8. **Security in the database.** Row-level security is done in PostgreSQL, so it holds under any dashboard tool.

## Options that were not chosen

| Option | Why not here |
|---|---|
| Inmon: a normalized enterprise warehouse first, marts later | Too much modeling before any answer; three sessions is not enough |
| Data Vault (hubs, links, satellites) | Good for many changing sources and audit needs; too many tables for one small source |
| One big table | Fast to build, but no shared dimensions for the project and no clean place for price history |
| ETL outside the database | Extra tools to install; SQL in PostgreSQL is what the class already knows |

## What this decision costs

- Queries need joins. That is accepted; the tables are small.
- Type 2 makes the product lookup depend on the sale time. Late sales must be checked.
- Shared dimensions need agreed standards (see `02_grain_and_star_schema.md`).

## Decisions left to your group

Add your own records below this one (ADR-002, ADR-003, …), one short paragraph each:

- Plain SQL scripts or dbt, and why.
- What a delete in the change log does to your fact table.
- Where the new source column goes in the star schema.
- Which rule you use when two source rows disagree about the same student, course or receipt line.
- Every change you made to the given tables.

---

## Group Architecture Decision Records

### ADR-002: Plain PostgreSQL SQL Scripts Over dbt
**Status:** Accepted. **Decided by:** Data Architect & ETL Engineer.
We chose plain, idempotent PostgreSQL SQL scripts (`\set ON_ERROR_STOP on`, explicit transactions) over dbt so every team member can run the entire warehouse pipeline with zero Python/virtual-environment setup overhead while directly using native PostgreSQL features (`ON CONFLICT ... DO UPDATE`, procedural LSN loops, and row-level security policies).

### ADR-003: Handling Change-Log Deletes via Physical Delete + Persistent Tombstone Table
**Status:** Accepted. **Decided by:** Data Architect & ETL Engineer.
When a `D` (delete) event arrives in `src.sales_change_log`, we delete the matching `(receipt_no, line_no)` row from `mart.fct_sales` so analytical queries and governed metrics immediately reflect accurate net sales without requiring `WHERE NOT is_deleted` filters everywhere. Simultaneously, we record `(receipt_no, line_no, deleted_lsn)` in `audit.deleted_sales_keys` so full reruns or backfills from `src.sales` never resurrect deleted rows unless a newer LSN re-inserts them.

### ADR-004: Placement of New `order_channel` Column in the Star Schema (Evidence 2.5)
**Status:** Accepted. **Decided by:** Data Architect.
When the May 18, 2026 POS upgrade added `order_channel` (`COUNTER`, `PREORDER_APP`) to `src.sales`, different lines within the same receipt carried different channels (e.g., `BKS-MAIN-20260518-0001` line 1 = `PREORDER_APP`, line 2 = `COUNTER`). Because `order_channel` is a low-cardinality transactional attribute at the receipt-line grain with no independent hierarchy or attributes of its own, we placed it directly on `mart.fct_sales` as a degenerate attribute (`order_channel text NOT NULL DEFAULT 'UNKNOWN'`) alongside `txn_type` and `payment_method`. Pre-May 18 rows retain `'UNKNOWN'` so historical rows remain 100% valid with no `NULL`s in group-by reports.

### ADR-005: Tie-Breaking Rule for Conflicting Duplicate Source Rows
**Status:** Accepted. **Decided by:** Data Architect & Data Steward.
When duplicate rows share the same natural key (`receipt_no + line_no` in sales, `product_code` in products, `customer_id` in customers), we rank candidates deterministically by `updated_at DESC` (`registered_on DESC` for customers, completeness score for enrollment students) with `ctid DESC` as a final deterministic tie-breaker, keeping `rn = 1` and logging superseded sales rows in `int.int_sales_dedup_removed` for full audit reconciliation.

### ADR-006: Schema Additions Beyond Starter DDL
**Status:** Accepted. **Decided by:** Data Architect.
We added `order_channel text NOT NULL DEFAULT 'UNKNOWN'` to `mart.fct_sales` (and `text` to `stg.stg_sales` and `rej.rej_sales`), created `audit.etl_watermark` and `audit.deleted_sales_keys` to guarantee idempotent watermark/change-log/rerun loads, and created `int.int_sales_dedup_removed` so `02_audit_totals.sql` reconciles every source row to zero unexplained difference.
