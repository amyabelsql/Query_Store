# Query Store Workshop

A hands-on, step-by-step workshop on SQL Server's Query Store: what it is, how to configure it correctly, and how to use it to find and fix query performance regressions. All guidance is sourced from and links back to [Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store).

## How to use this repo

Work through the numbered folders in order. Each one is self-contained: a short `README.md` explaining the step, plus the `.sql` script(s) to run. Everything is safe to run repeatedly against a throwaway copy of `AdventureWorks2022` — the setup step clears Query Store data at the start.

| Folder | What you'll do |
|---|---|
| [00_Prerequisites](00_Prerequisites/) | Install SQL Server, SSMS, and AdventureWorks2022; learn what Query Store is |
| [01_Setup](01_Setup/) | Enable and configure Query Store with workshop-friendly settings |
| [02_Generate_Workload](02_Generate_Workload/) | Run sample queries so Query Store has data to show |
| [03_Explore_Catalog_Views](03_Explore_Catalog_Views/) | Query the catalog views directly to see queries, plans, and stats |
| [04_Find_And_Fix_Regressions](04_Find_And_Fix_Regressions/) | Detect a regressed query and fix it by forcing a plan |
| [05_SQL_2022_Features](05_SQL_2022_Features/) | Apply a query hint without touching application code |
| [06_Maintenance_And_Best_Practices](06_Maintenance_And_Best_Practices/) | Clean up, reset to production settings, and review the best-practices checklist |
| [07_Production_Runbook](07_Production_Runbook/) | *(reference, not a lab)* Ad hoc troubleshooting queries for a real database |
| [08_Automated_Monitoring](08_Automated_Monitoring/) | *(reference, not a lab)* A SQL Server Agent job that alerts on Query Store problems |

Run these in SSMS or the [mssql VS Code extension](https://learn.microsoft.com/sql/tools/visual-studio-code-extensions/mssql/mssql-extension-visual-studio-code).

## Source of truth

Every claim in this repo is checked against Microsoft Learn, primarily:

- [Monitor performance by using the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Best practices for managing the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Query Store catalog views](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)

Each folder's `README.md` links its specific sources at the bottom.
