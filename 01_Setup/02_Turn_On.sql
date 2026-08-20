/*
    Run this whole script once, top to bottom (e.g. F5 in SSMS).

    1. Turns Query Store on (READ_WRITE) using SQL Server defaults
    2. Confirms the mode for each targeted database

    Options:
      - Set @ApplyToAllDatabases = 0 to target only @DatabaseName
      - Set @ApplyToAllDatabases = 1 to target all eligible user databases

    Run 03_Configure.sql next to set the thresholds this repo uses.
*/

USE master;
GO

DECLARE @ApplyToAllDatabases BIT = 1; -- 0 = one DB, 1 = all eligible user DBs
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- used when @ApplyToAllDatabases = 0
DECLARE @Sql NVARCHAR(MAX);
DECLARE @CurrentDatabase SYSNAME;
DECLARE @i INT = 1;
DECLARE @n INT;

DECLARE @Targets TABLE
(
    RowNum INT IDENTITY(1,1) PRIMARY KEY,
    DatabaseName SYSNAME NOT NULL
);

IF OBJECT_ID(N'tempdb..#Results', N'U') IS NOT NULL
    DROP TABLE #Results;

CREATE TABLE #Results
(
    [Database] SYSNAME NOT NULL,
    [Actual State] NVARCHAR(60) NULL,
    [Desired State] NVARCHAR(60) NULL,
    [Result] NVARCHAR(20) NOT NULL,
    [Error Message] NVARCHAR(4000) NULL
);

IF @ApplyToAllDatabases = 1
BEGIN
    INSERT @Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.database_id > 4               -- user databases only
      AND d.state_desc = N'ONLINE'
      AND d.is_read_only = 0
      AND d.source_database_id IS NULL;   -- exclude snapshots
END
ELSE
BEGIN
    IF DB_ID(@DatabaseName) IS NULL
        THROW 50001, 'Database in @DatabaseName does not exist.', 1;

    INSERT @Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.name = @DatabaseName
      AND d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.is_read_only = 0
      AND d.source_database_id IS NULL;
END;

IF NOT EXISTS (SELECT 1 FROM @Targets)
    THROW 50002, 'No eligible databases found to configure Query Store.', 1;

SELECT @n = COUNT(*) FROM @Targets;

-- Turns Query Store on in READ_WRITE mode per target database
WHILE @i <= @n
BEGIN
    SELECT @CurrentDatabase = t.DatabaseName
    FROM @Targets AS t
    WHERE t.RowNum = @i;

    BEGIN TRY
        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);';
        EXEC (@Sql);

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT
    DB_NAME() AS [Database],
    actual_state_desc AS [Actual State],
    desired_state_desc AS [Desired State],
    CAST(N''Success'' AS NVARCHAR(20)) AS [Result],
    CAST(NULL AS NVARCHAR(4000)) AS [Error Message]
FROM sys.database_query_store_options;';

        INSERT #Results
        EXEC (@Sql);
    END TRY
    BEGIN CATCH
        INSERT #Results ([Database], [Actual State], [Desired State], [Result], [Error Message])
        VALUES
        (
            @CurrentDatabase,
            NULL,
            NULL,
            N'Failed',
            ERROR_MESSAGE()
        );
    END CATCH;

    SET @i += 1;
END;

-- Confirmation for each targeted database
SELECT
    [Database],
    [Actual State],
    [Desired State],
    [Result],
    [Error Message]
FROM #Results
ORDER BY [Database];
GO
