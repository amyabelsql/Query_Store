# 02 - Generate Workload

Query Store has nothing to show until queries actually run. 

Run [01_Generate_Workload.sql](01_Generate_Workload.sql) to create two
stored procedures and call them repeatedly, plus a batch of ad hoc,
non-parameterized queries that show how query-text bloat happens.

Wait about a minute after running it for the first interval to flush,
then move on.

Continue with [03_Explore_Catalog_Views](../03_Explore_Catalog_Views/).
