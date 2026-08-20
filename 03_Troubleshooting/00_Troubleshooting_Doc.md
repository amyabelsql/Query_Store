# Troubleshooting

Everything Query Store collects lives in system views inside the user database. Query them directly with T-SQL, no GUI needed.

Requirements:

- `VIEW DATABASE STATE` permission (SQL Server 2016-2019)
- `VIEW DATABASE PERFORMANCE STATE` permission (SQL Server 2022+)

## Scripts

| Script | What it does | SSMS report equivalent |
|---|---|---|
| [01_Health_Checks.sql](01_Health_Checks.sql) | Confirms Query Store itself is healthy | Queries With Forced Plans (section 6) |
| [02_Catalog_Views_Reference.sql](02_Catalog_Views_Reference.sql) | Views the other scripts don't already cover | - |
| [03_Find_Query_By_Text.sql](03_Find_Query_By_Text.sql) | Finds a query_id from pasted query text | - |
| [04_Top_Resource_Consumers.sql](04_Top_Resource_Consumers.sql) | Top queries by duration, CPU, IO, memory | Top Resource Consuming Queries |
| [05_High_Variation_Queries.sql](05_High_Variation_Queries.sql) | Unstable queries, a parameter sniffing candidate | Queries With High Variation |
| [06_Regressed_Queries.sql](06_Regressed_Queries.sql) | Queries slower than their prior interval | Regressed Queries |
| [07_Wait_Statistics_By_Category.sql](07_Wait_Statistics_By_Category.sql) | Wait time by category, then top queries in it | Query Wait Statistics |
| [08_Simulate_And_Force_A_Regression.sql](08_Simulate_And_Force_A_Regression.sql) | Causes a regression, then forces the fix | - |
| [09_Overall_Resource_Consumption.sql](09_Overall_Resource_Consumption.sql) | Totals across every query, per interval | Overall Resource Consumption |
| [10_Track_A_Query.sql](10_Track_A_Query.sql) | One query_id's full plan and stats history | Tracked Queries |
| [11_Recover_From_Error_State.sql](11_Recover_From_Error_State.sql) | Fixes Query Store when it's in an `ERROR` state | - |

## Workflow

- If an alert from [06_Monitoring](../06_Monitoring/) already gave you a `query_id`, skip straight to forcing.
- Run [01_Health_Checks.sql](01_Health_Checks.sql) first, always. 
- A `READ_ONLY` or `ERROR` Query Store makes everything else misleading. 
- No live alert to chase? Run [08_Simulate_And_Force_A_Regression.sql](08_Simulate_And_Force_A_Regression.sql) instead, it creates one on purpose so you can practice.
- Forcing a plan is a fast mitigation, not the fix. 
- Still add or restore the right index, update stale statistics, rewrite the query, or parameterize ad hoc SQL.
- All scripts default to `AdventureWorks2022`, change the `USE` statement if needed.

## The circle, square, and triangle in the SSMS GUI

SSMS's Query Store charts (Top Resource Consuming Queries, Regressed Queries) mark executions with different shapes:

| Shape | Execution Type | Meaning |
|---|---|---|
| Circle | Regular | Finished normally |
| Square | Aborted | Interrupted, a timeout, a Cancel, a `KILL` |
| Triangle | Exception | Failed with a real error |

These shapes are just `execution_type_desc` in `sys.query_store_runtime_stats`. [01_Health_Checks.sql](01_Health_Checks.sql) sections 7-8 query it directly, no GUI needed. Watch for a growing `Aborted` or `Exception` count next to `Regular`, even when average duration looks fine, it's often the earlier warning sign.

## Why a forced plan stops working

Forcing isn't guaranteed to keep working. `force_failure_count` (health checks section 6) increments on recompile, and `last_force_failure_reason_desc` names why:

| Reason | Means |
|---|---|
| `NO_INDEX` | An index the plan depends on no longer exists or was disabled, the most common cause after a schema change |
| `NO_DB` | The database referenced in the plan doesn't exist |
| `VIEW_COMPILE_FAILED` | An indexed view referenced in the plan has a problem |
| `HINT_CONFLICT` | The plan conflicts with a query hint now in effect |
| `TIME_OUT` | The optimizer gave up trying to reproduce the forced plan's shape |
| `NO_PLAN` | The forced plan couldn't be verified as valid for the query at all |
| `ONLINE_INDEX_BUILD` | The query is trying to modify data while a target index is mid-build online |
| `COMPILATION_ABORTED_BY_CLIENT` | The client cancelled compilation before it finished |
| `GENERAL_FAILURE` | Anything not covered by a more specific reason above |

`NO_INDEX` is the one worth remembering. [08_Simulate_And_Force_A_Regression.sql](08_Simulate_And_Force_A_Regression.sql)'s bonus block demonstrates it on purpose, dropping the index a forced plan depends on.

## Gotcha

AdventureWorks2022 ships with a nonclustered index on `Sales.SalesOrderDetail(ProductID)` (`IX_SalesOrderDetail_ProductID`). [08_Simulate_And_Force_A_Regression.sql](08_Simulate_And_Force_A_Regression.sql) disables it before dropping this repo's own index. Skip that and the optimizer keeps using the built-in index, and the regression won't show up.

## Management Procedures

- `sp_query_store_force_plan` forces a plan, `sp_query_store_unforce_plan` removes it.
- `sp_query_store_reset_exec_stats` clears runtime stats for a plan.
- `sp_query_store_remove_plan` deletes a plan, `sp_query_store_remove_query` deletes a query and everything under it.
- `sp_query_store_flush_db` forces an immediate flush to disk.
- `sp_query_store_consistency_check` recovers from an `ERROR` state (2017+).
- `sp_query_store_set_hints` and `sp_query_store_clear_hints` apply or remove a hint (2022+).

## Related

| Folder | Why |
|---|---|
| [05_Maintenance](../05_Maintenance/) | Maintenance actions and their impacts, run when you're done or when things drift |
| [06_Monitoring](../06_Monitoring/) | Where the alerts come from |
| [08_Best_Practices](../08_Best_Practices/) | Proactive guidance, so you need this folder less often |

Continue with [04_Version_Dependencies](../04_Version_Dependencies/).

## Sources

- [Query Store catalog views - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/query-store-catalog-views-transact-sql)
- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store) (circle/square/triangle shape legend)
- [sys.query_store_plan - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-plan-transact-sql) (plan forcing limitations and failure reasons)
- [Monitor performance by using the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store) (Query Store lives inside the user database)
