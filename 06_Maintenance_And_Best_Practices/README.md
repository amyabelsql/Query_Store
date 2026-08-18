# 06 - Maintenance And Best Practices

Run [maintenance-cleanup.sql](maintenance-cleanup.sql) to check size/state, purge stale ad hoc queries, and reset the database back to production-realistic settings (`AUTO` capture, full-length intervals) once you're done with the labs.

Below is a one-page summary of [Microsoft's Query Store best practices](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store) — print this, or keep it open during the workshop.

## Configuration

| Type  | Recommendation                                                       | Why                                                               |
| ----- | -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Do    | Leave `QUERY_CAPTURE_MODE = AUTO`                                    | Filters out low-value queries automatically                       |
| Do    | Set `STALE_QUERY_THRESHOLD_DAYS`                                     | Prevents old data from lingering                                  |
| Do    | Keep `SIZE_BASED_CLEANUP_MODE = AUTO`                                | Keeps Query Store in `READ_WRITE` mode instead of going read-only |
| Do    | Use `QUERY_CAPTURE_MODE = CUSTOM` on large or ad hoc-heavy databases | Tunes capture instead of disabling it                             |
| Avoid | Leaving `QUERY_CAPTURE_MODE = ALL` on busy production servers        | Only for active troubleshooting; revert to `AUTO` after           |

## Monitoring

| Type | Recommendation                                                                             | Why                                                                                     |
| ---- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| Do   | Compare `actual_state_desc` to `desired_state_desc` in `sys.database_query_store_options`  | A mismatch means Query Store silently changed mode, usually from hitting its size quota |
| Do   | Use the built-in SSMS Query Store reports                                                  | Regressed Queries, Top Resource Consuming Queries, Query Wait Statistics                |
| Do   | Check `force_failure_count` and `last_force_failure_reason_desc` in `sys.query_store_plan` | Surfaces forced plans that stopped forcing successfully                                 |

## Query and schema hygiene

| Type  | Recommendation                                                                | Why                                                                   |
| ----- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Do    | Parameterize queries via stored procedures or `sp_executesql`                 | Reduces ad hoc plan bloat                                             |
| Do    | Use `ALTER` instead of `DROP`/`CREATE` on procedures, functions, and triggers | Recreating an object breaks Query Store history and any forced plan   |
| Avoid | Renaming a database with forced plans                                         | Plan forcing references the database by name and fails after a rename |

## Plan forcing

| Type | Recommendation                                                                                                | Why                                                         |
| ---- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Do   | Treat plan forcing as a mitigation, not a fix                                                                 | Follow up with root-cause work (index, statistics, rewrite) |
| Do   | Prefer [Query Store hints](../05_SQL_2022_Features/#query-store-hints) on SQL Server 2022+ / Azure SQL Database | Steers one query without editing application code           |

## Mission-critical / high-throughput servers

| Type | Recommendation                                                 | Why                                                           |
| ---- | -------------------------------------------------------------- | ------------------------------------------------------------- |
| Do   | Use `CUSTOM` capture policies instead of disabling Query Store | Disabling it discards all troubleshooting history             |
| Note | Trace flag 7745 skips the final disk flush on shutdown         | Faster shutdown, small risk of losing the last flush interval |
| Note | Trace flag 7752 enables async Query Store load                 | SQL Server 2016–2017 only; engine-controlled from 2019 on     |

## Availability groups / geo-replication

| Type | Recommendation                                                   | Why                                                                     |
| ---- | ---------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Do   | Match secondary replica service tier/compute size to the primary | Mismatched tiers throttle the transaction log                           |
| Note | Query Store on a readable secondary is read-only by default      | SQL Server 2025+ can capture from secondaries too — see [09_Query_Store_On_Secondary_Replicas](../09_Query_Store_On_Secondary_Replicas/) (preview, requires an AG) |

Next: [07_Production_Runbook](../07_Production_Runbook/) — this is the last workshop lab; the folders after this one are standalone production tooling rather than step-by-step labs.

## Sources

- [Best practices for managing the Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
