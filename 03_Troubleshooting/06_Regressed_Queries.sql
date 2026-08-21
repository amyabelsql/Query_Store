/*
    Read-only. Finds queries that got slower in the latest interval.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @RegressionThresholdPct DECIMAL(5, 2) = 50.0; -- minimum slowdown percent to include in results
DECLARE @TopN INT = 10; -- number of most regressed queries to return per database
DECLARE @SevereRegressionPct DECIMAL(10,2) = 200.0; -- severe slowdown classification threshold
DECLARE @LargeRegressionPct DECIMAL(10,2) = 100.0; -- large slowdown classification threshold
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Regressed', N'U') IS NOT NULL DROP TABLE #Regressed;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Regressed
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Pct Change] DECIMAL(10, 2) NULL,
    [Prev Avg Duration MS] FLOAT NULL,
    [Current Avg Duration MS] FLOAT NULL,
    [Current Interval Start] DATETIMEOFFSET(7) NULL,
    [Previous Interval Start] DATETIMEOFFSET(7) NULL,
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
WITH ranked_intervals AS
(
    SELECT
        q.query_id,
        qt.query_sql_text,
        rsi.start_time,
        rs.avg_duration,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rsi.start_time DESC) AS interval_rank
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
)
SELECT TOP (@TopN)
    DB_NAME() AS [Database],
    cur.query_id AS [Query Id],
    CAST(100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) AS DECIMAL(10, 2)) AS [Pct Change],
    prev.avg_duration / 1000.0 AS [Prev Avg Duration MS],
    cur.avg_duration / 1000.0 AS [Current Avg Duration MS],
    cur.start_time AS [Current Interval Start],
    prev.start_time AS [Previous Interval Start],
    LEFT(REPLACE(REPLACE(cur.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), 220) AS [Query Text Sample]
FROM ranked_intervals AS cur
JOIN ranked_intervals AS prev
    ON cur.query_id = prev.query_id
   AND prev.interval_rank = cur.interval_rank + 1
WHERE cur.interval_rank = 1
  AND cur.avg_duration > prev.avg_duration
  AND 100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) >= @RegressionThresholdPct
ORDER BY [Pct Change] DESC;';

        INSERT #Regressed
        EXEC sp_executesql
            @Sql,
            N'@RegressionThresholdPct DECIMAL(5, 2), @TopN INT',
            @RegressionThresholdPct = @RegressionThresholdPct,
            @TopN = @TopN;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

SELECT
    [Database],
    [Pct Change],
    [Prev Avg Duration MS],
    [Current Avg Duration MS],
    [Current Avg Duration MS] - [Prev Avg Duration MS] AS [Regression Amount MS],
    CONVERT(VARCHAR(19), CAST([Current Interval Start] AS DATETIME2(0)), 120) AS [Current Interval Start],
    CONVERT(VARCHAR(19), CAST([Previous Interval Start] AS DATETIME2(0)), 120) AS [Previous Interval Start],
    CASE
        WHEN [Pct Change] >= @SevereRegressionPct THEN N'Severe regression'
        WHEN [Pct Change] >= @LargeRegressionPct THEN N'Large regression'
        ELSE N'Moderate regression'
    END AS [Why It Is Flagged],
    CASE
        WHEN [Pct Change] >= @SevereRegressionPct THEN N'Compare current vs previous plan first; check scans, joins, and missing indexes.'
        WHEN [Pct Change] >= @LargeRegressionPct THEN N'Check if plan changed or cardinality estimates shifted; review waits for this query.'
        ELSE N'Validate with more executions, then review plan and parameter sensitivity.'
    END AS [What To Check First],
    [Query Id],
    [Query Text Sample]
FROM #Regressed
ORDER BY [Pct Change] DESC;
GO

-- Quick legend for users new to Query Store
SELECT
    N'Pct Change' AS [Metric],
    N'((Current Avg Duration - Previous Avg Duration) / Previous Avg Duration) * 100' AS [Meaning],
    N'Higher = query got slower between consecutive intervals.' AS [How To Read]
UNION ALL
SELECT
    N'Regression Threshold',
    N'@RegressionThresholdPct',
    N'Only queries at or above this slowdown percent are returned.'
UNION ALL
SELECT
    N'Regression Amount MS',
    N'Current Avg Duration MS - Previous Avg Duration MS',
    N'Absolute slowdown in milliseconds, useful for impact sizing.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
