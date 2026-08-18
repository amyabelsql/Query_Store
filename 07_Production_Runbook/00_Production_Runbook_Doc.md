# 07 - Production Runbook

Use after an alert fires. Confirm Query Store is healthy, find the bad query, fix it, confirm it's stable.

## Start here based on the alert

| Alert type | Run | Look for | Common fix |
|---|---|---|---|
| Space or state | [01_Query_Store_Health_Checks.sql](01_Query_Store_Health_Checks.sql) | `actual_state_desc <> desired_state_desc`, high quota use, forced-plan failures | Clean up old data, increase storage, reduce ad hoc noise, fix broken forced plans |
| Regressed query | [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) section 4 | A query whose latest interval is slower than the prior one | Force the last good plan, then fix index, stats, or query shape |
| Performance threshold | [02_Performance_Troubleshooting_Queries.sql](02_Performance_Troubleshooting_Queries.sql) sections 2, 5, 6 | Top resource consumers, dominant wait category | Tune the top query, add an index, reduce lock pressure, or adjust memory use |

## Steps

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

## Related

- [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/) - the same story as a guided lab
- [08_Automated_Monitoring](../08_Automated_Monitoring/) - where the alerts come from
- [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) - how to keep Query Store healthy long term
