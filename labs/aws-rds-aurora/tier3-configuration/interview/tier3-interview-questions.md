# Tier 3 Interview Questions - Configuration and Extensions

**Format:** Each question lists the target level. Use these in order during interviews - start with Junior and stop when the candidate struggles.

**Levels:**
- Junior - 0-2 years PostgreSQL experience
- Mid - 2-5 years
- Senior - 5-10 years
- Principal - 10+ years, designs systems

---

## Topic 1 - Parameter Groups

### Junior
**Q1:** What is a parameter group in RDS and why do you need one?

*Good answer covers:* Named set of configuration settings. Cannot edit `postgresql.conf` directly on RDS. Parameter groups replace that. Must create a custom one to make any changes - cannot edit the default.

---

**Q2:** You modify `work_mem` in a parameter group with `apply-immediately`. Does PostgreSQL restart? Will the change take effect for current sessions?

*Good answer covers:* `work_mem` is dynamic - no restart needed. Existing sessions pick up the new value for their NEXT query (some settings only apply to new connections). No outage.

---

**Q3:** After applying a parameter group with `shared_buffers` changed, your instance shows `pending-reboot` status. What does that mean and what should you do?

*Good answer covers:* `shared_buffers` is a static parameter - requires a restart to take effect. The instance is still running with the old value. Must reboot to apply. Schedule it during a maintenance window for production.

---

### Mid
**Q4:** You have an Aurora cluster with 1 writer and 3 readers. You change a parameter in the cluster parameter group. What happens on each node? What if you also have a per-instance DB parameter group on the writer?

*Good answer covers:* Cluster parameter group applies to all instances in the cluster. Per-instance DB parameter group can override cluster-level settings for specific parameters. Static params on cluster group require reboot of each node. Instance-level override takes precedence.

---

**Q5:** A developer says "I need `max_connections = 1000` for our load test." What questions do you ask before making this change?

*Good answer covers:* What instance class? Each connection uses ~5-10 MB RAM. 1000 connections on a small instance can cause OOM. What is the actual concurrency need vs number of connections? Suggest PgBouncer connection pooling instead. Check current connection usage first. What type of load test? Synthetic connections vs actual app connections.

---

**Q6:** How do you see ALL parameters that have been changed from their engine defaults in a parameter group?

*Good answer covers:* `aws rds describe-db-parameters --source user` - the `--source user` flag filters to only user-modified parameters. Without it, you see all hundreds of engine defaults.

---

### Senior
**Q7:** You inherit an RDS PostgreSQL instance using the default parameter group. The database is in production. What is your migration plan to move it to a custom parameter group with zero downtime?

*Good answer covers:* Create new custom parameter group. Do not change any values yet - just copy the defaults. Attach it to the instance with `apply-immediately` (dynamic parameters - no downtime for the group attachment itself). Verify `in-sync` status. Now you can safely modify dynamic parameters in the custom group. Static parameter changes still need a reboot - plan maintenance window.

---

**Q8:** How does `effective_cache_size` work? Why does changing it not require a reboot even though it affects query planning?

*Good answer covers:* `effective_cache_size` is a planner hint - it tells the optimizer how much memory is available for caching (both PostgreSQL shared_buffers plus OS page cache). The planner uses it to decide whether index scans or sequential scans are better. It does NOT allocate any memory - it's purely advisory to the query planner. Because nothing is actually allocated, there is no need to restart. Changes take effect for the next query.

---

### Principal
**Q9:** You are designing a multi-tenant SaaS on RDS with 50 tenants sharing 3 database instances. Each tenant has different workload characteristics. How do you handle parameter tuning per tenant given that parameter groups apply instance-wide?

*Good answer covers:* Parameter groups are instance-wide - cannot tune per-database or per-tenant. Options: 1) Per-session settings with `SET` commands in application connection string. 2) PgBouncer with per-pool `server_reset_query` that sets session parameters. 3) Separate instances for tenants with wildly different workloads. 4) Application-level connection pooling with tenant-specific pools. 5) Alter role defaults per database user (`ALTER ROLE app_tenant_1 SET work_mem TO '128MB'`). Discuss trade-offs of each.

---

---

## Topic 2 - Option Groups

### Junior
**Q10:** What is an option group? Do you need to worry about it for PostgreSQL on RDS?

*Good answer covers:* Option groups enable engine-level plugins. For PostgreSQL, they have no meaningful options - the list is empty. PostgreSQL uses extensions instead. You create one during provisioning but it doesn't do anything useful for PostgreSQL. Oracle and SQL Server use option groups heavily.

---

### Mid
**Q11:** A new team member says "I enabled the PostgreSQL audit extension by adding it to the option group." What is wrong with this statement?

*Good answer covers:* pgaudit is not an option group option for PostgreSQL - option groups have no PostgreSQL-specific features. pgaudit is enabled through: 1) adding to `shared_preload_libraries` in the parameter group, 2) rebooting, 3) running `CREATE EXTENSION pgaudit` in the database. The team member confused option groups (Oracle/SQL Server world) with extensions (PostgreSQL world).

---

---

## Topic 3 - Extensions

### Junior
**Q12:** How do you find out which extensions are available on your RDS PostgreSQL instance?

*Good answer covers:* `SELECT * FROM pg_available_extensions;` - shows name, default_version, installed_version, and description. `installed_version` is null if not installed. Can also check AWS documentation for the specific engine version.

---

**Q13:** What is `shared_preload_libraries` and why do some extensions need to be in it?

*Good answer covers:* Parameter that lists modules to load into shared memory at PostgreSQL startup. Some extensions (pg_stat_statements, pgaudit) need to hook into core PostgreSQL internals early in the startup process - they cannot be loaded dynamically later. Must add to this list, reboot, then run `CREATE EXTENSION`. It's a static parameter - requires reboot.

---

**Q14:** You installed `pg_stat_statements` but when you run `SELECT * FROM pg_stat_statements` you get "relation does not exist." What did you miss?

*Good answer covers:* Two possible issues: 1) Added to `shared_preload_libraries` but forgot to run `CREATE EXTENSION pg_stat_statements` in the database. Or 2) Ran `CREATE EXTENSION` but forgot to add to `shared_preload_libraries` and reboot - in this case the CREATE EXTENSION command itself would have failed. The most common issue: forgot to reboot after changing `shared_preload_libraries`, so the module isn't loaded even though it's in the parameter.

---

### Mid
**Q15:** A table has 50 GB of dead tuples from a DELETE operation. You need to reclaim the space, but the table has a live application hitting it 24/7. What are your options?

*Good answer covers:* `VACUUM` - marks space as reusable, no lock, but doesn't shrink file size. `VACUUM FULL` - shrinks file but takes exclusive lock (table offline). `pg_repack` - shrinks the table online with only a brief lock at the end (good option here). Compare trade-offs. Also: Was autovacuum keeping up? Why did 50 GB of dead tuples accumulate? Check autovacuum settings.

---

**Q16:** You enabled pgaudit with `pgaudit.log = 'all'`. The storage usage on your RDS instance increased dramatically. What happened and how do you fix it?

*Good answer covers:* `pgaudit.log = 'all'` logs every single statement including SELECT queries, which can be extremely verbose. The logs are written to the PostgreSQL log files which count against your storage. Fix: Narrow the audit scope - `pgaudit.log = 'ddl,write'` is typical for compliance. Also: enable CloudWatch log export and set a retention policy so logs cycle out. Check if `log_min_duration_statement` is set too low (logging many slow queries). Consider log rotation settings.

---

### Senior
**Q17:** How does pg_repack work at a high level? Why is it safer than VACUUM FULL for production tables?

*Good answer covers:* pg_repack creates a copy of the table with a log trigger to capture changes. It copies data to the new table in the background. At the end, it acquires a brief exclusive lock, replays the log of changes made during the copy, swaps the old and new table, and releases the lock. The exclusive lock period is very short (seconds, not minutes). `VACUUM FULL` holds the lock for the entire duration of the rewrite (minutes to hours for large tables). pg_repack also rebuilds indexes cleanly.

---

**Q18:** A developer asks if they can install a custom C extension they wrote on RDS. What is your answer and what alternatives can you offer?

*Good answer covers:* No - AWS does not allow arbitrary C extensions on RDS because they can crash the PostgreSQL server process (shared memory), access the filesystem, or create security vulnerabilities. Alternatives: 1) Trusted Language Extensions (TLE/pg_tle) - write the logic in SQL, PL/pgSQL, or PL/v8. 2) Implement the logic in the application layer. 3) Consider whether PostGIS, pgcrypto, or another available extension already provides the needed functionality. 4) Self-managed PostgreSQL on EC2 if C extensions are truly required (full control, full responsibility).

---

### Principal
**Q19:** Design a strategy for managing extension versions across a fleet of 200 RDS PostgreSQL instances that span 4 AWS accounts and 3 regions. Include update policy, testing, and rollback.

*Good answer covers:* Inventory: maintain a CMDB with all instances, their PostgreSQL version, and installed extensions with versions (can query pg_extensions or use AWS Config). Policy: group instances by criticality tier (prod/staging/dev). Extension updates flow dev -> staging -> prod with a time gate. Testing: maintain automated tests for each extension (query pg_stat_statements after enable, verify pgaudit log output, etc.). Rollback: `ALTER EXTENSION [name] UPDATE TO [previous-version]` if the previous version is still available. If not, restore from snapshot. IaC: use Terraform or CDK to define parameter group and extension configuration as code. Drift detection: nightly check that installed extension versions match the approved baseline.

---

---

## Topic 4 - pgvector

### Junior
**Q20:** What is pgvector and what kind of data does it store?

*Good answer covers:* pgvector is a PostgreSQL extension that adds a `vector` data type. Vectors (embeddings) are arrays of floating-point numbers that represent data (text, images) in a mathematical space. Similar items have similar vectors. Used for semantic search, recommendations, and AI/ML applications.

---

**Q21:** What is the difference between `<->`, `<=>`, and `<#>` operators in pgvector?

*Good answer covers:* `<->` is L2 (Euclidean) distance - straight-line distance between points. `<=>` is cosine distance - angle between vectors. `<#>` is negative inner product (dot product). Cosine is most common for text embeddings (OpenAI, etc.). L2 is general purpose. All three order by ascending (smaller = more similar).

---

### Mid
**Q22:** Your pgvector similarity search is returning wrong results (products unrelated to the query). What are the possible causes?

*Good answer covers:* 1) IVFFlat `lists` too small for the data size (too few clusters, index almost useless). 2) `probes` too low (not searching enough clusters). 3) HNSW `ef_search` too low. 4) Wrong distance operator used (cosine vs L2 - depends on how embeddings were generated). 5) Embeddings were generated by different models or with different normalization than the query embedding. 6) No index (sequential scan on huge table). Approach: compare exact scan (`SET enable_indexscan=off`) vs index scan results to diagnose index quality.

---

**Q23:** What is the recommended `lists` value for an IVFFlat index? What happens if you use too few?

*Good answer covers:* `sqrt(row_count)` as a starting point. For 1 million rows: ~1000 lists. Too few lists: each list contains many vectors, the index barely narrows the search space, poor recall (wrong results), performance doesn't improve as expected. Too many lists: long build time, sparse clusters, also poor recall. Rebuild the index as data grows significantly (e.g., 10x row count change).

---

### Senior
**Q24:** When would you choose HNSW over IVFFlat for a pgvector workload? What are the trade-offs?

*Good answer covers:* HNSW when: query latency is critical, data is relatively static (few inserts), and you have memory budget. IVFFlat when: data inserts are frequent (HNSW inserts are expensive because they update the graph), memory is constrained, and build speed matters. HNSW builds a multi-layer graph structure - queries traverse fewer nodes to find neighbors. IVFFlat builds clusters - queries only search the most relevant clusters. HNSW generally has higher recall for the same query speed, but uses more memory and takes longer to build.

---

**Q25:** You have 50 million embeddings. Nightly full index rebuilds are taking 8 hours. How do you optimize?

*Good answer covers:* 1) Increase `maintenance_work_mem` for faster index build. 2) Switch to HNSW if rebuilds are due to IVFFlat lists needing adjustment - HNSW doesn't need periodic rebuilds for accuracy. 3) Implement incremental indexing: add new vectors without rebuilding (pgvector supports `INSERT` without rebuild). 4) Use Aurora with multiple read replicas - serve search queries from replicas, rebuild index on writer off-peak. 5) Partition the table by date/category and maintain indexes per partition. 6) Increase `max_parallel_maintenance_workers` to build the index using parallel workers.

---

### Principal
**Q26:** Design a production pgvector architecture on AWS for a 100 million vector dataset with 10,000 QPS similarity search and P99 latency < 50ms requirement. Include RDS/Aurora considerations.

*Good answer covers:* At this scale, RDS single instance may not be sufficient. Options: 1) Aurora with read replicas - search queries routed to up to 15 readers via the reader endpoint. Writer only for inserts. 2) Partition the dataset by category/segment so each partition has fewer vectors. 3) HNSW index on SSD (Aurora Optimized Reads to cache hot index pages in memory). 4) Pre-warm the index: run sample queries after deployment to populate OS page cache. 5) Application-level sharding: split vectors across multiple Aurora clusters by hash of ID. 6) Consider dedicated vector databases (Pinecone, Weaviate) at this scale and compare cost vs pgvector. 7) Monitor recall with automated tests - a fast query with wrong results is not acceptable.

---

---

## Topic 5 - Trusted Language Extensions (TLE)

### Junior
**Q27:** Why can't you install a custom C extension on RDS? What does TLE solve?

*Good answer covers:* RDS is managed - AWS controls the PostgreSQL binary and cannot allow arbitrary C code that could crash the server or access OS resources. TLE provides a safe sandbox using interpreted languages (SQL, PL/pgSQL, PL/v8). These languages cannot crash the server. AWS allows TLE on RDS.

---

**Q28:** What are the steps to install a TLE extension from scratch?

*Good answer covers:* 1) Add `pg_tle` to `shared_preload_libraries` in the parameter group. 2) Reboot the instance. 3) `CREATE EXTENSION pg_tle`. 4) `SELECT pgtle.install_extension(...)` to register your TLE. 5) `CREATE EXTENSION [your-tle-name]` to activate it in a specific database.

---

### Mid
**Q29:** You want to deploy a new version of your TLE extension without breaking users on the old version. What is the process?

*Good answer covers:* `SELECT pgtle.install_extension_version_sql('my_ext', '2.0', $upgrade_sql$...$upgrade_sql$)` to register the new version. `SELECT pgtle.set_default_version('my_ext', '2.0')` to set it as the new default for new installs. Existing databases stay on version 1.0. Users upgrade with `ALTER EXTENSION my_ext UPDATE TO '2.0'`. This is non-breaking - users choose when to upgrade.

---

### Senior
**Q30:** Compare the security model of TLE vs a native C extension vs a PL/pgSQL function. When is each appropriate?

*Good answer covers:* Native C extension: Runs with no sandbox, can access OS, allocate arbitrary memory, crash the server. Not allowed on RDS. Appropriate only on self-managed PostgreSQL when you need maximum performance or OS access. PL/pgSQL function: Interpreted, sandboxed by PostgreSQL's security model. Can access database objects, cannot access OS. No packaging - just a function. Appropriate for business logic. TLE: Adds versioning, dependency management, and installability on top of PL/pgSQL. Same sandbox as PL/pgSQL. Appropriate when you need to distribute reusable packaged functionality across many databases with version control.

---

---

## Topic 6 - Foreign Data Wrappers

### Junior
**Q31:** What is postgres_fdw used for? Give a practical example.

*Good answer covers:* postgres_fdw lets you query a remote PostgreSQL database as if its tables were local. Example: Your order database needs current product prices from a separate inventory database. Instead of duplicating data or building an API, you query the inventory database directly through a foreign table. The SQL looks local but runs on the remote server.

---

**Q32:** What three objects do you need to create to use postgres_fdw?

*Good answer covers:* 1) Foreign Server - defines the connection details (host, port, database name). 2) User Mapping - maps the local user to the remote user/credentials. 3) Foreign Table - local proxy that maps to the remote table. Optionally: use `IMPORT FOREIGN SCHEMA` instead of creating each foreign table by hand.

---

### Mid
**Q33:** A query joining a local table (1 million rows) with a foreign table (500 rows) is slow. Why? How do you fix it?

*Good answer covers:* PostgreSQL fetches all rows from the foreign table across the network and then joins locally. With only 500 remote rows this is fast. If the query plan shows it fetching all 1M local rows and all 500 foreign rows and joining locally, use EXPLAIN VERBOSE to see the Remote SQL. The local table should be the probe side of a hash join. Fix: ensure the WHERE clause on the foreign table pushes down. If the query is truly slow with 500 remote rows, check network latency between instances, index on the join column in both tables. Consider a materialized view of the foreign table if it doesn't change often.

---

**Q34:** How do you secure the password stored in a user mapping?

*Good answer covers:* The password is stored in `pg_user_mappings`. By default, only superusers and the mapped user can see their own mapping. Non-superusers cannot see other users' mappings. Protections: 1) Use `REVOKE` to ensure app users don't have superuser. 2) Use a dedicated FDW user with minimal privileges (read-only) on the remote server. 3) Consider using SSL certificates instead of password authentication for the FDW connection. 4) Rotate the FDW user password regularly and update the user mapping.

---

### Senior
**Q35:** How does predicate pushdown work in postgres_fdw? What prevents a predicate from being pushed down?

*Good answer covers:* postgres_fdw analyzes the WHERE clause and joins to determine which conditions can be evaluated remotely. Safe predicates (use only remote columns, supported operators, no local-only functions) are included in the Remote SQL sent to the remote server. Prevents pushdown: 1) Functions not available on the remote server. 2) References to local columns (must fetch remote data first). 3) VOLATILE functions (results vary per call). 4) Complex expressions that postgres_fdw cannot safely translate. Use `EXPLAIN VERBOSE` to see the Remote SQL and verify what pushed down. The `use_remote_estimate` option on the server helps the planner make better decisions by getting actual row count estimates from the remote.

---

### Principal
**Q36:** Design a data federation architecture using postgres_fdw for a company with 15 microservices, each with its own RDS PostgreSQL database. Finance needs daily cross-service reports. What are the trade-offs vs alternatives?

*Good answer covers:* FDW approach: Set up a "reporting" RDS instance with foreign tables pointing to each of the 15 service databases. Report queries fan out across 15 connections. Trade-offs: adds latency (network hops), each service DB takes on extra load, joins across services are expensive (data pulled locally), complex to manage 15 foreign server credentials. Alternatives: 1) ETL/ELT pipeline - nightly load into a centralized data warehouse (Redshift, Snowflake). Better for historical reports. 2) AWS Glue + S3 - extract each service's data to S3, query with Athena. 3) Change Data Capture (CDC) with DMS - stream changes into a reporting database. 4) Event-driven: each service publishes events, reporting service maintains its own materialized view. For the use case (daily reports), ETL to Redshift is usually the better production architecture. FDW works for ad-hoc queries and operational reporting where freshness matters.

---

---

## Topic 7 - Engine Versions and Upgrades

### Junior
**Q37:** What is the difference between a major version upgrade and a minor version upgrade for PostgreSQL on RDS?

*Good answer covers:* Minor: e.g., 16.3 to 16.4. Bug fixes and security patches. Always backwards compatible. Brief restart (like any maintenance). Low risk. Major: e.g., 15.x to 16.x. New features, potentially breaking changes. Longer downtime. Must test extensions compatibility. Must validate application behavior. Cannot rollback easily.

---

**Q38:** How do you find what PostgreSQL engine versions are available on RDS?

*Good answer covers:* CLI: `aws rds describe-db-engine-versions --engine postgres`. Console: Create Database > Engine options > PostgreSQL > Version dropdown. To find upgrade paths from current version: `aws rds describe-db-engine-versions --engine postgres --engine-version [CURRENT] --query 'DBEngineVersions[0].ValidUpgradeTarget'`.

---

### Mid
**Q39:** What is `AutoMinorVersionUpgrade` and should you leave it enabled in production?

*Good answer covers:* When enabled, AWS automatically upgrades your instance to the latest minor version during your maintenance window. Pros: stay current with security patches automatically. Cons: unexpected restarts during maintenance windows, minor versions can occasionally have regressions (rare but possible). Production recommendation: disable it, test minor versions in staging first, then apply manually on a controlled schedule. Staging/dev: can leave enabled for automatic patching.

---

**Q40:** Before upgrading a production RDS instance from PostgreSQL 15 to PostgreSQL 16, what is your pre-upgrade checklist?

*Good answer covers:* 1) Create a manual snapshot. 2) Verify all extensions are available on PG16 (test with a new PG16 instance). 3) Read PG15->16 release notes for breaking changes. 4) Test the upgrade on a restored snapshot first. 5) Run your application test suite against the test instance. 6) Measure actual upgrade time for maintenance window planning. 7) Notify all stakeholders. 8) Confirm rollback plan (restore from pre-upgrade snapshot).

---

### Senior
**Q41:** A major version upgrade fails halfway through. The instance is in an unknown state. Describe your immediate response.

*Good answer covers:* First: do NOT attempt another upgrade or reboot yet. Check the RDS Events log for the failure reason. Check CloudWatch logs. Contact AWS Support immediately - they can access internal logs not visible to customers and may be able to recover or advise. If the instance is `incompatible-parameters` or `failed`: attempt a restore from the pre-upgrade snapshot taken before the upgrade. Accept the data loss from the upgrade window. If a snapshot is not available, AWS Support is the only path. Lesson: always take a manual snapshot before major upgrades.

---

**Q42:** After upgrading from PostgreSQL 15 to 16, some queries are 5x slower. What is your investigation process?

*Good answer covers:* 1) Check pg_stat_statements for the specific queries that regressed. 2) Run EXPLAIN ANALYZE on the affected queries - compare plans. New query plans? Statistics stale? 3) Check `ANALYZE` - PostgreSQL statistics may not have been refreshed after upgrade. Run `ANALYZE` on the affected tables. 4) Check for planner parameter changes - pg_settings comparison between PG15 and PG16 default values. 5) Check if any statistics targets changed (default_statistics_target). 6) Check if `pg_upgrade` reset statistics (it does on self-managed upgrades; RDS upgrade should preserve them). 7) Check for parallel query regressions (max_parallel_workers_per_gather setting). 8) Check extension versions - some extensions have planner-affecting changes between major versions.

---

### Principal
**Q43:** You manage 300 RDS PostgreSQL instances across production and staging. PostgreSQL 13 reaches end of support next year. Design an upgrade program that gets all 300 instances to PostgreSQL 16 within 6 months with zero unplanned outages.

*Good answer covers:* Phase 1 - Inventory (Month 1): Document all 300 instances: version, size, extensions, criticality, business owner, maintenance windows, application deployment dependencies. Phase 2 - Compatibility testing (Month 1-2): Create PG16 test instances from snapshots for each unique application stack. Run automated test suites. Identify and fix all compatibility issues. Phase 3 - Staging upgrades (Month 2-3): Upgrade all staging instances. Run 2-week soak test per batch. Fix regressions. Phase 4 - Production waves (Month 3-6): Wave 1: Lowest criticality (dev-prod, internal tools). Wave 2: Medium criticality. Wave 3: High criticality. Each wave: 1 week staging -> 1 week prod soak. Rollback: pre-snapshot + PITR. Communication: automated status dashboard, weekly stakeholder update. Tooling: upgrade script using AWS CLI, automated validation scripts, CloudWatch alarms for regression detection. Success metric: zero P1 incidents related to upgrades.
