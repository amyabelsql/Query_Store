/*
    Read-only. Shows forced plan health and troubleshooting details.
    Edit variables below, then run the full script.

    Regression lab scripts are in 04_Regression_Testing:
      01_Phase1_Capture_Before.sql
      02_Phase2_Create_Regression.sql
      03_Phase3_Force_And_Validate.sql
      04_Phase4_Force_Plan.sql
      05_Phase5_Validate_And_Cleanup.sql
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @TopN INT = 200; -- max forced-plan rows to return per database
DECLARE @TextSampleLength INT = 220; -- max query text sample length in result rows
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#ForcedPlans', N'U') IS NOT NULL DROP TABLE #ForcedPlans;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #ForcedPlans
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Plan Id] BIGINT NOT NULL,
    [Forced] BIT NOT NULL,
    [Last Execution] DATETIMEOFFSET(7) NULL,
    [Avg Duration MS] FLOAT NULL,
    [Avg Logical IO Reads] FLOAT NULL,
    [Force Failure Count] BIGINT NULL,
    [Last Force Failure Reason] VARCHAR(120) NULL,
    [Force Health] VARCHAR(30) NOT NULL,
    [Who Forced] VARCHAR(80) NOT NULL,
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
    p.is_forced_plan AS [Forced],
    p.last_execution_time AS [Last Execution],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads],
    p.force_failure_count AS [Force Failure Count],
    p.last_force_failure_reason_desc AS [Last Force Failure Reason],
    CASE
        WHEN p.force_failure_count > 0 THEN N''Forcing failures detected''
        ELSE N''Forced and healthy''
    END AS [Force Health],
    N''Not available in Query Store metadata'' AS [Who Forced],
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), @TextSampleLength) AS [Query Text Sample]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
LEFT JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE p.is_forced_plan = 1;';

        INSERT #ForcedPlans
        EXEC sp_executesql @Sql, N'@TopN INT, @TextSampleLength INT', @TopN = @TopN, @TextSampleLength = @TextSampleLength;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

-- 1) Forced plan details
SELECT
    [Database],
    [Query Id],
    [Plan Id],
    CONVERT(VARCHAR(19), CAST([Last Execution] AS DATETIME2(0)), 120) AS [Last Execution],
    [Avg Duration MS],
    [Avg Logical IO Reads],
    [Force Failure Count],
    [Last Force Failure Reason],
    [Force Health],
    [Who Forced],
    CASE
        WHEN [Force Failure Count] > 0 THEN N'Validate required indexes/schema still exist and compare current waits.'
        ELSE N'Continue monitoring; verify forced plan is still best for current workload.'
    END AS [What To Check First],
    [Query Text Sample]
FROM #ForcedPlans
ORDER BY [Database], [Force Failure Count] DESC, [Last Execution] DESC;
GO

-- 2) Forced plan summary by database
SELECT
    [Database],
    COUNT(*) AS [Forced Plan Count],
    SUM(CASE WHEN [Force Failure Count] > 0 THEN 1 ELSE 0 END) AS [Forced Plans With Failures],
    CAST(100.0 * SUM(CASE WHEN [Force Failure Count] > 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS [Pct Forced Plans With Failures]
FROM #ForcedPlans
GROUP BY [Database]
ORDER BY [Database];
GO

-- 3) Quick legend
SELECT
    N'Force Failure Count' AS [Metric],
    N'Number of times SQL Server could not apply the forced plan.' AS [Meaning],
    N'If > 0, forcing is not reliably effective; investigate reason and dependencies.' AS [How To Read]
UNION ALL
SELECT
    N'Who Forced',
    N'Not exposed by Query Store metadata.',
    N'Use SQL Audit or Extended Events to capture actor attribution going forward.';
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
