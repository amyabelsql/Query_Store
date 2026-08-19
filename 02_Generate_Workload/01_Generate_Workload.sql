/*
    Run this entire script, top to bottom (e.g. F5 in SSMS). The GO
    batches below are required, not a signal to run it a piece at a time.

    1. Creates a supporting index and two stored procedures
    2. Runs each procedure 50 times with different parameters
    3. Runs 8 distinct non-parameterized ad hoc queries, 6 times each,
       to show query-text bloat
    4. Prints when to come back and check Query Store

    Run 01_Setup/02_Turn_On.sql and 01_Setup/03_Configure.sql first.
    Run 02_Generate_Exception_Query.sql separately for an Exception
    execution, not part of this script.
*/

USE [AdventureWorks2022];
GO

-- Supporting index plus two parameterized procedures
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_QSDemo_SalesOrderDetail_ProductID'
             AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail'))
    DROP INDEX IX_QSDemo_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail;
GO

CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
    ON Sales.SalesOrderDetail (ProductID)
    INCLUDE (OrderQty, UnitPrice, LineTotal);
GO

CREATE OR ALTER PROCEDURE dbo.QS_ProductSales
    @ProductID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.SalesOrderID, d.ProductID, d.OrderQty, d.UnitPrice, d.LineTotal
    FROM Sales.SalesOrderDetail AS d
    WHERE d.ProductID = @ProductID;
END
GO

CREATE OR ALTER PROCEDURE dbo.QS_OrdersByCustomer
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT h.SalesOrderID, h.OrderDate, h.TotalDue, d.ProductID, d.OrderQty
    FROM Sales.SalesOrderHeader AS h
    JOIN Sales.SalesOrderDetail AS d ON d.SalesOrderID = h.SalesOrderID
    WHERE h.CustomerID = @CustomerID;
END
GO

-- Runs each procedure 50 times with different parameters, same query
-- shape each time, so Query Store aggregates them under one query_id
DECLARE @i INT = 1, @ProductID INT, @CustomerID INT;
WHILE @i <= 50
BEGIN
    SET @ProductID = 707 + (@i % 20);
    SET @CustomerID = 29485 + (@i % 30);
    EXEC dbo.QS_ProductSales @ProductID = @ProductID;
    EXEC dbo.QS_OrdersByCustomer @CustomerID = @CustomerID;
    SET @i += 1;
END
GO

-- Runs 8 distinct non-parameterized queries, 6 times each.
-- Each literal is its own query_id, so this shows one query shape getting 8 separate
-- plans instead of one shared, parameterized plan.
-- This is the pattern that bloats Query Store and the plan cache.
-- Each one runs 6 times (not once) so QUERY_CAPTURE_MODE = AUTO actually captures it, a query
-- that only runs once usually doesn't clear AUTO's capture bar.
-- See 04_Regressions_And_Forcing.
DECLARE @sql NVARCHAR(500), @j INT = 1, @k INT;
WHILE @j <= 8
BEGIN
    SET @k = 1;
    WHILE @k <= 6
    BEGIN
        SET @sql = N'SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = ' + CAST(707 + @j AS NVARCHAR(10));
        EXEC (@sql);
        SET @k += 1;
    END
    SET @j += 1;
END
GO

PRINT 'Workload generated. Wait about 15 minutes, the Query Store interval set in 01_Setup/03_Configure.sql, for the first interval to flush, then run 03_Catalog_Views/01_Catalog_Views.sql.';
