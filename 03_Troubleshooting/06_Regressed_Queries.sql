/*
    Read-only. Run the whole script. Edit @RegressionThresholdPct first.

    Regressed queries: most recent interval vs. the one before it, same
    signal as the SSMS "Regressed Queries" report. Flags queries whose
    average duration got meaningfully worse between two consecutive
    intervals.

    Returns nothing? Check 01_Health_Checks.sql, Query Store may not
    have collected two intervals yet.
*/

USE [AdventureWorks2022];
GO

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
