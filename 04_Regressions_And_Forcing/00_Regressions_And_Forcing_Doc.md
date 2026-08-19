# 04 - Regressions And Forcing

Shows Query Store catching a bad plan and forcing a fix, the same workflow you'd use in production when an index change, a statistics update, or a schema change makes a previously-fast query slow.

## Scripts

| Step | What it does |
|---|---|
| [01_Find_Top_Resource_Consumers.sql](01_Find_Top_Resource_Consumers.sql) | Captures the baseline, before the regression |
| [02_Find_Regressed_Queries.sql](02_Find_Regressed_Queries.sql) | Creates the regression by removing the supporting indexes |
| [03_Force_And_Unforce_Plan.sql](03_Force_And_Unforce_Plan.sql) | Forces the better plan back |

## What each query shows you

| Query | Shows | Look for |
|---|---|---|
| 01, all 3 queries | Top 10 queries by CPU, logical reads, and memory grant | The query at the top of each list is your best tuning target for that resource, especially if `Executions` is also high |
| 02, final query | Runtime stats per interval for the demo query, before and after the regression | Two `Plan Id` values for the same `Query Id`, with the later interval showing higher `Avg Duration MS` and `Avg Logical IO Reads` |
| 03, step 2 | Available `Plan Id` values for the regressed query | Pick the `Plan Id` with the lower `Avg Logical IO Reads`, that's the index seek plan you want to force |
| 03, step 4 | Confirms which plan is currently forced | `Forced` should be `1` for the `Plan Id` you just forced |

## Workflow

1. Run 01_Find_Top_Resource_Consumers.sql for a baseline.
2. Run 02_Find_Regressed_Queries.sql to create the regression.
3. Open the SSMS **Regressed Queries** report, or run [07_Troubleshooting/02_Performance_Troubleshooting_Queries.sql](../07_Troubleshooting/02_Performance_Troubleshooting_Queries.sql).
4. Compare the good and bad plans.
5. Run 03_Force_And_Unforce_Plan.sql to force the better plan.
6. Re-run the workload and confirm performance recovers.

Forcing a plan is a fast mitigation, not the fix. Still add/restore the right index, update stale statistics, rewrite the query, or parameterize ad hoc SQL.

If an alert from [08_Monitoring](../08_Monitoring/) already gave you a `query_id`, start there instead of step 1.

## SSMS reports worth showing

| Report | Shows |
|---|---|
| Regressed Queries | The query that got slower |
| Top Resource Consuming Queries | Impact before/after the fix |
| Queries With Forced Plans | The mitigation in place |
| Query Wait Statistics | Whether it's CPU, IO, memory, or locking |

## Gotcha

AdventureWorks2022 ships with a nonclustered index on `Sales.SalesOrderDetail(ProductID)` (`IX_SalesOrderDetail_ProductID`). 02_Find_Regressed_Queries.sql disables it before dropping this repo's own index. Skip that and the optimizer can keep using the built-in index, and the regression won't show up.

## Related

| Folder | Why |
|---|---|
| [08_Monitoring](../08_Monitoring/) | Where a real `query_id` for this workflow would come from |
| [07_Troubleshooting](../07_Troubleshooting/) | Same idea, but for cancelled and errored executions instead of slow ones (health checks sections 7-8) |

Continue with [05_Version_Dependencies](../05_Version_Dependencies/).

## Sources

- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Monitor performance by using the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
