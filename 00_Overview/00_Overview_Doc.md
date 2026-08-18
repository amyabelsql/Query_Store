# 00 - Overview of Query Store

## What is Query Store?

Query Store is a SQL Server feature that records the history of your queries, their execution plans and how fast they ran, over time. When a query that used to be fast suddenly gets slow, you can look back at Query Store, see exactly what plan changed, and switch back to the plan that worked.

It works on every SQL Server edition. You need SQL Server 2016 or later to use it at all, and SQL Server 2017 or later to capture wait statistics (why a query was slow, e.g. CPU, locking, or I/O).

## What you need

| Requirement | Notes |
|---|---|
| SQL Server 2016+ (this repo uses 2022) | [Download](https://www.microsoft.com/sql-server/sql-server-downloads) |
| SQL Server Management Studio (latest) | [Download](https://aka.ms/ssms) |
| AdventureWorks2022 sample database | [Install instructions](https://learn.microsoft.com/sql/samples/adventureworks-install-configure) |

## Table of contents

| Folder | What's in it |
|---|---|
| [01_Setup](../01_Setup/) | Check prerequisites, turn Query Store on, configure it |
| [02_Generate_Workload](../02_Generate_Workload/) | Run a sample workload so Query Store has data to capture |
| [03_Explore_Catalog_Views](../03_Explore_Catalog_Views/) | Query the raw Query Store system views |
| [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/) | Create a regression, find it, force the good plan back |
| [05_SQL_2022_Features](../05_SQL_2022_Features/) | Apply a query hint through Query Store |
| [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) | Clean up and reset to production settings |
| [07_Production_Runbook](../07_Production_Runbook/) | Investigate an alert and fix the root cause |
| [08_Automated_Monitoring](../08_Automated_Monitoring/) | Set up SQL Agent alerts |
| [09_Query_Store_On_Secondary_Replicas](../09_Query_Store_On_Secondary_Replicas/) | Notes for Availability Group secondaries |

Continue with [01_Setup](../01_Setup/).

## Source

[Monitor performance by using the Query Store, Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
