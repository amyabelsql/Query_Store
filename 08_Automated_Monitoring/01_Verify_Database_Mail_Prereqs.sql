/*
    The monitoring job in this folder alerts by calling
    msdb.dbo.sp_send_dbmail directly from the stored procedures in
    02_Monitoring_Procedures.sql. That requires Database Mail to be
    enabled and a working profile to already exist. Run this script to
    check state before creating anything in 02 or 03.

    Database Mail setup is an instance-level, environment-specific
    decision (SMTP relay, credentials), so this script only checks and
    tests. It does not create an account/profile for you. The commented
    template at the bottom shows the shape if you need one.
*/

-- Is Database Mail XPs enabled?
SELECT
    name AS [Name],
    value_in_use AS [Value In Use]
FROM sys.configurations
WHERE name = 'Database Mail XPs';
GO

-- If value_in_use = 0, enable it:
-- EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
-- EXEC sp_configure 'Database Mail XPs', 1; RECONFIGURE;
-- EXEC sp_configure 'show advanced options', 0; RECONFIGURE;

-- What profiles and accounts already exist?
SELECT
    profile_id AS [Profile Id],
    name AS [Name],
    description AS [Description]
FROM msdb.dbo.sysmail_profile;
GO

SELECT
    account_id AS [Account Id],
    name AS [Name],
    email_address AS [Email Address],
    mailserver_type AS [Mail Server Type]
FROM msdb.dbo.sysmail_account;
GO

-- Is the SQL Server Agent service account able to use Database Mail?
-- (SQL Server Agent must be running, and MSDB must have Database Mail
-- profile access, this is normally automatic once a profile exists.)
SELECT is_enabled AS [Enabled] FROM msdb.dbo.sysmail_configuration
WHERE paramname = 'DatabaseMailEnabled';
GO

-- Sends a test message once you have a profile name. Replace
-- @profile_name and @recipients, then check delivery status with the
-- query below.
/*
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'<your Database Mail profile>',
    @recipients   = N'dba-team@example.com',
    @subject      = N'Query Store monitoring - test message',
    @body         = N'If you received this, Database Mail is working.';
*/

SELECT TOP (10)
    mailitem_id AS [Mail Item Id],
    subject AS [Subject],
    sent_status AS [Sent Status],
    sent_date AS [Sent Date],
    last_mod_date AS [Last Modified]
FROM msdb.dbo.sysmail_allitems
ORDER BY mailitem_id DESC;
GO

/*
    Template: create a new account + profile if none exists. Fill in
    your SMTP server details and run manually. Not part of the
    repeatable monitoring setup because credentials are
    environment-specific.

EXEC msdb.dbo.sysmail_add_account_sp
    @account_name    = N'Query Store Monitoring',
    @email_address   = N'sqlagent@example.com',
    @mailserver_name = N'smtp.example.com';

EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = N'Query Store Monitoring';

EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name   = N'Query Store Monitoring',
    @account_name   = N'Query Store Monitoring',
    @sequence_number = 1;

-- Grants the msdb DatabaseMailUserRole to the SQL Server Agent service
-- account (or makes the profile public) so the Agent job can send mail:
EXEC msdb.dbo.sysmail_add_principalprofile_sp
    @profile_name    = N'Query Store Monitoring',
    @principal_name  = N'public',
    @is_default      = 1;
*/
