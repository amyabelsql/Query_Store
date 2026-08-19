/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS). All
    three queries are read-only. Same technique behind the SSMS
    "Top Resource Consuming Queries" report.

    1. Top 10 queries by average CPU time
    2. Top 10 queries by total logical reads
    3. Top 10 queries by memory grant

    Each query excludes internal Query Store queries and this repo's own
    setup DDL (CREATE INDEX, ALTER DATABASE, the DROP INDEX check).
    QUERY_CAPTURE_MODE = AUTO (set in 01_Setup/03_Configure.sql) cuts
    down low-value noise generally, but it filters by execution
    frequency and cost, not statement type, so a one-time CREATE INDEX
    that does real work can still get captured and crowd out the actual
    workload here.

    Gives you a before/after baseline for the regression in
    02_Find_Regressed_Queries.sql.
*/

USE [AdventureWorks2022];
GO

-- Top 10 by average CPU time. The queries at the top are your best
-- CPU-tuning targets, especially if [Executions] is also high, since
-- the cost multiplies across every call.
SELECT TOP (10)
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.avg_cpu_time / 1000.0 AS [Avg CPU MS],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads],
    rs.count_executions AS [Executions]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE q.is_internal_query = 0
  AND qt.query_sql_text NOT LIKE 'CREATE%'
  AND qt.query_sql_text NOT LIKE 'ALTER%'
  AND qt.query_sql_text NOT LIKE 'DROP%'
  AND qt.query_sql_text NOT LIKE 'IF EXISTS%'
ORDER BY rs.avg_cpu_time DESC;
GO

-- Top 10 by total logical reads, accounting for execution count.
-- [Total Logical Reads] combines per-call cost with how often it runs,
-- so a query near the top with modest [Avg Logical IO Reads] but very
-- high [Executions] is more about call volume than a missing index.
SELECT TOP (10)
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads],
    rs.count_executions AS [Executions],
    rs.avg_logical_io_reads * rs.count_executions AS [Total Logical Reads]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE q.is_internal_query = 0
  AND qt.query_sql_text NOT LIKE 'CREATE%'
  AND qt.query_sql_text NOT LIKE 'ALTER%'
  AND qt.query_sql_text NOT LIKE 'DROP%'
  AND qt.query_sql_text NOT LIKE 'IF EXISTS%'
ORDER BY [Total Logical Reads] DESC;
GO

-- Top 10 by memory grant, a common source of RESOURCE_SEMAPHORE waits.
-- A surprisingly high [Avg Memory Grant KB] for a simple query usually
-- means the optimizer overestimated the row count, worth checking for
-- stale statistics or parameter sniffing on that query.
SELECT TOP (10)
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.avg_query_max_used_memory AS [Avg Memory Grant KB],
    rs.count_executions AS [Executions]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE q.is_internal_query = 0
  AND qt.query_sql_text NOT LIKE 'CREATE%'
  AND qt.query_sql_text NOT LIKE 'ALTER%'
  AND qt.query_sql_text NOT LIKE 'DROP%'
  AND qt.query_sql_text NOT LIKE 'IF EXISTS%'
ORDER BY rs.avg_query_max_used_memory DESC;
GO
