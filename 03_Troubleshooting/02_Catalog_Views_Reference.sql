/*
    Read-only. Run the whole script.

    A primer on the views the other scripts don't already cover.

    1. Every captured query, joined to its text and plans
    2. SET options each plan was compiled under
    3. Query Store hints applied to a query (SQL Server 2022+, skipped
       on older versions, the view doesn't exist there)
    4. Plan count per query hash, spot non-parameterized ad hoc bloat
    5. The time intervals runtime stats and wait stats are bucketed into

    Run 02_Generate_Workload/01_Generate_Workload.sql first so there's
    something to see.
*/

USE [AdventureWorks2022];
GO

-- Every captured query, its text, and every plan the optimizer picked
-- for it. Multiple [Plan Id] rows under the same [Query Id] means the
-- optimizer chose more than one plan for it over time.
SELECT
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text],
    q.query_parameterization_type_desc AS [Parameterization],
    q.object_id AS [Containing Object Id],
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    p.last_compile_start_time AS [Last Compile Start]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
ORDER BY p.last_compile_start_time DESC;
GO

-- SET options each plan was compiled under. Plans compiled under
-- different context settings are never interchangeable, which is why
-- the same query text can end up with more plans than expected.
SELECT
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    cs.context_settings_id AS [Context Settings Id],
    cs.set_options AS [Set Options Bitmask],
    cs.language_id AS [Language Id],
    cs.date_format AS [Date Format]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_context_settings AS cs ON q.context_settings_id = cs.context_settings_id;
GO

-- Query Store hints applied to a query (SQL Server 2022+). Empty is
-- normal, most queries never get one. See
-- 04_Version_Dependencies/01_Query_Store_Hints.sql to set one.
SELECT
    query_id AS [Query Id],
    query_hint_text AS [Hint Text],
    last_query_hint_failure_reason_desc AS [Last Failure Reason],
    query_hint_failure_count AS [Failure Count]
FROM sys.query_store_query_hints;
GO

-- Plan count per distinct query shape (query_hash). A high count on one
-- hash with many different [Distinct Query Texts] usually means
-- non-parameterized, ad hoc statements are each getting their own plan
-- instead of sharing one. Same pressure 01_Health_Checks.sql section 5
-- reports as a single ratio, this breaks it out per shape.
SELECT
    q.query_hash AS [Query Hash],
    COUNT(p.plan_id) AS [Plan Count],
    COUNT(DISTINCT qt.query_text_id) AS [Distinct Query Texts]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
GROUP BY q.query_hash
ORDER BY [Plan Count] DESC;
GO

-- The time buckets runtime stats and wait stats are grouped into.
-- Bucket width comes from [Interval Minutes] in
-- 01_Setup/03_Configure.sql (INTERVAL_LENGTH_MINUTES).
SELECT
    runtime_stats_interval_id AS [Interval Id],
    start_time AS [Interval Start],
    end_time AS [Interval End]
FROM sys.query_store_runtime_stats_interval
ORDER BY start_time DESC;
GO
