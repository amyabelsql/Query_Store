/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS).

    1. Turns Query Store on for @DatabaseName, using SQL Server's own
       default thresholds
    2. Confirms it's actually on and in the mode requested

    Change @DatabaseName below. Run 03_Configure.sql next to set the
    thresholds this repo uses.
*/

USE master;
GO

DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022';
DECLARE @Sql NVARCHAR(MAX);

-- Turns Query Store on in read/write mode, so it starts capturing now
SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);';
EXEC (@Sql);

-- Confirms it's actually on and in the mode we asked for
SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';
SELECT
    DB_NAME() AS [Database],
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State]
FROM sys.database_query_store_options;';
EXEC (@Sql);
GO
