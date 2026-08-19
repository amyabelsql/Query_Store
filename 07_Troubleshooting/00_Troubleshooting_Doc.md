# 07 - Troubleshooting

What to run after an alert fires or something's already wrong: state, storage, regressions, resource thresholds, timeouts and cancellations, forced plans. Confirm Query Store is healthy, find the bad query, fix it, confirm it's stable. For proactive guidance before anything breaks, see [10_Best_Practices](../10_Best_Practices/).

## Scripts

| Step | What it does |
|---|---|
| [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) | Confirms Query Store itself is healthy before you trust anything downstream |
| [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) | Finds the bad query, by section, depending on the alert |

## What each query shows you

| Query | Shows | Look for |
|---|---|---|
| 01, section 1 | Current state vs. desired state, storage, capture and cleanup mode | `Actual State` should match `Desired State`, a mismatch usually means it hit its size quota |
| 01, section 2 | Plain-text decode of `Readonly Reason` | Any bit set here explains why section 1 shows a mismatch |
| 01, section 3 | Storage headroom | `Pct Of Quota Used` climbing toward 100 means it's close to `READ_ONLY` or size-based cleanup |
| 01, section 4 | CUSTOM capture policy thresholds (2019+) | Non-null values confirm CUSTOM capture is active, compare the thresholds to what your workload is actually doing |
| 01, section 5 | Ratio of unique query text to total captured queries | A ratio near 1.0 means ad hoc, non-parameterized queries are bloating Query Store |
| 01, section 6 | Forced plans and their failure counts | `Force Failure Count` above 0 means a forced plan stopped applying, usually a schema change |
| 01, section 7 | Execution counts by `Execution Type` (Regular / Aborted / Exception) per query | A growing `Aborted` or `Exception` count next to `Regular` is worth investigating, often a symptom of blocking, a slow query timing out, or bad data |
| 01, section 8 | Just the Aborted and Exception executions, with interval detail | See [02_Generate_Workload/02_Generate_Exception_Query.sql](../02_Generate_Workload/02_Generate_Exception_Query.sql) to generate a real Exception on purpose. A real Aborted execution needs an actual timeout or cancellation, nothing in this repo fakes one |
| 02, section 2 | Top resource consumers in the lookback window | The query at the top of `Total Duration MS` is generally the best overall target, cross check `Total CPU MS` and `Total Logical IO Reads` to see which resource is driving the cost |
| 02, section 3 | Queries with unstable performance | A high `Variation Ratio` flags a parameter sniffing candidate |
| 02, section 4 | Queries slower in the latest interval than the one before | Rows here are genuine regressions past the `@RegressionThresholdPct` you set |
| 02, section 5 | Wait time by category in the lookback window | The category at the top tells you if it's CPU, IO, memory, or locking |
| 02, section 6 | Top queries within the dominant wait category | The query at the top of `Total Wait Time MS` is your best target for that wait category |

## Start here based on the alert

| Alert type | Run | Look for | Common fix |
|---|---|---|---|
| Space or state | [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) | `actual_state_desc <> desired_state_desc`, high quota use, forced-plan failures | Clean up old data, increase storage, reduce ad hoc noise, fix broken forced plans |
| Timeouts or cancellations | [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) sections 7-8 | A query with a growing `Aborted` or `Exception` count | Investigate blocking, tune the query if it's timing out from being slow, or fix the underlying data/app bug |
| Regressed query | [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) section 4 | A query whose latest interval is slower than the prior one | Force the last good plan, then fix index, stats, or query shape |
| Performance threshold | [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) sections 2, 5, 6 | Top resource consumers, dominant wait category | Tune the top query, add an index, reduce lock pressure, or adjust memory use |

## Workflow

1. Run [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) first. A `READ_ONLY` or `ERROR` Query Store makes everything downstream misleading.
2. If healthy, run the section of [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) that matches the alert. If you already have a `query_id`, start there.
3. Fix the immediate problem.
4. Re-run the check and confirm the issue is gone or trending down.

## Fix order

1. **Stabilize** - force the good plan or remove the blocker
2. **Explain** - is it CPU, IO, memory, or locking?
3. **Fix** - index, statistics, rewrite, or parameterization
4. **Confirm** - rerun and show the alert clears

Both scripts default to `AdventureWorks2022`, change the `USE` statement if needed.

## The circle, square, and triangle in the SSMS GUI

The scatter charts in SSMS's Query Store reports (Top Resource Consuming Queries, Regressed Queries) mark executions with different shapes, confirmed against Microsoft's own legend:

| Shape | Execution Type | Meaning |
|---|---|---|
| Circle | Regular | Finished normally |
| Square | Aborted | Interrupted before finishing, a client `CommandTimeout`, someone clicking Cancel, a `KILL`, a lock timeout |
| Triangle | Exception | Failed with a real error while running |

Those shapes are just a picture of one column, `execution_type_desc` in `sys.query_store_runtime_stats`. You don't need the GUI at all, [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) sections 7-8 query it directly.

**Why this is worth querying instead of just eyeballing the chart.** Query Store keeps Regular, Aborted, and Exception executions of the same plan as separate rows, one per execution type per interval. A "top slow queries" report that groups by plan without splitting on `Execution Type` can quietly blend a handful of cancelled or errored runs into what looks like your normal performance baseline, understating or distorting it depending on how long those runs ran before they were cut off. Querying `Execution Type` directly, instead of trusting an average that already mixed them together, is how you catch that.

What it actually catches in practice:

- A query whose `Regular` average duration looks fine, but has a growing `Aborted` count, is a query that's borderline slow enough to hit a client timeout under load, even though its "successful" runs still look healthy.
- A spike in `Aborted` executions clustered in one time window correlates with an incident, a deployment, a blocking chain, a spike in concurrent load, faster to find than digging through app logs alone.
- A query throwing the same `Exception` repeatedly (not once) points at a data quality or application bug, not a performance problem, worth routing to the app team even though nothing here is "slow."

## Why a forced plan stops working

Plan forcing tells the optimizer to reuse a specific plan, but forcing isn't guaranteed to keep succeeding forever. Per Microsoft's documented plan forcing limitations, it fails when:

- **The plan uses something forcing doesn't support**, an `INSERT BULK` statement, a reference to an external table, a distributed query or full-text operation, an elastic query, or a dynamic/keyset cursor (SQL Server 2019+ and Azure SQL Database do support static and fast-forward cursors).
- **Something the plan depends on is gone**, the database the plan was compiled against no longer exists, or an index the plan relies on was dropped or disabled.
- **The plan itself has a problem**, it's no longer legal for the query, the optimizer exceeded its allowed search operations trying to reproduce it, or the plan XML is malformed.

`force_failure_count` (section 6) only increments on recompile, not every execution, and `last_force_failure_reason_desc` names the specific reason:

| Reason | Means |
|---|---|
| `NO_INDEX` | An index the plan depends on no longer exists or was disabled, the most common cause after a schema change |
| `NO_DB` | The database referenced in the plan doesn't exist |
| `VIEW_COMPILE_FAILED` | An indexed view referenced in the plan has a problem |
| `HINT_CONFLICT` | The plan conflicts with a query hint now in effect |
| `TIME_OUT` | The optimizer gave up trying to reproduce the forced plan's shape |
| `NO_PLAN` | The forced plan couldn't be verified as valid for the query at all |
| `ONLINE_INDEX_BUILD` | The query is trying to modify data while a target index is mid-build online |
| `COMPILATION_ABORTED_BY_CLIENT` | The client cancelled compilation before it finished |
| `GENERAL_FAILURE` | Anything not covered by a more specific reason above |

`NO_INDEX` is the one worth remembering, it's exactly what `04_Regressions_And_Forcing/03_Force_And_Unforce_Plan.sql`'s bonus block demonstrates on purpose, dropping the index a forced plan depends on.

## Query Store and backup/restore

Query Store isn't a separate system store, it's ordinary tables living inside the user database itself. That has real consequences:

- **A full backup includes it, and a restore brings it back.** Restoring an older backup to a scratch instance gives you working, queryable Query Store history from that point in time, useful for investigating an incident after the live data has aged out or been cleaned up.
- **Restoring production to a lower environment carries the query text with it.** Non-parameterized queries are captured with their literal values baked into the text. Restoring a production backup into dev or test can leak real data through `sys.query_store_query_text` even if the table data itself was scrubbed, worth knowing before you hand a "sanitized" restore to a lower environment.
- **Only what's already flushed to disk is in the backup.** Query Store buffers in memory before writing to disk on `DATA_FLUSH_INTERVAL_SECONDS`. Run `sp_query_store_flush_db` first if you need a guaranteed-current snapshot before backing up.
- To purge Query Store data after a restore (or anytime), `ALTER DATABASE ... SET QUERY_STORE CLEAR` wipes it, see [06_Maintenance](../06_Maintenance/).

## Common fixes by symptom

| Symptom | Fix |
|---|---|
| Near quota | Clean up old data, keep `AUTO` cleanup, reduce ad hoc capture |
| Regressed query | Force the last good plan, then fix index or statistics issues |
| Many unique queries | Parameterize with stored procedures or `sp_executesql` |
| Forced plan stopped working | Check for schema changes, then re-evaluate the plan |

## Related

| Folder | Why |
|---|---|
| [04_Regressions_And_Forcing](../04_Regressions_And_Forcing/) | The same story as a guided lab |
| [06_Maintenance](../06_Maintenance/) | Maintenance actions and their impacts, run when you're done or when things drift |
| [08_Monitoring](../08_Monitoring/) | Where the alerts come from |
| [10_Best_Practices](../10_Best_Practices/) | Proactive guidance, so you need this folder less often |

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store) (circle/square/triangle shape legend)
- [sys.query_store_plan - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-plan-transact-sql) (plan forcing limitations and failure reasons)
- [Monitor performance by using the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store) (Query Store lives inside the user database)
