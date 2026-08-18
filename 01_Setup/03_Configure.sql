/*
    Sets Query Store thresholds for @DatabaseName.
    Changes the settings to what is below.

    OPERATION_MODE          READ_WRITE   Actively records and is readable
    CLEANUP_POLICY           90 days     Purges data older than this
    DATA_FLUSH_INTERVAL      60 sec      Writes to disk this often
    MAX_STORAGE_SIZE         1024 MB     Storage cap
    INTERVAL_LENGTH          15 min      Bucket size for stats
    SIZE_BASED_CLEANUP_MODE  AUTO        Purges old data instead of going read-only near the cap
    QUERY_CAPTURE_MODE       ALL         Captures every query, not just frequent ones
    MAX_PLANS_PER_QUERY      200         Plans kept per query
    WAIT_STATS_CAPTURE_MODE  ON          Also records wait stats per query

    INTERVAL_LENGTH sets how long a Query Store stats bucket stays open.
    04_Find_And_Fix_Regressions/02_Find_Regressed_Queries.sql waits past
    one full interval so its "before" and "after" plans land in separate
    buckets, so its WAITFOR DELAY has to stay longer than this value.
*/

USE master;
GO

DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022';
DECLARE @Sql NVARCHAR(MAX);

-- Sets the thresholds
SET @Sql = N'
ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 15,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    QUERY_CAPTURE_MODE = ALL,
    MAX_PLANS_PER_QUERY = 200,
    WAIT_STATS_CAPTURE_MODE = ON
);';
EXEC (@Sql);

-- Confirms the thresholds actually applied
SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';
SELECT
    DB_NAME() AS [Database],
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    interval_length_minutes AS [Interval Minutes],
    flush_interval_seconds AS [Flush Interval Seconds],
    query_capture_mode_desc AS [Query Capture Mode],
    wait_stats_capture_mode_desc AS [Wait Stats Capture Mode]
FROM sys.database_query_store_options;';
EXEC (@Sql);
GO
