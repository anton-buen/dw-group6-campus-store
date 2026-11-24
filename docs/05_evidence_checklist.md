# Evidence checklist for `GroupName_CampusStore.pdf`

One PDF, three parts, in this order. For each item show the query (or command) and its output as a
screenshot or pasted text, then one or two sentences on what it proves. Write the name and role of
the member who did it. Page 1: group name, members and roles, and the link to your repository.

## Session 1: Initial load and data quality (35 points)

Graded on: clean staging · correct surrogate keys · audit totals that match · shared tables built · tests and reject table working.

| # | Show this |
|---|---|
| 1.1 | **Staging.** Row counts of each `src` table next to its `stg_` table. They are equal. |
| 1.2 | **Cleaning rules.** A table of your rules: the problem, fix or reject, and how many rows each rule touched. |
| 1.3 | **Dimensions.** Row count of each dimension. The `-1` rows of `dim_customer` and `dim_term`. |
| 1.4 | **Surrogate keys.** Row count of `fct_sales`. A query that proves no fact row has a missing or wrong key. |
| 1.5 | **Audit totals.** Source rows = loaded + rejected + duplicates removed. Peso totals, with every difference explained. |
| 1.6 | **Shared tables.** Row counts of `dim_student`, `dim_program`, `dim_college`, `dim_term`. The college spellings you found and the 5 they map to. A join from `dim_customer` to `dim_student`. |
| 1.7 | **Tests.** Your test results table: at least one each of completeness, validity, uniqueness, consistency and freshness. |
| 1.8 | **Rejects.** The reject table grouped by reason, and 3 sample rows. |
| 1.9 | **Alert.** The alert firing: which branch is stale as of 2026-05-01, and by how many days. |
| 1.10 | **Plan.** `EXPLAIN (ANALYZE, BUFFERS)` of the fact load lookup, with a short reading (join method, buffers). |

## Session 2: Change handling and analytics (35 points)

Graded on: correct CDC and SCD Type 2 history · late data handled · rerun gives the same totals · analytical queries with checked totals · one governed metric on a dashboard.

| # | Show this |
|---|---|
| 2.1 | **Watermark load.** Watermark before and after. Rows picked up; inserted vs updated. One corrected row before and after. Audit totals again. |
| 2.2 | **Change log load.** Events read; applied by type (I, U, D); last lsn saved. One deleted row shown gone. The log applied a second time: nothing changes. |
| 2.3 | **SCD Type 2.** Both rows of one changed product in `dim_product`. Sales before the change point to the old row; sales after it point to the new row. |
| 2.4 | **Late sale.** The late sales joined to `dim_product`: they carry the price that was true on the day of the sale. |
| 2.5 | **New column.** The column in staging and in the mart. Old rows are still valid. Your ADR note on where it lives. |
| 2.6 | **Rerun.** Totals before and after running the whole load again: equal. What happened to the deleted rows. |
| 2.7 | **Backfill.** Totals of 2026-03-17 before, after, and after loading it a second time. Totals of all other days unchanged. |
| 2.8 | **Layers.** Your repository tree showing staging, intermediate and mart. |
| 2.9 | **Analytical SQL.** Q1 to Q6 with outputs. For each ROLLUP or CUBE answer, the check that subtotals add up to the grand total. |
| 2.10 | **Metric.** The one definition of net sales. One query and one dashboard chart showing the same number. |
| 2.11 | **Dashboard.** Screenshot of the dashboard (3 to 5 charts). |
| 2.12 | **Plan.** One business question's plan before and after an index or summary table. |

## Session 3: Governance and recovery (30 points)

Graded on: row-level security tested as the role · lineage diagram · a recovery drill that worked · a usable runbook · the demo.

| # | Show this |
|---|---|
| 3.1 | **Row-level security.** The role, grants and policy. The same query run as the branch manager and as the owner, with different results. |
| 3.2 | **Lineage.** One diagram from the source files to the dashboard. |
| 3.3 | **Recovery drill.** Backup command, size and time. What you broke. Restore command and time. Totals before and after. What you had to fix after the restore. |
| 3.4 | **Runbook.** The one-page runbook. |
| 3.5 | **Demo.** Done live in the lab, 5 minutes: load a change, show a test catching a bad row, answer one question on the dashboard, log in as a branch manager. |

## Last page

Each member: three lines. What I built, what broke, what I would change.
