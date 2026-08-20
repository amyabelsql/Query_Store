/*
    Read-only. Run the whole script. Edit @LookbackHours first.

    Queries with high variation (unstable performance), same signal as
    the SSMS "Queries With High Variation" report. A high stdev relative
    to the mean flags a parameter sniffing candidate, the same plan
    performing very differently depending on the parameter values it
    was compiled with.
*/

USE [AdventureWorks2022];
GO

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
