# 03 - Explore Catalog Views

Everything Query Store collects is queryable through catalog views in the user database — no external tooling required. Run [explore-catalog-views.sql](explore-catalog-views.sql) after generating the workload.

## Core catalog views

| View | Purpose |
|---|---|
| `sys.database_query_store_options` | Current Query Store configuration and state for the database |
| `sys.query_store_query` | One row per captured query: parameterization type, object it belongs to, compile stats |
| `sys.query_store_query_text` | The raw SQL text for each distinct query |
| `sys.query_store_plan` | One row per captured execution plan (including plan XML and forcing status) |
| `sys.query_store_runtime_stats` | Aggregated execution stats (duration, CPU, I/O, memory, rows) per plan per interval |
| `sys.query_store_runtime_stats_interval` | The start/end time of each aggregation interval |
| `sys.query_store_wait_stats` | Wait statistics per plan per interval, grouped into wait categories |
| `sys.query_context_settings` | SET options and other context a query was compiled under |
| `sys.query_store_query_hints` | Query Store hints applied via `sp_query_store_set_hints` (SQL Server 2022+) |
| `sys.database_query_store_internal_state` | Internal diagnostic state — rarely needed outside support cases |

## How the views join together

```
sys.query_store_query_text  (query_text_id)
        │
sys.query_store_query        (query_id, query_text_id)
        │
sys.query_store_plan          (plan_id, query_id)
        │
sys.query_store_runtime_stats (runtime_stats_id, plan_id, runtime_stats_interval_id)
        │
sys.query_store_runtime_stats_interval (runtime_stats_interval_id)
```

`sys.query_store_wait_stats` joins to `plan_id` the same way `runtime_stats` does.

## Baseline query: everything about a query

```sql
SELECT qt.query_sql_text, q.query_id, p.plan_id, rs.*
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id;
```

Key columns in `sys.query_store_runtime_stats` you'll use constantly: `avg_duration`, `avg_cpu_time`, `avg_logical_io_reads`, `avg_query_max_used_memory`, `count_executions`, `execution_type_desc`, `last_execution_time`. All time values are in **microseconds**; I/O values are in **8-KB pages**.

## Stored procedures (management actions)

| Procedure | Purpose |
|---|---|
| `sp_query_store_force_plan` | Force a specific plan for a query |
| `sp_query_store_unforce_plan` | Remove a forced plan |
| `sp_query_store_reset_exec_stats` | Clear runtime stats for a plan |
| `sp_query_store_remove_plan` | Delete a single plan |
| `sp_query_store_remove_query` | Delete a query and all its plans/stats |
| `sp_query_store_flush_db` | Force an immediate flush of in-memory data to disk |
| `sp_query_store_consistency_check` | Attempt to recover Query Store from an `ERROR` state (SQL Server 2017+) |
| `sp_query_store_set_hints` / `sp_query_store_clear_hints` | Apply or remove a Query Store hint (SQL Server 2022+) |

## Permissions

- SQL Server 2016–2019: requires `VIEW DATABASE STATE`.
- SQL Server 2022+: requires `VIEW DATABASE PERFORMANCE STATE` (or a broader permission like `VIEW DATABASE STATE`).

Next: [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/)

## Sources

- [Query Store catalog views — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)
- [sys.query_store_runtime_stats — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql)
- [sys.query_store_query — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-query-transact-sql)
