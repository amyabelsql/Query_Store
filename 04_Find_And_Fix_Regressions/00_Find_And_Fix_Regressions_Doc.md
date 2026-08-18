# 04 - Find And Fix A Regression

Shows Query Store catching a bad plan and forcing a fix.

## Steps

1. [01_Find_Top_Resource_Consumers.sql](01_Find_Top_Resource_Consumers.sql), baseline.
2. [02_Find_Regressed_Queries.sql](02_Find_Regressed_Queries.sql), create the regression.
3. Open the SSMS **Regressed Queries** report, or run [07_Production_Runbook/02_Performance_Troubleshooting_Queries.sql](../07_Production_Runbook/02_Performance_Troubleshooting_Queries.sql).
4. Compare the good and bad plans.
5. [03_Force_And_Unforce_Plan.sql](03_Force_And_Unforce_Plan.sql), force the better plan.
6. Re-run the workload and confirm performance recovers.

Forcing a plan is a fast mitigation, not the fix. Still add/restore the right index, update stale statistics, rewrite the query, or parameterize ad hoc SQL.

If an alert from [08_Automated_Monitoring](../08_Automated_Monitoring/) already gave you a `query_id`, start there instead of step 1.

## SSMS reports worth showing

| Report | Shows |
|---|---|
| Regressed Queries | The query that got slower |
| Top Resource Consuming Queries | Impact before/after the fix |
| Queries With Forced Plans | The mitigation in place |
| Query Wait Statistics | Whether it's CPU, IO, memory, or locking |

## Gotcha

AdventureWorks2022 ships with a nonclustered index on `Sales.SalesOrderDetail(ProductID)` (`IX_SalesOrderDetail_ProductID`). [02_Find_Regressed_Queries.sql](02_Find_Regressed_Queries.sql) disables it before dropping this repo's own index. Skip that and the optimizer can keep using the built-in index, and the regression won't show up.

Continue with [05_SQL_2022_Features](../05_SQL_2022_Features/).

## Sources

- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
- [Monitor performance by using the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
