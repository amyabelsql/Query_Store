# 08 - Best Practices

Proactive guidance for running Query Store well, before anything breaks. For what to do once something's already wrong, see [03_Troubleshooting](../03_Troubleshooting/).

## Before you turn it on

- Check available disk space against your planned `MAX_STORAGE_SIZE_MB`, plus headroom. A heavy ad hoc workload burns through quota faster than a parameterized one, size for what you actually have, not the demo default.
- If you already have a sense of the workload's ad hoc ratio, use it to estimate quota needs before turning Query Store on for the first time. `03_Troubleshooting`' plan-count query shows you how to measure this once it's running, use the same judgment qualitatively beforehand, lots of dynamic SQL or ORM-generated queries means more bloat.
- Start with `QUERY_CAPTURE_MODE = AUTO`, the production default, not `ALL`, on any database you don't already know intimately. `ALL` captures every one-off ad hoc query too, and can fill the quota before you've learned what your normal baseline even looks like.
- Confirm version, edition, and Availability Group membership first with `01_Setup/01_Prerequisites.sql`, trace flag guidance and wait-stats availability both depend on it.

## Rolling out across many databases

If you manage more than a handful of databases, don't turn Query Store on everywhere at once.

- Pilot on 2-3 low-risk databases first, dev or a lightly used reporting database, not your busiest production database on day one.
- Watch actual overhead for a real workday before expanding. Query Store's write path adds some CPU and I/O, it should be small, but confirm that against your own numbers rather than assuming it.
- Roll out in waves once the pilot holds up. Non-critical databases first, then business-hours-critical ones, save anything genuinely mission-critical, where trace flags `7745`/`7752` are worth considering (see `01_Setup`), for its own careful wave.
- Standardize the settings you land on (`INTERVAL_LENGTH_MINUTES`, `MAX_STORAGE_SIZE_MB`, `CLEANUP_POLICY`, `QUERY_CAPTURE_MODE`) across the fleet before later waves. `01_Setup/03_Configure.sql` is a starting template to adapt per database, not a script to run verbatim everywhere.

## Configuration philosophy

`01_Setup` documents what each setting does and its range of values. The proactive question is what values fit your environment, not this demo's:

| Setting | What to actually think about |
|---|---|
| `INTERVAL_LENGTH_MINUTES` | Smaller intervals (15) surface trends faster but create more rows and more storage churn. Larger intervals (60) are the steadier production default. Match it to how quickly you need to notice a regression, don't just copy the demo. |
| `MAX_STORAGE_SIZE_MB` | Size for your actual query volume and ad hoc ratio. A database with a lot of dynamic SQL fills its quota faster than a fully parameterized one. |
| `QUERY_CAPTURE_MODE` | `AUTO` by default. Only move to `CUSTOM` after measuring that `AUTO` is either missing queries you care about or still capturing too much noise, don't guess at it. |
| `CLEANUP_POLICY` (`STALE_QUERY_THRESHOLD_DAYS`) | Retention is only useful if you'll actually use it, e.g. month-over-month trend analysis. Longer than that is just wasted quota. |
| `WAIT_STATS_CAPTURE_MODE` | Leave it `ON` (2017+). The overhead is low, and it's the difference between knowing a query is slow and knowing why. |

## Monitoring and thresholds

`06_Monitoring` ships working defaults (`@WarningPercent` = 80, `@RegressionThresholdPct` = 50, `@DurationThresholdMs` = 5000). Before relying on them in production:

- Run the checks manually against your real workload first, `06_Monitoring`'s "Trigger an alert manually" section, to see what a normal day actually looks like. Set thresholds relative to that baseline, not the out-of-box defaults blindly.
- Start conservative, higher thresholds and fewer alerts, then tighten over time. An alert that fires constantly gets ignored, which defeats the point of alerting at all.
- `@RegressionThresholdPct = 50` means 50% slower than the last interval. For a 5-ms query that's noise. For a 5-second query it's real. Decide whether one global threshold fits your workload, or whether your genuinely critical queries need their own, tighter check.
- Forced plan failures and forced plan changes (`06_Monitoring`) are rare by nature and cheap to check often. Resource and regression checks are the ones worth tuning cadence and thresholds on carefully.

## Best-practice checklist

General guidance for running Query Store well day to day.

| Do this | Why |
|---|---|
| Use `QUERY_CAPTURE_MODE = AUTO` in production | Filters out low-value queries |
| Keep `SIZE_BASED_CLEANUP_MODE = AUTO` | Helps prevent `READ_ONLY` mode |
| Watch `actual_state_desc` vs. `desired_state_desc` | Shows when Query Store changed mode |
| Keep wait stats capture on | Makes it easier to explain CPU, IO, memory, and lock pressure |
| Parameterize app queries | Reduces ad hoc bloat |
| Use `ALTER`, not `DROP` + `CREATE`, for procedures and functions | Preserves Query Store history and forced plans |
| Treat forced plans as temporary | Stabilize first, then fix the root cause |

## Related

| Folder | Why |
|---|---|
| [01_Setup](../01_Setup/) | Prerequisites, turning it on, and what each setting does |
| [06_Monitoring](../06_Monitoring/) | The actual alerting scripts these thresholds apply to |
| [03_Troubleshooting](../03_Troubleshooting/) | What to do once something's already wrong |

## Sources

- [Best practices for managing the Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/manage-the-query-store)
- [Best practices for monitoring workloads with Query Store - Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/best-practice-with-the-query-store)
