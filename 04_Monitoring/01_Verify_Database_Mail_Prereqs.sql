/*
	Run this script top to bottom.
	It checks Database Mail prerequisites used by monitoring jobs.
*/

SELECT
	name AS [Name],
	value_in_use AS [Value In Use]
FROM sys.configurations
WHERE name = 'Database Mail XPs';
GO

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

SELECT is_enabled AS [Enabled]
FROM msdb.dbo.sysmail_configuration
WHERE paramname = 'DatabaseMailEnabled';
GO

SELECT TOP (10)
	mailitem_id AS [Mail Item Id],
	subject AS [Subject],
	sent_status AS [Sent Status],
	sent_date AS [Sent Date],
	last_mod_date AS [Last Modified]
FROM msdb.dbo.sysmail_allitems
ORDER BY mailitem_id DESC;
GO
