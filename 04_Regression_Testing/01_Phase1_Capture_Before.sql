/*
	Phase 1 of 5: Capture baseline.
	Run this first.
*/

USE [AdventureWorks2022];
GO

DECLARE @ProductId INT = 712; -- ProductID for baseline execution
DECLARE @BaselineExecutions INT = 10; -- Number of baseline executions to capture
DECLARE @ExecutionCounter INT = 1; -- Loop counter for repeated executions

-- Baseline executions while supporting indexes are in place
WHILE @ExecutionCounter <= @BaselineExecutions
BEGIN
	EXEC dbo.QS_ProductSales @ProductID = @ProductId;
	SET @ExecutionCounter += 1;
END;

SELECT
	N'Phase 1 complete' AS [Status],
	CONCAT(N'Captured ', @BaselineExecutions, N' baseline executions. Run Phase 2 with the same execution count.') AS [Message],
	N'Optional: run 03_Troubleshooting/04_Top_Resource_Consumers.sql for before baseline. Then run Phase 2.' AS [Next Step];
GO
