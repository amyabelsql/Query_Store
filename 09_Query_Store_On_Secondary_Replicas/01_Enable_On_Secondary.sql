/*
    Enables Query Store for readable secondary replicas (SQL Server
    2025+). Run this entire script while connected to the PRIMARY
    replica.

    Prerequisite: an Always On availability group must already be
    configured, with AdventureWorks2022 (or your target database) as a
    member database and at least one readable secondary replica. This
    script does not create the AG. See
    https://learn.microsoft.com/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server

    On SQL Server 2022: the FOR SECONDARY clause below does not exist in
    the parser at all until trace flag 12606 is enabled. Without it
    you'll get "Msg 102, Level 15, State 1: Incorrect syntax near 'FOR'."
    Step 0 turns it on. It must be enabled on the PRIMARY and EVERY
    readable secondary, not just the replica you're connected to.
    Microsoft documents this as limited preview on 2022, not supported
    in production. SQL Server 2025+ doesn't need this step.
*/

USE master;
GO

-- SQL Server 2022 only. Run this on the primary AND on every readable
-- secondary (connect to each one separately, DBCC TRACEON doesn't
-- propagate across replicas). -1 enables it instance-wide; it resets on
-- service restart, so re-run after any restart, or set -T12606 as a
-- startup parameter in SQL Server Configuration Manager for it to
-- survive restarts (that requires restarting the service once). Skip
-- this step entirely on SQL Server 2025+.
-- DBCC TRACEON (12606, -1);
-- GO

-- Query Store must be on and READ_WRITE on the primary first. No-op if
-- it's already enabled. See 01_Setup for the full setup.
ALTER DATABASE [AdventureWorks2022]
    SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
GO

-- Enables Query Store capture on every readable secondary replica.
-- Issued from the primary; applies across the replica set.
ALTER DATABASE [AdventureWorks2022]
    FOR SECONDARY
    SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE);
GO

-- Optional: lets automatic tuning force the last-known-good plan on
-- secondaries too, not just the primary.
ALTER DATABASE [AdventureWorks2022]
    FOR SECONDARY
    SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

PRINT 'Now connect to the SECONDARY replica and confirm actual_state_desc = READ_CAPTURE_SECONDARY:';
PRINT '  SELECT desired_state_desc, actual_state_desc, readonly_reason FROM sys.database_query_store_options;';
GO

-- To turn this back off, run on the primary, in master:
-- ALTER DATABASE [AdventureWorks2022]
--     FOR SECONDARY
--     SET QUERY_STORE = ON
--     (OPERATION_MODE = READ_ONLY);
-- GO
