/*
    Query Store Readiness Check
    Read-only. Makes no changes.

    Determines whether Query Store can be enabled on each user database
    and identifies anything that would prevent or impact it.

    Results
        1. Instance Overview
        2. User Databases Overview
        3. Findings and recommendations.

Severity
    Blocker - Must be fixed before enabling Query Store.
    Warning - Query Store will work but may become unhealthy.
    Note - Informational only.
    Ready - No issues found.
*/

USE master;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #TraceFlags;
DROP TABLE IF EXISTS #Databases;
DROP TABLE IF EXISTS #Findings;

-------------------------------------------------------------------------------
-- INSTANCE FACTS
-------------------------------------------------------------------------------

DECLARE @MajorVersion int = CONVERT(int, SERVERPROPERTY('ProductMajorVersion'));
DECLARE @IsAG bit = CONVERT(bit, SERVERPROPERTY('IsHadrEnabled'));
DECLARE @ProductVersion nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion'));
DECLARE @ProductLevel nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('ProductLevel'));
DECLARE @Edition nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('Edition'));

DECLARE @VersionName varchar(40) =
    CASE @MajorVersion
        WHEN 13 THEN 'SQL Server 2016'
        WHEN 14 THEN 'SQL Server 2017'
        WHEN 15 THEN 'SQL Server 2019'
        WHEN 16 THEN 'SQL Server 2022'
        WHEN 17 THEN 'SQL Server 2025'
        ELSE 'Major version ' + CONVERT(varchar(10), @MajorVersion)
END;

CREATE TABLE #TraceFlags
(
    TraceFlag int,
    Status bit,
    GlobalFlag bit,
    SessionFlag bit
);

DECLARE @TF7745 bit = 0;

IF @IsAG = 1
BEGIN
    INSERT #TraceFlags
    EXEC ('DBCC TRACESTATUS (7745) WITH NO_INFOMSGS');

SELECT @TF7745 =
       ISNULL((SELECT TOP (1) Status FROM #TraceFlags WHERE TraceFlag = 7745), 0);
END;

-------------------------------------------------------------------------------
-- DATABASE FACTS
-------------------------------------------------------------------------------

CREATE TABLE #Databases
(
    DatabaseName sysname NOT NULL PRIMARY KEY CLUSTERED,
    StateDesc nvarchar(60) NOT NULL,
    IsReadOnly bit NOT NULL,
    IsSnapshot bit NOT NULL,
    QueryStoreOn bit NOT NULL,
    SizeMB decimal(18,2) NULL,
    QSState nvarchar(60) NULL,
    QSUsedMB decimal(18,2) NULL,
    QSMaxMB decimal(18,2) NULL,
    QSReadOnlyReason int NULL
);

INSERT #Databases
    (DatabaseName, StateDesc, IsReadOnly, IsSnapshot, QueryStoreOn, SizeMB)
SELECT
    d.name,
    d.state_desc,
    d.is_read_only,
    CASE WHEN d.source_database_id IS NOT NULL THEN 1 ELSE 0 END,
    d.is_query_store_on,
    f.SizeMB
FROM sys.databases d
    OUTER APPLY
    (
        SELECT SUM(mf.size) / 128.0 AS SizeMB
        FROM sys.master_files mf
        WHERE mf.database_id = d.database_id
    ) f
WHERE d.database_id > 4;

-- Query Store settings live inside each database and there is no cross
-- database view of them, so they need one read per database. Driven by
-- a WHILE loop over the key, I do not like cursors.

DECLARE @DatabaseName sysname = N'';
DECLARE @Sql nvarchar(max);
DECLARE @QSState nvarchar(60);
DECLARE @QSUsedMB decimal(18,2);
DECLARE @QSMaxMB decimal(18,2);
DECLARE @QSReadOnlyReason int;

WHILE 1 = 1
BEGIN
SELECT TOP (1) @DatabaseName = DatabaseName
FROM #Databases
WHERE DatabaseName > @DatabaseName
  AND StateDesc = 'ONLINE'
  AND QueryStoreOn = 1
  AND HAS_DBACCESS(DatabaseName) = 1
ORDER BY DatabaseName;

IF @@ROWCOUNT = 0 BREAK;

    SET @QSState = NULL;
    SET @QSUsedMB = NULL;
    SET @QSMaxMB = NULL;
    SET @QSReadOnlyReason = NULL;

BEGIN TRY
SET @Sql =
            N'SELECT
                  @State = actual_state_desc,
                  @Used = current_storage_size_mb,
                  @Max = max_storage_size_mb,
                  @Reason = readonly_reason
              FROM ' + QUOTENAME(@DatabaseName) + N'.sys.database_query_store_options;';

EXEC sp_executesql
            @Sql,
            N'@State nvarchar(60) OUTPUT,
              @Used decimal(18,2) OUTPUT,
              @Max decimal(18,2) OUTPUT,
              @Reason int OUTPUT',
            @State = @QSState OUTPUT,
            @Used = @QSUsedMB OUTPUT,
            @Max = @QSMaxMB OUTPUT,
            @Reason = @QSReadOnlyReason OUTPUT;

UPDATE #Databases
SET QSState = @QSState,
    QSUsedMB = @QSUsedMB,
    QSMaxMB = @QSMaxMB,
    QSReadOnlyReason = @QSReadOnlyReason
WHERE DatabaseName = @DatabaseName;
END TRY
BEGIN CATCH
        -- Leave QSState null for this database. The findings below turn
        -- any database we could not read into a warning.
SET @QSState = NULL;
END CATCH;
END;

-------------------------------------------------------------------------------
-- FINDINGS
-------------------------------------------------------------------------------

-- Scope is either a database name or the literal 'Instance Check' for
-- findings that apply to the whole instance rather than one database.

CREATE TABLE #Findings
(
    SortOrder int NOT NULL,
    Scope sysname NOT NULL,
    Severity varchar(10) NOT NULL,
    Finding varchar(200) NOT NULL,
    Fix varchar(300) NOT NULL
);

-- Instance wide, applies to every database
IF @MajorVersion < 13
    INSERT #Findings
    VALUES (1, 'Instance Check', 'Blocker',
            'Query Store needs SQL Server 2016 or later.',
            'Upgrade the instance. Nothing else in this repo will run.');

IF @IsAG = 1
   AND EXISTS (SELECT 1
               FROM sys.dm_hadr_database_replica_states
               WHERE synchronization_health_desc <> 'HEALTHY')
    INSERT #Findings
    VALUES (2, 'Instance Check', 'Warning',
            'A replica in this Availability Group is not synchronizing.',
            'Query Store data reaches secondaries through the log. Fix sync before trusting it there.');

IF @IsAG = 1
   AND @TF7745 = 0
    INSERT #Findings
    VALUES (3, 'Instance Check', 'Note',
            'Trace flag 7745 is off.',
            'Turn on 7745 so failover does not wait for Query Store to flush. You lose unflushed data in trade for a faster failover.');

IF @MajorVersion = 13
    INSERT #Findings
    VALUES (3, 'Instance Check', 'Note',
            'Wait stats capture needs SQL Server 2017 or later.',
            'Query Store still works. You just will not get wait categories.');

-- Blockers
INSERT #Findings
SELECT 1, DatabaseName, 'Blocker',
       'Database is ' + StateDesc + '.',
       'Bring it online before enabling Query Store.'
FROM #Databases
WHERE StateDesc <> 'ONLINE';

INSERT #Findings
SELECT 1, DatabaseName, 'Blocker',
       'Database is read only.',
       'Query Store has nowhere to write. Set the database to READ_WRITE.'
FROM #Databases
WHERE IsReadOnly = 1
  AND IsSnapshot = 0;

INSERT #Findings
SELECT 1, DatabaseName, 'Blocker',
       'Database is a snapshot.',
       'Query Store cannot run on a snapshot. Use the source database instead.'
FROM #Databases
WHERE IsSnapshot = 1;

INSERT #Findings
SELECT 1, d.DatabaseName, 'Blocker',
       'A file in this database has reached its max size.',
       'Query Store writes into the database itself. Raise MAXSIZE or add a file.'
FROM #Databases d
WHERE EXISTS (SELECT 1
              FROM sys.master_files mf
              WHERE mf.database_id = DB_ID(d.DatabaseName)
                AND mf.max_size <> -1
                AND mf.size >= mf.max_size);

INSERT #Findings
SELECT 1, DatabaseName, 'Blocker',
       'Query Store is already on but in ERROR state.',
       'Run 03_Troubleshooting/11_Recover_From_Error_State.sql against this database.'
FROM #Databases
WHERE QSState = 'ERROR';

-- Warnings
INSERT #Findings
SELECT 2, DatabaseName, 'Warning',
       'Query Store is on but READ_ONLY, so it stopped capturing. readonly_reason = '
           + CONVERT(varchar(10), QSReadOnlyReason) + '.',
       'Usually the size quota. Raise MAX_STORAGE_SIZE_MB, then set OPERATION_MODE = READ_WRITE.'
FROM #Databases
WHERE QSState = 'READ_ONLY';

INSERT #Findings
SELECT 2, DatabaseName, 'Warning',
       'Query Store is using over 90 percent of its size quota.',
       'Raise MAX_STORAGE_SIZE_MB or it will flip to READ_ONLY and stop capturing.'
FROM #Databases
WHERE QSState = 'READ_WRITE'
  AND QSMaxMB > 0
  AND QSUsedMB * 100.0 / QSMaxMB > 90;

INSERT #Findings
SELECT 2, d.DatabaseName, 'Warning',
       'A file in this database has autogrowth turned off.',
       'Size it for the Query Store data you expect, or turn autogrowth on.'
FROM #Databases d
WHERE EXISTS (SELECT 1
              FROM sys.master_files mf
              WHERE mf.database_id = DB_ID(d.DatabaseName)
                AND mf.growth = 0);

-- Covers both a read that threw and a database HAS_DBACCESS skipped,
-- for example a secondary replica that is not readable.
INSERT #Findings
SELECT 2, DatabaseName, 'Warning',
       'Query Store is on but its settings could not be read.',
       'Check that the database is readable from this replica.'
FROM #Databases
WHERE QueryStoreOn = 1
  AND StateDesc = 'ONLINE'
  AND QSState IS NULL;

-- Notes
INSERT #Findings
SELECT 3, DatabaseName, 'Note',
       'Query Store is already on and capturing.',
       'Nothing to turn on. Skip 02_Turn_On.sql and go to 03_Configure.sql.'
FROM #Databases
WHERE QSState = 'READ_WRITE';

-- Anything with no findings at all is good to go. Skipped when the
-- instance itself is too old, since then nothing is ready.
INSERT #Findings
SELECT 4, d.DatabaseName, 'Ready',
       'Nothing blocking Query Store here.',
       'Run 02_Turn_On.sql against this database.'
FROM #Databases d
WHERE @MajorVersion >= 13
  AND NOT EXISTS (SELECT 1
                  FROM #Findings f
                  WHERE f.Scope = d.DatabaseName);

-------------------------------------------------------------------------------
-- RESULT 1 - INSTANCE OVERVIEW
-------------------------------------------------------------------------------

DECLARE @DatabaseCount int = (SELECT COUNT(*) FROM #Databases);

SELECT Item, Value
FROM
    (
        VALUES
            (10, 'SQL Server',
             CONVERT(varchar(120), @VersionName + ' (' + @ProductVersion + ' ' + @ProductLevel + ')')),
            (20, 'Edition', CONVERT(varchar(120), @Edition)),
            (30, 'Availability Group',
             CONVERT(varchar(120), CASE WHEN @IsAG = 1 THEN 'Yes' ELSE 'No' END)),
            (40, 'Trace Flag 7745',
             CONVERT(varchar(120),
                     CASE
                         WHEN @IsAG = 0 THEN 'N/A, not in an Availability Group'
                         WHEN @TF7745 = 1 THEN 'Enabled'
                         ELSE 'Disabled'
                         END)),
            (50, 'Databases Scanned', CONVERT(varchar(120), @DatabaseCount))
    ) AS o (SortOrder, Item, Value)
ORDER BY SortOrder;

-------------------------------------------------------------------------------
-- RESULT 2 - DATABASE OVERVIEW
-------------------------------------------------------------------------------

SELECT
    DatabaseName AS [Database],

    StateDesc + ', '
        + CASE WHEN IsReadOnly = 1 THEN 'READ_ONLY' ELSE 'READ_WRITE' END AS [State],

    CONVERT(decimal(18,0), SizeMB) AS [Size MB],

    CASE
        WHEN QueryStoreOn = 0 THEN 'Off'
        WHEN QSState IS NULL THEN 'On'
        ELSE 'On, ' + QSState
END AS [Query Store],

    CASE
        WHEN QueryStoreOn = 1 AND QSMaxMB > 0
        THEN CONVERT(varchar(20), QSUsedMB) + ' of '
             + CONVERT(varchar(20), QSMaxMB) + ' MB ('
             + CONVERT(varchar(10), CONVERT(decimal(5,1), QSUsedMB * 100.0 / QSMaxMB))
             + ' percent)'
        ELSE 'N/A'
END AS [Storage]
FROM #Databases
ORDER BY DatabaseName;

-------------------------------------------------------------------------------
-- RESULT 3 - RECOMMENDATIONS
-------------------------------------------------------------------------------

SELECT
    Scope,
    Severity,
    Finding,
    Fix
FROM #Findings
ORDER BY
    CASE WHEN Scope = 'Instance Check' THEN 0 ELSE 1 END,
    Scope,
    SortOrder,
    Finding;

DROP TABLE #TraceFlags;
DROP TABLE #Databases;
DROP TABLE #Findings;
GO
