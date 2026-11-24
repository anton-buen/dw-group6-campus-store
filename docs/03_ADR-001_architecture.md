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
