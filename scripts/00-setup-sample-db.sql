[ew3]/*
    00 - Setup
    Resets Query Store on AdventureWorks2022 and configures it for the
    workshop. Safe to re-run at any point to get back to a clean slate.

    NOTE: INTERVAL_LENGTH_MINUTES and DATA_FLUSH_INTERVAL_SECONDS are set
    much lower here than Microsoft's production defaults (60 min / 900 sec)
    purely so the labs produce visible results in minutes instead of hours.
    See docs/02-enabling-and-configuring.md for real-world defaults, and
    scripts/08-maintenance-cleanup.sql resets these at the end.
*/

USE master;
GO

IF DB_ID(N'AdventureWorks2022') IS NULL
BEGIN
    RAISERROR(N'AdventureWorks2022 not found. Install it first: https://learn.microsoft.com/sql/samples/adventureworks-install-configure', 16, 1);
END
GO

ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
GO

USE [AdventureWorks2022];
GO

-- Wipe any prior Query Store history so the workshop starts clean.
ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE CLEAR;
GO

ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE
(
    OPERATION_MODE           = READ_WRITE,
    CLEANUP_POLICY           = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 60,     -- workshop only; production default is 900
    MAX_STORAGE_SIZE_MB      = 1024,
    INTERVAL_LENGTH_MINUTES  = 1,         -- workshop only; production default is 60
    SIZE_BASED_CLEANUP_MODE  = AUTO,
    QUERY_CAPTURE_MODE       = ALL,       -- workshop only, so nothing gets filtered; use AUTO in production
    MAX_PLANS_PER_QUERY      = 200,
    WAIT_STATS_CAPTURE_MODE  = ON
);
GO

-- Confirm it's on and configured as expected.
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb,
       max_storage_size_mb, interval_length_minutes, flush_interval_seconds,
       query_capture_mode_desc
FROM sys.database_query_store_options;
GO

