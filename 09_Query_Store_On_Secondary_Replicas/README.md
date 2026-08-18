# 09 - Query Store on Secondary Replicas (SQL Server 2025)

**This folder is different from everything before it.** Folders 00–08 run
against a single default instance. This one requires an **Always On
availability group (AG) with at least one readable secondary** — there's
no way to demo it on one lone instance. If you don't have an AG handy,
read this folder for the concepts and come back to run it once you do.

**This feature is in preview** on every platform that supports it
(SQL Server 2025, Azure SQL Database, Azure SQL Managed Instance) as of
this writing. Treat it as evaluate-and-learn, not something to lean on
for production alerting yet.

## What it is

Historically, Query Store on a readable secondary replica couldn't
capture anything — the secondary database is read-only, and Query Store
needs to write plan/stats data somewhere. You could only see whatever
the *primary* had already captured and replicated down; read-only
reporting workloads running directly against the secondary were
invisible to Query Store.

SQL Server 2025 (17.x) fixes that with **Query Store for readable
secondary replicas**: secondaries capture query execution info locally,
then stream it back to the primary over the same transport the AG
already uses for log shipping. The primary persists it into its own
Query Store — the one Query Store the whole replica set shares — and
that data flows back out to every replica. Nothing is duplicated or
kept separately per replica; it's all tagged with *which role* it came
from (primary, secondary, geo secondary, geo HA secondary, or a named
replica) so you can slice by role afterward.

## Availability

| Platform | Available | Enabled by default |
|---|---|---|
| SQL Server 2025 (17.x) | Yes | **No** — opt in per database |
| SQL Server 2022 (16.x) | Limited preview only, via trace flag `12606` on primary **and** every secondary | No — **not supported in production** |
| Azure SQL Database (not Hyperscale) | Yes | Yes, always on |
| Azure SQL Managed Instance (Always-up-to-date update policy) | Yes | Yes, always on |
| Azure SQL Managed Instance (2025/2022 update policy) | No | — |
| Azure SQL Database Hyperscale | Not supported | — |

Requires an Always On availability group to already be configured — see
Microsoft's [Always On availability groups overview](https://learn.microsoft.com/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server) if you need to
stand one up. That's out of scope for this workshop; everything else
here assumes it already exists.

## Setup

All of this runs from the **primary** replica.

1. **SQL Server 2022 only:** run Step 0 in
   [01-enable-on-secondary.sql](01-enable-on-secondary.sql) — enable
   trace flag `12606` on the primary **and** every readable secondary
   (connect to each one separately). Skip this on SQL Server 2025+.
2. Run the rest of [01-enable-on-secondary.sql](01-enable-on-secondary.sql)
   — enables Query Store on the primary if it isn't already, then
   enables it `FOR SECONDARY`, and optionally turns on automatic plan
   correction for secondaries.
3. Connect to the **secondary** replica directly and confirm it's
   capturing:

   ```sql
   SELECT desired_state_desc, actual_state_desc, readonly_reason
   FROM sys.database_query_store_options;
   ```

   Expect `actual_state_desc = READ_CAPTURE_SECONDARY` and
   `readonly_reason = 8`. If `actual_state_desc` still says
   `READ_ONLY`, the `FOR SECONDARY` step above hasn't taken effect yet
   or wasn't run against the right database.

### Troubleshooting

**`Msg 102, Level 15, State 1: Incorrect syntax near 'FOR'.`** — the
engine doesn't recognize the `FOR SECONDARY` clause at all. This is a
parser-level rejection, not a config problem, and almost always means
one of:

- You're on SQL Server 2022 and haven't enabled trace flag `12606` yet
  (Step 0 above) — this is the most common cause.
- You're on SQL Server 2022 and enabled the trace flag on only one
  replica. It has to be on the primary **and** every secondary
  individually; it doesn't propagate.
- You enabled it with plain `DBCC TRACEON (12606)` (session-scoped)
  instead of `DBCC TRACEON (12606, -1)` (instance-wide) — the session
  that ran the `ALTER DATABASE` needs it, not just the session you
  turned it on in.
- The trace flag was enabled with `DBCC TRACEON`, then the instance
  restarted — that resets it. Confirm with `DBCC TRACESTATUS(12606);`,
  or set `-T12606` as a permanent startup parameter instead.

Run `SELECT @@VERSION;` if you're not sure which SQL Server version
you're actually connected to — it's easy to assume 2025 when the
instance is actually 2022.

## Demo it

1. With setup done, connect to the **secondary** (e.g. `sqlcmd -S
   <secondary_instance> -d AdventureWorks2022`, or set
   `ApplicationIntent=ReadOnly` in your connection) and run a batch of
   `SELECT`s against it — reuse the query shapes from
   [02_Generate_Workload](../02_Generate_Workload/generate-workload.sql)
   if you want something familiar.
2. Back on the **primary**, run
   [02-cross-replica-demo-queries.sql](02-cross-replica-demo-queries.sql)
   to see `sys.query_store_replicas` list the replica set, and the
   top-CPU-by-replica query attribute your secondary's `SELECT`s to the
   `SECONDARY` role specifically.
3. Try forcing a plan for one of those queries — plan forcing for a
   secondary is issued **from the primary connection**, using
   `@replica_group_id` from `sys.query_store_replicas`. See the
   commented example at the bottom of the same script.
4. Optional, if you're comfortable doing a manual failover in your test
   AG: fail over, then re-run `SELECT * FROM sys.query_store_replicas`.
   You'll see it gain rows — it keeps one row per `role_type` it has
   ever observed a replica in, so a 2-replica AG goes from 2 rows to 4
   after a single failover (each replica has now been seen as both
   primary and secondary).

## What may or may not work

- **It's a preview feature.** Behavior, defaults, and even these
  catalog views can change before general availability.
- **SQL Server 2022 is not a real option for this.** The trace flag
  12606 path is explicitly called out by Microsoft as not intended for
  production 2022 deployments — treat it as a curiosity, not something
  to plan around.
- **The same capture-mode filtering that applies on the primary applies
  to secondaries.** A single one-shot ad hoc query run against the
  secondary can show up with a **negative** `query_id`/`plan_id` — a
  temporary local placeholder — and never get promoted to a real,
  positive ID if it never crosses the primary's configured capture
  thresholds (same `AUTO`-mode filtering behavior covered in
  [01_Setup](../01_Setup/) and [06_Maintenance_And_Best_Practices](../06_Maintenance_And_Best_Practices/)). Don't
  read a negative ID as a bug — it's an in-flight query waiting on the
  primary's capture decision.
- **Plan forcing must be issued from the primary**, even though the
  plan applies to a secondary. Running `sp_query_store_force_plan`
  while connected to the secondary itself isn't the supported path.
- **This shares bandwidth with AG log traffic**, not a separate
  connection — query text, plans, and runtime/wait stats are
  multiplexed over the same HADR transport that carries log records.
  Under heavy load, expect possible latency/backpressure on that
  channel; check `pending_message_count` and `messaging_memory_used_mb`
  in `sys.database_query_store_internal_state` if something feels
  slow.
- **Storage grows on the primary**, not the secondary — everything
  captured anywhere in the replica set lands in the primary's Query
  Store, so `MAX_STORAGE_SIZE_MB` and your cleanup policy matter more
  with this on than without it.
- **Azure SQL Database Hyperscale doesn't support this at all.**
- **Azure's Query Performance Insight dashboard doesn't disambiguate by
  replica yet** — it aggregates runtime/wait stats from every replica
  together, even though the underlying telemetry (`is_primary_b`,
  `replica_group_id`) carries the distinction.

## Sources

- [Query Store for Secondary Replicas — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/performance/query-store-for-secondary-replicas)
- [sys.query_store_replicas — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-replicas)
- [sys.query_store_plan_forcing_locations — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-plan-forcing-locations-transact-sql)
- [sp_query_store_force_plan — Microsoft Learn](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-query-store-force-plan-transact-sql)
