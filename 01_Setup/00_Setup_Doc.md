# 01 - Setup

Run in order:

1. [01_Prerequisites.sql](01_Prerequisites.sql) - instance-level checks (version, Availability Group membership, trace flags)
2. [02_Turn_On.sql](02_Turn_On.sql) - turns Query Store on for `@DatabaseName`, using SQL Server's own default thresholds
3. [03_Configure.sql](03_Configure.sql) - replaces those defaults with this repo's demo thresholds on the same database

`02_Turn_On.sql` and `03_Configure.sql` each start with:

```sql
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022';
```

Change that value, then run the script. `01_Prerequisites.sql` is instance-wide and needs no parameter.

## What 03_Configure.sql changes

| Setting | Demo value | Production default | Why the demo differs |
|---|---|---|---|
| `INTERVAL_LENGTH_MINUTES` | 15 | 60 | Shorter intervals so query stats show up faster while you're working through the demo |
| `DATA_FLUSH_INTERVAL_SECONDS` | 60 | 900 | Flushes to disk more often so recent activity is visible sooner |
| `MAX_STORAGE_SIZE_MB` | 1024 | 100 | Demo workload can fill the default cap quickly |
| `CLEANUP_POLICY` (`STALE_QUERY_THRESHOLD_DAYS`) | 90 | 30 | Keeps demo history around longer |
| `QUERY_CAPTURE_MODE` | `ALL` | `AUTO` (2019+) | Captures every query, including one-off/ad hoc ones, instead of only frequent or expensive ones |
| `MAX_PLANS_PER_QUERY` | 200 | 200 | Same as default |
| `SIZE_BASED_CLEANUP_MODE` | `AUTO` | `AUTO` | Same as default |
| `WAIT_STATS_CAPTURE_MODE` | `ON` | `ON` (2017+) | Same as default |

[06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) resets these to the production-default column at the end of the demo.

## Watch for this

If `actual_state_desc` doesn't match `desired_state_desc`, Query Store changed mode on its own, usually because space pressure pushed it to `READ_ONLY`.

Continue with [02_Generate_Workload](../02_Generate_Workload/).

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [sys.database_query_store_options - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql)
- [ALTER DATABASE SET QUERY_STORE - Microsoft Learn](https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-set-options#query_store_options)
