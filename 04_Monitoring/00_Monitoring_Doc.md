# Monitoring

This folder sets up Query Store alerting jobs.

Run order

1. `01_Verify_Database_Mail_Prereqs.sql`
2. `02_Monitoring_Procedures.sql`
3. `03_Create_Agent_Job.sql`

What it checks

- Query Store state and size
- Regressed queries
- Slow queries by threshold
- Forced plan failures
- Forced plan changes

Notes

- Run setup first
- Use Database Mail profile that works
- Run either individual jobs or the combined job
- Do not run both modes at the same time
