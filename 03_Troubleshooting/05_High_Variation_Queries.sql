/*
    Read-only. Finds queries with unstable duration.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @LookbackHours INT = 24; -- analysis window size in hours (UTC)
DECLARE @TopN INT = 25; -- number of highest-variation rows to return per database
DECLARE @MinExecutions BIGINT = 5; -- minimum execution count to reduce low-sample noise
DECLARE @HighVariationThreshold DECIMAL(10,2) = 2.0; -- high-risk variation ratio threshold
DECLARE @MediumVariationThreshold DECIMAL(10,2) = 1.0; -- medium-risk variation ratio threshold
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Variation', N'U') IS NOT NULL DROP TABLE #Variation;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Variation
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Executions] BIGINT NOT NULL,
    [Avg Duration MS] FLOAT NULL,
    [Stdev Duration MS] FLOAT NULL,
    [Variation Ratio] DECIMAL(10, 2) NULL,
    [Risk] VARCHAR(20) NOT NULL,
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
SELECT TOP (@TopN)
    DB_NAME() AS [Database],
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.stdev_duration / 1000.0 AS [Stdev Duration MS],
    CAST(rs.stdev_duration / NULLIF(rs.avg_duration, 0) AS DECIMAL(10, 2)) AS [Variation Ratio],
    CASE
        WHEN rs.stdev_duration / NULLIF(rs.avg_duration, 0) >= @HighVariationThreshold THEN N''High''
        WHEN rs.stdev_duration / NULLIF(rs.avg_duration, 0) >= @MediumVariationThreshold THEN N''Medium''
        ELSE N''Low''
    END AS [Risk],
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), 220) AS [Query Text Sample]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
  AND rs.count_executions > @MinExecutions
ORDER BY [Variation Ratio] DESC;';

        INSERT #Variation
        EXEC sp_executesql
            @Sql,
            N'@LookbackHours INT, @TopN INT, @MinExecutions BIGINT, @HighVariationThreshold DECIMAL(10,2), @MediumVariationThreshold DECIMAL(10,2)',
            @LookbackHours = @LookbackHours,
            @TopN = @TopN,
            @MinExecutions = @MinExecutions,
            @HighVariationThreshold = @HighVariationThreshold,
            @MediumVariationThreshold = @MediumVariationThreshold;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

SELECT
    [Database],
    [Risk],
    [Variation Ratio],
    [Executions],
    [Avg Duration MS],
    [Stdev Duration MS],
    CASE
        WHEN [Variation Ratio] >= @HighVariationThreshold THEN N'Very unstable runtime (big spikes vs average).'
        WHEN [Variation Ratio] >= @MediumVariationThreshold THEN N'Unstable runtime (noticeable spread from average).'
        ELSE N'Relatively stable runtime.'
    END AS [What This Means],
    CASE
        WHEN [Variation Ratio] >= @HighVariationThreshold THEN N'Check parameter sniffing, plan changes, waits, and memory grant feedback first.'
        WHEN [Variation Ratio] >= @MediumVariationThreshold THEN N'Track this query over time and compare plans/intervals for skew or blocking.'
        ELSE N'Monitor only; prioritize higher-variation queries first.'
    END AS [What To Check First],
    [Query Id],
    [Plan Id],
    [Query Text Sample]
FROM #Variation
ORDER BY [Variation Ratio] DESC;


-- Quick legend for users new to Query Store
SELECT
    N'Variation Ratio' AS [Metric],
    N'Stdev Duration / Avg Duration for that query+plan+interval row.' AS [Meaning],
    N'Higher means less predictable performance (spiky runtime).' AS [How To Read]
UNION ALL
SELECT
    N'Risk = High',
    CONCAT(N'Variation Ratio >= ', CAST(@HighVariationThreshold AS VARCHAR(20))),
    N'Prioritize investigation now.'
UNION ALL
SELECT
    N'Risk = Medium',
    CONCAT(N'Variation Ratio >= ', CAST(@MediumVariationThreshold AS VARCHAR(20)), N' and < ', CAST(@HighVariationThreshold AS VARCHAR(20))),
    N'Investigate after high-risk items.'
UNION ALL
SELECT
    N'Risk = Low',
    CONCAT(N'Variation Ratio < ', CAST(@MediumVariationThreshold AS VARCHAR(20))),
    N'Usually stable; monitor.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
