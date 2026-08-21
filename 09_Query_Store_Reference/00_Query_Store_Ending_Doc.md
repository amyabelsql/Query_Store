# Query Store Ending Guide

This is a practical ending guide for Query Store operations.
Use it as a final reference.

## Turn Query Store off

```sql
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE = OFF;
```

Use off only when needed.
If Query Store is off, no new Query Store data is captured.

## Turn Query Store on

```sql
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE = ON;
```

## Set read only and read write

```sql
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE (OPERATION_MODE = READ_ONLY);
GO
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
```

## Clear Query Store data

```sql
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE CLEAR;
```

This removes Query Store history in that database.
Use with care.

## Flush in memory Query Store data to disk

```sql
EXEC sys.sp_query_store_flush_db;
```

Use this before backup if you need current Query Store data persisted.

## What to check first when there is an issue

- sys.database_query_store_options state and storage columns
- actual_state_desc and desired_state_desc mismatch
- current_storage_size_mb close to max_storage_size_mb
- query_capture_mode and stale_query_threshold_days
- force_failure_count and last_force_failure_reason_desc in sys.query_store_plan

## Common causes of Query Store issues

- Very high ad hoc query volume
- Low max storage size
- Query Store switched to read only due to size
- Metadata corruption or internal error state
- Frequent schema churn causing many recompiles
- Permission gaps for monitoring jobs

## Why a plan can become invalid

- Required index dropped
- Required index disabled
- Schema change affects objects used by the plan
- Query or object shape changed enough that the old plan cannot be replayed
- Query hints conflict with forced plan shape

## Why a forced plan may not work

- Plan is not actually forced
- Force failure count is increasing
- Last force failure reason shows no index or hint conflict
- Forced plan became incompatible after schema changes
- Optimizer cannot reproduce forced shape in current conditions

## Useful checks

```sql
SELECT
	qso.actual_state_desc,
	qso.desired_state_desc,
	qso.current_storage_size_mb,
	qso.max_storage_size_mb,
	qso.query_capture_mode_desc
FROM sys.database_query_store_options AS qso;
```

```sql
SELECT
	p.query_id,
	p.plan_id,
	p.is_forced_plan,
	p.force_failure_count,
	p.last_force_failure_reason_desc,
	p.last_execution_time
FROM sys.query_store_plan AS p
ORDER BY p.force_failure_count DESC, p.last_execution_time DESC;
```

## Final summary

Query Store is best used as a daily safety system.
Keep it on.
Keep it healthy.
Use forced plans to stabilize quickly.
Then fix the root cause and remove the force when safe.
