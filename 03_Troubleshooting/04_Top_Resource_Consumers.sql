/*
    Read-only. Returns top resource-consuming queries.
    Edit variables below, then run the full script.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @LookbackHours INT = 24; -- analysis window size in hours (UTC)
DECLARE @TopN INT = 10; -- number of top queries to return per database
DECLARE @SlowPerExecutionMs FLOAT = 1000.0; -- threshold for slow average duration per execution
DECLARE @HighFrequencyExecutions BIGINT = 1000; -- threshold for high execution count
DECLARE @HighLogicalReadsPerExecution FLOAT = 10000.0; -- threshold for high logical reads per execution
DECLARE @HighCpuPerExecutionMs FLOAT = 500.0; -- threshold for high average CPU per execution
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#TopConsumers', N'U') IS NOT NULL DROP TABLE #TopConsumers;
IF OBJECT_ID(N'tempdb..#Errors', N'U') IS NOT NULL DROP TABLE #Errors;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #TopConsumers
(
    [Database] SYSNAME NOT NULL,
    [Query Id] BIGINT NOT NULL,
    [Total Executions] BIGINT NOT NULL,
    [Total Duration MS] FLOAT NULL,
    [Total CPU MS] FLOAT NULL,
    [Total Logical IO Reads] FLOAT NULL,
    [Total Memory Grant KB] FLOAT NULL,
    [Avg Duration Per Execution MS] FLOAT NULL,
    [Avg CPU Per Execution MS] FLOAT NULL,
    [Avg Logical IO Reads Per Execution] FLOAT NULL,
    [Avg Memory Grant KB Per Execution] FLOAT NULL,
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
;WITH agg AS
(
    SELECT
        q.query_id AS [Query Id],
        SUM(rs.count_executions) AS [Total Executions],
        SUM(rs.avg_duration * rs.count_executions) / 1000.0 AS [Total Duration MS],
        SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS [Total CPU MS],
        SUM(rs.avg_logical_io_reads * rs.count_executions) AS [Total Logical IO Reads],
        SUM(rs.avg_query_max_used_memory * rs.count_executions) AS [Total Memory Grant KB],
        LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N'' ''), CHAR(10), N'' ''), 220) AS [Query Text Sample]
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
    GROUP BY q.query_id, qt.query_sql_text
)
SELECT TOP (@TopN)
    DB_NAME() AS [Database],
    a.[Query Id],
    a.[Total Executions],
    a.[Total Duration MS],
    a.[Total CPU MS],
    a.[Total Logical IO Reads],
    a.[Total Memory Grant KB],
    a.[Total Duration MS] / NULLIF(a.[Total Executions], 0) AS [Avg Duration Per Execution MS],
    a.[Total CPU MS] / NULLIF(a.[Total Executions], 0) AS [Avg CPU Per Execution MS],
    a.[Total Logical IO Reads] / NULLIF(a.[Total Executions], 0) AS [Avg Logical IO Reads Per Execution],
    a.[Total Memory Grant KB] / NULLIF(a.[Total Executions], 0) AS [Avg Memory Grant KB Per Execution],
    a.[Query Text Sample]
FROM agg AS a
ORDER BY [Total Duration MS] DESC;';

        INSERT #TopConsumers
        EXEC sp_executesql @Sql, N'@LookbackHours INT, @TopN INT', @LookbackHours = @LookbackHours, @TopN = @TopN;
    END TRY
    BEGIN CATCH
        INSERT #Errors ([Database], [Error Message])
        VALUES (@CurrentDatabase, ERROR_MESSAGE());
    END CATCH;
END;

SELECT
    [Database],
    [Query Id],
    [Total Executions],
    [Total Duration MS],
    [Total CPU MS],
    [Total Logical IO Reads],
    [Total Memory Grant KB],
    [Avg Duration Per Execution MS],
    [Avg CPU Per Execution MS],
    [Avg Logical IO Reads Per Execution],
    [Avg Memory Grant KB Per Execution],
    CAST(100.0 * [Total Duration MS] / NULLIF(SUM([Total Duration MS]) OVER (PARTITION BY [Database]), 0) AS DECIMAL(6,2)) AS [Pct Of Duration In Returned Top Set],
    CASE
        WHEN [Avg Duration Per Execution MS] >= @SlowPerExecutionMs THEN N'Slow per execution'
        WHEN [Total Executions] >= @HighFrequencyExecutions THEN N'High frequency'
        WHEN [Avg Logical IO Reads Per Execution] >= @HighLogicalReadsPerExecution THEN N'High logical IO per execution'
        WHEN [Avg CPU Per Execution MS] >= @HighCpuPerExecutionMs THEN N'High CPU per execution'
        ELSE N'Mixed workload pressure'
    END AS [Why It Is Top],
    CASE
        WHEN [Avg Duration Per Execution MS] >= @SlowPerExecutionMs THEN N'Check execution plan for scans/lookups/sorts, then index and predicate selectivity.'
        WHEN [Total Executions] >= @HighFrequencyExecutions THEN N'Check app call frequency and repeated statements; reduce chatty patterns.'
        WHEN [Avg Logical IO Reads Per Execution] >= @HighLogicalReadsPerExecution THEN N'Check missing indexes and sargability; reduce rows read.'
        WHEN [Avg CPU Per Execution MS] >= @HighCpuPerExecutionMs THEN N'Check expensive operators, scalar UDFs, and cardinality estimates.'
        ELSE N'Review plan shape and wait profile (07_Wait_Statistics_By_Category.sql).'
    END AS [What To Check First],
    [Query Text Sample]
FROM #TopConsumers
ORDER BY [Total Duration MS] DESC;
GO

SELECT [Database], [Error Message]
FROM #Errors
ORDER BY [Database];
GO
