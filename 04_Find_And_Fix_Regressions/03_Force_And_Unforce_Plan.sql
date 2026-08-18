/*
    Fixes the regression created in 02_Find_Regressed_Queries.sql by
    forcing the faster (index seek) plan back on, then shows what
    happens when a forced plan can no longer be used.
    Run 02_Find_Regressed_Queries.sql first.
*/

USE [AdventureWorks2022];
GO

-- Restores both supporting indexes so the good plan is achievable again
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_QSDemo_SalesOrderDetail_ProductID'
                 AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail'))
    CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
        ON Sales.SalesOrderDetail (ProductID)
        INCLUDE (OrderQty, UnitPrice, LineTotal);
GO

ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
GO

-- Lists the query_id and available plan_ids from 02_Find_Regressed_Queries.sql
SELECT
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    p.last_execution_time AS [Last Execution],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE qt.query_sql_text LIKE N'%WHERE d.ProductID = @ProductID%'
ORDER BY p.plan_id;
GO

-- Forces the faster plan. Replace <query_id> and <plan_id> with the
-- values above, picking the plan_id with the lower avg_logical_io_reads
-- (the index seek plan).
EXEC sys.sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;
GO

-- Confirms it's forced
SELECT
    query_id AS [Query Id],
    plan_id AS [Plan Id],
    is_forced_plan AS [Forced]
FROM sys.query_store_plan
WHERE is_forced_plan = 1;
GO

-- Runs it again. SQL Server now uses the forced plan
EXEC dbo.QS_ProductSales @ProductID = 855;
GO

-- Unforces when you're done (replace with your own values)
EXEC sys.sp_query_store_unforce_plan @query_id = <query_id>, @plan_id = <plan_id>;
GO

/*
    Bonus: what a forcing failure looks like.
    Forces the plan again, then drops the index it depends on. SQL
    Server can't satisfy the forced plan, silently falls back to a
    normal compile, and records the failure. This is what
    force_failure_count is for.
*/
/*
EXEC sys.sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;
DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail DISABLE;
EXEC dbo.QS_ProductSales @ProductID = 855;

SELECT
    p.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    p.force_failure_count AS [Force Failure Count],
    p.last_force_failure_reason_desc AS [Last Force Failure Reason]
FROM sys.query_store_plan AS p
WHERE p.is_forced_plan = 1;

EXEC sys.sp_query_store_unforce_plan @query_id = <query_id>, @plan_id = <plan_id>;

-- Restores both indexes again, since this block disabled them a second time
CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
    ON Sales.SalesOrderDetail (ProductID)
    INCLUDE (OrderQty, UnitPrice, LineTotal);
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
*/
