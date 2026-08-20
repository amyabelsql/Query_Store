/*
    Do NOT just run this whole script at once. On SQL Server 2022 only,
    Step 0 has to run separately, on the PRIMARY and on EVERY readable
    secondary (connect to each one individually, it doesn't propagate).
    Skip Step 0 entirely on SQL Server 2025+. Everything from Step 1 on
    runs together, while connected to the PRIMARY replica.

    0. SQL Server 2022 only: turns on trace flag 12606, without it the
       FOR SECONDARY clause below doesn't parse at all
    1. Turns Query Store on and READ_WRITE on the primary, a no-op if
       it's already enabled
    2. Enables Query Store capture on every readable secondary replica
    3. Optional: lets automatic tuning force the last-known-good plan on
       secondaries too
    4. Prints the query to run on the secondary, to confirm it's
       capturing

    The commented block at the bottom shows how to turn this back off.

    Prerequisite: an Always On availability group must already exist,
    with AdventureWorks2022 (or your target database) as a member
    database and at least one readable secondary replica. This script
    does not create the AG. See
    https://learn.microsoft.com/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server

    On SQL Server 2022, Microsoft documents Step 0's trace flag as
    limited preview, not supported in production. Skipping Step 0
    without SQL Server 2025+ fails with "Msg 102, Level 15, State 1:
    Incorrect syntax near 'FOR'."
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
-- secondaries too, not just the primary. Requires Enterprise Edition
-- (SQL Server 2017+), fails on Standard, see 04_Version_Dependencies.
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
