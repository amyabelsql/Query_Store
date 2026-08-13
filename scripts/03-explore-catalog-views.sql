/*
    03 - Explore the catalog views
    Companion to docs/03-catalog-views-and-dmvs.md. Run after
    02-generate-sample-workload.sql.
*/

USE [AdventureWorks2022];
GO

-- Query Store configuration and current health
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb,
       max_storage_size_mb, readonly_reason, interval_length_minutes,
       query_capture_mode_desc, size_based_cleanup_mode_desc
FROM sys.database_query_store_options;
GO

-- Every captured query relevant to this workshop: text, plan, and runtime stats
SELECT qt.query_sql_text,
       q.query_id,
       q.query_parameterization_type_desc,
       p.plan_id,
       p.is_forced_plan,
       rs.count_executions,
       rs.avg_duration / 1000.0 AS avg_duration_ms,
       rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms,
       rs.avg_logical_io_reads
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE N'%SalesOrderDetail%'
   OR qt.query_sql_text LIKE N'%SalesOrderHeader%'
ORDER BY rs.avg_duration DESC;
GO

-- Plan count per distinct query shape (query_hash) -- a quick way to spot
-- non-parameterized / ad hoc bloat. A high plan_count for one query_hash
-- with many different query_text_id values means many near-identical,
-- differently-literal'd statements are each getting their own plan.
SELECT COUNT(p.plan_id) AS plan_count,
       q.query_hash,
       qt.query_text_id,
       qt.query_sql_text
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
GROUP BY q.query_hash, qt.query_text_id, qt.query_sql_text
ORDER BY plan_count DESC;
GO
