# Regression Testing (Query Store Forcing Lab)

## What is a query regression?

A **query regression** is a query that starts running measurably *worse* than it used to,
even though the T-SQL text of the query has not changed. Query Store tracks multiple
execution plans per query over time, so it can show that the *same* query id used a
fast plan yesterday and a slow plan today. That plan change (not a code change) is what
"regressed" refers to here.

Common causes of a real-world regression:

- **An index was dropped, disabled, or rebuilt differently**, removing a path the optimizer relied on.
- **Statistics were updated (or went stale)**, changing the optimizer's row estimates.
- **Parameter sniffing** — a plan was compiled/cached for one parameter value's data
  distribution and reused for a very different value.
- **Schema changes** (e.g., new constraints, changed data types) that alter available plan choices.
- **Server/database setting changes** (e.g., compatibility level, MAXDOP) that shift plan shape.
- **Data growth or skew** that no longer matches the plan the optimizer originally chose.

Query Store's `sys.query_store_runtime_stats` records average duration, CPU, and logical
reads per plan per time interval, so a regression shows up as the same `query_id` having
a materially worse row in a later interval than an earlier one — this is exactly what
`03_Troubleshooting/06_Regressed_Queries.sql` detects and classifies.

## Purpose of this lab

This folder lets you safely and repeatably **simulate** a regression against
AdventureWorks2022 (by removing a supporting index to force a worse plan), confirm it
was captured and detected by Query Store, then force the prior good plan back and clean up.

## Run order

1. `01_Phase1_Capture_Before.sql` — Capture baseline executions while the good plan exists.
2. `02_Phase2_Create_Regression.sql` — Create the regression and capture slower executions.
3. `03_Phase3_Force_And_Validate.sql` — Restore indexes and identify `Query Id` / `Plan Id` values.
4. `04_Force_Plan.sql` — Force the chosen plan.
5. `05_Validate_Forced_Plan.sql` — Return numeric before/regressed/after proof.
6. `06_Cleanup_Forced_Plan.sql` — Unforce and verify cleanup.

## Notes

- Use a non-production environment.
- Edit top-level `DECLARE` values first.
- Step 3 provides ids used by steps 4–6.
- Keep execution counts similar across baseline, regressed, and forced validation runs.
