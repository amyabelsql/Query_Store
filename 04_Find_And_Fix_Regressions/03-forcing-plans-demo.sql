/*
    03 - Force and unforce a plan
    Companion to README.md in this folder. Fixes the regression created
    in 02-find-regressed-queries.sql by forcing the faster (index seek)
    plan back on, then demonstrates what happens when a forced plan can
    no longer be used.

    Run 02-find-regressed-queries.sql first.
*/

USE [AdventureWorks2022];
GO

-- Step 1: restore the supporting indexes so the good plan is achievable
-- again -- both the workshop's covering index and AdventureWorks2022's
-- native one, which 02-find-regressed-queries.sql disabled.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_QSDemo_SalesOrderDetail_ProductID'
                 AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail'))
    CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
        ON Sales.SalesOrderDetail (ProductID)
        INCLUDE (OrderQty, UnitPrice, LineTotal);
GO

ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
GO

-- Step 2: list the query_id and available plan_ids
-- (query_id and the earlier/faster plan_id come from 05-find-regressed-queries.sql)
SELECT q.query_id, p.plan_id, p.is_forced_plan, p.last_execution_time,
       rs.avg_duration / 1000.0 AS avg_duration_ms,
       rs.avg_logical_io_reads
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE qt.query_sql_text LIKE N'%WHERE d.ProductID = @ProductID%'
ORDER BY p.plan_id;
GO

-- Step 3: force the faster plan.
-- Replace <query_id> and <plan_id> with the values from Step 2 (pick the
-- plan_id with the lower avg_logical_io_reads -- that's the index seek plan).
EXEC sys.sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;
GO

-- Step 4: verify it's forced
SELECT query_id, plan_id, is_forced_plan
FROM sys.query_store_plan
WHERE is_forced_plan = 1;
GO

-- Step 5: run it again -- SQL Server now uses the forced plan
EXEC dbo.QS_ProductSales @ProductID = 855;
GO

-- Step 6: unforce when you're done (replace with your own values)
EXEC sys.sp_query_store_unforce_plan @query_id = <query_id>, @plan_id = <plan_id>;
GO

-- ---------------------------------------------------------------------------
-- Bonus: what a forcing FAILURE looks like.
-- Force the plan again, then drop the index it depends on. SQL Server can't
-- satisfy the forced plan, silently falls back to a normal compile, and
-- records the failure -- this is what force_failure_count is for.
-- ---------------------------------------------------------------------------
/*
EXEC sys.sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;
DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail DISABLE;
EXEC dbo.QS_ProductSales @ProductID = 855;

SELECT p.query_id, p.plan_id, p.is_forced_plan,
       p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
WHERE p.is_forced_plan = 1;

EXEC sys.sp_query_store_unforce_plan @query_id = <query_id>, @plan_id = <plan_id>;

-- Restore both indexes again -- this block disabled them a second time.
CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
    ON Sales.SalesOrderDetail (ProductID)
    INCLUDE (OrderQty, UnitPrice, LineTotal);
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
*/
