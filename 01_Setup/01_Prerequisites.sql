/*
    Query Store prerequisites check. Read-only, changes nothing.
    Edition doesn't matter, the version does.

    1. SQL Server version (Query Store needs 2016, 13.x, or later)
    2. Whether this instance is in an Availability Group
    3. Trace flag 7745, only suggested if this instance is in an AG
    4. Trace flag 7752, only suggested on SQL Server 2016/2017 (13.x-14.x)
    5. Databases that already have Query Store on
*/

USE master;
GO

DECLARE @MajorVersion INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);
DECLARE @InAG BIT = CAST(SERVERPROPERTY('IsHadrEnabled') AS BIT);

DECLARE @TraceFlags TABLE (TraceFlag INT, Status BIT, Global BIT, Session BIT);
INSERT INTO @TraceFlags
EXEC('DBCC TRACESTATUS(7745, 7752) WITH NO_INFOMSGS');

DECLARE @TF7745 BIT = ISNULL((SELECT Status FROM @TraceFlags WHERE TraceFlag = 7745), 0);
DECLARE @TF7752 BIT = ISNULL((SELECT Status FROM @TraceFlags WHERE TraceFlag = 7752), 0);

-- Can Query Store even run here, and do the optional trace flags actually apply?
SELECT
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS [Product Version],
    CASE WHEN @MajorVersion >= 13 THEN 'Yes' ELSE 'NO -- upgrade to 2016 (13.x) or later' END AS [Query Store Supported],
    CASE WHEN @InAG = 1 THEN 'Yes' ELSE 'No' END AS [In Availability Group],
    CASE WHEN @InAG = 0 THEN 'N/A -- not in an AG'
         WHEN @TF7745 = 1 THEN 'Already on'
         ELSE 'Consider turning on' END AS [Trace Flag 7745 Recommendation],
    CASE WHEN @MajorVersion >= 15 THEN 'N/A -- 2019+ (15.x+) does this automatically'
         WHEN @TF7752 = 1 THEN 'Already on'
         ELSE 'Consider turning on' END AS [Trace Flag 7752 Recommendation];
GO

-- Databases that already have Query Store on
SELECT name AS [Databases With Query Store On]
FROM sys.databases
WHERE database_id > 4
  AND is_query_store_on = 1
ORDER BY name;
GO
