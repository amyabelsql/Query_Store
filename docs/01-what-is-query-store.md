# What Is Query Store?

Query Store is a built-in SQL Server feature that continuously captures a history of queries, their execution plans, and runtime statistics and retains it across restarts and failovers. Microsoft describes it as a "flight data recorder" for your database.

## Why it exists

The plan cache only ever holds the *current* plan for a query, and plans get evicted under memory pressure. When a query suddenly gets slower, the plan cache can't tell you what changed or what the previous (faster) plan looked like. Query Store solves that by persisting plan history to disk, separated into time windows, so you can see exactly when a plan changed and compare before/after.

## The three stores

Query Store data lives in three internal stores inside the user database:

| Store | Contains |
|---|---|
| **Plan store** | Execution plan XML for every captured plan |
| **Runtime stats store** | Aggregated execution statistics (duration, CPU, I/O, memory, row counts) per plan, per time interval |
| **Wait stats store** | Wait statistics per query per time interval (SQL Server 2017+) |

## What it captures

Query Store captures plans and stats for DML statements: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `BULK INSERT`. It does **not** capture DDL statements (`CREATE INDEX`, etc.) directly, though it does capture the underlying DML those operations execute internally.

Cursors, queries inside stored procedures, and natively compiled queries are captured whenever the capture mode is `ALL`, `AUTO`, or `CUSTOM`. Natively compiled procedures require an extra opt-in — see [sys.sp_xtp_control_query_exec_stats](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sys-sp-xtp-control-query-exec-stats-transact-sql).

## Enabled by default?

| Platform | Default |
|---|---|
| SQL Server 2016 – 2019 | **Off** — must be enabled explicitly |
| SQL Server 2022 (16.x)+ | **On**, in `READ_WRITE` mode, for every new database |
| Azure SQL Database / Managed Instance | **On** by default; can't be turned off on single databases/elastic pools |
| Azure Synapse Analytics dedicated pools | Off — must be enabled explicitly, with limited configuration |

## Common use cases

- Quickly fix a performance regression by forcing the previous (faster) plan.
- Find the top *n* most expensive queries by CPU, duration, I/O, or memory over a time window.
- Audit the full plan history for a specific query.
- Identify queries that are waiting on locks, memory, or I/O, and which queries are causing it.
- Detect ad hoc/non-parameterized query patterns that are bloating the plan cache.

Next: [Enabling and configuring Query Store](02-enabling-and-configuring.md)

## Sources

- [Monitor performance by using the Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
