/*
    Ranks captured queries by CPU, I/O, and memory grant so you have a
    before/after baseline. Same technique behind the SSMS "Top Resource
    Consuming Queries" report.
*/

USE [AdventureWorks2022];
GO

-- Top 10 by average CPU time
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
ORDER BY rs.avg_cpu_time DESC;
GO

-- Top 10 by total logical reads, accounting for execution count
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
ORDER BY [Total Logical Reads] DESC;
GO

-- Top 10 by memory grant, a common source of RESOURCE_SEMAPHORE waits
SELECT TOP (10)
    qt.query_sql_text AS [Query Text],
    q.query_id AS [Query Id],
    rs.avg_query_max_used_memory AS [Avg Memory Grant KB],
    rs.count_executions AS [Executions]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
ORDER BY rs.avg_query_max_used_memory DESC;
GO
