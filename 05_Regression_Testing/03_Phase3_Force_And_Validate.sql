/*
	Phase 3 of 5: Restore indexes and identify force candidate.
	This script does not force or validate.
*/

USE [AdventureWorks2022];
GO

IF NOT EXISTS
(
	SELECT 1
	FROM sys.indexes
	WHERE name = N'IX_QSDemo_SalesOrderDetail_ProductID'
	  AND object_id = OBJECT_ID(N'Sales.SalesOrderDetail')
)
	CREATE NONCLUSTERED INDEX IX_QSDemo_SalesOrderDetail_ProductID
		ON Sales.SalesOrderDetail (ProductID)
		INCLUDE (OrderQty, UnitPrice, LineTotal);
GO

ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail REBUILD;
GO

DECLARE @QueryTextPattern VARCHAR(200) = '%WHERE d.ProductID = @ProductID%'; -- text pattern to find demo query
DECLARE @TargetQueryId BIGINT = NULL; -- Optional specific query_id

;WITH CandidateQueries AS
(
	SELECT
		q.query_id,
		MAX(p.last_execution_time) AS last_execution_time
	FROM sys.query_store_query AS q
	JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
	JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
	WHERE qt.query_sql_text LIKE @QueryTextPattern
	GROUP BY q.query_id
),
TargetQuery AS
(
	SELECT query_id
	FROM CandidateQueries
	WHERE query_id = ISNULL(@TargetQueryId, query_id)
	  AND
	  (
		@TargetQueryId IS NOT NULL
		OR query_id =
		(
			SELECT TOP (1) cq.query_id
			FROM CandidateQueries AS cq
			ORDER BY cq.last_execution_time DESC
		)
	  )
),
PlanRollup AS
(
	SELECT
		q.query_id,
		p.plan_id,
		p.is_forced_plan,
		MAX(p.last_execution_time) AS last_execution_time,
		SUM(rs.count_executions) AS execution_count,
		CAST(SUM((rs.avg_duration / 1000.0) * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS DECIMAL(18,3)) AS weighted_avg_duration_ms,
		CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS DECIMAL(18,2)) AS weighted_avg_logical_reads
	FROM sys.query_store_query AS q
	JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
	JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
	JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
	JOIN TargetQuery AS tq ON tq.query_id = q.query_id
	WHERE qt.query_sql_text LIKE @QueryTextPattern
	GROUP BY q.query_id, p.plan_id, p.is_forced_plan
)
SELECT
	pr.query_id AS [Query Id],
	pr.plan_id AS [Plan Id],
	pr.is_forced_plan AS [Forced],
	pr.last_execution_time AS [Last Execution],
	pr.execution_count AS [Execution Count],
	pr.weighted_avg_duration_ms AS [Avg Duration MS],
	pr.weighted_avg_logical_reads AS [Avg Logical IO Reads],
	CASE
		WHEN pr.weighted_avg_logical_reads = MIN(pr.weighted_avg_logical_reads) OVER (PARTITION BY pr.query_id)
			THEN N'Recommended to force'
		ELSE N'Not recommended'
	END AS [Force Recommendation]
FROM PlanRollup AS pr
ORDER BY pr.query_id, pr.weighted_avg_logical_reads, pr.weighted_avg_duration_ms;
GO

SELECT
	N'Phase 3 complete' AS [Status],
	N'Copy Query Id and Plan Id from the recommended row, then run 04_Force_Plan.sql.' AS [Next Step];
GO
