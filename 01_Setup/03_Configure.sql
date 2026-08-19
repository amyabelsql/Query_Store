/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS).
    Sets Query Store thresholds for @DatabaseName to the values below,
    then confirms they applied.

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
    QUERY_CAPTURE_MODE = AUTO,
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
    size_based_cleanup_mode_desc AS [Size Based Cleanup Mode],
    flush_interval_seconds AS [Flush Interval Seconds],
    query_capture_mode_desc AS [Query Capture Mode],
    wait_stats_capture_mode_desc AS [Wait Stats Capture Mode]
FROM sys.database_query_store_options;';
EXEC (@Sql);
GO
