/*
    The 4 numbered queries below are read-only and can run together, top
    to bottom, while connected to the PRIMARY replica (SQL Server
    2025+). The plan-forcing block near the bottom is commented out on
    purpose, it needs <query_id>/<plan_id>/<replica_group_id> values
    from the queries above filled in first, run it manually.

    1. Lists the replica set and what role each replica has been seen in
    2. Shows streaming health for the channel that carries Query Store
       data from secondaries back to the primary
    3. Top 50 queries by CPU across all replicas, broken out by role
    4. Reviews what's forced where

    Run 01_Enable_On_Secondary.sql first, then generate a read workload
    directly against the secondary (see this folder's doc) before
    running the queries below.
*/

USE [AdventureWorks2022];
GO

-- Who's in the replica set, and what role has each replica been seen
-- in? role_type: 1=Primary, 2=Secondary, 3=Geo-Primary, 4=Geo-Secondary,
-- 5+=Named replica. One row per (replica, role_type) ever observed; a
-- failover adds rows rather than replacing them. If only role_type 1
-- (Primary) shows up, the secondary hasn't captured anything yet, run
-- a read workload against it first.
SELECT
    replica_group_id AS [Replica Group Id],
    role_type AS [Role Type],
    replica_name AS [Replica Name]
FROM sys.query_store_replicas
ORDER BY replica_group_id, role_type;
GO

-- Streaming health: pending messages / memory used for the channel that
-- carries Query Store data from secondaries back to the primary. Rising
-- pending_message_count under load points at backpressure on the
-- shared HADR transport, not a Query Store-specific problem.
SELECT
    pending_message_count AS [Pending Message Count],
    messaging_memory_used_mb AS [Messaging Memory Used MB]
FROM sys.database_query_store_internal_state;
GO

-- Top 50 queries by CPU across ALL replicas in the last 8 hours, broken
-- out by which role ran them. Adapted from Microsoft's own example, see
-- this folder's doc for the source link. Rows with [Replica Type] =
-- SECONDARY confirm secondary capture is actually working, if none
-- appear, no read workload has hit the secondary yet. Excludes internal
-- Query Store queries and this repo's own setup DDL (CREATE INDEX and
-- similar), QUERY_CAPTURE_MODE = AUTO doesn't reliably filter those out
-- on its own since it goes by cost and frequency, not statement type.
DECLARE @hours AS INT = 8;

SELECT TOP 50
       qsq.query_id AS [Query Id],
       qsp.plan_id AS [Plan Id],
       CASE qrs.replica_group_id
           WHEN 1 THEN 'PRIMARY'
           WHEN 2 THEN 'SECONDARY'
           WHEN 3 THEN 'GEO SECONDARY'
           WHEN 4 THEN 'GEO HA SECONDARY'
           ELSE CONCAT('NAMED REPLICA_', qrs.replica_group_id)
       END AS [Replica Type],
       qsq.query_hash AS [Query Hash],
       qsp.query_plan_hash AS [Query Plan Hash],
       SUM(qrs.count_executions) AS [Sum Executions],
       SUM(qrs.count_executions * qrs.avg_logical_io_reads) AS [Total Logical Reads],
       SUM(qrs.count_executions * qrs.avg_cpu_time / 1000.0) AS [Total CPU MS],
       AVG(qrs.avg_logical_io_reads) AS [Avg Logical IO Reads],
       AVG(qrs.avg_cpu_time / 1000.0) AS [Avg CPU MS],
       ROUND(TRY_CAST(SUM(qrs.avg_duration * qrs.count_executions) AS FLOAT)
             / NULLIF(SUM(qrs.count_executions), 0) * 0.001, 2) AS [Avg Duration MS],
       COUNT(DISTINCT qsp.plan_id) AS [Number Of Distinct Plans],
       qsqt.query_sql_text AS [Query Text]
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
  AND qsq.is_internal_query = 0
  AND qsqt.query_sql_text NOT LIKE 'CREATE%'
  AND qsqt.query_sql_text NOT LIKE 'ALTER%'
  AND qsqt.query_sql_text NOT LIKE 'DROP%'
  AND qsqt.query_sql_text NOT LIKE 'IF EXISTS%'
GROUP BY qsq.query_id, qsq.query_hash, qsp.query_plan_hash, qsp.plan_id,
         qrs.replica_group_id, qsqt.query_sql_text
ORDER BY SUM(qrs.count_executions * qrs.avg_cpu_time / 1000.0) DESC,
         AVG(qrs.avg_cpu_time / 1000.0) DESC;
GO

-- Forces a plan on a specific secondary (run from the PRIMARY). Fill in
-- @query_id / @plan_id from the query above, and @replica_group_id from
-- the replica set query. Omitting @replica_group_id forces on the
-- primary only.
-- EXEC sp_query_store_force_plan
--     @query_id = <query_id>,
--     @plan_id = <plan_id>,
--     @disable_optimized_plan_forcing = 0,
--     @replica_group_id = '<replica_group_id from sys.query_store_replicas>';
-- GO

-- Reviews what's forced where. Empty means nothing is currently
-- forced. After running the commented force block above, expect one
-- row per [Replica Group Id] you forced for.
SELECT
    qsp.query_plan AS [Query Plan],
    pfl.query_id AS [Query Id],
    pfl.plan_id AS [Plan Id],
    pfl.replica_group_id AS [Replica Group Id]
FROM sys.query_store_plan AS qsp
JOIN sys.query_store_plan_forcing_locations AS pfl
    ON pfl.query_id = qsp.query_id
   AND pfl.plan_id = qsp.plan_id;
GO
