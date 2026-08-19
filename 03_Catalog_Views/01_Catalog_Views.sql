/*
    All three queries are read-only. They will show you what Query
    Store is capturing, and how it's capturing it.

    1. Shows Query Store's configuration and current health
    2. Shows text, plan, and runtime stats for queries touching the two
       demo procedures
    3. Shows plan count per query shape, to spot non-parameterized ad
       hoc bloat

    Run 02_Generate_Workload/01_Generate_Workload.sql first.
*/

USE [AdventureWorks2022];
GO

-- Query Store configuration and current health. [Actual State] should
-- match [Desired State], if it doesn't, something pushed Query Store
-- out of read/write on its own, usually low disk space. [Current
-- Storage MB] should stay comfortably under [Max Storage MB].
SELECT
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    current_storage_size_mb AS [Current Storage MB],
    max_storage_size_mb AS [Max Storage MB],
    readonly_reason AS [Readonly Reason],
    interval_length_minutes AS [Interval Minutes],
    query_capture_mode_desc AS [Query Capture Mode],
    size_based_cleanup_mode_desc AS [Size Based Cleanup Mode]
FROM sys.database_query_store_options;
GO

-- Text, plan, and runtime stats for every captured query touching the
-- two demo procedures. Multiple [Plan Id] rows under the same
-- [Query Id] means the optimizer picked more than one plan for it,
-- worth comparing [Avg Duration MS] between them.
SELECT
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    q.query_parameterization_type_desc AS [Parameterization],
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_cpu_time / 1000.0 AS [Avg CPU MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE N'%SalesOrderDetail%'
   OR qt.query_sql_text LIKE N'%SalesOrderHeader%'
ORDER BY rs.avg_duration DESC;
GO

-- Plan count per distinct query shape (query_hash), a quick way to spot
-- non-parameterized, ad hoc bloat. A high plan count for one query_hash
-- with many different query_text_id values means many near-identical,
-- differently-literal'd statements are each getting their own plan.
-- Scoped to the ad hoc SELECT COUNT(*) queries from
-- 02_Generate_Workload, the ones this is actually about, AUTO capture
-- mode doesn't exclude this repo's own setup DDL (CREATE INDEX and
-- similar can be costly enough on a single run to still get captured).
SELECT
    COUNT(p.plan_id) AS [Plan Count],
    q.query_hash AS [Query Hash],
    qt.query_text_id AS [Query Text Id],
    qt.query_sql_text AS [Query Text]
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE qt.query_sql_text LIKE N'SELECT COUNT(*)%'
GROUP BY q.query_hash, qt.query_text_id, qt.query_sql_text
ORDER BY [Plan Count] DESC;
GO
