# Generate Workload

Creates the Query Store data to use for the rest of this repo.

## Steps

Run both scripts against AdventureWorks2022, in order.

| Step | What it does |
|---|---|
| [01_Generate_Workload.sql](01_Generate_Workload.sql) | Creates two stored procedures and calls them repeatedly, plus 8 distinct ad hoc queries run 6 times each, to show query-text bloat |
| [02_Generate_Exception_Query.sql](02_Generate_Exception_Query.sql) | Creates a real divide-by-zero error, fully automatic, no manual step, no special settings |

Wait about 15 minutes for the first Query Store interval to flush (the interval length is set in `01_Setup/03_Configure.sql`), then continue.

Continue with [03_Troubleshooting](../03_Troubleshooting/).