# 06 - Monitoring

Sets up Query Store alerts for space/state, regressed queries, performance thresholds, forced plan failures, and forced plan changes.

## What the alerts cover

| Alert | Catches |
|---|---|
| Space / state | Query Store changed mode (e.g. went `READ_ONLY`) or is near its size limit |
| Regressed queries | A query got slower than its prior interval |
| Performance thresholds | A query is slow right now, even with no prior baseline |
| Forced plan failures | A forced plan stopped applying, usually a schema change invalidated it |
| Forced plan changes | Someone forced or unforced a plan since the last check, also lists everything currently forced |

## Setup

Finish [01_Setup](../01_Setup/) and [02_Generate_Workload](../02_Generate_Workload/) first.

| Step | What it does |
|---|---|
| [01_Verify_Database_Mail_Prereqs.sql](01_Verify_Database_Mail_Prereqs.sql) | Confirms Database Mail is set up before the alerts need it |
| [02_Monitoring_Procedures.sql](02_Monitoring_Procedures.sql) | Creates the alert procedures (and a small tracking table for forced-plan changes) in `msdb`, since they scan every Query Store-enabled database on the instance |
| [03_Create_Agent_Job.sql](03_Create_Agent_Job.sql) | Schedules the SQL Agent jobs, after you edit `@MailProfile` and `@Recipients` in it |

## What each query shows you

| Query | Shows | Look for |
|---|---|---|
| 01, Database Mail XPs | Whether the feature is turned on at the instance level | `Value In Use` should be 1 |
| 01, profiles and accounts | What's already configured | An empty result means you need to create a profile/account using the template at the bottom of the file |
| 01, Agent mail access | Whether Database Mail is usable | `Enabled` should be 1 once a profile exists |
| 01, last 10 mail items | Delivery status after a test message | `Sent Status` should show `sent`, `unsent` or `failed` points at the mail/SMTP setup, not this script |
| 02 | Creates the monitoring function, tracking table, and procedures | No rows returned, a clean run is silent. Confirm it worked by running one procedure manually, see "Trigger an alert manually" below |
| 03 | Creates the SQL Agent jobs | No rows returned. Run the `Verify:` block commented out at the bottom of the file to confirm the jobs exist |

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

EXEC msdb.dbo.usp_QS_CheckForcedPlanFailures
    @MailProfile = N'<your Database Mail profile>',
    @Recipients = N'dba-team@example.com';

EXEC msdb.dbo.usp_QS_CheckForcedPlanChanges
    @MailProfile = N'<your Database Mail profile>',
    @Recipients = N'dba-team@example.com';
```

`usp_QS_CheckForcedPlanFailures` only sends mail if a forced plan has actually failed, force a plan and then drop the index it depends on (see `03_Troubleshooting/08_Simulate_And_Force_A_Regression.sql`'s bonus block) to see it fire. `usp_QS_CheckForcedPlanChanges` sends mail on its very first run against a database that has anything forced, since the tracking table starts empty, that's expected, not a bug.

Or start the job directly:

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Space';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Regressed Queries';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Performance';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Forced Plan Failures';
EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Forced Plan Changes';
```

The low thresholds above (`@WarningPercent`, `@DurationThresholdMs`, `@CpuThresholdMs`) are there to force an alert to fire on demand instead of waiting on real data.

## From alert to fix

| Alert | Next stop | Common fix |
|---|---|---|
| Space / state | [03_Troubleshooting](../03_Troubleshooting/) health checks | Clean up old data, increase quota, reduce ad hoc capture |
| Regressed query | [03_Troubleshooting](../03_Troubleshooting/) or the runbook regression query | Force the last good plan, then fix index or stats issues |
| Performance threshold | Runbook top queries and wait stats | Tune the hot query, reduce locking, or fix IO/memory pressure |
| Forced plan failure | [03_Troubleshooting](../03_Troubleshooting/) health checks, section 6 | Re-evaluate the plan, the schema likely changed underneath it, may need to unforce and force a fresh one |
| Forced plan change | [03_Troubleshooting/08_Simulate_And_Force_A_Regression.sql](../03_Troubleshooting/08_Simulate_And_Force_A_Regression.sql) | Confirm the change was intentional, forced plans are meant to be temporary, not permanent |

## Related

| Folder | Why |
|---|---|
| [03_Troubleshooting](../03_Troubleshooting/) | Investigate the alert once it fires, or run the guided lab to show a bad plan and recovery |
| [08_Best_Practices](../08_Best_Practices/) | Proactive guidance on choosing these thresholds in the first place |
| [05_Maintenance](../05_Maintenance/) | Cleanup actions and their impacts |
