/*
    Not read-only, this takes Query Store offline and back on. Run
    manually, only when 01_Health_Checks.sql query 1 shows
    actual_state_desc = 'ERROR' (SQL Server 2017+).

    Turns Query Store off, runs sp_query_store_consistency_check to
    repair it, turns it back on, then forces READ_WRITE so it starts
    capturing again.
*/

USE [AdventureWorks2022];
GO

ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = OFF;
GO

EXEC sp_query_store_consistency_check;
GO

ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE = ON;
GO

ALTER DATABASE [AdventureWorks2022] SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
GO
