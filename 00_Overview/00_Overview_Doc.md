# Overview of Query Store

## What Query Store is

Query Store keeps query history, plan history, and runtime stats in each user database.
It helps you find regressions and compare plan behavior over time.

## Version support

- SQL Server 2016 and later supports Query Store
- SQL Server 2017 and later supports Query Store wait stats

## Backup and restore notes

Query Store data is stored in the user database.
A full backup includes Query Store data that has been flushed to disk.
Use `sys.sp_query_store_flush_db` before backup if you need current in memory data saved.

## Folder order

| Folder | Purpose |
|---|---|
| [01_Setup](../01_Setup/) | Enable and configure Query Store |
| [02_Generate_Workload](../02_Generate_Workload/) | Create workload data for labs and troubleshooting |
| [03_Troubleshooting](../03_Troubleshooting/) | Troubleshoot health, regressions, and forced plans |
| [04_Monitoring](../04_Monitoring/) | Build alerts and SQL Agent monitoring jobs |
| [05_Regression_Testing](../05_Regression_Testing/) | Run the step by step regression and forced plan lab |
| [08_Best_Practices](../08_Best_Practices/) | Day to day operating guidance |
| [09_Query_Store_Reference](../09_Query_Store_Reference/) | Final operations guide and quick references |

Start with [01_Setup](../01_Setup/).
