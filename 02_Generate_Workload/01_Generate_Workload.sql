/*
    Creates two stored procedures and calls each one 50 times with
    different parameters, then runs 30 non-parameterized ad hoc queries.
    Gives Query Store real data to capture for the rest of this repo, and
    the ad hoc batch shows how query-text bloat happens.
    Run 01_Setup/02_Turn_On.sql and 01_Setup/03_Configure.sql first.
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

-- Runs 30 non-parameterized queries, each with a different literal, so
-- SQL Server compiles a near-new plan almost every time. This is the
-- pattern that bloats Query Store and the plan cache. See
-- 04_Find_And_Fix_Regressions.
DECLARE @sql NVARCHAR(500), @j INT = 1;
WHILE @j <= 30
BEGIN
    SET @sql = N'SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = ' + CAST(707 + @j AS NVARCHAR(10));
    EXEC (@sql);
    SET @j += 1;
END
GO

PRINT 'Workload generated. Wait about a minute for the first Query Store interval to flush, then run 03_Explore_Catalog_Views/01_Explore_Catalog_Views.sql.';
