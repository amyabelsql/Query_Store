# Setup

Query Store is configured on the database level, not the instance level. Storage, thresholds, and every setting below apply only to the database you target, other databases on the same instance are unaffected. If the database is in an Availability Group, run these scripts on the primary replica.

## Run These In Order

| Step | What it does                                                                  |
|---|-------------------------------------------------------------------------------|
| [01_Prerequisites.sql](01_Prerequisites.sql) | Instance-level checks (version, Availability Group membership, trace flags)   |
| [02_Turn_On.sql](02_Turn_On.sql) | Turns Query Store on (`READ_WRITE`) for one database or all eligible user databases |
| [03_Configure.sql](03_Configure.sql) | Applies this repo's Query Store thresholds for one database or all eligible user databases |

`02_Turn_On.sql` and `03_Configure.sql` now support two targeting options:

```sql
DECLARE @ApplyToAllDatabases BIT = 0; -- 0 = one DB, 1 = all eligible user DBs
DECLARE @DatabaseName SYSNAME = N'AdventureWorks2022';
```

Use one of these patterns:

- `@ApplyToAllDatabases = 0`: set `@DatabaseName` and run against only that database
- `@ApplyToAllDatabases = 1`: run against all eligible user databases (`ONLINE`, not read-only, not snapshots)

Both scripts output one row per targeted database, including `Result` and `Error Message` columns so you can quickly spot failures.

`01_Prerequisites.sql` is instance-wide and needs no parameter.

## What Each Setting Controls

| Setting | What it controls | Possible values | This repo sets |
|---|---|---|---|
| `OPERATION_MODE` | Whether Query Store is actively capturing new data, or frozen read-only | `READ_WRITE`, `READ_ONLY` | `READ_WRITE` |
| `CLEANUP_POLICY` (`STALE_QUERY_THRESHOLD_DAYS`) | How many days since a query last ran before it's considered stale and purged. It's based on last execution, not when it was first captured | Any number of days | 90 |
| `DATA_FLUSH_INTERVAL_SECONDS` | How often captured data is written from memory to disk. Anything not yet flushed is lost on an unexpected shutdown, and isn't in a backup taken before the flush | Any number of seconds | 60 |
| `MAX_STORAGE_SIZE_MB` | The storage quota Query Store can use. Once it hits this limit, Query Store switches to `READ_ONLY` and stops capturing new data, unless `SIZE_BASED_CLEANUP_MODE` is `AUTO` and can free up space first | Any number of MB | 1024 |
| `INTERVAL_LENGTH_MINUTES` | How long each runtime-stats time bucket stays open before a new one starts | 1, 5, 10, 15, 30, 60, or 1440 | 15 |
| `SIZE_BASED_CLEANUP_MODE` | What happens as storage nears the quota | `AUTO` (purges old data automatically to make room), `OFF` (lets it go `READ_ONLY` instead) | `AUTO` |
| `QUERY_CAPTURE_MODE` | Which queries get captured | `ALL` (everything), `AUTO` (skips one-off, low-cost queries), `NONE`, `CUSTOM` (2019+, your own thresholds) | `AUTO` |
| `MAX_PLANS_PER_QUERY` | The most distinct plans Query Store tracks per query | Any number, 0 = unlimited | 200 |
| `WAIT_STATS_CAPTURE_MODE` | Whether wait statistics (why a query was slow, not just how slow) are captured too | `ON`, `OFF` (2017+ only) | `ON` |

[Best-Practices](../10_Best_Practices/) covers baseline best practices to start with.

## Watch For This

If `actual_state_desc` doesn't match `desired_state_desc`, Query Store changed mode on its own. Usually space pressure pushed it to `READ_ONLY`.

Continue with [02_Generate_Workload](../02_Generate_Workload/).

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [sys.database_query_store_options - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql)
- [ALTER DATABASE SET QUERY_STORE - Microsoft Learn](https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-set-options#query_store_options)
