# Regression Testing

## What a query regression means

A query regression means the same query now runs worse than before.
The query text can stay the same.
The plan changed and performance got worse.

Common causes

- Index dropped or disabled
- Statistics stale or changed
- Parameter sniffing
- Data size change
- Compatibility level or other setting change

## Run order

1. `01_Phase1_Capture_Before.sql`
2. `02_Phase2_Create_Regression.sql`
3. `03_Phase3_Force_And_Validate.sql`
4. `04_Force_Plan.sql`
5. `05_Validate_Forced_Plan.sql`
6. `06_Cleanup_Forced_Plan.sql`

## Notes

- Use non production only
- Step 3 gives the ids for steps 4 to 6
- Keep execution counts similar for fair comparison
