/*
    Read-only. Finds query_id values from query text.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @SearchText VARCHAR(200) = '%SalesOrderDetail%'; -- LIKE pattern used to find query text candidates
DECLARE @TextSampleLength INT = 220; -- max query text sample length in result rows
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Results', N'U') IS NOT NULL DROP TABLE #Results;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Results
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Containing Object Id] INT NULL,
    [Parameterization] VARCHAR(60) NULL,
    [Last Execution] DATETIMEOFFSET(7) NULL,
    [Query Text Sample] VARCHAR(220) NULL
);

CREATE TABLE #Errors
(
    [Database] SYSNAME NOT NULL,
    [Error Message] VARCHAR(4000) NOT NULL
);

IF @ApplyToAllDatabases = 1
BEGIN
    INSERT #Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.source_database_id IS NULL;
END
ELSE
BEGIN
    IF DB_ID(@DatabaseName) IS NULL
        THROW 50001, 'Database in @DatabaseName does not exist.', 1;

    INSERT #Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.name = @DatabaseName
      AND d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.source_database_id IS NULL;
END;

IF NOT EXISTS (SELECT 1 FROM #Targets)
    THROW 50002, 'No eligible databases found to search.', 1;

WHILE EXISTS (SELECT 1 FROM #Targets)
BEGIN
    SELECT TOP (1) @CurrentDatabase = t.DatabaseName
    FROM #Targets AS t
    ORDER BY t.DatabaseName;

    DELETE FROM #Targets WHERE DatabaseName = @CurrentDatabase;

    BEGIN TRY
        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    q.query_id AS [Query Id],
    q.object_id AS [Containing Object Id],
    q.query_parameterization_type_desc AS [Parameterization],
    q.last_execution_time AS [Last Execution],
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), @TextSampleLength) AS [Query Text Sample]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE qt.query_sql_text LIKE @SearchText
ORDER BY q.last_execution_time DESC;';

        INSERT #Results
        EXEC sp_executesql
            @Sql,
            N'@SearchText VARCHAR(200), @TextSampleLength INT',
            @SearchText = @SearchText,
            @TextSampleLength = @TextSampleLength;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

SELECT
    [Database],
    [Query Id],
    [Parameterization],
    CONVERT(VARCHAR(19), CAST([Last Execution] AS DATETIME2(0)), 120) AS [Last Execution],
    CASE
        WHEN [Containing Object Id] IS NOT NULL AND [Containing Object Id] > 0 THEN N'Likely from a module (proc/view/function).'
        ELSE N'Likely ad hoc or dynamic SQL text.'
    END AS [What This Match Suggests],
    CASE
        WHEN [Containing Object Id] IS NOT NULL AND [Containing Object Id] > 0 THEN N'Use object_id to identify module, then run 10_Track_A_Query.sql with Query Id.'
        ELSE N'Run 10_Track_A_Query.sql with Query Id and 04_Top_Resource_Consumers.sql for impact.'
    END AS [Next Step],
    [Containing Object Id],
    [Query Text Sample]
FROM #Results
ORDER BY [Last Execution] DESC;
GO

SELECT
    N'How to use this script' AS [Topic],
    N'Paste a unique fragment in @SearchText to get query_id candidates.' AS [Guidance]
UNION ALL
SELECT
    N'After you find Query Id',
    N'Run 10_Track_A_Query.sql to review plan/interval behavior for that query_id.'
UNION ALL
SELECT
    N'If many matches return',
    N'Make @SearchText more specific (table alias, predicate, or procedure text fragment).';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
