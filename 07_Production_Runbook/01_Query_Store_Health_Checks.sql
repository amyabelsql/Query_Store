/*
    Diagnoses Query Store itself: is it running, is it in the mode you
    expect, is it near its size quota, is it silently dropping data. Run
    this first, before 02_Performance_Troubleshooting_Queries.sql. A
    Query Store that has gone READ_ONLY or ERROR gives misleading or
    stale answers to everything downstream.
    Companion to 01_Setup/00_Setup_Doc.md and
    06_Maintenance_And_Best_Practices/00_Maintenance_And_Best_Practices_Doc.md.
*/

USE [AdventureWorks2022];
GO

-- Current state vs. desired state. A mismatch means Query Store changed
-- mode on its own, most commonly READ_WRITE -> READ_ONLY after hitting
-- its size quota.
SELECT
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    readonly_reason AS [Readonly Reason],
    query_capture_mode_desc AS [Query Capture Mode],
    size_based_cleanup_mode_desc AS [Size Based Cleanup Mode]
FROM sys.database_query_store_options;
GO

-- Decodes readonly_reason into plain text. It's a bitmask, more than
-- one condition can apply at once. Reference: sys.database_query_store_options
-- on Microsoft Learn.
SELECT
    readonly_reason AS [Readonly Reason],
    CASE WHEN readonly_reason & 1      = 1      THEN 'Database is in read-only mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 2      = 2      THEN 'Database is in single-user mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 4      = 4      THEN 'Database is in emergency mode; ' ELSE '' END +
    CASE WHEN readonly_reason & 8      = 8      THEN 'Database is a secondary replica; ' ELSE '' END +
    CASE WHEN readonly_reason & 65536  = 65536  THEN 'Number of distinct statement types has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason & 131072 = 131072 THEN 'Storage size has exceeded max_storage_size_mb; ' ELSE '' END +
    CASE WHEN readonly_reason & 262144 = 262144 THEN 'Number of statements has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason & 524288 = 524288 THEN 'Number of plans has exceeded the in-memory limit; ' ELSE '' END +
    CASE WHEN readonly_reason = 0 THEN 'Not read-only' ELSE '' END AS [Readonly Reason Decoded]
FROM sys.database_query_store_options;
GO

-- Storage headroom, an alert threshold candidate for monitoring (used
-- as-is by 08_Automated_Monitoring/02_Monitoring_Procedures.sql)
SELECT
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    CAST(100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5, 2)) AS [Pct Of Quota Used]
FROM sys.database_query_store_options;
GO

-- Query capture policy pressure (SQL Server 2019+ CUSTOM capture mode).
-- Non-null values mean CUSTOM capture is configured; compare execution
-- count / compile duration / total duration thresholds against what
-- your workload is actually doing, to see if low-value queries are
-- still slipping through.
SELECT
    query_capture_mode_desc AS [Query Capture Mode],
    query_capture_policy_execution_count AS [Capture Policy Execution Count],
    query_capture_policy_total_compile_cpu_time_ms AS [Capture Policy Compile CPU MS],
    query_capture_policy_total_execution_cpu_time_ms AS [Capture Policy Execution CPU MS],
    query_capture_policy_stale_threshold_hours AS [Capture Policy Stale Threshold Hours]
FROM sys.database_query_store_options;
GO

-- Ad hoc / unique-query pressure. A ratio near 1.0 means most captured
-- queries are unique text (ad hoc), which bloats Query Store and pushes
-- it toward its quota faster than a parameterized workload would. See
-- 04_Find_And_Fix_Regressions.
SELECT
    COUNT(*) AS [Total Queries],
    COUNT(DISTINCT query_hash) AS [Distinct Query Hashes],
    CAST(100.0 * COUNT(DISTINCT query_hash) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS [Pct Unique]
FROM sys.query_store_query;
GO

-- Forced-plan health. A force_failure_count above 0 means a forced plan
-- stopped applying, usually a schema change invalidated it, and Query
-- Store silently fell back to the optimizer's normal choice.
SELECT
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    q.object_id AS [Containing Object Id],
    p.force_failure_count AS [Force Failure Count],
    p.last_force_failure_reason_desc AS [Last Force Failure Reason]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
WHERE p.is_forced_plan = 1
ORDER BY p.force_failure_count DESC;
GO

-- Recovering from an ERROR state (SQL Server 2017+). Uncomment and run
-- manually if actual_state_desc = 'ERROR'.
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = OFF;
-- EXEC sp_query_store_consistency_check;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = ON;
-- ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
