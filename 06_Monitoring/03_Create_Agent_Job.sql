/*
    Edit @MailProfile and @Recipients in each of the 6 job sections
    below before running this, they default to placeholder text. Once
    edited, run the whole script once, top to bottom (e.g. F5 in SSMS).
    Safe to re-run afterward, each block drops and recreates its job so
    edits to the schedule or parameters take effect.

    1. Creates the space/state job, every 15 minutes
    2. Creates the regressed queries job, every 30 minutes
    3. Creates the performance thresholds job, every 30 minutes
    4. Creates the forced plan failures job, every 30 minutes
    5. Creates the forced plan changes job, every 15 minutes
    6. Creates the combined "All Checks" job, every 30 minutes, disabled
       by default

    Run either the five individual jobs or the combined job, not both,
    running both would alert twice for the same breach. The combined job
    is created disabled (@enabled = 0) for that reason, enable it and
    disable the other five if you'd rather manage one job than five.

    Each job scans every database on the instance with Query Store
    enabled (see dbo.udf_QSMonitoredDatabases in
    02_Monitoring_Procedures.sql). There is no per-database job to
    create or maintain as databases are added or removed.

    Prerequisites:
      - 01_Verify_Database_Mail_Prereqs.sql confirms Database Mail works
      - 02_Monitoring_Procedures.sql has been run, it creates the
        objects these jobs call
      - SQL Server Agent service is running
      - The job's run-as context (SQL Server Agent service account, or a
        proxy/owner you assign) has access to the Query Store catalog
        views in every database being monitored, see the permissions
        note at the top of 02_Monitoring_Procedures.sql

    To confirm the jobs were created as expected, run the Verify: block
    of commented-out queries at the bottom of this file.
*/

USE [msdb];
GO

-- ============================================================
-- Job 1: Space / state
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - Space';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';
DECLARE @WarningPercent DECIMAL(5, 2) = 80.0;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

-- CHAR(39) (a single quote) is used to build the command instead of
-- doubled-quote literals, so the escaping is easy to verify by eye
-- rather than relying on nested '''' sequences.
DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_CheckSpace' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @WarningPercent = ' + CAST(@WarningPercent AS NVARCHAR(10)) + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs dbo.usp_QS_CheckSpace against every Query Store-enabled database on the instance ' +
        N'and alerts by Database Mail if any database''s state or storage usage is out of bounds.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Check Query Store space/state',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 15 minutes. Cheap check, worth catching quickly.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 15 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- ============================================================
-- Job 2: Regressed queries
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - Regressed Queries';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';
DECLARE @RegressionThresholdPct DECIMAL(5, 2) = 50.0;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_CheckRegressedQueries' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @RegressionThresholdPct = ' + CAST(@RegressionThresholdPct AS NVARCHAR(10)) + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs dbo.usp_QS_CheckRegressedQueries against every Query Store-enabled database on the ' +
        N'instance and alerts by Database Mail when a query regresses interval-over-interval.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Check for regressed queries',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 30 minutes. Matches the typical Query Store interval length,
-- so consecutive runs usually compare against a freshly closed interval.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 30 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 30,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- ============================================================
-- Job 3: Performance thresholds
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - Performance';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';
DECLARE @LookbackMinutes INT = 30;
DECLARE @DurationThresholdMs INT = 5000;
DECLARE @CpuThresholdMs INT = 5000;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_CheckPerformance' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @LookbackMinutes = ' + CAST(@LookbackMinutes AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @DurationThresholdMs = ' + CAST(@DurationThresholdMs AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @CpuThresholdMs = ' + CAST(@CpuThresholdMs AS NVARCHAR(10)) + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs dbo.usp_QS_CheckPerformance against every Query Store-enabled database on the ' +
        N'instance and alerts by Database Mail when a query exceeds a duration or CPU threshold.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Check performance thresholds',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 30 minutes; @LookbackMinutes above should match this interval so
-- the check has no gaps and no overlap.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 30 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 30,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- ============================================================
-- Job 4: Forced plan failures
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - Forced Plan Failures';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';
DECLARE @TopN INT = 10;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_CheckForcedPlanFailures' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @TopN = ' + CAST(@TopN AS NVARCHAR(10)) + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs dbo.usp_QS_CheckForcedPlanFailures against every Query Store-enabled database on ' +
        N'the instance and alerts by Database Mail when a forced plan has stopped applying.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Check for forced plan failures',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 30 minutes. Matches the other workload-driven checks.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 30 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 30,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- ============================================================
-- Job 5: Forced plan changes
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - Forced Plan Changes';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_CheckForcedPlanChanges' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs dbo.usp_QS_CheckForcedPlanChanges against every Query Store-enabled database on ' +
        N'the instance and alerts by Database Mail when a plan gets forced or unforced, someone stepped in ' +
        N'and manually pinned a plan. The alert also lists every plan currently forced.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Check for forced plan changes',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 15 minutes. Forcing a plan is a manual DBA action, not
-- workload-driven, worth catching quickly.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 15 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- ============================================================
-- Job 6: All checks combined (disabled by default; see the
-- warning at the top of this file about not running this
-- alongside the five individual jobs above)
-- ============================================================
DECLARE @JobName SYSNAME = N'Query Store Monitoring - All Checks';
DECLARE @MailProfile NVARCHAR(128) = N'<your Database Mail profile>';
DECLARE @Recipients NVARCHAR(400) = N'dba-team@example.com';
DECLARE @SpaceWarningPercent DECIMAL(5, 2) = 80.0;
DECLARE @RegressionThresholdPct DECIMAL(5, 2) = 50.0;
DECLARE @PerfLookbackMinutes INT = 30;
DECLARE @DurationThresholdMs INT = 5000;
DECLARE @CpuThresholdMs INT = 5000;
DECLARE @ForcedFailureTopN INT = 10;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

DECLARE @Q CHAR(1) = CHAR(39);
DECLARE @MailProfileEscaped NVARCHAR(128) = REPLACE(@MailProfile, @Q, @Q + @Q);
DECLARE @RecipientsEscaped NVARCHAR(400) = REPLACE(@Recipients, @Q, @Q + @Q);
DECLARE @JobId BINARY(16);
DECLARE @Command NVARCHAR(MAX) =
    N'EXEC dbo.usp_QS_RunAllChecks' + CHAR(13) + CHAR(10) +
    N'    @MailProfile = N' + @Q + @MailProfileEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @Recipients = N' + @Q + @RecipientsEscaped + @Q + N',' + CHAR(13) + CHAR(10) +
    N'    @SpaceWarningPercent = ' + CAST(@SpaceWarningPercent AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @RegressionThresholdPct = ' + CAST(@RegressionThresholdPct AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @PerfLookbackMinutes = ' + CAST(@PerfLookbackMinutes AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @DurationThresholdMs = ' + CAST(@DurationThresholdMs AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @CpuThresholdMs = ' + CAST(@CpuThresholdMs AS NVARCHAR(10)) + N',' + CHAR(13) + CHAR(10) +
    N'    @ForcedFailureTopN = ' + CAST(@ForcedFailureTopN AS NVARCHAR(10)) + N';';

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 0,  -- enable only if you disable the five individual jobs above
    @description = N'Runs dbo.usp_QS_RunAllChecks (space, regressed queries, performance, forced plan ' +
        N'failures, forced plan changes) against every Query Store-enabled database on the instance, in ' +
        N'one step. Disabled by default; do not enable alongside the individual per-check jobs.',
    @category_name = N'Database Maintenance',
    @job_id = @JobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobId,
    @step_name = N'Run all Query Store checks',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @command = @Command,
    @retry_attempts = 2,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Every 30 minutes; @PerfLookbackMinutes above should match this interval.
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobId,
    @name = N'Every 30 minutes',
    @freq_type = 4,                 -- daily
    @freq_interval = 1,
    @freq_subday_type = 4,          -- minutes
    @freq_subday_interval = 30,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobId,
    @server_name = N'(local)';
GO

-- Verify:
-- SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'Query Store Monitoring -%';
-- EXEC msdb.dbo.sp_start_job @job_name = N'Query Store Monitoring - Space'; -- run one job on demand
-- SELECT j.name, h.run_date, h.run_time, h.run_status, h.message
-- FROM msdb.dbo.sysjobhistory AS h
-- JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
-- WHERE j.name LIKE N'Query Store Monitoring -%'
-- ORDER BY h.instance_id DESC;

-- Uninstall one job:
-- EXEC msdb.dbo.sp_delete_job @job_name = N'Query Store Monitoring - Space', @delete_unused_schedule = 1;

-- Uninstall all six:
-- DECLARE @j SYSNAME;
-- DECLARE job_cursor CURSOR FOR SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Query Store Monitoring -%';
-- OPEN job_cursor;
-- FETCH NEXT FROM job_cursor INTO @j;
-- WHILE @@FETCH_STATUS = 0
-- BEGIN
--     EXEC msdb.dbo.sp_delete_job @job_name = @j, @delete_unused_schedule = 1;
--     FETCH NEXT FROM job_cursor INTO @j;
-- END
-- CLOSE job_cursor;
-- DEALLOCATE job_cursor;
