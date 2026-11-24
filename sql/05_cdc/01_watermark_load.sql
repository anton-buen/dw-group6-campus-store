-- SESSION 2, task 1a: CDC with a watermark                     Lead: ETL Engineer
-- 1. Write down your current watermark (largest updated_at you have loaded).
-- 2. Run source/02_source_changes_to_may07.sql   (the store kept selling)
-- 3. Load ONLY the rows with updated_at newer than your watermark. Some are new, some are
--    older rows that were corrected. Then move the watermark forward.
--
-- Evidence: watermark before and after, rows picked up, rows inserted vs rows updated,
-- one corrected row shown before and after, and the audit totals query again.

-- TODO
