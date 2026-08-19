/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS). Every
    CREATE is CREATE OR ALTER, safe to re-run. Nothing here sends mail
    by itself, it only creates the function, table, and procedures that
    03_Create_Agent_Job.sql schedules.

    1. Creates a helper function listing every database that has Query
       Store enabled, so all checks agree on what to scan
    2. Creates a table tracking which plans were forced last time
       usp_QS_CheckForcedPlanChanges ran
    3. Creates the space/state check, alerts when a database's actual
       and desired state have drifted apart, or storage is past
       @WarningPercent of quota
    4. Creates the regressed query check, alerts when a query's most
       recent interval is @RegressionThresholdPct slower than the one
       before it
    5. Creates the resource threshold check, alerts when a query exceeds
       @DurationThresholdMs or @CpuThresholdMs
    6. Creates the forced plan failure check, alerts when a forced plan
       has stopped applying (force_failure_count > 0)
    7. Creates the forced plan change check, alerts when a plan gets
       forced or unforced since the last run, and lists every plan
       currently forced
    8. Creates a wrapper procedure that runs all five checks in one call

    Each check scans every database on the instance with Query Store
    enabled, not a single named database, and sends one Database Mail
    message per check listing every database that breached its
    threshold. A clean run sends nothing.

    Created in msdb rather than a user database because each check
    queries across databases via dynamic, three-part-named SQL (e.g.
    [SomeDb].sys.query_store_query). There's no single user database
    that's the natural home for that.

    Permissions: the account the checks run as (the SQL Server Agent
    service account, or the job's proxy/owner) needs access to the Query
    Store catalog views in every database being monitored. Membership in
    the sysadmin fixed server role is the simplest way to guarantee that
    for a monitoring job. A lighter-weight alternative is db_datareader
    (or VIEW DATABASE STATE) granted in each monitored database.

    Run 01_Verify_Database_Mail_Prereqs.sql first, to confirm Database
    Mail is enabled and a profile exists.

    A clean run creates the objects silently, there's nothing to check
    here. To confirm they actually work, run one manually (see
    00_Monitoring_Doc.md's "Trigger an alert manually" section) with a
    low threshold so it's guaranteed to send mail.
*/

USE [msdb];
GO

-- 1. Helper: which databases should be checked
-- Centralized here so every check agrees on what "a database using
-- Query Store" means.
CREATE OR ALTER FUNCTION dbo.udf_QSMonitoredDatabases()
RETURNS TABLE
AS
RETURN
(
    SELECT name AS database_name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
        AND is_query_store_on = 1
);
GO

-- 2. Helper: last known set of forced plans
-- usp_QS_CheckForcedPlanChanges compares the current set of forced
-- plans against this table to detect what changed since it last ran,
-- then overwrites it with the current set.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'QS_ForcedPlanSnapshot' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.QS_ForcedPlanSnapshot (
        database_name SYSNAME NOT NULL,
        query_id BIGINT NOT NULL,
        plan_id BIGINT NOT NULL,
        CONSTRAINT PK_QS_ForcedPlanSnapshot PRIMARY KEY (database_name, query_id, plan_id)
    );
END
GO

-- 3. Space and state check
-- Alerts, per database, when actual_state has drifted from desired_state
-- (Query Store silently changed mode) or storage is past @WarningPercent
-- of quota.
CREATE OR ALTER PROCEDURE dbo.usp_QS_CheckSpace
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @WarningPercent DECIMAL(5, 2) = 80.0
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #space (
        database_name SYSNAME,
        actual_state_desc NVARCHAR(60),
        desired_state_desc NVARCHAR(60),
        current_storage_size_mb DECIMAL(18, 2),
        max_storage_size_mb DECIMAL(18, 2)
    );

    DECLARE @DbName SYSNAME, @Sql NVARCHAR(MAX);
    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM dbo.udf_QSMonitoredDatabases();
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'SELECT ' + QUOTENAME(@DbName, N'''') + N' AS database_name,
                actual_state_desc, desired_state_desc, current_storage_size_mb, max_storage_size_mb
            FROM ' + QUOTENAME(@DbName) + N'.sys.database_query_store_options;';

        INSERT INTO #space (database_name, actual_state_desc, desired_state_desc, current_storage_size_mb, max_storage_size_mb)
        EXEC (@Sql);

        FETCH NEXT FROM db_cursor INTO @DbName;
    END
    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @ReportLines NVARCHAR(MAX);
    SELECT @ReportLines = STRING_AGG(
        CONCAT(database_name, N': actual=', actual_state_desc, N', desired=', desired_state_desc,
               N', ', current_storage_size_mb, N' MB / ', max_storage_size_mb, N' MB (',
               CAST(CASE WHEN max_storage_size_mb > 0 THEN 100.0 * current_storage_size_mb / max_storage_size_mb ELSE 0 END AS DECIMAL(5, 2)),
               N'%)'),
        NCHAR(13) + NCHAR(10)
    ) WITHIN GROUP (ORDER BY database_name)
    FROM #space
    WHERE actual_state_desc <> desired_state_desc
        OR (max_storage_size_mb > 0 AND 100.0 * current_storage_size_mb / max_storage_size_mb >= @WarningPercent);

    IF @ReportLines IS NOT NULL
    BEGIN
        DECLARE @Subject NVARCHAR(200) = N'Query Store alert: space/state (' + CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) + N')';
        DECLARE @Body NVARCHAR(MAX) =
            N'Warning threshold: ' + CAST(@WarningPercent AS NVARCHAR(10)) + N'%' + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10) + @ReportLines;

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @MailProfile,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @Body;
    END
END
GO

-- 4. Regressed query check
-- Alerts, per database, when any query's most recent interval is at
-- least @RegressionThresholdPct slower, on average, than the interval
-- before it. @TopN caps how many regressed queries are reported per
-- database, not across the whole instance.
CREATE OR ALTER PROCEDURE dbo.usp_QS_CheckRegressedQueries
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @RegressionThresholdPct DECIMAL(5, 2) = 50.0,
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #regressions (
        database_name SYSNAME,
        query_id BIGINT,
        query_sql_text NVARCHAR(4000),
        prev_avg_duration_ms DECIMAL(18, 2),
        current_avg_duration_ms DECIMAL(18, 2),
        pct_change DECIMAL(10, 2)
    );

    DECLARE @DbName SYSNAME, @Sql NVARCHAR(MAX);
    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM dbo.udf_QSMonitoredDatabases();
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N';WITH ranked_intervals AS (
                SELECT q.query_id, qt.query_sql_text, rsi.start_time, rs.avg_duration,
                       ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rsi.start_time DESC) AS interval_rank
                FROM ' + QUOTENAME(@DbName) + N'.sys.query_store_query AS q
                JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
                JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_plan AS p ON p.query_id = q.query_id
                JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
                JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_runtime_stats_interval AS rsi
                    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
            )
            SELECT TOP (@TopN)
                ' + QUOTENAME(@DbName, N'''') + N' AS database_name,
                cur.query_id, cur.query_sql_text,
                prev.avg_duration / 1000.0 AS prev_avg_duration_ms,
                cur.avg_duration / 1000.0 AS current_avg_duration_ms,
                CAST(100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) AS DECIMAL(10, 2)) AS pct_change
            FROM ranked_intervals AS cur
            JOIN ranked_intervals AS prev
                ON cur.query_id = prev.query_id AND prev.interval_rank = cur.interval_rank + 1
            WHERE cur.interval_rank = 1
                AND cur.avg_duration > prev.avg_duration
                AND 100.0 * (cur.avg_duration - prev.avg_duration) / NULLIF(prev.avg_duration, 0) >= @Threshold
            ORDER BY pct_change DESC;';

        INSERT INTO #regressions (database_name, query_id, query_sql_text, prev_avg_duration_ms, current_avg_duration_ms, pct_change)
        EXEC sp_executesql @Sql, N'@Threshold DECIMAL(5, 2), @TopN INT', @Threshold = @RegressionThresholdPct, @TopN = @TopN;

        FETCH NEXT FROM db_cursor INTO @DbName;
    END
    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @ReportLines NVARCHAR(MAX);
    SELECT @ReportLines = STRING_AGG(
        CONCAT(database_name, N' / query_id ', query_id, N': ', prev_avg_duration_ms, N' ms -> ', current_avg_duration_ms,
               N' ms (+', pct_change, N'%)', NCHAR(13), NCHAR(10), LEFT(query_sql_text, 200)),
        NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
    ) WITHIN GROUP (ORDER BY pct_change DESC)
    FROM #regressions;

    IF @ReportLines IS NOT NULL
    BEGIN
        DECLARE @Subject NVARCHAR(200) = N'Query Store alert: regressed queries (' + CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) + N')';
        DECLARE @Body NVARCHAR(MAX) =
            N'Threshold: ' + CAST(@RegressionThresholdPct AS NVARCHAR(10)) + N'% slower than the prior interval' +
            NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10) + @ReportLines;

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @MailProfile,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @Body;
    END
END
GO

-- 5. Resource threshold check
-- Alerts, per database, when any query executed in the last
-- @LookbackMinutes exceeded @DurationThresholdMs average duration or
-- @CpuThresholdMs average CPU time. Catches new slow queries that aren't
-- regressions (no prior interval to compare against, e.g. right after a
-- deployment).
CREATE OR ALTER PROCEDURE dbo.usp_QS_CheckPerformance
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @LookbackMinutes INT = 30,
    @DurationThresholdMs INT = 5000,
    @CpuThresholdMs INT = 5000,
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #offenders (
        database_name SYSNAME,
        query_id BIGINT,
        query_sql_text NVARCHAR(4000),
        avg_duration_ms DECIMAL(18, 2),
        avg_cpu_time_ms DECIMAL(18, 2),
        count_executions BIGINT
    );

    DECLARE @DbName SYSNAME, @Sql NVARCHAR(MAX);
    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM dbo.udf_QSMonitoredDatabases();
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'SELECT TOP (@TopN)
                ' + QUOTENAME(@DbName, N'''') + N' AS database_name,
                q.query_id, qt.query_sql_text,
                rs.avg_duration / 1000.0 AS avg_duration_ms,
                rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms,
                rs.count_executions
            FROM ' + QUOTENAME(@DbName) + N'.sys.query_store_query AS q
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_plan AS p ON p.query_id = q.query_id
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_runtime_stats_interval AS rsi
                ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
            WHERE rsi.start_time >= DATEADD(MINUTE, -@LookbackMinutes, GETUTCDATE())
                AND (rs.avg_duration / 1000.0 >= @DurationThresholdMs OR rs.avg_cpu_time / 1000.0 >= @CpuThresholdMs)
            ORDER BY rs.avg_duration DESC;';

        INSERT INTO #offenders (database_name, query_id, query_sql_text, avg_duration_ms, avg_cpu_time_ms, count_executions)
        EXEC sp_executesql @Sql,
            N'@TopN INT, @LookbackMinutes INT, @DurationThresholdMs INT, @CpuThresholdMs INT',
            @TopN = @TopN, @LookbackMinutes = @LookbackMinutes,
            @DurationThresholdMs = @DurationThresholdMs, @CpuThresholdMs = @CpuThresholdMs;

        FETCH NEXT FROM db_cursor INTO @DbName;
    END
    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @ReportLines NVARCHAR(MAX);
    SELECT @ReportLines = STRING_AGG(
        CONCAT(database_name, N' / query_id ', query_id, N': ', avg_duration_ms, N' ms avg duration, ', avg_cpu_time_ms,
               N' ms avg CPU, ', count_executions, N' executions', NCHAR(13), NCHAR(10), LEFT(query_sql_text, 200)),
        NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
    ) WITHIN GROUP (ORDER BY avg_duration_ms DESC)
    FROM #offenders;

    IF @ReportLines IS NOT NULL
    BEGIN
        DECLARE @Subject NVARCHAR(200) = N'Query Store alert: slow queries (' + CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) + N')';
        DECLARE @Body NVARCHAR(MAX) =
            N'Last ' + CAST(@LookbackMinutes AS NVARCHAR(10)) + N' min. Duration threshold: ' + CAST(@DurationThresholdMs AS NVARCHAR(10)) +
            N' ms. CPU threshold: ' + CAST(@CpuThresholdMs AS NVARCHAR(10)) + N' ms.' + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10) + @ReportLines;

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @MailProfile,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @Body;
    END
END
GO

-- 6. Forced plan failure check
-- Alerts, per database, when a forced plan has stopped applying at
-- least once (force_failure_count > 0), usually because a schema
-- change invalidated it and Query Store silently fell back to the
-- optimizer's normal choice.
CREATE OR ALTER PROCEDURE dbo.usp_QS_CheckForcedPlanFailures
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #failures (
        database_name SYSNAME,
        query_id BIGINT,
        plan_id BIGINT,
        force_failure_count INT,
        last_force_failure_reason_desc NVARCHAR(120),
        query_sql_text NVARCHAR(4000)
    );

    DECLARE @DbName SYSNAME, @Sql NVARCHAR(MAX);
    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM dbo.udf_QSMonitoredDatabases();
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'SELECT TOP (@TopN)
                ' + QUOTENAME(@DbName, N'''') + N' AS database_name,
                p.query_id, p.plan_id, p.force_failure_count, p.last_force_failure_reason_desc,
                qt.query_sql_text
            FROM ' + QUOTENAME(@DbName) + N'.sys.query_store_plan AS p
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query AS q ON p.query_id = q.query_id
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
            WHERE p.is_forced_plan = 1 AND p.force_failure_count > 0
            ORDER BY p.force_failure_count DESC;';

        INSERT INTO #failures (database_name, query_id, plan_id, force_failure_count, last_force_failure_reason_desc, query_sql_text)
        EXEC sp_executesql @Sql, N'@TopN INT', @TopN = @TopN;

        FETCH NEXT FROM db_cursor INTO @DbName;
    END
    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @ReportLines NVARCHAR(MAX);
    SELECT @ReportLines = STRING_AGG(
        CONCAT(database_name, N' / query_id ', query_id, N' / plan_id ', plan_id, N': ', force_failure_count,
               N' failure(s), last reason ', last_force_failure_reason_desc, NCHAR(13), NCHAR(10), LEFT(query_sql_text, 200)),
        NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
    ) WITHIN GROUP (ORDER BY force_failure_count DESC)
    FROM #failures;

    IF @ReportLines IS NOT NULL
    BEGIN
        DECLARE @Subject NVARCHAR(200) = N'Query Store alert: forced plan failures (' + CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) + N')';

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @MailProfile,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @ReportLines;
    END
END
GO

-- 7. Forced plan change check
-- Compares the plans forced right now against dbo.QS_ForcedPlanSnapshot
-- (the set as of the last run) and alerts if anything changed, a plan
-- got forced or unforced since then. The alert body also lists every
-- plan forced right now, so it doubles as a standing inventory. On the
-- very first run the snapshot is empty, so everything currently forced
-- shows up as "newly forced", that's expected, not a false alarm.
CREATE OR ALTER PROCEDURE dbo.usp_QS_CheckForcedPlanChanges
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #current_forced (
        database_name SYSNAME,
        query_id BIGINT,
        plan_id BIGINT,
        query_sql_text NVARCHAR(4000)
    );

    DECLARE @DbName SYSNAME, @Sql NVARCHAR(MAX);
    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM dbo.udf_QSMonitoredDatabases();
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'SELECT
                ' + QUOTENAME(@DbName, N'''') + N' AS database_name,
                p.query_id, p.plan_id, qt.query_sql_text
            FROM ' + QUOTENAME(@DbName) + N'.sys.query_store_plan AS p
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query AS q ON p.query_id = q.query_id
            JOIN ' + QUOTENAME(@DbName) + N'.sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
            WHERE p.is_forced_plan = 1;';

        INSERT INTO #current_forced (database_name, query_id, plan_id, query_sql_text)
        EXEC (@Sql);

        FETCH NEXT FROM db_cursor INTO @DbName;
    END
    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @NewlyForced NVARCHAR(MAX);
    SELECT @NewlyForced = STRING_AGG(
        CONCAT(c.database_name, N' / query_id ', c.query_id, N' / plan_id ', c.plan_id,
               NCHAR(13), NCHAR(10), LEFT(c.query_sql_text, 200)),
        NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
    )
    FROM #current_forced AS c
    LEFT JOIN dbo.QS_ForcedPlanSnapshot AS s
        ON s.database_name = c.database_name AND s.query_id = c.query_id AND s.plan_id = c.plan_id
    WHERE s.database_name IS NULL;

    DECLARE @NewlyUnforced NVARCHAR(MAX);
    SELECT @NewlyUnforced = STRING_AGG(
        CONCAT(s.database_name, N' / query_id ', s.query_id, N' / plan_id ', s.plan_id),
        NCHAR(13) + NCHAR(10)
    )
    FROM dbo.QS_ForcedPlanSnapshot AS s
    LEFT JOIN #current_forced AS c
        ON c.database_name = s.database_name AND c.query_id = s.query_id AND c.plan_id = s.plan_id
    WHERE c.database_name IS NULL;

    DECLARE @CurrentList NVARCHAR(MAX);
    SELECT @CurrentList = STRING_AGG(
        CONCAT(database_name, N' / query_id ', query_id, N' / plan_id ', plan_id),
        NCHAR(13) + NCHAR(10)
    ) WITHIN GROUP (ORDER BY database_name, query_id)
    FROM #current_forced;

    IF @NewlyForced IS NOT NULL OR @NewlyUnforced IS NOT NULL
    BEGIN
        DECLARE @Subject NVARCHAR(200) = N'Query Store alert: forced plan changed (' + CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) + N')';
        DECLARE @Body NVARCHAR(MAX) = N'';

        IF @NewlyForced IS NOT NULL
            SET @Body = @Body + N'Newly forced since last check:' + NCHAR(13) + NCHAR(10) + @NewlyForced + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10);

        IF @NewlyUnforced IS NOT NULL
            SET @Body = @Body + N'No longer forced since last check:' + NCHAR(13) + NCHAR(10) + @NewlyUnforced + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10);

        SET @Body = @Body + N'Currently forced (all):' + NCHAR(13) + NCHAR(10) + ISNULL(@CurrentList, N'(none)');

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @MailProfile,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @Body;
    END

    DELETE FROM dbo.QS_ForcedPlanSnapshot;
    INSERT INTO dbo.QS_ForcedPlanSnapshot (database_name, query_id, plan_id)
    SELECT database_name, query_id, plan_id FROM #current_forced;
END
GO

-- 8. Wrapper: runs all five checks in one call. 03_Create_Agent_Job.sql
-- creates both a separate job per check and one combined job that calls
-- this wrapper (disabled by default). Enable whichever mode you want,
-- not both, or the same breach will alert twice.
CREATE OR ALTER PROCEDURE dbo.usp_QS_RunAllChecks
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @SpaceWarningPercent DECIMAL(5, 2) = 80.0,
    @RegressionThresholdPct DECIMAL(5, 2) = 50.0,
    @PerfLookbackMinutes INT = 30,
    @DurationThresholdMs INT = 5000,
    @CpuThresholdMs INT = 5000,
    @ForcedFailureTopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_QS_CheckSpace
        @MailProfile = @MailProfile, @Recipients = @Recipients,
        @WarningPercent = @SpaceWarningPercent;

    EXEC dbo.usp_QS_CheckRegressedQueries
        @MailProfile = @MailProfile, @Recipients = @Recipients,
        @RegressionThresholdPct = @RegressionThresholdPct;

    EXEC dbo.usp_QS_CheckPerformance
        @MailProfile = @MailProfile, @Recipients = @Recipients,
        @LookbackMinutes = @PerfLookbackMinutes,
        @DurationThresholdMs = @DurationThresholdMs,
        @CpuThresholdMs = @CpuThresholdMs;

    EXEC dbo.usp_QS_CheckForcedPlanFailures
        @MailProfile = @MailProfile, @Recipients = @Recipients,
        @TopN = @ForcedFailureTopN;

    EXEC dbo.usp_QS_CheckForcedPlanChanges
        @MailProfile = @MailProfile, @Recipients = @Recipients;
END
GO
