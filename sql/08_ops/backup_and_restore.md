# Session 3, task 3: Backup and recovery drill

Lead: Performance Tuner, with the ETL Engineer.

1. Write down the row count and net sales of `mart.fct_sales`.
2. Take a backup with `pg_dump`. Record the command, the file size and the time it took.
3. Break something on purpose: drop `mart.fct_sales`, or delete one month of rows.
4. Restore from your backup with `pg_restore` (or `psql` for a plain SQL dump). Time it.
5. Check the row count and net sales again. They must equal step 1.
6. Check what else the drop removed (views, security policies, grants) and bring those back too.

Put your commands in `backup.sh` and `restore.sh` in this folder so anyone in the group can run them.

**Evidence:** the commands, the two timings, the before and after totals, and what you had to fix after the restore.
