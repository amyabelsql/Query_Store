# Query Store Workshop

A hands-on workshop on SQL Server's Query Store: what it is, how to configure it correctly, and how to use it to find and fix query performance regressions. All guidance is sourced from and links back to [Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store).

**Target platform:** SQL Server 2022 (16.x). Notes call out where behavior differs on older versions or Azure SQL Database.

## Prerequisites

| Requirement | Notes |
|---|---|
| SQL Server 2022 (Developer or Evaluation edition) | [Download](https://www.microsoft.com/sql-server/sql-server-downloads) |
| SQL Server Management Studio (latest) | [Download](https://aka.ms/ssms) — required for the Query Store GUI reports |
| AdventureWorks2022 sample database | [Install instructions](https://learn.microsoft.com/sql/samples/adventureworks-install-configure) — restore the `AdventureWorks2022.bak` file from the [sql-server-samples releases page](https://github.com/microsoft/sql-server-samples/releases/tag/adventureworks) |

## Agenda

| # | Topic | Doc | Time |
|---|---|---|---|
| 1 | What Query Store is and why it exists | [docs/01-what-is-query-store.md](docs/01-what-is-query-store.md) | 10 min |
| 2 | Enabling and configuring it correctly | [docs/02-enabling-and-configuring.md](docs/02-enabling-and-configuring.md) | 15 min |
| 3 | Catalog views and DMVs (the queryable data) | [docs/03-catalog-views-and-dmvs.md](docs/03-catalog-views-and-dmvs.md) | 15 min |
| 4 | Troubleshooting: regressions, waits, plan forcing | [docs/04-troubleshooting-scenarios.md](docs/04-troubleshooting-scenarios.md) | 20 min |
| 5 | SQL Server 2022 features: hints, optimized plan forcing | [docs/05-sql2022-features.md](docs/05-sql2022-features.md) | 15 min |
| 6 | Best-practices cheat sheet | [docs/06-best-practices-cheatsheet.md](docs/06-best-practices-cheatsheet.md) | 5 min |

## Hands-on labs

Run these in order against `AdventureWorks2022`, in SSMS or the [mssql VS Code extension](https://learn.microsoft.com/sql/tools/visual-studio-code-extensions/mssql/mssql-extension-visual-studio-code). Each script is self-contained and commented.

| Script | Purpose |
|---|---|
| [scripts/00-setup-sample-db.sql](scripts/00-setup-sample-db.sql) | Reset and enable Query Store with 2022-recommended settings |
| [scripts/01-enable-configure-query-store.sql](scripts/01-enable-configure-query-store.sql) | Enable/configure options and verify them |
| [scripts/02-generate-sample-workload.sql](scripts/02-generate-sample-workload.sql) | Generate query activity so Query Store has data to show |
| [scripts/03-explore-catalog-views.sql](scripts/03-explore-catalog-views.sql) | Join the core catalog views to see queries, plans, and stats |
| [scripts/04-find-top-resource-consumers.sql](scripts/04-find-top-resource-consumers.sql) | Find the most expensive queries by CPU, duration, and reads |
| [scripts/05-find-regressed-queries.sql](scripts/05-find-regressed-queries.sql) | Detect queries that got slower after a plan change |
| [scripts/06-forcing-plans-demo.sql](scripts/06-forcing-plans-demo.sql) | Force and unforce an execution plan |
| [scripts/07-query-store-hints-demo.sql](scripts/07-query-store-hints-demo.sql) | Apply a query hint without touching application code (SQL Server 2022+) |
| [scripts/08-maintenance-cleanup.sql](scripts/08-maintenance-cleanup.sql) | Check size/state, clean up, and recover a stuck Query Store |

## How to use this repo

1. Read a `docs/*.md` topic.
2. Run the matching `scripts/*.sql` file to see it live.
3. Everything here is safe to run repeatedly against a throwaway copy of `AdventureWorks2022` — the setup script clears Query Store data at the start.

## Source of truth

Every claim in this repo is checked against Microsoft Learn, primarily:

- [Monitor performance by using the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Best practices for managing the Query Store](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Query Store catalog views](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)

Each doc links its specific sources at the bottom.
