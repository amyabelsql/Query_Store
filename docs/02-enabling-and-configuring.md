# Enabling and Configuring Query Store

## Enable it

```sql
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
```

On SQL Server 2022, new databases already have this on by default — but always verify rather than assume (see [Verify Query Store is healthy](#verify-current-settings)).

Query Store **cannot** be enabled for `master` or `tempdb`.

## Configuration options and their defaults (SQL Server 2022)

| Option | Purpose | Default |
|---|---|---|
| `OPERATION_MODE` | `READ_WRITE` or `READ_ONLY` | `READ_WRITE` (new 2022 databases) |
| `MAX_STORAGE_SIZE_MB` | Disk space cap for Query Store data | `1000` MB |
| `INTERVAL_LENGTH_MINUTES` | Size of the aggregation window for runtime stats | `60` (allowed: 1, 5, 10, 15, 30, 60, 1440) |
| `STALE_QUERY_THRESHOLD_DAYS` | Retention period before cleanup | `30` |
| `SIZE_BASED_CLEANUP_MODE` | Auto-delete oldest/cheapest data as size approaches the limit | `AUTO` (triggers at 90% of max size, stops at ~80%) |
| `DATA_FLUSH_INTERVAL_SECONDS` | How often in-memory data is persisted to disk | `900` (15 min) |
| `QUERY_CAPTURE_MODE` | Which queries get captured (see below) | `AUTO` |
| `MAX_PLANS_PER_QUERY` | Cap on stored plans per query | `200` |
| `WAIT_STATS_CAPTURE_MODE` | Capture wait statistics per query | `ON` |

## Capture modes

| Mode | When to use |
|---|---|
| `ALL` | Full workload analysis — every query shape and its frequency. Default in SQL Server 2016/2017. |
| `AUTO` | **Recommended.** Filters out infrequent, low-cost queries automatically. Default since SQL Server 2019. |
| `CUSTOM` | Fine-tune capture thresholds yourself (execution count, compile/execution CPU time). Use on very large or ad hoc-heavy databases. |
| `NONE` | Stop capturing new queries; keep tracking already-captured ones. Use only for benchmarking/testing — you'll miss new query shapes. |

## Recommended settings for a production database

This mirrors the example Microsoft publishes for SQL Server 2022:

```sql
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 60,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    WAIT_STATS_CAPTURE_MODE = ON
);
```

## Custom capture policy (large or ad hoc-heavy databases)

If `AUTO` still captures too much, switch to `CUSTOM` and tune the thresholds directly:

```sql
ALTER DATABASE [AdventureWorks2022]
SET QUERY_STORE = ON
(
    QUERY_CAPTURE_MODE = CUSTOM,
    QUERY_CAPTURE_POLICY = (
        STALE_CAPTURE_POLICY_THRESHOLD = 24 HOURS,
        EXECUTION_COUNT = 30,
        TOTAL_COMPILE_CPU_TIME_MS = 1000,
        TOTAL_EXECUTION_CPU_TIME_MS = 100
    )
);
```

A query becomes eligible for capture once **any** threshold is crossed within the evaluation window.

## Verify current settings

```sql
SELECT actual_state_desc, desired_state_desc, current_storage_size_mb,
       max_storage_size_mb, readonly_reason, interval_length_minutes,
       stale_query_threshold_days, size_based_cleanup_mode_desc,
       query_capture_mode_desc
FROM sys.database_query_store_options;
```

If `actual_state_desc` differs from `desired_state_desc`, Query Store silently changed mode — usually because it hit the size quota and dropped to `READ_ONLY`. See [readonly_reason bitmap reference](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql) and the maintenance script [scripts/08-maintenance-cleanup.sql](../scripts/08-maintenance-cleanup.sql).

Hands-on: [scripts/01-enable-configure-query-store.sql](../scripts/01-enable-configure-query-store.sql)

Next: [Catalog views and DMVs](03-catalog-views-and-dmvs.md)

## Sources

- [Best practices for managing the Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [sys.database_query_store_options — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-query-store-options-transact-sql)
- [ALTER DATABASE SET options — Microsoft Learn](https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-set-options)
