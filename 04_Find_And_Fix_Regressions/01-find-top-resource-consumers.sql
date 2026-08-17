/*
    01 - Find top resource-consuming queries
    Companion to README.md in this folder. Same technique behind the
    SSMS "Top Resource Consuming Queries" report.
*/

USE [AdventureWorks2022];
GO

-- Top 10 by average CPU time
SELECT TOP (10)
    qt.query_sql_text,
    q.query_id,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.avg_logical_io_reads,
    rs.count_executions
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
ORDER BY rs.avg_cpu_time DESC;
GO

-- Top 10 by total logical reads (I/O pressure), accounting for execution count
SELECT TOP (10)
    qt.query_sql_text,
    q.query_id,
    rs.avg_logical_io_reads,
    rs.count_executions,
    rs.avg_logical_io_reads * rs.count_executions AS total_logical_reads
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
ORDER BY total_logical_reads DESC;
GO

-- Top 10 by memory grant (a common source of RESOURCE_SEMAPHORE / memory waits)
SELECT TOP (10)
    qt.query_sql_text,
    q.query_id,
    rs.avg_query_max_used_memory,
    rs.count_executions
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
ORDER BY rs.avg_query_max_used_memory DESC;
GO
