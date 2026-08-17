/*
    02 - Reference: recommended production configuration

    READ ONLY — do not run this against the workshop database. It sets
    QUERY_CAPTURE_MODE = AUTO and the full-length intervals, which would
    overwrite the fast settings 01-setup-sample-db.sql just applied and
    stall the rest of the labs. This file exists so you can see and copy
    the best-practice settings for a real database. See README.md in
    this folder for the full explanation.
*/

USE [AdventureWorks2022];
GO

-- Enable Query Store (no-op if already on)
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
GO

-- Recommended production settings (SQL Server 2022 defaults, spelled out
-- explicitly so they're easy to see and adjust)
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE
(
    OPERATION_MODE              = READ_WRITE,
    CLEANUP_POLICY               = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB         = 1024,
    INTERVAL_LENGTH_MINUTES     = 60,
    SIZE_BASED_CLEANUP_MODE     = AUTO,
    QUERY_CAPTURE_MODE          = AUTO,
    MAX_PLANS_PER_QUERY         = 200,
    WAIT_STATS_CAPTURE_MODE     = ON
);
GO

-- Alternative: CUSTOM capture policy for a very large / ad hoc-heavy database.
-- Only one of QUERY_CAPTURE_MODE = AUTO (above) or CUSTOM (below) applies at a time.
/*
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE
(
    QUERY_CAPTURE_MODE = CUSTOM,
    QUERY_CAPTURE_POLICY = (
        STALE_CAPTURE_POLICY_THRESHOLD = 24 HOURS,
        EXECUTION_COUNT = 30,
        TOTAL_COMPILE_CPU_TIME_MS = 1000,
        TOTAL_EXECUTION_CPU_TIME_MS = 100
    )
);
*/

-- Verify current settings
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb,
       max_storage_size_mb, readonly_reason, interval_length_minutes,
       stale_query_threshold_days, size_based_cleanup_mode_desc,
       query_capture_mode_desc, wait_stats_capture_mode_desc,
       max_plans_per_query
FROM sys.database_query_store_options;
GO
