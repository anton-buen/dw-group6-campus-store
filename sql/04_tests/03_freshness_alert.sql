-- SESSION 1, task 6: Freshness test and a simple alert         Lead: Data Steward
-- Rule (from the store): every branch sells Monday to Saturday. A branch is STALE when its
-- newest sale is more than 2 days older than the load date.
-- The Session 1 load date is 2026-05-01. Use that date, not today's date.
-- Alert = something a person will see: a row in an audit.alert table and a clear message
-- (RAISE WARNING, or a non-zero exit code in your run script) when a test fails or data is stale.
--
-- Evidence: the alert firing. Say which branch is stale and for how many days.

-- TODO
