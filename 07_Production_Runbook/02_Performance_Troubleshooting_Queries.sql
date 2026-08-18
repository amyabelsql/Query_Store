/*
    Uses Query Store to answer "what's slow and why": find a query by
    text, rank resource consumers, spot regressions and plan instability,
    and break down wait time by category. Run
    01_Query_Store_Health_Checks.sql first to confirm Query Store itself
    is healthy and has recent data.
    Companion to 03_Explore_Catalog_Views/00_Explore_Catalog_Views_Doc.md
    and 04_Find_And_Fix_Regressions/00_Find_And_Fix_Regressions_Doc.md.

    Each query below is its own GO batch, so @LookbackHours and other
    parameters are redeclared at the top of every section. Edit the
    value in the section you're running, not just the first one.
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
-- SSMS "Top Resource Consuming Queries" report.
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
-- 04_Find_And_Fix_Regressions/00_Find_And_Fix_Regressions_Doc.md.
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
-- wait_category_desc value with the highest total from the section above.
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
