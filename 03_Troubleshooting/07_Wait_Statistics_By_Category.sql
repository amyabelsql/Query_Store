/*
    Read-only. Run the whole script, then edit @WaitCategory using
    query 1's result and run query 2 again. Same signal as the SSMS
    "Query Wait Statistics" report. Requires SQL Server 2017+ with
    WAIT_STATS_CAPTURE_MODE = ON (default in SQL Server 2022).

    1. Wait time by category in the lookback window, the category at
       the top tells you if it's CPU, IO, memory, or locking
    2. Top queries within the dominant wait category
*/

USE [AdventureWorks2022];
GO

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
-- wait_category_desc value with the highest total from above. The
-- query at the top of [Total Wait Time MS] is your best target for it.
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
