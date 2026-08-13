/*
    02 - Generate a sample workload
    Creates two demo stored procedures and runs them repeatedly so Query
    Store has real data for the rest of the labs. Also runs a batch of
    non-parameterized ad hoc queries to demonstrate query-text bloat.

    Run 00-setup-sample-db.sql first.
*/

USE [AdventureWorks2022];
GO

-- ---------------------------------------------------------------------------
-- 1. A supporting index and two parameterized demo procedures
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 2. Parameterized workload: same query shape, different inputs.
--    This is the pattern Query Store handles well -- one query_id,
--    one plan, aggregated stats.
-- ---------------------------------------------------------------------------
DECLARE @i INT = 1;
WHILE @i <= 50
BEGIN
    EXEC dbo.QS_ProductSales @ProductID = 707 + (@i % 20);
    EXEC dbo.QS_OrdersByCustomer @CustomerID = 29485 + (@i % 30);
    SET @i += 1;
END
GO

-- ---------------------------------------------------------------------------
-- 3. Ad hoc / non-parameterized workload.
--    Each iteration is a different literal, so SQL Server compiles a
--    new plan almost every time. This is the pattern that bloats Query
--    Store and the plan cache -- see docs/04-troubleshooting-scenarios.md.
-- ---------------------------------------------------------------------------
DECLARE @sql NVARCHAR(500), @j INT = 1;
WHILE @j <= 30
BEGIN
    SET @sql = N'SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = ' + CAST(707 + @j AS NVARCHAR(10));
    EXEC (@sql);
    SET @j += 1;
END
GO

PRINT 'Workload generated. Wait about a minute for the first Query Store interval to flush, then run 03-explore-catalog-views.sql.';
