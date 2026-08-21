/*
    Read-only. Query Store catalog reference.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @TopQueryPlanRows INT = 100; -- max rows for query/plan inventory result set
DECLARE @TopContextRows INT = 100; -- max rows for context settings result set
DECLARE @TopHashRows INT = 50; -- max rows for query hash pressure result set
DECLARE @TopIntervalRows INT = 50; -- max rows for runtime interval result set
DECLARE @HighPlanCountThreshold INT = 5; -- plan-count threshold used in actionable summary
DECLARE @TextSampleLength INT = 220; -- max query text sample length in result rows
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#QueryPlans', N'U') IS NOT NULL DROP TABLE #QueryPlans;
IF OBJECT_ID(N'tempdb..#ContextSettings', N'U') IS NOT NULL DROP TABLE #ContextSettings;
IF OBJECT_ID(N'tempdb..#Hints', N'U') IS NOT NULL DROP TABLE #Hints;
IF OBJECT_ID(N'tempdb..#HashPressure', N'U') IS NOT NULL DROP TABLE #HashPressure;
IF OBJECT_ID(N'tempdb..#Intervals', N'U') IS NOT NULL DROP TABLE #Intervals;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #QueryPlans
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Parameterization] VARCHAR(60) NULL,
    [Forced] BIT NULL,
    [Last Compile Start] DATETIMEOFFSET(7) NULL,
    [Query Text Sample] VARCHAR(220) NULL
);

CREATE TABLE #ContextSettings
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Context Settings Id] BIGINT NULL,
    [Set Options Bitmask] BIGINT NULL,
    [Language Id] SMALLINT NULL,
    [Date Format] NCHAR(3) NULL
);

CREATE TABLE #Hints
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NULL,
    [Hint Text] VARCHAR(MAX) NULL,
    [Last Failure Reason] VARCHAR(120) NULL,
    [Failure Count] BIGINT NULL
);

CREATE TABLE #HashPressure
(
    [Database] SYSNAME NOT NULL,
    [Query Hash] BINARY(8) NOT NULL,
    [Plan Count] BIGINT NOT NULL,
    [Distinct Query Texts] BIGINT NOT NULL
);

CREATE TABLE #Intervals
(
    [Database] SYSNAME NOT NULL,
    [Interval Id] BIGINT NOT NULL,
    [Interval Start] DATETIMEOFFSET(7) NOT NULL,
    [Interval End] DATETIMEOFFSET(7) NOT NULL
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
SELECT TOP (@TopQueryPlanRows)
    DB_NAME() AS [Database],
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    q.query_parameterization_type_desc AS [Parameterization],
    p.is_forced_plan AS [Forced],
    p.last_compile_start_time AS [Last Compile Start],
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), @TextSampleLength) AS [Query Text Sample]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
ORDER BY p.last_compile_start_time DESC;';
        INSERT #QueryPlans
        EXEC sp_executesql @Sql, N'@TopQueryPlanRows INT, @TextSampleLength INT', @TopQueryPlanRows = @TopQueryPlanRows, @TextSampleLength = @TextSampleLength;

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT TOP (@TopContextRows)
    DB_NAME() AS [Database],
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    cs.context_settings_id AS [Context Settings Id],
    cs.set_options AS [Set Options Bitmask],
    cs.language_id AS [Language Id],
    cs.date_format AS [Date Format]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_context_settings AS cs ON q.context_settings_id = cs.context_settings_id;';
        INSERT #ContextSettings
        EXEC sp_executesql @Sql, N'@TopContextRows INT', @TopContextRows = @TopContextRows;

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
IF OBJECT_ID(N''sys.query_store_query_hints'', N''V'') IS NOT NULL
BEGIN
    SELECT
        DB_NAME() AS [Database],
        query_id AS [Query Id],
        query_hint_text AS [Hint Text],
        last_query_hint_failure_reason_desc AS [Last Failure Reason],
        query_hint_failure_count AS [Failure Count]
    FROM sys.query_store_query_hints;
END;';
        INSERT #Hints
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT TOP (@TopHashRows)
    DB_NAME() AS [Database],
    q.query_hash AS [Query Hash],
    COUNT(p.plan_id) AS [Plan Count],
    COUNT(DISTINCT qt.query_text_id) AS [Distinct Query Texts]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
GROUP BY q.query_hash
ORDER BY [Plan Count] DESC;';
        INSERT #HashPressure
        EXEC sp_executesql @Sql, N'@TopHashRows INT', @TopHashRows = @TopHashRows;

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT TOP (@TopIntervalRows)
    DB_NAME() AS [Database],
    runtime_stats_interval_id AS [Interval Id],
    start_time AS [Interval Start],
    end_time AS [Interval End]
FROM sys.query_store_runtime_stats_interval
ORDER BY start_time DESC;';
        INSERT #Intervals
        EXEC sp_executesql @Sql, N'@TopIntervalRows INT', @TopIntervalRows = @TopIntervalRows;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

-- 1) Query + plan inventory
SELECT
    [Database],
    [Query Id],
    [Plan Id],
    [Parameterization],
    [Forced],
    CONVERT(VARCHAR(19), CAST([Last Compile Start] AS DATETIME2(0)), 120) AS [Last Compile Start],
    [Query Text Sample]
FROM #QueryPlans
ORDER BY [Database], [Last Compile Start] DESC;


-- 2) Context settings
SELECT
    [Database],
    [Query Id],
    [Plan Id],
    [Context Settings Id],
    [Set Options Bitmask],
    [Language Id],
    [Date Format]
FROM #ContextSettings
ORDER BY [Database], [Context Settings Id];


-- 3) Query Store hints (if supported)
SELECT
    [Database],
    [Query Id],
    [Hint Text],
    [Last Failure Reason],
    [Failure Count]
FROM #Hints
ORDER BY [Database], [Failure Count] DESC;


-- 4) Plan count pressure by query hash
SELECT
    [Database],
    [Query Hash],
    [Plan Count],
    [Distinct Query Texts]
FROM #HashPressure
ORDER BY [Database], [Plan Count] DESC;


-- 5) Runtime stats intervals (latest)
SELECT
    [Database],
    [Interval Id],
    CONVERT(VARCHAR(19), CAST([Interval Start] AS DATETIME2(0)), 120) AS [Interval Start],
    CONVERT(VARCHAR(19), CAST([Interval End] AS DATETIME2(0)), 120) AS [Interval End]
FROM #Intervals
ORDER BY [Database], [Interval Start] DESC;


-- 6) What to look for (actionable summary)
SELECT
    s.[Database],
    N'Queries with multiple plans' AS [Check],
    CAST(s.[Queries With Multiple Plans] AS NVARCHAR(30)) AS [Current Value],
    N'Can indicate plan instability or context differences.' AS [What It Means],
    N'Review those query_ids in 10_Track_A_Query.sql and compare plans.' AS [What To Check First]
FROM
(
    SELECT
        qp.[Database],
        COUNT(*) AS [Queries With Multiple Plans]
    FROM
    (
        SELECT
            [Database],
            [Query Id]
        FROM #QueryPlans
        GROUP BY [Database], [Query Id]
        HAVING COUNT(DISTINCT [Plan Id]) > 1
    ) AS qp
    GROUP BY qp.[Database]
) AS s
UNION ALL
SELECT
    hp.[Database],
    N'High plan count query hashes' AS [Check],
    CAST(COUNT(*) AS NVARCHAR(30)) AS [Current Value],
    N'Can indicate ad hoc / non-parameterized plan cache pressure in Query Store.' AS [What It Means],
    N'Inspect top hashes above and parameterize literals-heavy statements.' AS [What To Check First]
FROM #HashPressure AS hp
WHERE hp.[Plan Count] >= @HighPlanCountThreshold
GROUP BY hp.[Database]
UNION ALL
SELECT
    i.[Database],
    N'Observed interval width (minutes)' AS [Check],
    CAST(DATEDIFF(MINUTE, i.[Interval Start], i.[Interval End]) AS NVARCHAR(30)) AS [Current Value],
    N'Controls how quickly regressions can be detected in interval-based reports.' AS [What It Means],
    N'If too coarse/fine, adjust INTERVAL_LENGTH_MINUTES in 01_Setup/03_Configure.sql.' AS [What To Check First]
FROM
(
    SELECT
        [Database],
        MIN([Interval Start]) AS [Interval Start],
        MIN([Interval End]) AS [Interval End]
    FROM #Intervals
    GROUP BY [Database]
) AS i
ORDER BY [Database], [Check];
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
