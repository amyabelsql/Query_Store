/*
	Phase 2 of 5: Create regression.
	Waits for next Query Store interval, then captures slower run.
	Runs for 5 minutes or delay interval set to run longer.
*/

USE [AdventureWorks2022];
GO

DECLARE @IntervalDelay CHAR(8) = '00:05:00'; -- Delay to move into next Query Store interval
DECLARE @AfterExecutions INT = 10; -- Number of regressed executions to capture
DECLARE @ExecutionCounter INT = 1; -- Loop counter for repeated executions

-- Wait past Query Store interval so before/after land in separate buckets.
-- Keep aligned with INTERVAL_LENGTH_MINUTES from 01_Setup/03_Configure.sql.
WAITFOR DELAY @IntervalDelay;

-- Remove supporting indexes and force recompile to produce slower plan.
IF EXISTS
(
	SELECT 1
	FROM sys.indexes
	WHERE name = N'IX_QSDemo_SalesOrderDetail_ProductID'
	  AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail')
)
	DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
ELSE
	PRINT N'IX_QSDemo_SalesOrderDetail_ProductID was not found. Continuing.';

IF EXISTS
(
	SELECT 1
	FROM sys.indexes
	WHERE name = N'IX_SalesOrderDetail_ProductID'
	  AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail')
	  AND is_disabled = 0
)
	ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail DISABLE;
ELSE
	PRINT N'IX_SalesOrderDetail_ProductID was not found or already disabled. Continuing.';

EXEC sp_recompile N'dbo.QS_ProductSales';

-- Capture "after" execution
DECLARE @AfterProductId INT = 712; -- ProductID for post-regression execution
WHILE @ExecutionCounter <= @AfterExecutions
BEGIN
	EXEC dbo.QS_ProductSales @ProductID = @AfterProductId;
	SET @ExecutionCounter += 1;
END;

SELECT
	N'Phase 2 complete' AS [Status],
	CONCAT(N'Captured ', @AfterExecutions, N' regressed executions with degraded indexing.') AS [Message],
	N'Run 03_Troubleshooting/06_Regressed_Queries.sql to confirm slowdown. Then run Phase 3.' AS [Next Step];
GO
