/*
    02 - Cross-replica Query Store demo queries (SQL Server 2025+)
    Companion to README.md in this folder. Run 01-enable-on-secondary.sql
    first, then generate a read workload directly against the secondary
    (see this folder's README) before running the queries below.

    Run against the PRIMARY replica.
*/

USE [AdventureWorks2022];
GO

-- ---------------------------------------------------------------------------
-- 1. Who's in the replica set, and what role has each replica been seen in?
--    role_type: 1=Primary, 2=Secondary, 3=Geo-Primary, 4=Geo-Secondary,
--    5+=Named replica. One row per (replica, role_type) ever observed --
--    a failover adds rows rather than replacing them.
-- ---------------------------------------------------------------------------
SELECT replica_group_id, role_type, replica_name
FROM sys.query_store_replicas
ORDER BY replica_group_id, role_type;
GO

-- ---------------------------------------------------------------------------
-- 2. Streaming health: pending messages / memory used for the channel that
--    carries Query Store data from secondaries back to the primary.
--    Rising pending_message_count under load points at backpressure on the
--    shared HADR transport, not a Query Store-specific problem.
-- ---------------------------------------------------------------------------
SELECT pending_message_count, messaging_memory_used_mb
FROM sys.database_query_store_internal_state;
GO

-- ---------------------------------------------------------------------------
-- 3. Top 50 queries by CPU across ALL replicas in the last 8 hours,
--    broken out by which role ran them. Adapted from Microsoft's own
--    example -- see this folder's README for the source link.
-- ---------------------------------------------------------------------------
DECLARE @hours AS INT = 8;

SELECT TOP 50
       qsq.query_id,
       qsp.plan_id,
       CASE qrs.replica_group_id
           WHEN 1 THEN 'PRIMARY'
           WHEN 2 THEN 'SECONDARY'
           WHEN 3 THEN 'GEO SECONDARY'
           WHEN 4 THEN 'GEO HA SECONDARY'
           ELSE CONCAT('NAMED REPLICA_', qrs.replica_group_id)
       END AS replica_type,
       qsq.query_hash,
       qsp.query_plan_hash,
       SUM(qrs.count_executions) AS sum_executions,
       SUM(qrs.count_executions * qrs.avg_logical_io_reads) AS total_logical_reads,
       SUM(qrs.count_executions * qrs.avg_cpu_time / 1000.0) AS total_cpu_ms,
       AVG(qrs.avg_logical_io_reads) AS avg_logical_io_reads,
       AVG(qrs.avg_cpu_time / 1000.0) AS avg_cpu_ms,
       ROUND(TRY_CAST(SUM(qrs.avg_duration * qrs.count_executions) AS FLOAT)
             / NULLIF(SUM(qrs.count_executions), 0) * 0.001, 2) AS avg_duration_ms,
       COUNT(DISTINCT qsp.plan_id) AS number_of_distinct_plans,
       qsqt.query_sql_text
FROM sys.query_store_runtime_stats_interval AS qsrsi
JOIN sys.query_store_runtime_stats AS qrs
    ON qrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS qsp
    ON qsp.plan_id = qrs.plan_id
JOIN sys.query_store_query AS qsq
    ON qsq.query_id = qsp.query_id
JOIN sys.query_store_query_text AS qsqt
    ON qsq.query_text_id = qsqt.query_text_id
WHERE qsrsi.start_time >= DATEADD(HOUR, -@hours, GETUTCDATE())
GROUP BY qsq.query_id, qsq.query_hash, qsp.query_plan_hash, qsp.plan_id,
         qrs.replica_group_id, qsqt.query_sql_text
ORDER BY SUM(qrs.count_executions * qrs.avg_cpu_time / 1000.0) DESC,
         AVG(qrs.avg_cpu_time / 1000.0) DESC;
GO

-- ---------------------------------------------------------------------------
-- 4. Force a plan on a specific secondary (run from the PRIMARY).
--    Fill in @query_id / @plan_id from query 3 above, and @replica_group_id
--    from query 1. Omitting @replica_group_id forces on the primary only.
-- ---------------------------------------------------------------------------
-- EXEC sp_query_store_force_plan
--     @query_id = <query_id>,
--     @plan_id = <plan_id>,
--     @disable_optimized_plan_forcing = 0,
--     @replica_group_id = '<replica_group_id from sys.query_store_replicas>';
-- GO

-- Review what's forced where:
SELECT qsp.query_plan, pfl.query_id, pfl.plan_id, pfl.replica_group_id
FROM sys.query_store_plan AS qsp
JOIN sys.query_store_plan_forcing_locations AS pfl
    ON pfl.query_id = qsp.query_id
   AND pfl.plan_id = qsp.plan_id;
GO
