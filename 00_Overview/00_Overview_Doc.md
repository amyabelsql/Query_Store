# Overview of Query Store

## What is Query Store?

Query Store is one of the easiest ways to troubleshoot query performance problems in SQL Server. It keeps a history of your queries, execution plans, and performance over time.

When a query suddenly gets slower, Query Store helps you see what changed and which plan was used.

## When Should You Use It?

Use Query Store when you need to identify query regressions and understand why performance changed.

Requirements:

- SQL Server 2016 or later for Query Store.
- SQL Server 2017 or later to capture wait statistics, such as CPU pressure, locking, or I/O delays.

Some Query Store features are version-dependent. See [05_Version_Dependencies](../05_Version_Dependencies/) for details.

## The Three Stores

Query Store is made up of three internal stores that work together, each with its own settings and system views.

| Store | Holds | Setting that governs it |
|---|---|---|
| Plan Store | Query text and execution plans | `MAX_PLANS_PER_QUERY`, `MAX_STORAGE_SIZE_MB` |
| Runtime Stats Store | Aggregated execution stats (duration, CPU, I/O, memory), bucketed by time interval | `INTERVAL_LENGTH_MINUTES` |
| Wait Stats Store | Aggregated wait statistics per interval, why a query was slow, not just how slow | `WAIT_STATS_CAPTURE_MODE` |

All three are flushed to disk based on `DATA_FLUSH_INTERVAL_SECONDS`. 
See [03_Catalog_Views](../03_Catalog_Views/)  for the system views behind each store.

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
| [03_Catalog_Views](../03_Catalog_Views/) | Query the raw Query Store system views |
| [04_Regressions_And_Forcing](../04_Regressions_And_Forcing/) | Create a regression, find it, force the good plan back |
| [05_Version_Dependencies](../05_Version_Dependencies/) | Every version gate in this repo in one table, plus SQL Server 2022's newest features |
| [06_Maintenance](../06_Maintenance/) | Clean up and reset to production settings |
| [07_Troubleshooting](../07_Troubleshooting/) | Investigate an alert and fix the root cause |
| [08_Monitoring](../08_Monitoring/) | Set up SQL Agent alerts |
| [09_Secondary_Replicas](../09_Secondary_Replicas/) | Notes for Availability Group secondaries |
| [10_Best_Practices](../10_Best_Practices/) | Proactive guidance, before anything breaks |

Continue with [01_Setup](../01_Setup/).

## Source

[Monitor performance by using the Query Store, Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
