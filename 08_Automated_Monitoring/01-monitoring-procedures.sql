/*
    Query Store monitoring procedures
    Three independent checks -- space/state, regressed queries, and
    resource thresholds -- plus a wrapper that runs all three. Each check
    scans every database on the instance that has Query Store enabled
    (sys.databases.is_query_store_on = 1), not a single named database,
    and sends one Database Mail message per check listing every database
    that breached its threshold. A clean run sends nothing.

    Created in msdb rather than a user database because each check
    queries across databases via dynamic, three-part-named SQL
    (e.g. [SomeDb].sys.query_store_query) -- there's no single user
    database that's the natural home for that.

    Permissions: the account the checks run as (the SQL Server Agent
    service account, or the job's proxy/owner) needs access to the Query
    Store catalog views in every database being monitored. Membership in
    the sysadmin fixed server role is the simplest way to guarantee that
    for a monitoring job; a lighter-weight alternative is db_datareader
    (or VIEW DATABASE STATE) granted in each monitored database.

    Prerequisite: Database Mail is enabled and @MailProfile exists. See
    00-verify-database-mail-prereqs.sql.
*/

USE [msdb];
GO

-- 0. Helper: which databases should be checked
-- Centralized here so all three checks (and any future one) agree on
-- what "a database using Query Store" means.
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

-- 1. Space and state check
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

-- 2. Regressed query check
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

-- 3. Resource threshold check
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

-- 4. Wrapper: runs all three checks in one call. 02-create-agent-job.sql
-- creates both a separate job per check and one combined job that calls
-- this wrapper (disabled by default) -- enable whichever mode you want,
-- not both, or the same breach will alert twice.
CREATE OR ALTER PROCEDURE dbo.usp_QS_RunAllChecks
    @MailProfile NVARCHAR(128),
    @Recipients NVARCHAR(400),
    @SpaceWarningPercent DECIMAL(5, 2) = 80.0,
    @RegressionThresholdPct DECIMAL(5, 2) = 50.0,
    @PerfLookbackMinutes INT = 30,
    @DurationThresholdMs INT = 5000,
    @CpuThresholdMs INT = 5000
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
END
GO
