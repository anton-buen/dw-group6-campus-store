-- SESSION 2, task 4: Rerun and backfill                        Lead: ETL Engineer + Data Steward
-- a) RERUN. Run your whole load again from the start of the source. Totals must not change.
--    Check the rows that the change log deleted: did they come back?
-- b) BACKFILL. Run source/06_reextract_2026-03-17.sql. It re-sends ONE past day for all branches.
--    Most rows are already loaded; one branch's rows are new. Load the day. Then load it again.
--
-- Evidence: totals before the rerun and after it (equal); totals for 2026-03-17 before the
-- backfill, after it, and after loading it a second time; totals of every other day unchanged.

-- TODO
