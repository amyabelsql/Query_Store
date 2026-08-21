/*
	Step 5 of 6: Validate forced plan with row based proof.
	Required inputs
	- QueryId from step 3
	- ForcedPlanId from step 4
*/

USE [AdventureWorks2022];
GO

DECLARE @QueryId BIGINT = <query_id>; -- Query Id from step 3
DECLARE @ForcedPlanId BIGINT = <plan_id>; -- Plan Id forced in step 4
DECLARE @ValidationProductId INT = 712; -- ProductID for post force executions
DECLARE @ValidationExecutions INT = 10; -- Number of post force executions
DECLARE @ValidationStartUtc DATETIME2(3) = SYSUTCDATETIME(); -- Start of post force validation window
DECLARE @ExecutionCounter INT = 1; -- Loop counter

DROP TABLE IF EXISTS #ValidationSink;
DROP TABLE IF EXISTS #PlanAll;
DROP TABLE IF EXISTS #ForcedAfter;
DROP TABLE IF EXISTS #Baseline;
DROP TABLE IF EXISTS #Regressed;

CREATE TABLE #ValidationSink
(
	SalesOrderID INT,
	ProductID INT,
	OrderQty SMALLINT,
	UnitPrice MONEY,
	LineTotal NUMERIC(38, 6)
);

CREATE TABLE #PlanAll
(
	PlanId BIGINT NOT NULL,
	ExecutionsAll BIGINT NULL,
	AvgDurationMsAll DECIMAL(18,2) NULL,
	AvgReadsAll DECIMAL(18,2) NULL
);

CREATE TABLE #ForcedAfter
(
	PlanId BIGINT NOT NULL,
	ExecutionsAfter BIGINT NULL,
	AvgDurationMsAfter DECIMAL(18,2) NULL,
	AvgReadsAfter DECIMAL(18,2) NULL
);

CREATE TABLE #Baseline
(
	PlanId BIGINT NULL,
	ExecutionsAll BIGINT NULL,
	AvgDurationMsAll DECIMAL(18,2) NULL,
	AvgReadsAll DECIMAL(18,2) NULL
);

CREATE TABLE #Regressed
(
	PlanId BIGINT NULL,
	ExecutionsAll BIGINT NULL,
	AvgDurationMsAll DECIMAL(18,2) NULL,
	AvgReadsAll DECIMAL(18,2) NULL
);

WHILE @ExecutionCounter <= @ValidationExecutions
BEGIN
	INSERT #ValidationSink
	EXEC dbo.QS_ProductSales @ProductID = @ValidationProductId;

	TRUNCATE TABLE #ValidationSink;
	SET @ExecutionCounter += 1;
END;

INSERT #PlanAll (PlanId, ExecutionsAll, AvgDurationMsAll, AvgReadsAll)
SELECT
	p.plan_id,
	SUM(rs.count_executions) AS executions_all,
	CAST(AVG(rs.avg_duration / 1000.0) AS DECIMAL(18,2)) AS avg_duration_ms_all,
	CAST(AVG(rs.avg_logical_io_reads) AS DECIMAL(18,2)) AS avg_reads_all
FROM sys.query_store_plan AS p
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE p.query_id = @QueryId
GROUP BY p.plan_id;

INSERT #ForcedAfter (PlanId, ExecutionsAfter, AvgDurationMsAfter, AvgReadsAfter)
SELECT
	p.plan_id,
	SUM(rs.count_executions) AS executions_after,
	CAST(AVG(rs.avg_duration / 1000.0) AS DECIMAL(18,2)) AS avg_duration_ms_after,
	CAST(AVG(rs.avg_logical_io_reads) AS DECIMAL(18,2)) AS avg_reads_after
FROM sys.query_store_plan AS p
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE p.query_id = @QueryId
  AND p.plan_id = @ForcedPlanId
  AND rsi.end_time >= @ValidationStartUtc
GROUP BY p.plan_id;

INSERT #Baseline (PlanId, ExecutionsAll, AvgDurationMsAll, AvgReadsAll)
SELECT
	pa.PlanId,
	pa.ExecutionsAll,
	pa.AvgDurationMsAll,
	pa.AvgReadsAll
FROM #PlanAll AS pa
WHERE pa.PlanId = @ForcedPlanId;

INSERT #Regressed (PlanId, ExecutionsAll, AvgDurationMsAll, AvgReadsAll)
SELECT TOP (1)
	pa.PlanId,
	pa.ExecutionsAll,
	pa.AvgDurationMsAll,
	pa.AvgReadsAll
FROM #PlanAll AS pa
WHERE pa.PlanId <> @ForcedPlanId
ORDER BY pa.AvgReadsAll DESC, pa.AvgDurationMsAll DESC;

SELECT
	N'Plan Metrics' AS [Section],
	N'Baseline forced plan history' AS [Stage],
	b.PlanId AS [Plan Id],
	b.ExecutionsAll AS [Executions],
	b.AvgDurationMsAll AS [Avg Duration Ms],
	b.AvgReadsAll AS [Avg Logical Reads]
FROM #Baseline AS b

UNION ALL

SELECT
	N'Plan Metrics' AS [Section],
	N'Regressed worst alternative plan' AS [Stage],
	r.PlanId AS [Plan Id],
	r.ExecutionsAll AS [Executions],
	r.AvgDurationMsAll AS [Avg Duration Ms],
	r.AvgReadsAll AS [Avg Logical Reads]
FROM #Regressed AS r

UNION ALL

SELECT
	N'Plan Metrics' AS [Section],
	N'After forced plan new runs' AS [Stage],
	@ForcedPlanId AS [Plan Id],
	f.ExecutionsAfter AS [Executions],
	f.AvgDurationMsAfter AS [Avg Duration Ms],
	f.AvgReadsAfter AS [Avg Logical Reads]
FROM #ForcedAfter AS f;

SELECT
	N'Comparison' AS [Section],
	N'Duration Delta Vs Baseline ms' AS [Metric],
	CAST((f.AvgDurationMsAfter - b.AvgDurationMsAll) AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Baseline AS b

UNION ALL

SELECT
	N'Comparison' AS [Section],
	N'Duration Delta Vs Regressed ms' AS [Metric],
	CAST((f.AvgDurationMsAfter - r.AvgDurationMsAll) AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Regressed AS r

UNION ALL

SELECT
	N'Comparison' AS [Section],
	N'Duration Improvement Vs Regressed pct' AS [Metric],
	CAST(((r.AvgDurationMsAll - f.AvgDurationMsAfter) / NULLIF(r.AvgDurationMsAll, 0)) * 100.0 AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Regressed AS r

UNION ALL

SELECT
	N'Comparison' AS [Section],
	N'Reads Delta Vs Baseline' AS [Metric],
	CAST((f.AvgReadsAfter - b.AvgReadsAll) AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Baseline AS b

UNION ALL

SELECT
	N'Comparison' AS [Section],
	N'Reads Delta Vs Regressed' AS [Metric],
	CAST((f.AvgReadsAfter - r.AvgReadsAll) AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Regressed AS r

UNION ALL

SELECT
	N'Comparison' AS [Section],
	N'Reads Improvement Vs Regressed pct' AS [Metric],
	CAST(((r.AvgReadsAll - f.AvgReadsAfter) / NULLIF(r.AvgReadsAll, 0)) * 100.0 AS DECIMAL(18,2)) AS [Value]
FROM #ForcedAfter AS f
CROSS JOIN #Regressed AS r;

SELECT
	N'Validation input check' AS [Section],
	N'Is Forced' AS [Metric],
	CAST(p.is_forced_plan AS DECIMAL(18,2)) AS [Value]
FROM sys.query_store_plan AS p
WHERE p.query_id = @QueryId
  AND p.plan_id = @ForcedPlanId

UNION ALL

SELECT
	N'Validation input check' AS [Section],
	N'Force Failure Count' AS [Metric],
	CAST(p.force_failure_count AS DECIMAL(18,2)) AS [Value]
FROM sys.query_store_plan AS p
WHERE p.query_id = @QueryId
  AND p.plan_id = @ForcedPlanId

UNION ALL

SELECT
	N'Validation input check' AS [Section],
	N'Regressed Plan Found' AS [Metric],
	CAST(CASE WHEN EXISTS (SELECT 1 FROM #Regressed) THEN 1 ELSE 0 END AS DECIMAL(18,2)) AS [Value];
GO
