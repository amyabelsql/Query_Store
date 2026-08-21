/*
    Not read-only. Recovery script for Query Store ERROR state.
    Run only when health checks show actual_state_desc = 'ERROR'.
*/

USE [master];
GO

DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = target one database, 1 = target all eligible user databases
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022'; -- target database name when @ApplyToAllDatabases = 0
DECLARE @Sql NVARCHAR(MAX); -- dynamic SQL command text
DECLARE @CurrentDatabase SYSNAME; -- current database being processed in loop

IF OBJECT_ID(N'tempdb..#Targets', N'U') IS NOT NULL DROP TABLE #Targets;
IF OBJECT_ID(N'tempdb..#Results', N'U') IS NOT NULL DROP TABLE #Results;
IF OBJECT_ID(N'tempdb..#State', N'U') IS NOT NULL DROP TABLE #State;

CREATE TABLE #Targets (DatabaseName SYSNAME NOT NULL PRIMARY KEY);

CREATE TABLE #Results
(
    [Database] SYSNAME NOT NULL,
    [Result] VARCHAR(20) NOT NULL,
    [Message] VARCHAR(4000) NULL
);

CREATE TABLE #State
(
    [Database] SYSNAME NOT NULL,
    [Actual State] VARCHAR(60) NULL
);

IF @ApplyToAllDatabases = 1
BEGIN
    INSERT #Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.source_database_id IS NULL;
END
ELSE
BEGIN
    IF DB_ID(@DatabaseName) IS NULL
        THROW 50001, 'Database in @DatabaseName does not exist.', 1;

    INSERT #Targets (DatabaseName)
    SELECT d.name
    FROM sys.databases AS d
    WHERE d.name = @DatabaseName
      AND d.database_id > 4
      AND d.state_desc = N'ONLINE'
      AND d.source_database_id IS NULL;
END;

IF NOT EXISTS (SELECT 1 FROM #Targets)
    THROW 50002, 'No eligible databases found for recovery.', 1;

WHILE EXISTS (SELECT 1 FROM #Targets)
BEGIN
    SELECT TOP (1) @CurrentDatabase = t.DatabaseName
    FROM #Targets AS t
    ORDER BY t.DatabaseName;

    DELETE FROM #Targets WHERE DatabaseName = @CurrentDatabase;

    BEGIN TRY
        DELETE FROM #State WHERE [Database] = @CurrentDatabase;

        SET @Sql = N'
USE ' + QUOTENAME(@CurrentDatabase) + N';
SELECT DB_NAME() AS [Database], actual_state_desc AS [Actual State]
FROM sys.database_query_store_options;';
        INSERT #State ([Database], [Actual State])
        EXEC (@Sql);

        IF EXISTS
        (
            SELECT 1
            FROM #State AS s
            WHERE s.[Database] = @CurrentDatabase
              AND s.[Actual State] <> N'ERROR'
        )
        BEGIN
            INSERT #Results ([Database], [Result], [Message])
            VALUES (@CurrentDatabase, N'Skipped', N'Query Store is not in ERROR state; no recovery action taken.');

            CONTINUE;
        END;

        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE = OFF;';
        EXEC (@Sql);

        SET @Sql = N'USE ' + QUOTENAME(@CurrentDatabase) + N'; EXEC sp_query_store_consistency_check;';
        EXEC (@Sql);

        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE = ON;';
        EXEC (@Sql);

        SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE (OPERATION_MODE = READ_WRITE);';
        EXEC (@Sql);

        INSERT #Results ([Database], [Result], [Message])
        VALUES (@CurrentDatabase, N'Success', N'Recovery completed.');
    END TRY
    BEGIN CATCH
        INSERT #Results ([Database], [Result], [Message])
        VALUES (@CurrentDatabase, N'Failed', ERROR_MESSAGE());
    END CATCH;
END;

SELECT [Database], [Result], [Message]
FROM #Results
ORDER BY [Database];
GO

SELECT [Database], [Actual State]
FROM #State
ORDER BY [Database];
GO
