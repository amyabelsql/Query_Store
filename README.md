# Query Store Demo

This repo is a simple, step-by-step demo for showing how Query Store helps you **set up monitoring, catch a problem, and fix it**. The main path is built around alerts first, then investigation.

## Demo path

Run these folders in this order:

1. [00_Overview](00_Overview/) - install SQL Server, SSMS, and AdventureWorks2022
2. [01_Setup](01_Setup/) - run `01_Prerequisites.sql`, `02_Turn_On.sql`, and `03_Configure.sql`
3. [02_Generate_Workload](02_Generate_Workload/) - create data for Query Store to capture
4. [08_Automated_Monitoring](08_Automated_Monitoring/) - set up alerts
5. [04_Find_And_Fix_Regressions](04_Find_And_Fix_Regressions/) - create a regression and fix it
6. [07_Production_Runbook](07_Production_Runbook/) - investigate the alert and confirm the cause
7. [06_Maintenance_And_Best_Practices](06_Maintenance_And_Best_Practices/) - reset the demo and review the best-practice checklist

If you want the shortest demo, use **01 -> 02 -> 08 -> 04 -> 07**.

## What each folder is for

| Folder | Simple name | Use it for |
|---|---|---|
| [00_Overview](00_Overview/) | Overview | What Query Store is, use cases, and prerequisites |
| [01_Setup](01_Setup/) | Setup Query Store | Check prerequisites, turn it on, then configure it |
| [02_Generate_Workload](02_Generate_Workload/) | Create demo activity | Generate queries and plans |
| [03_Explore_Catalog_Views](03_Explore_Catalog_Views/) | See the raw data | Look at the Query Store catalog views directly |
| [04_Find_And_Fix_Regressions](04_Find_And_Fix_Regressions/) | Fix a bad plan | Show a regression and force the better plan |
| [05_SQL_2022_Features](05_SQL_2022_Features/) | Use Query Store hints | Apply a hint without changing app code |
| [06_Maintenance_And_Best_Practices](06_Maintenance_And_Best_Practices/) | Reset and keep it healthy | Return to production-style settings and review best practices |
| [07_Production_Runbook](07_Production_Runbook/) | Catch and fix the issue | Follow the alert to the root cause |
| [08_Automated_Monitoring](08_Automated_Monitoring/) | Set up alerts | Create SQL Agent alerts for space, regressions, and slow queries |
| [09_Query_Store_On_Secondary_Replicas](09_Query_Store_On_Secondary_Replicas/) | Secondary replica notes | Optional preview feature for AG environments |

Run everything in SSMS or the [mssql VS Code extension](https://learn.microsoft.com/sql/tools/visual-studio-code-extensions/mssql/mssql-extension-visual-studio-code).

## Best-practice focus

This repo stays close to Microsoft guidance:

- Use `QUERY_CAPTURE_MODE = AUTO` in production
- Keep `SIZE_BASED_CLEANUP_MODE = AUTO`
- Watch for `actual_state_desc <> desired_state_desc`
- Use Query Store to catch regressions quickly
- Treat plan forcing as a fast mitigation, then fix the real cause

## Source of truth

Every recommendation in this repo is based on Microsoft Learn:

- [Monitor performance by using the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Best practices for managing the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Query Store catalog views](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)
