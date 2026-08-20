/*
    Read-only. Run the whole script. Edit @SearchText first.

    Finds a query_id from pasted query text. Start here when you have a
    query from an app log or a slow report but no query_id.
*/

USE [AdventureWorks2022];
GO

DECLARE @SearchText NVARCHAR(200) = N'%SalesOrderDetail%';

SELECT
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text],
    q.object_id AS [Containing Object Id],
    q.query_parameterization_type_desc AS [Parameterization]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE qt.query_sql_text LIKE @SearchText
ORDER BY q.last_execution_time DESC;
GO
