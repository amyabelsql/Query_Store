/*
	Query Store operations quick reference
	Replace database name before running
*/

USE [master];
GO

-- Turn on
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE = ON;
GO

-- Turn off
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE = OFF;
GO

-- Set read only
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE (OPERATION_MODE = READ_ONLY);
GO

-- Set read write
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
GO

-- Clear Query Store
ALTER DATABASE [YourDatabaseName]
SET QUERY_STORE CLEAR;
GO
