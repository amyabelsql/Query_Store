/*
    Read-only. Run the whole script. Edit @LookbackHours first.

    Top resource consumers in the lookback window, same signal as the
    SSMS "Top Resource Consuming Queries" report.

    Doesn't filter out DDL (CREATE INDEX, ALTER DATABASE), a runaway
    index build or schema change is a legitimate top consumer in real
    production data.

    Also doubles as a before/after baseline for
    08_Simulate_And_Force_A_Regression.sql, run it once before that
    script and again after.
*/

USE [AdventureWorks2022];
GO

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
