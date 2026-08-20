# Query Store Demo

A step-by-step demo of Query Store. Set up monitoring, catch a problem, fix it.

## Steps

| # | Folder | What it does |
|---|---|---|
| 1 | [00_Overview](00_Overview/) | Install SQL Server, SSMS, AdventureWorks2022 |
| 2 | [01_Setup](01_Setup/) | Check prerequisites, turn Query Store on, configure it |
| 3 | [08_Best_Practices](08_Best_Practices/) | Proactive guidance, read before going further |
| 4 | [02_Generate_Workload](02_Generate_Workload/) | Generate queries and plans for Query Store to capture |
| 5 | [06_Monitoring](06_Monitoring/) | Set up SQL Agent alerts |
| 6 | [03_Troubleshooting](03_Troubleshooting/) | Browse the catalog views, cause and fix a regression, investigate an alert |
| 7 | [05_Maintenance](05_Maintenance/) | Reset to production-style settings |
| - | [04_Version_Dependencies](04_Version_Dependencies/) | Every version gate in this repo, read anytime |
| - | [07_Secondary_Replicas](07_Secondary_Replicas/) | Notes for Availability Group secondaries, optional |

Shortest demo: 1 -> 2 -> 3 -> 4 -> 6.

Run everything in SSMS or the [mssql VS Code extension](https://learn.microsoft.com/sql/tools/visual-studio-code-extensions/mssql/mssql-extension-visual-studio-code).

## This repo follows

- Use `QUERY_CAPTURE_MODE = AUTO` in production
- Keep `SIZE_BASED_CLEANUP_MODE = AUTO`
- Watch for `actual_state_desc <> desired_state_desc`
- Use Query Store to catch regressions quickly
- Treat plan forcing as a fast mitigation, then fix the real cause

## Sources

- [Monitor performance by using the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Best practices for managing the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Query Store catalog views](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)
