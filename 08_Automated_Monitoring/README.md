# 08 - Automated Monitoring

SQL Server Agent jobs that watch Query Store health across every
database on the instance and alert by Database Mail only when something
needs attention — no per-database setup as databases are added or
removed. Three checks run:

| Check | Alerts when | Default threshold |
|---|---|---|
| Space / state | A database's `actual_state_desc` differs from `desired_state_desc`, or storage usage crosses the warning percentage | 80% of `max_storage_size_mb` |
| Regressed queries | A query's most recent runtime-stats interval is meaningfully slower, on average, than the interval before it | 50% slower |
| Resource thresholds | Any query in the lookback window exceeds a duration or CPU threshold — catches new slow queries with no prior interval to regress against | 5000 ms avg duration or avg CPU |

Every check scans `sys.databases` for databases where
`is_query_store_on = 1` and runs against each one via dynamic,
three-part-named SQL (`[SomeDb].sys.query_store_query`, etc.). A clean
run sends no mail; a breach produces one email per check, per run,
listing every database and query involved — not one email per database.

## Jobs

| Job | Runs | Schedule |
|---|---|---|
| Query Store Monitoring - Space | `dbo.usp_QS_CheckSpace` | Every 15 minutes |
| Query Store Monitoring - Regressed Queries | `dbo.usp_QS_CheckRegressedQueries` | Every 30 minutes |
| Query Store Monitoring - Performance | `dbo.usp_QS_CheckPerformance` | Every 30 minutes |
| Query Store Monitoring - All Checks | `dbo.usp_QS_RunAllChecks` (all three above) | Every 30 minutes, **disabled by default** |

Run either the three individual jobs or the combined job — not both, or
a single breach alerts twice. Pick individual jobs if you want each
check's schedule, thresholds, or enabled/disabled state managed
separately (e.g. pause only the performance check during a known-noisy
deployment); pick the combined job if you'd rather manage one job than
three.

All thresholds are stored procedure parameters — see the `EXEC` calls in
[02-create-agent-job.sql](02-create-agent-job.sql) and
[01-monitoring-procedures.sql](01-monitoring-procedures.sql) to change
them.

## Setup

Run in order against your target instance:

1. [00-verify-database-mail-prereqs.sql](00-verify-database-mail-prereqs.sql) — confirms Database Mail is enabled and a profile exists; sends a test message. Stop here and configure Database Mail first if this fails.
2. [01-monitoring-procedures.sql](01-monitoring-procedures.sql) — creates `dbo.udf_QSMonitoredDatabases`, `dbo.usp_QS_CheckSpace`, `dbo.usp_QS_CheckRegressedQueries`, `dbo.usp_QS_CheckPerformance`, and the `dbo.usp_QS_RunAllChecks` wrapper in `msdb`.
3. [02-create-agent-job.sql](02-create-agent-job.sql) — creates the four SQL Server Agent jobs described above. Edit `@MailProfile` and `@Recipients` at the top of each job block before running.

The procedures live in `msdb`, not a named user database, because each
one queries across every Query Store-enabled database dynamically —
there's no single user database that's the natural home for that.

## Permissions

The job's run-as context (the SQL Server Agent service account, or a
proxy/job owner you assign) needs access to the Query Store catalog
views in every database being monitored, since the checks query them
with three-part names. Membership in the `sysadmin` fixed server role is
the simplest way to guarantee that; a lighter-weight alternative is
granting `db_datareader` (or `VIEW DATABASE STATE`) in each monitored
database.

## Operating notes

- Re-running `02-create-agent-job.sql` drops and recreates the jobs, so
  edits to a schedule, mail profile, or recipients take effect on
  re-run.
- Test a check on demand without waiting for the schedule:
  `EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Space';`
- Force an alert to verify email delivery end-to-end by temporarily
  lowering a threshold, e.g.
  `EXEC dbo.usp_QS_CheckPerformance @MailProfile = N'...', @Recipients = N'...', @DurationThresholdMs = 0;`
- To remove everything: run the "Uninstall all four" block at the bottom
  of `02-create-agent-job.sql`, then drop the four procedures and the
  function created in step 2.

## Related

- [07_Production_Runbook](../07_Production_Runbook/) — the same regression and health logic, as ad hoc queries against one database at a time for manual troubleshooting rather than a recurring, instance-wide alert
- [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) — the space/state thresholds here are the operational form of the configuration guidance there
- [09_Query_Store_On_Secondary_Replicas](../09_Query_Store_On_Secondary_Replicas/) — if your monitored databases are in an availability group, secondary replicas need their own consideration (SQL Server 2025+ preview)
