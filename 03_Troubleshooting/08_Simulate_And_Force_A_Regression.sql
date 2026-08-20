/*
    Not read-only, this drops and rebuilds indexes and forces a plan.
    A guided lab: cause a regression on purpose, find it, force the
    good plan back. Same workflow you'd use in production when an index
    change, a statistics update, or a schema change makes a
    previously-fast query slow.

    Run steps 1-6 as one pass, that creates the regression, then stop.
    Step 8's output gives you the <query_id>/<plan_id> to paste into
    steps 9, 11, and 12 before running them. The commented-out bonus
    block at the bottom is separate, read it before running it.

    1. Captures the "before" plan while the supporting index is in place
    2. Run 04_Top_Resource_Consumers.sql now, for a before baseline
    3. Waits past the current Query Store interval, so "before" and
       "after" land as separate rows
    4. Removes the supporting indexes and forces a recompile
    5. Captures the "after" plan, now a clustered index scan
    6. Run 04_Top_Resource_Consumers.sql and 06_Regressed_Queries.sql
       now, to see the regression
    7. Restores both supporting indexes so the good plan is achievable
    8. Lists query_id and available plan_ids, pick the plan_id with the
       lower avg_logical_io_reads (the index seek plan)
    9. Forces that plan (edit the placeholders first)
    10. Confirms it's forced
    11. Runs the query again to show the forced plan being used
    12. Unforces the plan when you're done (edit the placeholders first)

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

PRINT 'Regression created. Run 04_Top_Resource_Consumers.sql and 06_Regressed_Queries.sql to see it, then come back here for steps 7+ to force the fix.';
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

-- Lists the query_id and available plan_ids for the demo query. Pick
-- the [Plan Id] with the lower [Avg Logical IO Reads], that's the index
-- seek plan you want to force.
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

-- Confirms it's forced. [Forced] should be 1 for the [Plan Id] you
-- just forced, and no other row for the same [Query Id] should show 1.
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
    force_failure_count is for (see 01_Health_Checks.sql section 6).
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
