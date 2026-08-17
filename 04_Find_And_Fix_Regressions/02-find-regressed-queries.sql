/*
    02 - Create and find a regressed query
    Deliberately regresses dbo.QS_ProductSales by dropping its supporting
    index, then shows how to spot the regression through the runtime
    stats interval history -- the same signal behind the SSMS
    "Regressed Queries" report.

    Run 01_Setup/01-setup-sample-db.sql and
    02_Generate_Workload/generate-workload.sql first.
*/

USE [AdventureWorks2022];
GO

-- Step 1: capture the "before" plan (supporting index still in place)
EXEC dbo.QS_ProductSales @ProductID = 712;
GO

-- Step 2: let the current Query Store interval close so "before" and
-- "after" are measured as separate rows. INTERVAL_LENGTH_MINUTES was set
-- to 1 in 00-setup-sample-db.sql for this reason (production databases
-- typically use 60).
WAITFOR DELAY '00:01:05';
GO

-- Step 3: remove the supporting index and force a recompile
DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
EXEC sp_recompile N'dbo.QS_ProductSales';
GO

-- Step 4: capture the "after" plan (index gone -> clustered index scan)
EXEC dbo.QS_ProductSales @ProductID = 712;
GO

-- Step 5: compare average duration and I/O per interval for this query.
-- You should see two plan_id values for the same query_id, and the later
-- interval showing higher avg_logical_io_reads / avg_duration_ms.
SELECT
    q.query_id,
    p.plan_id,
    rsi.start_time,
    rs.count_executions,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.avg_logical_io_reads
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE qt.query_sql_text LIKE N'%WHERE d.ProductID = @ProductID%'
ORDER BY rsi.start_time;
GO

PRINT 'Note the query_id and both plan_id values above -- you will use them in 06-forcing-plans-demo.sql.';
