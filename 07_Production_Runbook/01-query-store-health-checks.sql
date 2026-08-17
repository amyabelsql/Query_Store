/*
    Query Store health checks
    Diagnoses Query Store itself: is it running, is it in the mode you
    expect, is it near its size quota, is it silently dropping data.
    Run these first, before 02-performance-troubleshooting-queries.sql --
    a Query Store that has gone READ_ONLY or ERROR gives misleading or
    stale answers to everything downstream.

    Companion to 01_Setup/README.md and
    06_Maintenance_And_Best_Practices/README.md.
*/

USE [AdventureWorks2022];
GO

-- 1. Current state vs. desired state
-- A mismatch (actual_state_desc <> desired_state_desc) means Query Store
-- changed mode on its own, most commonly READ_WRITE -> READ_ONLY after
-- hitting its size quota.
SELECT
    actual_state_desc,
    desired_state_desc,
    current_storage_size_mb,
    max_storage_size_mb,
    readonly_reason,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
FROM sys.database_query_store_options;
GO

-- 2. Decode readonly_reason into plain text
-- readonly_reason is a bitmask; more than one condition can apply at once.
-- Reference: sys.database_query_store_options (Transact-SQL) on Microsoft Learn.
SELECT
    readonly_reason,
    CASE WHEN readonly_reason & 1      = 1      THEN 'Database is in read-only mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 2      = 2      THEN 'Database is in single-user mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 4      = 4      THEN 'Database is in emergency mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 8      = 8      THEN 'Database is a secondary replica; ' ELSE '' END +
    CASE WHEN readonly_reason & 65536  = 65536  THEN 'Number of distinct statement types has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason & 131072 = 131072 THEN 'Storage size has exceeded max_storage_size_mb; ' ELSE '' END +
    CASE WHEN readonly_reason & 262144 = 262144 THEN 'Number of statements has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason & 524288 = 524288 THEN 'Number of plans has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason = 0 THEN 'Not read-only' ELSE '' END AS readonly_reason_decoded
FROM sys.database_query_store_options;
GO

-- 3. Storage headroom -- alert threshold candidate for monitoring/
-- (used as-is by monitoring/01-monitoring-procedures.sql)
SELECT
    current_storage_size_mb,
    max_storage_size_mb,
    CAST(100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5, 2)) AS pct_of_quota_used
FROM sys.database_query_store_options;
GO

-- 4. Query capture policy pressure (SQL Server 2019+ CUSTOM capture mode)
-- Non-null values mean CUSTOM capture is configured; compare execution
-- count / compile duration / total duration thresholds against what your
-- workload is actually doing to see if low-value queries are still
-- slipping through.
SELECT
    query_capture_mode_desc,
    query_capture_policy_execution_count,
    query_capture_policy_total_compile_cpu_time_ms,
    query_capture_policy_total_execution_cpu_time_ms,
    query_capture_policy_stale_threshold_hours
FROM sys.database_query_store_options;
GO

-- 5. Ad hoc / unique-query pressure
-- A ratio near 1.0 means most captured queries are unique text (ad hoc),
-- which bloats Query Store and pushes it toward its quota faster than a
-- parameterized workload would. See 04_Find_And_Fix_Regressions/README.md.
SELECT
    COUNT(*) AS total_queries,
    COUNT(DISTINCT query_hash) AS distinct_query_hashes,
    CAST(100.0 * COUNT(DISTINCT query_hash) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS pct_unique
FROM sys.query_store_query;
GO

-- 6. Forced-plan health
-- force_failure_count > 0 means a forced plan stopped applying (usually a
-- schema change invalidated it) and Query Store silently fell back to the
-- optimizer's normal choice.
SELECT
    q.query_id,
    p.plan_id,
    q.object_id AS containing_object_id,
    p.force_failure_count,
    p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
WHERE p.is_forced_plan = 1
ORDER BY p.force_failure_count DESC;
GO

-- 7. Recovering from an ERROR state (SQL Server 2017+)
-- Uncomment and run manually if actual_state_desc = 'ERROR'.
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = OFF;
-- EXEC sp_query_store_consistency_check;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = ON;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
