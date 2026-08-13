# Troubleshooting Scenarios

## The basic workflow

1. Enable Query Store.
2. Let it collect data (usually a day is enough, even for complex workloads).
3. Pinpoint and fix the problematic queries.

## SSMS built-in reports

Object Explorer → your database → **Query Store** folder gives you GUI reports over the same catalog views:

| Report | Use it to |
|---|---|
| **Regressed Queries** | Find queries whose metrics recently got worse — the fastest way to correlate "the app got slow" with a specific query and plan change |
| **Top Resource Consuming Queries** | Find the queries with the highest CPU/duration/I/O/memory over a time window |
| **Overall Resource Consumption** | See total database resource use over time; spot daily vs. nightly load patterns |
| **Queries With Forced Plans** | List everything currently plan-forced |
| **Queries With High Variation** | Find queries with inconsistent performance across executions |
| **Query Wait Statistics** | See which wait categories dominate, and which queries drive them (SSMS 18+, SQL Server 2017+) |
| **Tracked Queries** | Watch a specific query's execution in near real time — useful after forcing a plan |

## Fixing a regressed query

When a query has multiple plans and the most recent one is worse:

1. Open **Regressed Queries**, select the query, compare the plans.
2. Force the better plan (GUI button, or `sp_query_store_force_plan` — see [scripts/06-forcing-plans-demo.sql](../scripts/06-forcing-plans-demo.sql)).
3. Check for a missing index recommendation surfaced in the plan.
4. Consider whether statistics are stale (large gap between estimated and actual rows).
5. Regularly re-check forced plans — schema changes can invalidate them:

```sql
SELECT p.plan_id, p.query_id, q.object_id AS containing_object_id,
       force_failure_count, last_force_failure_reason_desc
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
WHERE is_forced_plan = 1;
```

Plan forcing is a mitigation, not a fix — treat it as a stopgap while you address the root cause (missing index, stale stats, or a query rewrite).

## Wait statistics: from instance-level guesswork to per-query answers

Query Store groups individual wait types into **wait categories** so you can go straight from "the server is under X pressure" to "these specific queries are causing it."

| Old instance-level symptom | Query Store wait category | Action |
|---|---|---|
| High `RESOURCE_SEMAPHORE` waits | High **Memory** waits | Find top memory-consuming queries; consider `MAX_GRANT_PERCENT` hint |
| High `LCK_M_X` waits | High **Lock** waits | Find frequent/long modifiers of the same object; consider isolation level or app-level concurrency changes |
| High `PAGEIOLATCH_SH` waits | High **Buffer IO** waits | Find queries with high physical reads; add an index to enable seeks over scans |
| High `SOS_SCHEDULER_YIELD` waits | High **CPU** waits | Find top CPU queries; look for plan regressions or missing indexes |

Enable wait stats capture (on by default in SQL Server 2022):

```sql
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE (WAIT_STATS_CAPTURE_MODE = ON);
```

## Ad hoc and non-parameterized queries

Non-parameterized queries force a fresh plan compile per unique text, bloat Query Store, and can push it into read-only mode. Symptoms and fixes:

- Compare distinct `query_hash` count to total rows in `sys.query_store_query` — a ratio near 1 means most queries are unique/ad hoc.
- Wrap ad hoc SQL in a stored procedure or `sp_executesql`.
- Turn on [optimize for ad hoc workloads](https://learn.microsoft.com/sql/database-engine/configure-windows/optimize-for-ad-hoc-workloads-server-configuration-option) at the instance level.
- Consider [forced parameterization](https://learn.microsoft.com/sql/relational-databases/query-processing-architecture-guide#forced-parameterization) at the database level, or a [plan guide](https://learn.microsoft.com/sql/relational-databases/performance/specify-query-parameterization-behavior-by-using-plan-guides) for a single query.
- Set `QUERY_CAPTURE_MODE = AUTO` so low-value ad hoc queries are filtered out automatically.

```sql
-- Non-parameterized queries currently in Query Store
SELECT qsq.query_id, qsqt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_query_text AS qsqt ON qsq.query_text_id = qsqt.query_text_id
WHERE query_parameterization_type = 0;
```

## A gotcha: don't DROP and CREATE containing objects

Query Store ties a query's history to its containing object (stored procedure, function, trigger). Recreating that object (`DROP` + `CREATE`) starts a brand-new history and breaks any forced plan. Use `ALTER <object>` instead whenever possible.

Hands-on: [scripts/04-find-top-resource-consumers.sql](../scripts/04-find-top-resource-consumers.sql), [scripts/05-find-regressed-queries.sql](../scripts/05-find-regressed-queries.sql)

Next: [SQL Server 2022 features](05-sql2022-features.md)

## Sources

- [Best practices for monitoring workloads with Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Monitor performance by using the Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
