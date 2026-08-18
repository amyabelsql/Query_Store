/*
    Applies a query hint to dbo.QS_OrdersByCustomer through Query Store,
    without touching its Transact-SQL text (SQL Server 2022+ / Azure SQL
    Database).
    Run 02_Generate_Workload/01_Generate_Workload.sql first.
*/

USE [AdventureWorks2022];
GO

-- Finds the query_id for the target statement
SELECT
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text]
FROM sys.query_store_query_text AS qt
JOIN sys.query_store_query AS q ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text LIKE N'%FROM Sales.SalesOrderHeader AS h%';
GO

-- Applies a hint that caps the memory grant and pins MAXDOP to 1.
-- Replace <query_id> with the value returned above.
EXEC sys.sp_query_store_set_hints
    @query_id = <query_id>,
    @query_hints = N'OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 10)';
GO

-- Confirms the hint is registered
SELECT
    query_hint_id AS [Hint Id],
    query_id AS [Query Id],
    query_hint_text AS [Hint Text],
    last_query_hint_failure_reason_desc AS [Last Failure Reason],
    query_hint_failure_count AS [Failure Count],
    source_desc AS [Source]
FROM sys.query_store_query_hints
WHERE query_id = <query_id>;
GO

-- Re-runs the procedure. Capture the actual execution plan (Ctrl+M in
-- SSMS, or SET STATISTICS XML ON) and look for the
-- QueryStoreStatementHintText attribute on the statement.
EXEC dbo.QS_OrdersByCustomer @CustomerID = 29489;
GO

-- Removes the hint
EXEC sys.sp_query_store_clear_hints @query_id = <query_id>;
GO
