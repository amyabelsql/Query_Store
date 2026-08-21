/*
    Read-only. Core Query Store health check.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @StorageWarningPct DECIMAL(5,2) = 75.0; -- warning threshold for Query Store storage usage percent
DECLARE @StorageCriticalPct DECIMAL(5,2) = 90.0; -- critical threshold for Query Store storage usage percent
DECLARE @AdHocWarningPct DECIMAL(5,2) = 80.0; -- warning threshold for unique query hash percent
DECLARE @AdHocCriticalPct DECIMAL(5,2) = 95.0; -- critical threshold for unique query hash percent
DECLARE @TopProblemQueries INT = 50; -- number of non-regular query rows to return
DECLARE @TopProblemIntervals INT = 50; -- number of recent interval rows to return
DECLARE @QueryTextSampleLength INT = 180; -- max query text sample length in result rows
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL
    DROP TABLE #Targets;

IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL
    DROP TABLE #Errors;

IF OBJECT_ID(N'tempdb..#State', N'U') IS NOT NULL
    DROP TABLE #State;

IF OBJECT_ID(N'tempdb..#ReadonlyReason', N'U') IS NOT NULL
    DROP TABLE #ReadonlyReason;

IF OBJECT_ID(N'tempdb..#StorageHeadroom', N'U') IS NOT NULL
    DROP TABLE #StorageHeadroom;

IF OBJECT_ID(N'tempdb..#CapturePolicy', N'U') IS NOT NULL
    DROP TABLE #CapturePolicy;

IF OBJECT_ID(N'tempdb..#AdHocPressure', N'U') IS NOT NULL
    DROP TABLE #AdHocPressure;

IF OBJECT_ID(N'tempdb..#ForcedPlanHealth', N'U') IS NOT NULL
    DROP TABLE #ForcedPlanHealth;

IF OBJECT_ID(N'tempdb..#ExecCounts', N'U') IS NOT NULL
    DROP TABLE #ExecCounts;

IF OBJECT_ID(N'tempdb..#AbortedException', N'U') IS NOT NULL
    DROP TABLE #AbortedException;

IF OBJECT_ID(N'tempdb..#Findings', N'U') IS NOT NULL
    DROP TABLE #Findings;

CREATE TABLE #Targets
(
    DatabaseName SYSNAME NOT NULL PRIMARY KEY
);

CREATE TABLE #Errors
(
    [Database] SYSNAME NOT NULL,
    [Error Message] VARCHAR(4000) NOT NULL
);

CREATE TABLE #State
(
    [Database] SYSNAME NOT NULL,
    [Actual State] VARCHAR(60) NULL,
    [Desired State] VARCHAR(60) NULL,
    [Current Storage MB] BIGINT NULL,
    [Max Storage MB] BIGINT NULL,
    [Readonly Reason] INT NULL,
    [Query Capture Mode] VARCHAR(60) NULL,
    [Size Based Cleanup Mode] VARCHAR(60) NULL
);

CREATE TABLE #ReadonlyReason
(
    [Database] SYSNAME NOT NULL,
    [Readonly Reason] INT NULL,
    [Readonly Reason Decoded] VARCHAR(4000) NULL
);

CREATE TABLE #StorageHeadroom
(
    [Database] SYSNAME NOT NULL,
    [Current Storage MB] BIGINT NULL,
    [Max Storage MB] BIGINT NULL,
    [Pct Of Quota Used] DECIMAL(5, 2) NULL
);

CREATE TABLE #CapturePolicy
(
    [Database] SYSNAME NOT NULL,
    [Query Capture Mode] VARCHAR(60) NULL,
    [Capture Policy Execution Count] BIGINT NULL,
    [Capture Policy Compile CPU MS] BIGINT NULL,
    [Capture Policy Execution CPU MS] BIGINT NULL,
    [Capture Policy Stale Threshold Hours] BIGINT NULL
);

CREATE TABLE #AdHocPressure
(
    [Database] SYSNAME NOT NULL,
    [Total Queries] BIGINT NOT NULL,
    [Distinct Query Hashes] BIGINT NOT NULL,
    [Pct Unique] DECIMAL(5, 2) NULL
);

CREATE TABLE #ForcedPlanHealth
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Containing Object Id] BIGINT NULL,
    [Force Failure Count] BIGINT NULL,
    [Last Force Failure Reason] VARCHAR(120) NULL
);

CREATE TABLE #ExecCounts
(
    [Database] SYSNAME NOT NULL,
    [Query Text] VARCHAR(MAX) NULL,
    [Query Id] BIGINT NOT NULL,
    [Execution Type] VARCHAR(60) NOT NULL,
    [Executions] BIGINT NOT NULL
);

CREATE TABLE #AbortedException
(
    [Database] SYSNAME NOT NULL,
    [Query Text] VARCHAR(MAX) NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Execution Type] VARCHAR(60) NOT NULL,
    [Interval Start] DATETIMEOFFSET(7) NOT NULL,
    [Executions] BIGINT NOT NULL,
    [Avg Duration MS] FLOAT NULL
);

CREATE TABLE #Findings
(
    [Database] SYSNAME NOT NULL,
    [Severity] VARCHAR(10) NOT NULL,
    [Check] VARCHAR(80) NOT NULL,
    [Metric] VARCHAR(80) NOT NULL,
    [Current Value] VARCHAR(200) NULL,
    [Why It Matters] VARCHAR(300) NOT NULL,
    [Action] VARCHAR(300) NOT NULL
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
    THROW 50002, 'No eligible databases found to run health checks.', 1;

WHILE EXISTS (SELECT 1 FROM #Targets)
BEGIN
    SELECT TOP (1) @CurrentDatabase = t.DatabaseName
    FROM #Targets AS t
    ORDER BY t.DatabaseName;

    DELETE FROM #Targets
    WHERE DatabaseName = @CurrentDatabase;

    BEGIN TRY
        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    readonly_reason AS [Readonly Reason],
    query_capture_mode_desc AS [Query Capture Mode],
    size_based_cleanup_mode_desc AS [Size Based Cleanup Mode]
FROM sys.database_query_store_options;';
        INSERT #State
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    readonly_reason AS [Readonly Reason],
    CASE WHEN readonly_reason & 1      = 1      THEN ''Database is in read-only mode; '' ELSE '''' END +
    CASE WHEN readonly_reason & 2      = 2      THEN ''Database is in single-user mode; '' ELSE '''' END +
    CASE WHEN readonly_reason & 4      = 4      THEN ''Database is in emergency mode; '' ELSE '''' END +
    CASE WHEN readonly_reason & 8      = 8      THEN ''Database is a secondary replica; '' ELSE '''' END +
    CASE WHEN readonly_reason & 65536  = 65536  THEN ''Number of distinct statement types has exceeded the in-memory limit; '' ELSE '''' END +
    CASE WHEN readonly_reason & 131072 = 131072 THEN ''Storage size has exceeded max_storage_size_mb; '' ELSE '''' END +
    CASE WHEN readonly_reason & 262144 = 262144 THEN ''Number of statements has exceeded the in-memory limit; '' ELSE '''' END +
    CASE WHEN readonly_reason & 524288 = 524288 THEN ''Number of plans has exceeded the in-memory limit; '' ELSE '''' END +
    CASE WHEN readonly_reason = 0 THEN ''Not read-only'' ELSE '''' END AS [Readonly Reason Decoded]
FROM sys.database_query_store_options;';
        INSERT #ReadonlyReason
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    CAST(100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5, 2)) AS [Pct Of Quota Used]
FROM sys.database_query_store_options;';
        INSERT #StorageHeadroom
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    query_capture_mode_desc AS [Query Capture Mode],
    capture_policy_execution_count AS [Capture Policy Execution Count],
    capture_policy_total_compile_cpu_time_ms AS [Capture Policy Compile CPU MS],
    capture_policy_total_execution_cpu_time_ms AS [Capture Policy Execution CPU MS],
    capture_policy_stale_threshold_hours AS [Capture Policy Stale Threshold Hours]
FROM sys.database_query_store_options;';
        INSERT #CapturePolicy
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    COUNT(*) AS [Total Queries],
    COUNT(DISTINCT query_hash) AS [Distinct Query Hashes],
    CAST(100.0 * COUNT(DISTINCT query_hash) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS [Pct Unique]
FROM sys.query_store_query;';
        INSERT #AdHocPressure
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    q.object_id AS [Containing Object Id],
    p.force_failure_count AS [Force Failure Count],
    p.last_force_failure_reason_desc AS [Last Force Failure Reason]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
WHERE p.is_forced_plan = 1;';
        INSERT #ForcedPlanHealth
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.execution_type_desc AS [Execution Type],
    SUM(rs.count_executions) AS [Executions]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
GROUP BY qt.query_sql_text, q.query_id, rs.execution_type_desc;';
        INSERT #ExecCounts
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    rs.execution_type_desc AS [Execution Type],
    rsi.start_time AS [Interval Start],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rs.execution_type_desc <> ''Regular'';';
        INSERT #AbortedException
        EXEC (@Sql);
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

-- Build actionable findings (narrow columns, more rows)
INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    s.[Database],
    CASE WHEN s.[Actual State] = N'ERROR' THEN N'Critical' ELSE N'Warning' END,
    N'State Alignment',
    N'actual_state_desc vs desired_state_desc',
    CONCAT(s.[Actual State], N' / ', s.[Desired State]),
    N'Query Store is not in the expected mode.',
    N'If ERROR, run 11_Recover_From_Error_State.sql. If READ_ONLY, check storage and readonly reason.'
FROM #State AS s
WHERE s.[Actual State] = N'ERROR'
   OR s.[Actual State] <> s.[Desired State];

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    h.[Database],
    CASE
        WHEN h.[Pct Of Quota Used] >= @StorageCriticalPct THEN N'Critical'
        WHEN h.[Pct Of Quota Used] >= @StorageWarningPct THEN N'Warning'
        ELSE N'Info'
    END,
    N'Storage Headroom',
    N'Storage Used % of Query Store Max',
    CONCAT(CAST(h.[Pct Of Quota Used] AS VARCHAR(20)), N'%'),
    N'High usage can force READ_ONLY or aggressive cleanup.',
    N'Increase MAX_STORAGE_SIZE_MB, lower retention days, or reduce ad hoc query churn.'
FROM #StorageHeadroom AS h
WHERE h.[Pct Of Quota Used] >= @StorageWarningPct;

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    rr.[Database],
    N'Warning',
    N'Readonly Reason',
    N'readonly_reason',
    CAST(rr.[Readonly Reason] AS VARCHAR(20)),
    N'Non-zero means Query Store is blocked from writing.',
    rr.[Readonly Reason Decoded]
FROM #ReadonlyReason AS rr
WHERE rr.[Readonly Reason] <> 0;

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    a.[Database],
    CASE
        WHEN a.[Pct Unique] >= @AdHocCriticalPct THEN N'Critical'
        WHEN a.[Pct Unique] >= @AdHocWarningPct THEN N'Warning'
        ELSE N'Info'
    END,
    N'Ad Hoc Pressure',
    N'Pct Unique Query Hashes',
    CONCAT(CAST(a.[Pct Unique] AS VARCHAR(20)), N'% (', CAST(a.[Distinct Query Hashes] AS VARCHAR(20)), N' of ', CAST(a.[Total Queries] AS VARCHAR(20)), N')'),
    N'High uniqueness usually means ad hoc SQL and faster Query Store growth.',
    N'Parameterize queries and review literals-heavy patterns.'
FROM #AdHocPressure AS a
WHERE a.[Pct Unique] >= @AdHocWarningPct;

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    f.[Database],
    N'Warning',
    N'Forced Plan Health',
    N'Failed Force Attempts',
    CAST(SUM(COALESCE(f.[Force Failure Count], 0)) AS VARCHAR(20)),
    N'Forced plan failed and optimizer fallback occurred.',
    N'Review [Last Force Failure Reason], then validate indexes/schema for forced plans.'
FROM #ForcedPlanHealth AS f
GROUP BY f.[Database]
HAVING SUM(COALESCE(f.[Force Failure Count], 0)) > 0;

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    x.[Database],
    N'Warning',
    N'Aborted Activity',
    N'Aborted Executions',
    CAST(x.[AbortedExecutions] AS VARCHAR(20)),
    N'Aborted means execution was interrupted (client timeout/cancel, attention, or KILL).',
    N'Review top aborted queries and check app timeout settings, blocking, and long-running plans.'
FROM
(
    SELECT
        e.[Database],
        SUM(CASE WHEN e.[Execution Type] = N'Aborted' THEN e.[Executions] ELSE 0 END) AS [AbortedExecutions]
    FROM #ExecCounts AS e
    GROUP BY e.[Database]
) AS x
WHERE x.[AbortedExecutions] > 0;

INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    x.[Database],
    N'Warning',
    N'Exception Activity',
    N'Exception Executions',
    CAST(x.[ExceptionExecutions] AS VARCHAR(20)),
    N'Exception means the statement errored during execution (runtime SQL error).',
    N'Review top exception queries and map query_id to the SQL error from app logs or Extended Events.'
FROM
(
    SELECT
        e.[Database],
        SUM(CASE WHEN e.[Execution Type] = N'Exception' THEN e.[Executions] ELSE 0 END) AS [ExceptionExecutions]
    FROM #ExecCounts AS e
    GROUP BY e.[Database]
) AS x
WHERE x.[ExceptionExecutions] > 0;

-- If a database has no warnings/critical findings, add one concise info row.
INSERT #Findings ([Database], [Severity], [Check], [Metric], [Current Value], [Why It Matters], [Action])
SELECT
    s.[Database],
    N'Info',
    N'No Immediate Issues',
    N'Health Summary',
    N'No warning thresholds hit',
    N'No obvious Query Store risks from this check run.',
    N'Continue monitoring storage growth and aborted/exception activity.'
FROM #State AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM #Findings AS f
    WHERE f.[Database] = s.[Database]
      AND f.[Severity] IN (N'Critical', N'Warning')
);

-- 1) Quick database summary
SELECT
    s.[Database],
    CASE
        WHEN s.[Actual State] = s.[Desired State] THEN N'OK'
        ELSE N'Mismatch'
    END AS [State Check],
    s.[Actual State] AS [Current Query Store State],
    CAST(h.[Pct Of Quota Used] AS DECIMAL(5, 2)) AS [Storage Used % of Query Store Max],
    a.[Pct Unique]
FROM #State AS s
LEFT JOIN #StorageHeadroom AS h ON s.[Database] = h.[Database]
LEFT JOIN #AdHocPressure AS a ON s.[Database] = a.[Database]
ORDER BY s.[Database];


-- 2) Actionable findings (start here)
SELECT
    [Database],
    [Severity],
    [Check],
    [Metric],
    [Current Value],
    [Why It Matters],
    [Action]
FROM #Findings
ORDER BY
    [Database],
    CASE [Severity] WHEN N'Critical' THEN 1 WHEN N'Warning' THEN 2 ELSE 3 END,
    [Check];


-- 3) Top problem queries (aborted/exception only)
SELECT TOP (@TopProblemQueries)
    e.[Database],
    e.[Execution Type],
    CASE
        WHEN e.[Execution Type] = N'Aborted' THEN N'Interrupted before completion (timeout/cancel/KILL)'
        WHEN e.[Execution Type] = N'Exception' THEN N'Failed with runtime SQL error'
        ELSE N''
    END AS [What It Means],
    e.[Query Id],
    e.[Executions],
    LEFT(REPLACE(REPLACE(e.[Query Text], CHAR(13), N' '), CHAR(10), N' '), @QueryTextSampleLength) AS [Query Text Sample]
FROM #ExecCounts AS e
WHERE e.[Execution Type] <> N'Regular'
ORDER BY e.[Executions] DESC;


-- 4) Recent aborted/exception intervals
SELECT TOP (@TopProblemIntervals)
    a.[Database],
    a.[Execution Type],
    CONVERT(VARCHAR(19), CAST(a.[Interval Start] AS DATETIME2(0)), 120) AS [Interval Start],
    a.[Executions],
    a.[Avg Duration MS],
    a.[Query Id]
FROM #AbortedException AS a
ORDER BY a.[Interval Start] DESC;


-- Any database-level errors captured during the run
SELECT
    [Database],
    [Error Message]
FROM #Errors
ORDER BY [Database];
GO
