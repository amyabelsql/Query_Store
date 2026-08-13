/*
    07 - Query Store hints (SQL Server 2022+ / Azure SQL Database)
    Companion to docs/05-sql2022-features.md. Applies a query hint to
    dbo.QS_OrdersByCustomer without touching its Transact-SQL text.

    Run 02-generate-sample-workload.sql first.
*/

USE [AdventureWorks2022];
GO

-- Step 1: find the query_id for the target statement
SELECT q.query_id, qt.query_sql_text
FROM sys.query_store_query_text AS qt
JOIN sys.query_store_query AS q ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text LIKE N'%FROM Sales.SalesOrderHeader AS h%';
GO

-- Step 2: apply a hint -- cap the memory grant and pin MAXDOP to 1.
-- Replace <query_id> with the value returned above.
EXEC sys.sp_query_store_set_hints
    @query_id = <query_id>,
    @query_hints = N'OPTION (MAXDOP 1, MAX_GRANT_PERCENT = 10)';
GO

-- Step 3: confirm the hint is registered
SELECT query_hint_id, query_id, query_hint_text,
       last_query_hint_failure_reason_desc, query_hint_failure_count, source_desc
FROM sys.query_store_query_hints
WHERE query_id = <query_id>;
GO

-- Step 4: re-run the procedure -- capture the actual execution plan
-- (Ctrl+M in SSMS, or SET STATISTICS XML ON) and look for the
-- QueryStoreStatementHintText attribute on the statement.
EXEC dbo.QS_OrdersByCustomer @CustomerID = 29489;
GO

-- Step 5: remove the hint
EXEC sys.sp_query_store_clear_hints @query_id = <query_id>;
GO
