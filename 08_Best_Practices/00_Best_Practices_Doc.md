# Best Practices

This folder gives practical guidance for daily Query Store use.
It is short and focused.

## Start settings

- Keep Query Store on in read write mode
- Use query capture mode auto in most production databases
- Keep size based cleanup mode auto
- Keep wait stats capture on when available
- Set storage size based on real workload volume

## Rollout approach

- Start with low risk databases first
- Monitor storage growth and state changes
- Roll out in small waves
- Keep settings consistent unless a database has a clear special case

## Things to watch every week

- Actual state and desired state in sys.database_query_store_options
- Current storage size versus max storage size
- Number of forced plans and force failure count
- Top regressions by duration and reads
- Query text growth from one off ad hoc statements

## Good operating habits

- Parameterize application SQL when possible
- Avoid frequent drop and create of procedures
- Use alter for procedures and functions when possible
- Treat forced plans as a short term stabilizer
- Fix root cause after stabilizing with a forced plan

## Common mistakes

- Running with query capture mode all on busy ad hoc workloads
- Leaving max storage size too small
- Ignoring read only state changes
- Keeping forced plans forever without review
- Not checking force failure reasons after schema changes

## Related folders

- `01_Setup`
- `03_Troubleshooting`
- `04_Monitoring`
- `05_Regression_Testing`
