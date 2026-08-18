/*
    Checks Query Store health, purges ad hoc noise, and resets thresholds
    set in 01_Setup/03_Configure.sql back to production values. Run this
    when you're done working through this repo.
*/

USE [AdventureWorks2022];
GO

-- Current size and state
SELECT
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    readonly_reason AS [Readonly Reason]
FROM sys.database_query_store_options;
GO

-- If actual_state_desc is READ_ONLY and readonly_reason includes 65536
-- (size quota reached), raises the limit
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE (MAX_STORAGE_SIZE_MB = 2048);
GO

-- Alternative to raising the limit: wipes all Query Store data and
-- starts over. Destructive, deletes captured query/plan/runtime-stats
-- history.
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE CLEAR;
-- GO

-- Forces read-write mode back on explicitly
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
GO

-- Purges ad hoc/internal queries whose last execution was more than 5
-- minutes ago, so they don't crowd out queries worth keeping. Adapted
-- from Microsoft's own sample cleanup script, safe to run repeatedly.
SET NOCOUNT ON;
DECLARE @id INT;
DECLARE adhoc_queries_cursor CURSOR FOR
    SELECT q.query_id
    FROM sys.query_store_query_text AS qt
    JOIN sys.query_store_query AS q ON q.query_text_id = qt.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    WHERE q.is_internal_query = 1 OR q.object_id = 0
    GROUP BY q.query_id
    HAVING MAX(rs.last_execution_time) < DATEADD(MINUTE, -5, GETUTCDATE())
    ORDER BY q.query_id;
OPEN adhoc_queries_cursor;
FETCH NEXT FROM adhoc_queries_cursor INTO @id;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'EXEC sp_query_store_remove_query ' + CAST(@id AS VARCHAR(10));
    EXEC sp_query_store_remove_query @id;
    FETCH NEXT FROM adhoc_queries_cursor INTO @id;
END
CLOSE adhoc_queries_cursor;
DEALLOCATE adhoc_queries_cursor;
GO

-- Resets runtime stats for a single plan without deleting it
-- EXEC sp_query_store_reset_exec_stats @plan_id = <plan_id>;

-- Recovers from an ERROR state (SQL Server 2017+)
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = OFF;
-- EXEC sp_query_store_consistency_check;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = ON;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE (OPERATION_MODE = READ_WRITE);

-- Resets thresholds to production values
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE
(
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES     = 60,
    QUERY_CAPTURE_MODE          = AUTO
);
GO

-- If 04_Find_And_Fix_Regressions was run but 03_Force_And_Unforce_Plan.sql
-- (the fix step) wasn't, AdventureWorks2022's native
-- IX_SalesOrderDetail_ProductID index may still be disabled. Re-enables
-- it unconditionally so cleanup doesn't leave the sample database worse
-- off than it started. Rebuilding an already-enabled index is a
-- harmless no-op.
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_SalesOrderDetail_ProductID'
             AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail'))
    ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
GO

-- Optional: drops this repo's demo objects entirely
-- DROP PROCEDURE IF EXISTS dbo.QS_ProductSales;
-- DROP PROCEDURE IF EXISTS dbo.QS_OrdersByCustomer;
-- DROP INDEX IF EXISTS IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
