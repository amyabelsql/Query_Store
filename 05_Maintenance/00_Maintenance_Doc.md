# 05 - Maintenance

Run when you're done with the demo. This is also the checklist to come back to whenever a real Query Store starts drifting into `READ_ONLY` or filling up with ad hoc noise. For proactive guidance on running Query Store well day to day, see [08_Best_Practices](../08_Best_Practices/). For diagnosing something that's already wrong, see [03_Troubleshooting](../03_Troubleshooting/).

## Steps

Run [01_Maintenance_Cleanup.sql](01_Maintenance_Cleanup.sql) against AdventureWorks2022. It does 6 things:

| Step | What it does | Impact |
|---|---|---|
| 1. Check | Shows current Query Store size and state | Read-only, tells you whether the rest of this script is even needed |
| 2. Raise quota | Raises `MAX_STORAGE_SIZE_MB` | Only matters if step 1 showed `READ_ONLY` from hitting its size quota |
| 3. Force read/write | Sets `OPERATION_MODE = READ_WRITE` | Overrides whatever pushed it out of read/write, safe if it was already read/write |
| 4. Purge ad hoc noise | Removes ad hoc/internal queries idle for more than 5 minutes | Deletes their query, plan, and runtime-stats history permanently, can't be undone |
| 5. Reset thresholds | Resets `DATA_FLUSH_INTERVAL_SECONDS`, `INTERVAL_LENGTH_MINUTES`, and `QUERY_CAPTURE_MODE` to [best-practice](../08_Best_Practices/) values | Undoes the demo thresholds `01_Setup/03_Configure.sql` set, later folders' timing assumptions (like the ~16-minute wait in `02_Find_Regressed_Queries.sql`) no longer apply after this runs |
| 6. Restore index | Re-enables AdventureWorks2022's native `IX_SalesOrderDetail_ProductID` index if `03_Troubleshooting` left it disabled | Leaves the sample database no worse off than it started, harmless no-op if the index was never disabled |

A few extra actions are commented out at the bottom of the script (resetting stats for a single plan, dropping this repo's demo objects entirely), read the comment above each before uncommenting and running it separately. For recovering from an `ERROR` state, see [03_Troubleshooting/11_Recover_From_Error_State.sql](../03_Troubleshooting/11_Recover_From_Error_State.sql).

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
