# 06 - Reset And Best Practices

Run [01_Maintenance_Cleanup.sql](01_Maintenance_Cleanup.sql) when you're done. It checks Query Store health, cleans up ad hoc noise, and resets to production-style settings.

## Best-practice checklist

| Do this | Why |
|---|---|
| Use `QUERY_CAPTURE_MODE = AUTO` in production | Filters out low-value queries |
| Keep `SIZE_BASED_CLEANUP_MODE = AUTO` | Helps prevent `READ_ONLY` mode |
| Watch `actual_state_desc` vs. `desired_state_desc` | Shows when Query Store changed mode |
| Keep wait stats capture on | Makes it easier to explain CPU, IO, memory, and lock pressure |
| Parameterize app queries | Reduces ad hoc bloat |
| Use `ALTER`, not `DROP` + `CREATE`, for procedures and functions | Preserves Query Store history and forced plans |
| Treat forced plans as temporary | Stabilize first, then fix the root cause |

## Common fixes by symptom

| Symptom | Fix |
|---|---|
| Near quota | Clean up old data, keep `AUTO` cleanup, reduce ad hoc capture |
| Regressed query | Force the last good plan, then fix index or statistics issues |
| Many unique queries | Parameterize with stored procedures or `sp_executesql` |
| Forced plan stopped working | Check for schema changes, then re-evaluate the plan |

See also [07_Production_Runbook](../07_Production_Runbook/) for alert follow-up and [08_Automated_Monitoring](../08_Automated_Monitoring/) for recurring checks.

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
