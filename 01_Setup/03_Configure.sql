/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS).
    Sets Query Store thresholds, then confirms they applied.

    Options:
      - Set @ApplyToAllDatabases = 0 to target only @DatabaseName
      - Set @ApplyToAllDatabases = 1 to target all eligible user databases

    Setting                  Sets to      What it controls (other values)
    OPERATION_MODE           READ_WRITE   Actively capturing vs. frozen read-only (READ_ONLY)
    CLEANUP_POLICY            90 days     Days of history kept before purging (any number of days)
    DATA_FLUSH_INTERVAL       60 sec      How often data is written to disk (any number of seconds)
    MAX_STORAGE_SIZE          1024 MB     Storage quota before capture stops or cleans up (any MB value)
    INTERVAL_LENGTH           15 min      Length of each stats time bucket (1, 5, 10, 15, 30, 60, or 1440)
    SIZE_BASED_CLEANUP_MODE   AUTO        Auto-purge old data near the cap, vs. going READ_ONLY (OFF)
    QUERY_CAPTURE_MODE        AUTO        Skips one-off, low-cost queries (ALL, NONE, or CUSTOM on 2019+)
    MAX_PLANS_PER_QUERY       200         Plans kept per query before the oldest is evicted (0 = unlimited)
    WAIT_STATS_CAPTURE_MODE   ON          Also records why a query waited, not just how long (OFF)

    INTERVAL_LENGTH sets how long a Query Store stats bucket stays open.
    04_Regressions_And_Forcing/02_Find_Regressed_Queries.sql waits past
    one full interval so its "before" and "after" plans land in separate
    buckets, so its WAITFOR DELAY has to stay longer than this value.
*/

USE master;
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = one DB, 1 = all eligible user DBs
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- used when @ApplyToAllDatabases = 0
DECLARE @Sql NVARCHAR(MAX);
DECLARE @CurrentDatabase SYSNAME;

IF OBJECT_ID(N'tempdb..#Results', N'U') IS NOT NULL
    DROP TABLE #Results;

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL
    DROP TABLE #Targets;

CREATE TABLE #Targets
(
    DatabaseName SYSNAME NOT NULL PRIMARY KEY
);

CREATE TABLE #Results
(
    [Database] SYSNAME NOT NULL,
    [Actual State] NVARCHAR(60) NULL,
    [Desired State] NVARCHAR(60) NULL,
    [Current Storage MB] BIGINT NULL,
    [Max Storage MB] BIGINT NULL,
    [Interval Minutes] BIGINT NULL,
    [Size Based Cleanup Mode] NVARCHAR(60) NULL,
    [Flush Interval Seconds] BIGINT NULL,
    [Query Capture Mode] NVARCHAR(60) NULL,
    [Wait Stats Capture Mode] NVARCHAR(60) NULL,
    [Result] NVARCHAR(20) NOT NULL,
    [Error Message] NVARCHAR(4000) NULL
);

IF @ApplyToAllDatabases = 1
BEGIN
    INSERT #Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.is_read_only = 0
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
      AND d.is_read_only = 0
      AND d.source_database_id IS NULL;
END;

IF NOT EXISTS (SELECT 1 FROM #Targets)
    THROW 50002, 'No eligible databases found to configure Query Store.', 1;

WHILE EXISTS (SELECT 1 FROM #Targets)
BEGIN
    SELECT TOP (1) @CurrentDatabase = t.DatabaseName
    FROM #Targets AS t
    ORDER BY t.DatabaseName;

    DELETE FROM #Targets
    WHERE DatabaseName = @CurrentDatabase;

    BEGIN TRY
        -- Sets the thresholds
        SET @Sql = N'
ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 15,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    WAIT_STATS_CAPTURE_MODE = ON
);';
        EXEC (@Sql);

        -- Confirms the thresholds actually applied
        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    interval_length_minutes AS [Interval Minutes],
    size_based_cleanup_mode_desc AS [Size Based Cleanup Mode],
    flush_interval_seconds AS [Flush Interval Seconds],
    query_capture_mode_desc AS [Query Capture Mode],
    wait_stats_capture_mode_desc AS [Wait Stats Capture Mode],
    CAST(N''Success'' AS NVARCHAR(20)) AS [Result],
    CAST(NULL AS NVARCHAR(4000)) AS [Error Message]
FROM sys.database_query_store_options;';

        INSERT #Results
        EXEC (@Sql);
    END TRY
    BEGIN CATCH
        INSERT #Results
        (
            [Database],
            [Actual State],
            [Desired State],
            [Current Storage MB],
            [Max Storage MB],
            [Interval Minutes],
            [Size Based Cleanup Mode],
            [Flush Interval Seconds],
            [Query Capture Mode],
            [Wait Stats Capture Mode],
            [Result],
            [Error Message]
        )
        VALUES
        (
            @CurrentDatabase,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            N'Failed',
            ERROR_MESSAGE()
        );
    END CATCH;
END;

SELECT
    [Database],
    [Actual State],
    [Desired State],
    [Current Storage MB],
    [Max Storage MB],
    [Interval Minutes],
    [Size Based Cleanup Mode],
    [Flush Interval Seconds],
    [Query Capture Mode],
    [Wait Stats Capture Mode],
    [Result],
    [Error Message]
FROM #Results
ORDER BY [Database];
GO
