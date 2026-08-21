/*
    Read-only. Shows overall Query Store resource trend.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @LookbackHours INT = 24; -- analysis window size in hours (UTC)
DECLARE @SpikeMultiplier FLOAT = 1.5; -- marks interval as spike when current > previous * multiplier
DECLARE @DropMultiplier FLOAT = 0.7; -- marks interval as drop when current < previous * multiplier
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Overall', N'U') IS NOT NULL DROP TABLE #Overall;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Overall
(
    [Database] SYSNAME NOT NULL,
    [Interval Start] DATETIMEOFFSET(7) NOT NULL,
    [Total Executions] BIGINT NOT NULL,
    [Total Duration MS] FLOAT NULL,
    [Total CPU MS] FLOAT NULL,
    [Total Logical IO Reads] FLOAT NULL,
    [Total Memory Grant KB] FLOAT NULL
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
    rsi.start_time AS [Interval Start],
    SUM(rs.count_executions) AS [Total Executions],
    SUM(rs.avg_duration * rs.count_executions) / 1000.0 AS [Total Duration MS],
    SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS [Total CPU MS],
    SUM(rs.avg_logical_io_reads * rs.count_executions) AS [Total Logical IO Reads],
    SUM(rs.avg_query_max_used_memory * rs.count_executions) AS [Total Memory Grant KB]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY rsi.start_time;';

        INSERT #Overall
        EXEC sp_executesql @Sql, N'@LookbackHours INT', @LookbackHours = @LookbackHours;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

;WITH trend AS
(
    SELECT
        o.[Database],
        o.[Interval Start],
        o.[Total Executions],
        o.[Total Duration MS],
        o.[Total CPU MS],
        o.[Total Logical IO Reads],
        o.[Total Memory Grant KB],
        LAG(o.[Total Duration MS]) OVER (PARTITION BY o.[Database] ORDER BY o.[Interval Start]) AS [Prev Total Duration MS]
    FROM #Overall AS o
)
SELECT
    [Database],
    CONVERT(VARCHAR(19), CAST([Interval Start] AS DATETIME2(0)), 120) AS [Interval Start],
    [Total Executions],
    [Total Duration MS],
    [Total CPU MS],
    [Total Logical IO Reads],
    [Total Memory Grant KB],
    CAST(100.0 * ([Total Duration MS] - [Prev Total Duration MS]) / NULLIF([Prev Total Duration MS], 0) AS DECIMAL(10,2)) AS [Duration Change vs Prior Interval %],
    CASE
        WHEN [Prev Total Duration MS] IS NULL THEN N'First interval in range'
        WHEN [Total Duration MS] > [Prev Total Duration MS] * @SpikeMultiplier THEN N'Spike in total duration'
        WHEN [Total Duration MS] < [Prev Total Duration MS] * @DropMultiplier THEN N'Drop in total duration'
        ELSE N'No major change'
    END AS [What It Suggests],
    CASE
        WHEN [Prev Total Duration MS] IS NULL THEN N'Use next interval for trend comparison.'
        WHEN [Total Duration MS] > [Prev Total Duration MS] * @SpikeMultiplier THEN N'Run 04_Top_Resource_Consumers.sql for same window to find responsible query_ids.'
        WHEN [Total Duration MS] < [Prev Total Duration MS] * @DropMultiplier THEN N'Confirm expected workload drop or successful fix/deployment.'
        ELSE N'Continue monitoring trend; no immediate broad regression signal.'
    END AS [What To Check First]
FROM trend
ORDER BY [Database], [Interval Start] DESC;
GO

SELECT
    N'Duration Change vs Prior Interval %' AS [Metric],
    N'Percent change in total duration compared to previous interval for that database.' AS [Meaning],
    N'Large positive values suggest broad workload slowdown, not necessarily one query.' AS [How To Read]
UNION ALL
SELECT
    N'Spike in total duration',
    N'Current interval duration > 150% of previous interval.',
    N'Correlate with 04_Top_Resource_Consumers.sql and 07_Wait_Statistics_By_Category.sql.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
