# Catalog Views

Everything Query Store collects lives in system views inside the user database, query them directly with T-SQL, no GUI needed.

Requirements:

- `VIEW DATABASE STATE` permission (SQL Server 2016-2019)
- `VIEW DATABASE PERFORMANCE STATE` permission (SQL Server 2022+)

## Steps

Run [01_Catalog_Views.sql](01_Catalog_Views.sql) on the databases using Query Store. It runs 3 queries:

| Query | Shows | Look for |
|---|---|---|
| 1. Configuration and health | Current Query Store settings and storage usage | `Actual State` should match `Desired State`. If it doesn't, something pushed Query Store out of read/write on its own, usually low disk space |
| 2. Per-query stats | Text, plan, and runtime stats for queries touching the two demo procedures | Multiple `Plan Id` rows under the same `Query Id` means the optimizer picked more than one plan for it, worth comparing `Avg Duration MS` between them |
| 3. Plan count per query shape | How many distinct plans exist per `Query Hash` | A high `Plan Count` on one hash with many different `Query Text Id` values means non-parameterized ad hoc queries are bloating Query Store |

## The Three Stores

Query Store is really three internal stores (see [00_Overview](../00_Overview/)).

| Store | View | Purpose |
|---|---|---|
| Plan Store | `query_store_query_text` | Raw SQL text for each distinct query |
| Plan Store | `query_store_query` | One row per captured query |
| Plan Store | `query_store_plan` | One row per captured execution plan |
| Plan Store | `query_context_settings` | SET options a query was compiled under |
| Plan Store | `query_store_query_hints` | Query Store hints (SQL Server 2022+) |
| Runtime Stats Store | `query_store_runtime_stats` | Duration, CPU, I/O, memory, rows per plan per interval |
| Runtime Stats Store | `query_store_runtime_stats_interval` | Start/end time of each aggregation interval |
| Wait Stats Store | `query_store_wait_stats` | Wait statistics per plan per interval |
| Not part of a store | `database_query_store_options` | Current Query Store configuration and state |
| Not part of a store | `database_query_store_internal_state` | Internal diagnostic state, rarely needed |

## Baseline Query

```sql
SELECT qt.query_sql_text, q.query_id, p.plan_id, rs.*
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id;
```

Columns you'll use most: `avg_duration`, `avg_cpu_time`, `avg_logical_io_reads`, `avg_query_max_used_memory`, `count_executions`, `last_execution_time`. Time is in **microseconds**, I/O in **8-KB pages**.

## Management Procedures

| Procedure | Purpose |
|---|---|
| `sp_query_store_force_plan` | Force a specific plan for a query |
| `sp_query_store_unforce_plan` | Remove a forced plan |
| `sp_query_store_reset_exec_stats` | Clear runtime stats for a plan |
| `sp_query_store_remove_plan` | Delete a single plan |
| `sp_query_store_remove_query` | Delete a query and all its plans/stats |
| `sp_query_store_flush_db` | Force an immediate flush of in-memory data to disk |
| `sp_query_store_consistency_check` | Recover Query Store from an `ERROR` state (2017+) |
| `sp_query_store_set_hints` / `sp_query_store_clear_hints` | Apply or remove a Query Store hint (2022+) |

Continue with [04_Regressions_And_Forcing](../04_Regressions_And_Forcing/).

## Sources

- [Query Store catalog views - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)
- [sys.query_store_runtime_stats - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql)
- [sys.query_store_query - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-query-transact-sql)
