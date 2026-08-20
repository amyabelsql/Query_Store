/*
    Read-only. Run the whole script. Edit @QueryId first.

    Same signal as the SSMS "Tracked Queries" report. Once you have a
    query_id from any other script, this shows its full plan and
    performance history, every plan, every interval.
*/

USE [AdventureWorks2022];
GO

DECLARE @QueryId INT = <query_id>;

SELECT
    p.plan_id AS [Plan Id],
    p.is_forced_plan AS [Forced],
    rsi.start_time AS [Interval Start],
    rs.count_executions AS [Executions],
    rs.avg_duration / 1000.0 AS [Avg Duration MS],
    rs.avg_cpu_time / 1000.0 AS [Avg CPU MS],
    rs.avg_logical_io_reads AS [Avg Logical IO Reads]
FROM sys.query_store_plan AS p
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE p.query_id = @QueryId
ORDER BY rsi.start_time, p.plan_id;
GO
