-- SESSION 2, task 2: SCD Type 2 on product price               Lead: Data Architect + ETL Engineer
-- Run source/04_price_change_may15.sql. Prices changed and new products appeared.
-- The source keeps only the current price. Your warehouse must keep history:
--   keep the old price row, close it (valid_to, is_current), add the new row.
-- Then load the new sales with your watermark load.
--
-- Evidence: both rows of one changed product in mart.dim_product, and a query showing that
-- sales before the change point to the old row and sales after it point to the new row.

-- TODO
