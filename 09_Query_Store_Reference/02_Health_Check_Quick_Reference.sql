/*
	Query Store quick health checks
	Run in target user database
*/

SELECT
	qso.actual_state_desc,
	qso.desired_state_desc,
	qso.readonly_reason,
	qso.current_storage_size_mb,
	qso.max_storage_size_mb,
	qso.query_capture_mode_desc,
	qso.wait_stats_capture_mode_desc,
	qso.stale_query_threshold_days
FROM sys.database_query_store_options AS qso;
GO

SELECT
	p.query_id,
	p.plan_id,
	p.is_forced_plan,
	p.force_failure_count,
	p.last_force_failure_reason_desc,
	p.last_execution_time
FROM sys.query_store_plan AS p
ORDER BY p.force_failure_count DESC, p.last_execution_time DESC;
GO
