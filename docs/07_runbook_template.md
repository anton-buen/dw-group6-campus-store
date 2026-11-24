# Runbook: Campus Store warehouse

Keep it to one page. Write commands that a groupmate can copy and run.

| | |
|---|---|
| Database | |
| Repository | |
| Owner of each part | |

## 1. Load (first time)
Commands, in order. How long it takes. How you know it worked (which numbers to check).

## 2. Load new data (daily)
Watermark load. Change log load. Where the watermark and the last lsn are kept.

## 3. Run again / backfill a day
The command. Why it is safe to run twice. How to backfill one past day.

## 4. Back up
Command, where the file goes, how often.

## 5. Restore
Command. Time it took in your drill. What to check and re-create after a restore.

## 6. When a test fails or data is stale
Who looks first. Where the failing rows are. When to stop the load and when to continue. Who to tell.
