/*
    Run the section that matches your alert, not necessarily the whole
    file, see 00_Troubleshooting_Doc.md for which section to use.
    Each section is its own GO batch with its own @LookbackHours and
    other parameters, edit the value in the section you're running, not
    just the first one. Section 6 needs a @WaitCategory value you get by
    reading section 5's output first.

    1. Finds a query by text
    2. Top resource consumers in the lookback window
    3. Queries with high variation (unstable performance, a parameter
       sniffing candidate)
    4. Regressed queries, most recent interval vs. the one before it
    5. Wait time by category in the lookback window
    6. Top queries within the dominant wait category (edit
       @WaitCategory using section 5's result first)

    Run 01_Query_Store_Health_Checks.sql first to confirm Query Store
    itself is healthy and has recent data. Companion to
    03_Catalog_Views/00_Catalog_Views_Doc.md and
    04_Regressions_And_Forcing/00_Regressions_And_Forcing_Doc.md.

    Nothing here filters out DDL (CREATE INDEX, ALTER DATABASE, and the
    like). That's intentional, a runaway index build or schema change is
    a legitimate top resource consumer in real production data.
*/

USE [AdventureWorks2022];
GO

-- Finds a query by text. Start here when you have a query pasted from
-- an app log or a slow report but no query_id.
DECLARE @SearchText NVARCHAR(200) = N'%SalesOrderDetail%';

SELECT
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text],
    q.object_id AS [Containing Object Id],
    q.query_parameterization_type_desc AS [Parameterization]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE qt.query_sql_text LIKE @SearchText
ORDER BY q.last_execution_time DESC;
GO

-- Top resource consumers in the lookback window. Same signal as the
-- SSMS "Top Resource Consuming Queries" report. The query at the top
-- of [Total Duration MS] is generally the best overall target, cross
-- check [Total CPU MS] and [Total Logical IO Reads] to see which
-- resource is actually driving the cost.
DECLARE @LookbackHours INT = 24;

SELECT TOP (25)
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text],
    SUM(rs.count_executions) AS [Total Executions],
    SUM(rs.avg_duration * rs.count_executions) / 1000.0 AS [Total Duration MS],
    SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS [Total CPU MS],
    SUM(rs.avg_logical_io_reads * rs.count_executions) AS [Total Logical IO Reads],
    SUM(rs.avg_query_max_used_memory * rs.count_executions) AS [Total Memory Grant KB]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY q.query_id, qt.query_sql_text
ORDER BY [Total Duration MS] DESC;
GO

-- Queries with high variation (unstable performance). A high stdev
-- relative to the mean flags a candidate for parameter sniffing: the
-- same plan performs very differently depending on the parameter
-- values it was compiled with.
DECLARE @LookbackHours INT = 24;

SELECT TOP (25)
    q.query_id AS [Query Id],
    p.plan_id AS [Plan Id],
    qt.query_sql_text AS [Query Text],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.stdev_duration / 1000.0 AS [Stdev Duration MS],
    CAST(rs.stdev_duration / NULLIF(rs.avg_duration, 0) AS DECIMAL(10, 2)) AS [Variation Ratio],
    rs.count_executions AS [Executions]
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
    AND rs.count_executions > 5
ORDER BY [Variation Ratio] DESC;
GO

-- Regressed queries: most recent interval vs. the one before it. Flags
-- queries whose average duration got meaningfully worse between two
-- consecutive intervals, the fastest way to correlate "the app just got
-- slow" with a specific query and plan change. See
-- 01_Query_Store_Health_Checks.sql if this returns nothing (Query Store
-- may not have collected two intervals yet).
DECLARE @RegressionThresholdPct DECIMAL(5, 2) = 50.0;

WITH ranked_intervals AS (
    SELECT
        q.query_id,
        qt.query_sql_text,
        p.plan_id,
        rsi.start_time,
        rs.avg_duration,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rsi.start_time DESC) AS interval_rank
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS rsi
        ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
)
SELECT
    cur.query_id AS [Query Id],
    cur.query_sql_text AS [Query Text],
    prev.avg_duration / 1000.0 AS [Prev Avg Duration MS],
    cur.avg_duration / 1000.0 AS [Current Avg Duration MS],
    CAST(100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) AS DECIMAL(10, 2)) AS [Pct Change]
FROM ranked_intervals AS cur
JOIN ranked_intervals AS prev
    ON cur.query_id = prev.query_id AND prev.interval_rank = cur.interval_rank + 1
WHERE cur.interval_rank = 1
    AND cur.avg_duration > prev.avg_duration
    AND 100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) >= @RegressionThresholdPct
ORDER BY [Pct Change] DESC;
GO

-- Wait time by category in the lookback window. Requires
-- WAIT_STATS_CAPTURE_MODE = ON (default in SQL Server 2022). See the
-- wait-category-to-action table in
-- 04_Regressions_And_Forcing/00_Regressions_And_Forcing_Doc.md.
DECLARE @LookbackHours INT = 24;

SELECT
    ws.wait_category_desc AS [Wait Category],
    SUM(ws.total_query_wait_time_ms) AS [Total Wait Time MS]
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY ws.wait_category_desc
ORDER BY [Total Wait Time MS] DESC;
GO

-- Top queries within the dominant wait category. Swap in the
-- wait_category_desc value with the highest total from the section
-- above. The query at the top of [Total Wait Time MS] is contributing
-- the most to that wait category, and is your best target for it.
DECLARE @LookbackHours INT = 24;
DECLARE @WaitCategory NVARCHAR(60) = N'Buffer IO';

SELECT TOP (25)
    q.query_id AS [Query Id],
    qt.query_sql_text AS [Query Text],
    SUM(ws.total_query_wait_time_ms) AS [Total Wait Time MS]
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_plan AS p ON ws.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
    AND ws.wait_category_desc = @WaitCategory
GROUP BY q.query_id, qt.query_sql_text
ORDER BY [Total Wait Time MS] DESC;
GO
