/*
    Read-only. Run the whole script.

    1. Current state vs. desired state
    2. Decodes readonly_reason into plain text
    3. Storage headroom
    4. Query capture policy pressure (CUSTOM capture mode, 2019+)
    5. Ad hoc / unique-query pressure
    6. Forced-plan health
    7. Execution counts by type (Regular / Aborted / Exception) per query
    8. Just the Aborted and Exception executions, with interval detail

    Run this first, every other script here assumes Query Store is
    healthy. If query 1 shows actual_state_desc = 'ERROR', run
    11_Recover_From_Error_State.sql to fix it.
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
-- as-is by 06_Monitoring/02_Monitoring_Procedures.sql).
-- [Pct Of Quota Used] climbing toward 100 means Query Store is close
-- to forcing itself into READ_ONLY or starting size-based cleanup.
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
    capture_policy_execution_count AS [Capture Policy Execution Count],
    capture_policy_total_compile_cpu_time_ms AS [Capture Policy Compile CPU MS],
    capture_policy_total_execution_cpu_time_ms AS [Capture Policy Execution CPU MS],
    capture_policy_stale_threshold_hours AS [Capture Policy Stale Threshold Hours]
FROM sys.database_query_store_options;
GO

-- Ad hoc / unique-query pressure. A ratio near 1.0 means most captured
-- queries are unique text (ad hoc), which bloats Query Store and pushes
-- it toward its quota faster than a parameterized workload would. See
-- 02_Catalog_Views_Reference.sql for the same pressure broken out per
-- query shape.
SELECT
    COUNT(*) AS [Total Queries],
    COUNT(DISTINCT query_hash) AS [Distinct Query Hashes],
    CAST(100.0 * COUNT(DISTINCT query_hash) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS [Pct Unique]
FROM sys.query_store_query;
GO

-- Forced-plan health. A force_failure_count above 0 means a forced plan
-- stopped applying, and Query Store silently fell back to the
-- optimizer's normal choice. [Last Force Failure Reason] names why,
-- most often NO_INDEX (an index the plan depended on was dropped or
-- disabled). See 00_Troubleshooting_Doc.md for the full list of reasons.
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

-- Execution counts by [Execution Type] per query. Regular is normal,
-- the circle marker in SSMS's Query Store report charts. Aborted means
-- something interrupted it before it finished, a client CommandTimeout,
-- someone clicking Cancel, or a KILL, the square marker. Exception
-- means the statement itself failed while running, a real error, not
-- an interruption, the triangle marker. A query with a growing Aborted
-- or Exception count next to its Regular count is worth investigating
-- even if its average duration looks fine, timeouts and cancellations
-- are often a symptom of something else: blocking, a missing index
-- making it slow enough to time out, or bad data reaching a query that
-- assumed it was clean.
SELECT
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.execution_type_desc AS [Execution Type],
    SUM(rs.count_executions) AS [Executions]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
GROUP BY qt.query_sql_text, q.query_id, rs.execution_type_desc
ORDER BY CASE WHEN rs.execution_type_desc = 'Regular' THEN 1 ELSE 0 END, [Executions] DESC;
GO

-- Just the Aborted and Exception executions, with per-interval detail.
SELECT
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
WHERE rs.execution_type_desc <> 'Regular'
ORDER BY rsi.start_time DESC;
GO
