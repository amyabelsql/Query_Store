/*
    Regresses dbo.QS_ProductSales by removing every index that supports
    its WHERE clause, then shows how to spot the regression through the
    runtime stats interval history. Same signal behind the SSMS
    "Regressed Queries" report.
    Run 01_Setup/02_Turn_On.sql, 01_Setup/03_Configure.sql, and
    02_Generate_Workload/01_Generate_Workload.sql first.
*/

USE [AdventureWorks2022];
GO

-- Captures the "before" plan while the supporting index is still in place
EXEC dbo.QS_ProductSales @ProductID = 712;
GO

-- Lets the current Query Store interval close, so "before" and "after"
-- land as separate rows. This has to stay in sync with
-- 01_Setup/03_Configure.sql's INTERVAL_LENGTH_MINUTES setting (15), so
-- it waits past that.
WAITFOR DELAY '00:16:00';
GO

-- Removes the supporting index and forces a recompile.
-- AdventureWorks2022 ships its own nonclustered index on this column
-- (IX_SalesOrderDetail_ProductID), in addition to this repo's covering
-- index. Both have to go or the optimizer just falls back to the native
-- index and the plan barely changes.
DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail DISABLE;
EXEC sp_recompile N'dbo.QS_ProductSales';
GO

-- Captures the "after" plan, now a clustered index scan
EXEC dbo.QS_ProductSales @ProductID = 712;
GO

-- Compares average duration and I/O per interval for this query. Expect
-- two plan_id values for the same query_id, with the later interval
-- showing higher I/O and duration.
SELECT
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    rsi.start_time AS [Interval Start],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE qt.query_sql_text LIKE N'%WHERE d.ProductID = @ProductID%'
ORDER BY rsi.start_time;
GO

PRINT 'Note the query_id and both plan_id values above. You will use them in 03_Force_And_Unforce_Plan.sql.';
