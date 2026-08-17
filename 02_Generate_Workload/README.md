# 02 - Generate Workload

Query Store has nothing to show until queries actually run. Run
[generate-workload.sql](generate-workload.sql) to create two demo
stored procedures and call them repeatedly, plus a batch of ad hoc,
non-parameterized queries that show how query-text bloat happens.

Wait about a minute after running it for the first interval to flush,
then move on.

Next: [03_Explore_Catalog_Views](../03_Explore_Catalog_Views/)
