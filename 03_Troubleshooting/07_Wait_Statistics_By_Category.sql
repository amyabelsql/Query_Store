/*
    Read-only. Analyzes Query Store waits.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @LookbackHours INT = 24; -- analysis window size in hours (UTC)
DECLARE @TopN INT = 25; -- number of top queries to return for dominant wait category
DECLARE @TextSampleLength INT = 220; -- max query text sample length in result rows
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#WaitCategoryTotals', N'U') IS NOT NULL DROP TABLE #WaitCategoryTotals;
IF OBJECT_ID(N'tempdb..#TopWaitQueries', N'U') IS NOT NULL DROP TABLE #TopWaitQueries;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #WaitCategoryTotals
(
    [Database] SYSNAME NOT NULL,
    [Wait Category] VARCHAR(60) NOT NULL,
    [Total Wait Time MS] BIGINT NOT NULL
);

CREATE TABLE #TopWaitQueries
(
    [Database] SYSNAME NOT NULL,
    [Wait Category] VARCHAR(60) NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Total Wait Time MS] BIGINT NOT NULL,
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
    THROW 50002, 'No eligible databases found to analyze.', 1;

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
    ws.wait_category_desc AS [Wait Category],
    SUM(ws.total_query_wait_time_ms) AS [Total Wait Time MS]
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY ws.wait_category_desc;';

        INSERT #WaitCategoryTotals
        EXEC sp_executesql @Sql, N'@LookbackHours INT', @LookbackHours = @LookbackHours;

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
WITH dominant AS
(
    SELECT TOP (1)
        ws.wait_category_desc AS wait_category_desc
    FROM sys.query_store_wait_stats AS ws
    JOIN sys.query_store_runtime_stats_interval AS rsi
        ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
    GROUP BY ws.wait_category_desc
    ORDER BY SUM(ws.total_query_wait_time_ms) DESC
)
SELECT TOP (@TopN)
    DB_NAME() AS [Database],
    d.wait_category_desc AS [Wait Category],
    q.query_id AS [Query Id],
    SUM(ws.total_query_wait_time_ms) AS [Total Wait Time MS],
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), @TextSampleLength) AS [Query Text Sample]
FROM dominant AS d
JOIN sys.query_store_wait_stats AS ws ON ws.wait_category_desc = d.wait_category_desc
JOIN sys.query_store_plan AS p ON ws.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY d.wait_category_desc, q.query_id, qt.query_sql_text
ORDER BY [Total Wait Time MS] DESC;';

        INSERT #TopWaitQueries
        EXEC sp_executesql
            @Sql,
            N'@LookbackHours INT, @TopN INT, @TextSampleLength INT',
            @LookbackHours = @LookbackHours,
            @TopN = @TopN,
            @TextSampleLength = @TextSampleLength;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

-- 1) Wait totals by category
SELECT
    [Database],
    [Wait Category],
    [Total Wait Time MS],
    CAST(100.0 * [Total Wait Time MS] / NULLIF(SUM([Total Wait Time MS]) OVER (PARTITION BY [Database]), 0) AS DECIMAL(6,2)) AS [Pct Of Wait In Lookback],
    CASE
        WHEN [Wait Category] IN (N'Lock', N'LCK_M_IX', N'LCK_M_X') THEN N'Blocking/concurrency pressure'
        WHEN [Wait Category] LIKE N'%IO%' OR [Wait Category] = N'Buffer IO' THEN N'Storage or read pattern pressure'
        WHEN [Wait Category] LIKE N'%CPU%' THEN N'CPU pressure'
        WHEN [Wait Category] LIKE N'%Memory%' THEN N'Memory grant pressure'
        ELSE N'General wait category, inspect top queries below'
    END AS [What It Suggests]
FROM #WaitCategoryTotals
ORDER BY [Database], [Total Wait Time MS] DESC;
GO

-- 2) Top queries in each database's dominant wait category
SELECT
    [Database],
    [Wait Category],
    [Query Id],
    [Total Wait Time MS],
    CASE
        WHEN [Wait Category] IN (N'Lock', N'LCK_M_IX', N'LCK_M_X') THEN N'Check blocking chain, transaction length, and indexing for seekability.'
        WHEN [Wait Category] LIKE N'%IO%' OR [Wait Category] = N'Buffer IO' THEN N'Check logical reads, missing indexes, and scan-heavy plans.'
        WHEN [Wait Category] LIKE N'%CPU%' THEN N'Check expensive operators, UDF usage, and cardinality estimates.'
        WHEN [Wait Category] LIKE N'%Memory%' THEN N'Check memory grants, spills to tempdb, and join/sort patterns.'
        ELSE N'Check execution plan + runtime stats for this query_id.'
    END AS [What To Check First],
    [Query Text Sample]
FROM #TopWaitQueries
ORDER BY [Database], [Total Wait Time MS] DESC;
GO

SELECT
    N'Pct Of Wait In Lookback' AS [Metric],
    N'Percent of total wait time for the database in the selected lookback window.' AS [Meaning],
    N'Highest percentage points to the dominant bottleneck type first.' AS [How To Read]
UNION ALL
SELECT
    N'Dominant Wait Category',
    N'Category with highest summed wait time in the window.',
    N'Use top-query rows for that category to choose query_id investigation targets.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
