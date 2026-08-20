/*
    Read-only. Run the whole script. Edit @LookbackHours first.

    Totals across every query, per interval, not ranked by query, same
    signal as the SSMS "Overall Resource Consumption" report. A spike
    here with nothing obvious in 04_Top_Resource_Consumers.sql usually
    means many queries got a little worse, not one query a lot worse.
*/

USE [AdventureWorks2022];
GO

DECLARE @LookbackHours INT = 24;

SELECT
    rsi.start_time AS [Interval Start],
    SUM(rs.count_executions) AS [Total Executions],
    SUM(rs.avg_duration * rs.count_executions) / 1000.0 AS [Total Duration MS],
    SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS [Total CPU MS],
    SUM(rs.avg_logical_io_reads * rs.count_executions) AS [Total Logical IO Reads],
    SUM(rs.avg_query_max_used_memory * rs.count_executions) AS [Total Memory Grant KB]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, GETUTCDATE())
GROUP BY rsi.start_time
ORDER BY rsi.start_time DESC;
GO
