/*
    Read-only. Tracks one query_id across plans and intervals.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @QueryId BIGINT = <query_id>; -- query_id to track
DECLARE @WorseMultiplier FLOAT = 1.5; -- marks interval as worse when current > previous * multiplier
DECLARE @BetterMultiplier FLOAT = 0.7; -- marks interval as better when current < previous * multiplier
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Track', N'U') IS NOT NULL DROP TABLE #Track;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Track
(
    [Database] SYSNAME NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Forced] BIT NULL,
    [Interval Start] DATETIMEOFFSET(7) NULL,
    [Executions] BIGINT NULL,
    [Avg Duration MS] FLOAT NULL,
    [Avg CPU MS] FLOAT NULL,
    [Avg Logical IO Reads] FLOAT NULL
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
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    rsi.start_time AS [Interval Start],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_cpu_time / 1000.0 AS [Avg CPU MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads]
FROM sys.query_store_plan AS p
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE p.query_id = @QueryId;';

        INSERT #Track
        EXEC sp_executesql @Sql, N'@QueryId BIGINT', @QueryId = @QueryId;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

;WITH trend AS
(
    SELECT
        t.[Database],
        t.[Plan Id],
        t.[Forced],
        t.[Interval Start],
        t.[Executions],
        t.[Avg Duration MS],
        t.[Avg CPU MS],
        t.[Avg Logical IO Reads],
        LAG(t.[Avg Duration MS]) OVER (PARTITION BY t.[Database], t.[Plan Id] ORDER BY t.[Interval Start]) AS [Prev Avg Duration MS]
    FROM #Track AS t
)
SELECT
    [Database],
    [Plan Id],
    [Forced],
    CONVERT(VARCHAR(19), CAST([Interval Start] AS DATETIME2(0)), 120) AS [Interval Start],
    [Executions],
    [Avg Duration MS],
    [Avg CPU MS],
    [Avg Logical IO Reads],
    CAST(100.0 * ([Avg Duration MS] - [Prev Avg Duration MS]) / NULLIF([Prev Avg Duration MS], 0) AS DECIMAL(10,2)) AS [Duration Change vs Prior Interval %],
    CASE
        WHEN [Prev Avg Duration MS] IS NULL THEN N'No prior point for this plan'
        WHEN [Avg Duration MS] > [Prev Avg Duration MS] * @WorseMultiplier THEN N'Performance worsened for this plan'
        WHEN [Avg Duration MS] < [Prev Avg Duration MS] * @BetterMultiplier THEN N'Performance improved for this plan'
        ELSE N'No major change for this plan'
    END AS [What It Suggests],
    CASE
        WHEN [Prev Avg Duration MS] IS NULL THEN N'Collect more intervals for trend confidence.'
        WHEN [Avg Duration MS] > [Prev Avg Duration MS] * @WorseMultiplier THEN N'Compare current and previous plan details; check waits and parameter values.'
        WHEN [Avg Duration MS] < [Prev Avg Duration MS] * @BetterMultiplier THEN N'Keep monitoring; improvement likely from better plan or lower contention.'
        ELSE N'Use with 06_Regressed_Queries.sql if broad slowdown is suspected.'
    END AS [What To Check First]
FROM trend
ORDER BY [Database], [Interval Start], [Plan Id];
GO

SELECT
    N'Duration Change vs Prior Interval %' AS [Metric],
    N'Percent change in average duration for the same plan_id between adjacent intervals.' AS [Meaning],
    N'Use this to spot plan-specific slowdowns over time.' AS [How To Read]
UNION ALL
SELECT
    N'Forced = 1',
    N'Plan was forced by Query Store.',
    N'If still slow, forced plan may no longer be optimal for current data/workload.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
