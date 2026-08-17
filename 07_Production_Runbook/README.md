# 07 - Production Runbook

Runbook-style T-SQL for diagnosing Query Store itself and using it to
diagnose query performance problems. Unlike the numbered folders before
this one, these scripts are meant to be run directly against a real
database when something is wrong, not stepped through as a lab.

| Script | Use it to |
|---|---|
| [01-query-store-health-checks.sql](01-query-store-health-checks.sql) | Confirm Query Store is running in the expected mode, has storage headroom, and its forced plans are still applying |
| [02-performance-troubleshooting-queries.sql](02-performance-troubleshooting-queries.sql) | Find a specific query, rank resource consumers, spot regressions and plan instability, and break down wait time by category |

## How to use these

1. Run `01-query-store-health-checks.sql` first. A Query Store that is
   `READ_ONLY` or in an `ERROR` state gives stale or misleading answers to
   everything else — fix that before troubleshooting a specific query.
2. Run the sections of `02-performance-troubleshooting-queries.sql` you
   need. Each section is a standalone `GO` batch with its own parameters
   (lookback window, search text, thresholds) declared at the top — edit
   those values in place before running.
3. Both scripts default to `AdventureWorks2022` to match the rest of this
   repo. Change the `USE` statement to point at your target database.

## Related

- [03_Explore_Catalog_Views](../03_Explore_Catalog_Views/) — what the catalog views used here mean
- [04_Find_And_Fix_Regressions](../04_Find_And_Fix_Regressions/) — narrative walkthroughs of the same scenarios (regressions, waits, ad hoc query bloat)
- [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/) — configuration and hygiene checklist
- [08_Automated_Monitoring](../08_Automated_Monitoring/) — turns the space and regression checks here into a recurring, alerting SQL Agent job
