/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS). Fully
    automatic, no manual step, no special settings.

    1. Creates a procedure that raises a genuine divide-by-zero error
    2. Runs it 3 times, so Query Store has a real Exception execution
       to show, see 03_Troubleshooting/01_Health_Checks.sql
       sections 7-8 to check for it

    Run 01_Setup/02_Turn_On.sql and 01_Setup/03_Configure.sql first.
*/

USE [AdventureWorks2022];
GO

-- Raises a genuine divide-by-zero error. UnitPrice - UnitPrice is
-- always 0, but it's a column, not a literal, so the optimizer can't
-- fold it away at compile time, the error only happens once real rows
-- are processed at runtime. Query Store records this as an Exception
-- execution (the triangle marker in SSMS's Query Store report charts).
CREATE OR ALTER PROCEDURE dbo.QS_DivideByZeroDemo
    AS
BEGIN
    SET NOCOUNT ON;
SELECT SalesOrderID, UnitPrice / (UnitPrice - UnitPrice) AS ForcedDivideByZero
FROM Sales.SalesOrderDetail;
END
GO

-- Runs it 3 times so Query Store has more than one execution to show.
-- Each run fails with a real divide-by-zero error, that's the point,
-- not a bug in this script.
EXEC dbo.QS_DivideByZeroDemo;
GO
EXEC dbo.QS_DivideByZeroDemo;
GO
EXEC dbo.QS_DivideByZeroDemo;
GO

PRINT ''
PRINT 'Errors are normal, they are used to test the rest of the scripts.'
PRINT ''
PRINT 'You can view this in Query Store once the inverval flush happens based on settings';
