# 08 - Automated Monitoring

Sets up Query Store alerts for space/state, regressed queries, and performance thresholds.

## What the alerts cover

| Alert | Catches |
|---|---|
| Space / state | Query Store changed mode or is near its size limit |
| Regressed queries | A query got slower than its prior interval |
| Performance thresholds | A query is slow right now, even with no prior baseline |

## Setup

1. Finish [01_Setup](../01_Setup/) and [02_Generate_Workload](../02_Generate_Workload/).
2. Run [01_Verify_Database_Mail_Prereqs.sql](01_Verify_Database_Mail_Prereqs.sql).
3. Run [02_Monitoring_Procedures.sql](02_Monitoring_Procedures.sql) in `msdb`.
4. Edit `@MailProfile` and `@Recipients` in [03_Create_Agent_Job.sql](03_Create_Agent_Job.sql), then run it.

The procedures live in `msdb` because they scan every Query Store-enabled database on the instance.

## Trigger an alert manually

```sql
EXEC msdb.dbo.usp_QS_CheckSpace
    @MailProfile = N'<your Database Mail profile>',
    @Recipients = N'dba-team@example.com',
    @WarningPercent = 0.01;

EXEC msdb.dbo.usp_QS_CheckRegressedQueries
    @MailProfile = N'<your Database Mail profile>',
    @Recipients = N'dba-team@example.com',
    @RegressionThresholdPct = 10.0;

EXEC msdb.dbo.usp_QS_CheckPerformance
    @MailProfile = N'<your Database Mail profile>',
    @Recipients = N'dba-team@example.com',
    @LookbackMinutes = 30,
    @DurationThresholdMs = 1,
    @CpuThresholdMs = 1;
```

Or start the job directly:

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Space';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Regressed Queries';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Performance';
```

The low thresholds above (`@WarningPercent`, `@DurationThresholdMs`, `@CpuThresholdMs`) are there to force an alert to fire on demand instead of waiting on real data.

## From alert to fix

| Alert | Next stop | Common fix |
|---|---|---|
| Space / state | [07_Production_Runbook](../07_Production_Runbook/) health checks | Clean up old data, increase quota, reduce ad hoc capture |
| Regressed query | [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/) or the runbook regression query | Force the last good plan, then fix index or stats issues |
| Performance threshold | Runbook top queries and wait stats | Tune the hot query, reduce locking, or fix IO/memory pressure |

## Related

- [07_Production_Runbook](../07_Production_Runbook/) - investigate the alert
- [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/) - easiest way to show a bad plan and recovery
- [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) - production guidance behind the thresholds
