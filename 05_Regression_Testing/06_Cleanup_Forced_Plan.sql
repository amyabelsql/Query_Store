/*
	Step 6 of 6: Cleanup forced plan.
	Unforces the plan that was forced in step 4.
*/

USE [AdventureWorks2022];
GO

DECLARE @QueryId BIGINT = <query_id>; -- Query Id from step 3
DECLARE @PlanId BIGINT = <plan_id>; -- Forced plan id from step 4

EXEC sys.sp_query_store_unforce_plan
	@query_id = @QueryId,
	@plan_id = @PlanId;

SELECT
	p.query_id AS [Query Id],
	p.plan_id AS [Plan Id],
	p.is_forced_plan AS [Forced],
	p.force_failure_count AS [Force Failure Count],
	p.last_force_failure_reason_desc AS [Last Force Failure Reason]
FROM sys.query_store_plan AS p
WHERE p.query_id = @QueryId
ORDER BY p.plan_id;
GO
