# Voleon DBA Interview Guide

## How to Use This Guide

Each question maps to a specific requirement in Voleon's DBA job description. For each question, this guide covers: the question, why Voleon asks it, key points your answer must hit, an answer outline, and which lab exercise demonstrates the skill.

Use this guide to structure 30-minute mock interviews. Do not memorize answers verbatim - internalize the key points and let experience fill in the specifics.

---

## Question 1: PostgreSQL MVCC

**Question:** Explain how MVCC works in PostgreSQL and what problems it solves. What is table bloat and how does autovacuum address it?

**Why Voleon asks this:** Voleon's ML pipelines run long-running read queries against tables that are also receiving high-frequency writes (market data ingestion). MVCC is fundamental to understanding why this works, and why it requires vacuum.

**Key points to cover:**
- MVCC = Multi-Version Concurrency Control
- Writers never block readers; readers never block writers
- Each row has `xmin` (created by) and `xmax` (deleted by) system columns
- Dead tuples accumulate because DELETE/UPDATE does not physically remove old row versions
- Autovacuum reclaims dead tuple space and updates visibility maps
- Transaction ID wraparound is a real threat - autovacuum prevents it
- `pg_stat_user_tables.n_dead_tup` tells you how much bloat exists
- `pg_class.relpages` vs actual data tells you about page bloat

**Answer outline:**
- Define MVCC: readers get a consistent snapshot, writers create new row versions
- Walk through an UPDATE: old row marked with xmax, new row inserted with new xmin
- Explain dead tuples: neither version is removed from disk immediately
- Vacuum's job: mark dead tuples as reusable, update the visibility map, advance relfrozenxid
- Autovacuum triggers: when dead_tuple_count exceeds `autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * reltuples`
- Transaction ID wraparound: PostgreSQL only has 2^31 XID values; autovacuum freezes old rows before wraparound occurs (emergency vacuum at `autovacuum_freeze_max_age`)
- Signs of bloat problems: table size growing faster than row count, slow sequential scans

**Lab exercise:** cbus lab - run a high-update workload on a table, monitor `pg_stat_user_tables.n_dead_tup`, observe autovacuum behavior, manually run `VACUUM VERBOSE`.

---

## Question 2: WAL and Durability

**Question:** What is the Write-Ahead Log in PostgreSQL? Walk me through what happens between a client issuing a COMMIT and the data being durable on disk.

**Why Voleon asks this:** Position data and market data must never be lost. Understanding WAL durability is the foundation for designing backup and replication correctly.

**Key points to cover:**
- WAL records changes before they happen in the data files
- `fsync` guarantees WAL is on durable storage before COMMIT returns to client
- `synchronous_commit` controls when COMMIT returns relative to WAL flushing
- `wal_buffers` - WAL is written to a shared buffer before flushing to disk
- Full page writes: on the first write to a page after a checkpoint, PostgreSQL writes the entire page to WAL (protects against partial page writes on crash)
- `checkpoint_completion_target` and when dirty pages make it from shared_buffers to data files
- WAL segments: 16MB files in `pg_wal/`
- WAL is also the mechanism for streaming replication

**Answer outline:**
- Client issues COMMIT
- PostgreSQL flushes WAL buffers to WAL file on disk (`fsync()`)
- COMMIT returns to client - at this point, WAL record is durable
- Dirty data pages are still in shared_buffers - NOT yet in the data files
- At checkpoint time, dirty pages are written from shared_buffers to data files
- If the server crashes after COMMIT but before checkpoint, WAL replay recovers the data on restart
- The data files are always "behind" the WAL - that is intentional

**Lab exercise:** cbus lab - observe `pg_wal/` directory, set `synchronous_commit = off` and benchmark the throughput difference, cause a crash and watch WAL replay on restart.

---

## Question 3: Streaming Replication and Lag

**Question:** How do you set up streaming replication in PostgreSQL? How do you monitor replication lag, and what steps do you take when lag is increasing?

**Why Voleon asks this:** Voleon needs high availability. A replica that is significantly behind primary is useless for failover. Monitoring and troubleshooting lag is a core DBA skill.

**Key points to cover:**
- Physical streaming replication: WAL records stream from primary to standby in real time
- Configuration: `primary_conninfo` on the standby, `wal_keep_size` on the primary, replication slots
- `pg_stat_replication` on the primary shows connected standbys and their lag
- `pg_stat_wal_receiver` on the standby shows connection status
- Lag types: write lag, flush lag, replay lag - each tells you something different
- Replication slots: prevent the primary from discarding WAL the standby needs (but can fill disk if standby is down)
- Causes of lag: heavy write workload on primary, standby I/O bottleneck, network saturation, long-running queries on standby with hot_standby_feedback

**Answer outline:**
- Primary: `wal_level = replica`, create replication user with REPLICATION privilege
- Standby: `pg_basebackup` for initial clone, `primary_conninfo` in `postgresql.conf`, `standby.signal` file
- Monitor with: `SELECT * FROM pg_stat_replication;` on primary, check `write_lag`, `flush_lag`, `replay_lag`
- Troubleshoot rising lag:
  1. Check if standby is connected at all (`state = streaming`)
  2. Check standby server resources (disk I/O, CPU - replay is single-threaded per database)
  3. Check for long-running queries on standby blocking replay (HOT standby conflict)
  4. Check network bandwidth between primary and standby
  5. Check if replication slot is accumulating (`pg_replication_slots.wal_status`)

**Lab exercise:** cbus lab - configure streaming replication between two PostgreSQL instances, generate write load on primary, observe lag metrics, simulate a network delay.

---

## Question 4: Backup and PITR with pgBackRest

**Question:** Describe your backup strategy for a production PostgreSQL instance. How would you set up pgBackRest and how does point-in-time recovery work?

**Why Voleon asks this:** Financial data loss is catastrophic. Voleon needs a DBA who can define and validate RPO/RTO targets and implement them with real tools.

**Key points to cover:**
- pgBackRest vs pg_dump: pgBackRest is for physical backups with WAL archiving (full PITR), pg_dump is for logical backups of specific objects
- pgBackRest components: stanza (configuration for a database cluster), repository (backup storage - local, S3, or SFTP), WAL archiving
- Backup types: full, differential, incremental - pgBackRest manages the dependency chain
- WAL archiving: `archive_command` ships every WAL segment to the repository as it is completed
- PITR: restore a base backup, then replay WAL segments up to a specific timestamp or transaction ID
- RPO: how much data can you lose? - determined by WAL archiving frequency
- RTO: how long can recovery take? - determined by backup age and WAL volume
- Always test restores - a backup you have never tested is not a backup

**Answer outline:**
- Configure pgBackRest: `/etc/pgbackrest.conf` with stanza name, pg1-path, repository path (S3 URI for Voleon)
- Enable WAL archiving: `archive_mode = on`, `archive_command = 'pgbackrest --stanza=main archive-push %p'`
- Schedule: full backup weekly, differential daily, WAL archive continuous
- Monitor: `pgbackrest info --stanza=main`, check archive gap with `pg_current_wal_lsn()` vs last archived WAL
- PITR process: `pgbackrest --stanza=main --delta restore`, set `recovery_target_time` in `postgresql.conf`, `pg_ctl start`
- Validate quarterly: restore to a test instance and verify data integrity with row counts and checksums

**Lab exercise:** cbus lab - configure pgBackRest with a local repository, take full backup, insert test data, drop a table, recover to the point before the drop.

---

## Question 5: Ceph RBD Storage for Databases

**Question:** Voleon uses Ceph RBD for database storage volumes. How does RBD differ from local NVMe, and how do you tune PostgreSQL for the higher latency characteristics of network-attached storage?

**Why Voleon asks this:** Directly from the JD - storage administration is explicitly listed. A candidate who has only used local storage will make tuning mistakes on Ceph.

**Key points to cover:**
- RBD latency (1-5ms) vs local NVMe (0.1ms) - the difference matters for WAL fsyncs
- WAL commit latency is the most sensitive operation
- Ceph rebalancing events increase latency - DBAs need to know about scheduled maintenance
- `checkpoint_completion_target = 0.9` to spread I/O
- `random_page_cost` should be lower than default (2.0 vs 4.0) because Ceph has no rotational seek time
- RBD snapshots enable fast backup workflows
- Monitor: watch `pg_stat_bgwriter` for slow checkpoint duration

**Answer outline:**
- Explain the I/O path: PostgreSQL fsync -> kernel -> rbd kernel module -> Ceph OSDs over network
- Each fsync on WAL traverses the network, hits primary OSD, then 2 replica OSDs
- Key PostgreSQL settings to adjust: `wal_buffers`, `checkpoint_completion_target`, `effective_io_concurrency` (200+ for Ceph)
- Lower `random_page_cost` to 2.0 - Ceph is distributed so there is no mechanical seek penalty
- Monitor `checkpoint_write_time` and `checkpoint_sync_time` in `pg_stat_bgwriter` - sustained high `checkpoint_sync_time` indicates I/O saturation
- Coordinate with storage team on Ceph maintenance windows - OSD rebalancing causes latency spikes

**Lab exercise:** cbus lab - PostgreSQL data directory on a loopback/LVM volume (simulating Ceph indirection), observe checkpoint timing, tune settings and compare.

---

## Question 6: Containerized PostgreSQL

**Question:** When would you run PostgreSQL in a container versus on bare metal? Walk me through setting up a PostgreSQL container with proper volume management and resource limits.

**Why Voleon asks this:** Voleon runs Kubernetes for services and dev/test environments. The DBA needs to manage containerized databases and understand the tradeoffs.

**Key points to cover:**
- Bare metal for production primary - lowest latency, simplest failure domain
- Containers for dev/test/CI - fast provisioning, isolation, reproducibility
- Named volumes vs bind mounts - named volumes are managed by Docker, bind mounts are explicit host paths
- Memory limits must match PostgreSQL's `shared_buffers` and `work_mem` settings
- `--memory-swap` should equal `--memory` to disable swap for databases
- Health checks ensure dependent services wait for PostgreSQL to be ready
- StatefulSets in Kubernetes with PVCs for persistent storage

**Answer outline:**
- Decision criteria: production with strict SLAs = bare metal; everything else = evaluate containers
- Container setup:
  ```bash
  docker run -d \
    --name pg-staging \
    --memory=4g --memory-swap=4g \
    --cpus=2 \
    -v pg-staging-data:/var/lib/postgresql/data \
    -p 5432:5432 \
    -e POSTGRES_PASSWORD=stagingpass \
    postgres:16
  ```
- Set `shared_buffers = 1GB` (25% of 4GB limit) inside the container
- Use `pg_isready` in the health check
- Kubernetes: StatefulSet with PVC backed by Ceph RBD StorageClass

**Lab exercise:** cbus lab - run PostgreSQL in a Docker/Podman container with a named volume, configure resource limits, verify data persistence across container restart.

---

## Question 7: Ansible for Database Operations

**Question:** How do you use Ansible to manage PostgreSQL configuration across a fleet of database servers? Give an example of a task you would automate with Ansible.

**Why Voleon asks this:** Configuration management is explicitly in the JD. Manual configuration drift across a large fleet is unacceptable at a firm with strict compliance and reproducibility requirements.

**Key points to cover:**
- Ansible roles: reusable, structured playbooks for specific software (e.g., `postgresql` role)
- `ansible.builtin.template` for `postgresql.conf` and `pg_hba.conf` (Jinja2 templates with host variables)
- `community.postgresql` collection: `postgresql_db`, `postgresql_user`, `postgresql_privs` modules
- Idempotency: Ansible tasks must be safe to run multiple times - no side effects on re-run
- Handlers: restart PostgreSQL only when configuration actually changes
- Inventory groups: group servers by role (primary, replica, backup) and apply different variables

**Answer outline:**
- Show a realistic task: rolling out a `pg_hba.conf` change across 10 servers
  1. Template the `pg_hba.conf` file with variables for allowed hosts
  2. Deploy with `ansible.builtin.template`
  3. Handler to `pg_reload_conf()` (not restart - just reload) when file changes
  4. Verify with `community.postgresql.postgresql_query` to check `pg_hba_file_rules`
- Mention: always run in check mode first (`--check`) before applying to production
- Tag tasks so you can run subsets (`ansible-playbook site.yml --tags pg_hba`)

**Lab exercise:** cbus lab - Ansible playbook to deploy PostgreSQL configuration changes, add a new database user, and validate the change.

---

## Question 8: Redis Caching with PostgreSQL

**Question:** Describe a pattern where you use Redis to cache data from PostgreSQL. How do you handle cache invalidation, and what are the risks?

**Why Voleon asks this:** Redis is in the JD and in the signal generation pipeline. The DBA needs to understand how the cache layer interacts with the database.

**Key points to cover:**
- Cache-aside pattern: application checks Redis first, falls back to PostgreSQL on miss, populates Redis
- Write-through: write to both PostgreSQL and Redis on every update
- Write-behind: write to Redis first, asynchronously sync to PostgreSQL (risky - data loss on Redis failure)
- TTL-based invalidation: simpler but may serve stale data
- Event-based invalidation: PostgreSQL NOTIFY or application-level events tell Redis to evict keys
- Redis eviction policies: `allkeys-lru`, `volatile-lru` - what happens when Redis runs out of memory
- Risk: PostgreSQL is the source of truth - if Redis contains stale data and the application trusts it, decisions are made on wrong data (critical in a trading environment)

**Answer outline:**
- Voleon context: ML scoring services look up feature values per symbol per timestamp
- Pattern: score request comes in -> check Redis for `feature:{symbol}:{date}` key -> hit: return cached value, miss: query PostgreSQL, store in Redis with TTL
- Invalidation: when PostgreSQL feature table is updated (new market data ingested), publish a NOTIFY message -> listener invalidates or updates the Redis key
- Monitor Redis hit rate: `INFO stats` -> `keyspace_hits` / (`keyspace_hits` + `keyspace_misses`)
- Never use write-behind for financial data where PostgreSQL must be authoritative

**Lab exercise:** cbus lab - run Redis alongside PostgreSQL, populate Redis from a PostgreSQL query, implement a simple cache-aside lookup in Python.

---

## Question 9: PgBouncer Connection Pooling

**Question:** Why do you need a connection pooler in front of PostgreSQL? Explain the difference between session pooling, transaction pooling, and statement pooling. When would you use each?

**Why Voleon asks this:** Slurm jobs create burst connection patterns. Without a pooler, PostgreSQL would exhaust its `max_connections` limit under load.

**Key points to cover:**
- PostgreSQL spawns a process per connection - each connection consumes memory (~5-10MB) regardless of activity
- `max_connections = 200` means 200 backend processes and ~1-2GB of overhead just for connections
- PgBouncer maintains a small pool of actual PostgreSQL connections and queues/multiplexes client connections
- Session pooling: client holds a server connection for its entire session - least efficient but supports all features
- Transaction pooling: server connection is returned to pool after each transaction - most efficient, but breaks SET/PREPARE/LISTEN
- Statement pooling: server connection returned after each statement - rarely used, most restrictive
- For Voleon's ML jobs: transaction pooling is appropriate (no prepared statements, no SET session-level config)
- Monitor: `SHOW POOLS;` and `SHOW STATS;` in PgBouncer admin console

**Answer outline:**
- Explain the problem: 500 Slurm workers each open a database connection = 500 PostgreSQL backend processes
- PgBouncer sits in front: workers connect to PgBouncer (port 6432), PgBouncer maintains 20 real PostgreSQL connections
- Transaction pooling for typical application workloads
- Session pooling required for: SET LOCAL, advisory locks, temp tables, LISTEN/NOTIFY
- Configuration: `pool_mode = transaction`, `max_client_conn = 1000`, `default_pool_size = 20`
- Show query from PgBouncer: `SHOW POOLS;` to see client connections vs server connections

**Lab exercise:** cbus lab - configure PgBouncer in front of PostgreSQL, benchmark with and without pooling under high concurrency, observe PostgreSQL's `pg_stat_activity`.

---

## Question 10: Prometheus and Grafana for Database Monitoring

**Question:** Walk me through setting up monitoring for a PostgreSQL cluster using Prometheus and Grafana. What are the most important metrics to alert on?

**Why Voleon asks this:** Prometheus and Grafana are explicitly in the JD. Infrastructure-team DBAs own their own observability, not just dashboards built by someone else.

**Key points to cover:**
- `postgres_exporter` scrapes PostgreSQL internal views and exposes them as Prometheus metrics
- Key metrics: `pg_stat_activity_count` by state, `pg_replication_lag_seconds`, `pg_stat_bgwriter_*`, `pg_locks_count`, `pg_stat_database_*`
- Alert thresholds: replication lag > 60s (warning), > 300s (critical); connection usage > 80%; dead tuple ratio > 20%
- `pg_stat_statements` for query-level performance tracking (requires the extension)
- Grafana dashboards: import community dashboards as a starting point, customize for Voleon's workloads
- On-call alerting: Prometheus Alertmanager routes alerts to PagerDuty or Slack

**Answer outline:**
- Deploy `postgres_exporter` as a systemd service or sidecar container
- Configure Prometheus scrape job targeting `postgres_exporter:9187`
- Build Grafana dashboard with panels for:
  - Active connections by state (idle, active, idle in transaction)
  - TPS (transactions per second)
  - Replication lag per standby
  - Checkpoint write/sync duration
  - Cache hit ratio (`pg_stat_database.blks_hit / (blks_hit + blks_read)`)
  - Top queries by total_time from `pg_stat_statements`
- Alertmanager rules: replication lag, connection saturation, checkpoint duration, dead tuple accumulation

**Lab exercise:** cbus lab - deploy postgres_exporter, configure Prometheus scrape, build a Grafana dashboard, set up a test alert.

---

## Question 11: PostgreSQL Security

**Question:** How do you secure a PostgreSQL cluster? Walk through authentication, authorization, and network access controls.

**Why Voleon asks this:** Financial data requires strict access controls. Regulatory and internal compliance requirements demand auditability.

**Key points to cover:**
- `pg_hba.conf`: controls who can connect from where, using what method
- SCRAM-SHA-256: the current recommended password hashing method (replaces md5)
- Role-based access: GRANT/REVOKE on databases, schemas, tables - principle of least privilege
- `NOLOGIN` roles for grouping permissions, `LOGIN` roles for actual users
- SSL/TLS: `ssl = on`, certificates for encryption in transit
- Row-level security (RLS): PostgreSQL supports per-row access policies
- `pg_audit` extension for audit logging
- Never use the `postgres` superuser for application connections
- `search_path` injection risk: always qualify schema names in application SQL

**Answer outline:**
- `pg_hba.conf` first: restrict connections to known IPs, require `scram-sha-256` for all non-local connections
- Create role hierarchy: `readonly_role`, `readwrite_role`, `admin_role` as `NOLOGIN` group roles
- Assign application users to appropriate group roles
- `REVOKE ALL ON SCHEMA public FROM PUBLIC` - lock down the public schema
- Enable SSL: install certificates, set `ssl_cert_file` and `ssl_key_file`, require `hostssl` in pg_hba.conf
- `pg_audit` for audit logging of DDL and DML on sensitive tables
- Rotate passwords regularly, use connection strings in environment variables (never hardcoded)

**Lab exercise:** cbus lab - configure SCRAM-SHA-256 authentication, create role hierarchy, test that a read-only user cannot write, verify SSL connection.

---

## Question 12: Multi-Database Experience

**Question:** Describe your experience with MySQL, Oracle, and SQL Server. What are the key differences in how you approach backup, replication, and performance tuning compared to PostgreSQL?

**Why Voleon asks this:** Voleon explicitly requires experience with multiple database engines. The DBA manages all of them, not just PostgreSQL.

**Key points to cover:**
- MySQL: InnoDB engine (MVCC, row locking, ACID), binary log for replication, `mysqldump` or Percona XtraBackup for physical backups, `SHOW SLAVE STATUS` for replication monitoring
- Oracle: UNDO tablespace for MVCC (not row versioning like PostgreSQL), RAC for HA, RMAN for backup, Data Guard for replication, AWR/ASH for performance analysis
- SQL Server: SQL Server Agent for jobs, Always On Availability Groups for HA, SQL Server Backup to disk or Azure, `sys.dm_exec_query_stats` for performance
- Key differences from PostgreSQL: Oracle uses a shared server model with a single large SGA; MySQL's optimizer is less sophisticated; SQL Server has excellent built-in tooling (SSMS)
- Backup philosophy is similar across all: physical backups for full instance recovery, logical backups for portability, log shipping for PITR

**Answer outline:**
- MySQL: daily XtraBackup physical backup + binary log archiving for PITR. Replication via GTID-based binlog replication. Tune `innodb_buffer_pool_size` (70-80% of RAM).
- Oracle: RMAN with archived redo logs for PITR. Data Guard physical standby for HA. AWR snapshot analysis for query performance. `v$session`, `v$sql` for active monitoring.
- SQL Server: Always On AG for primary HA target. SQL Server Agent for backup jobs. `sys.dm_exec_requests`, `sys.dm_os_wait_stats` for performance.
- Common thread: understand the transaction log / redo log / WAL equivalent in each engine - it drives backup and replication in all of them.

**Lab exercise:** No specific lab for MySQL/Oracle/SQL Server - bring live work examples from experience.

---

## Question 13: Python Scripting for DBA Automation

**Question:** Give an example of a DBA automation task you built in Python. What libraries did you use, and how did you handle error conditions?

**Why Voleon asks this:** Python is the dominant language at Voleon. DBAs write automation scripts, monitoring tools, and data pipeline components in Python.

**Key points to cover:**
- `psycopg2` or `psycopg3` for PostgreSQL connections
- Parameterized queries - never f-strings for SQL
- Connection pooling in Python: `psycopg2.pool.ThreadedConnectionPool`
- Error handling: catch `psycopg2.OperationalError` separately from `psycopg2.ProgrammingError`
- Context managers: `with conn.cursor() as cur:` ensures cursor cleanup
- Logging: use Python `logging` module, not `print`
- CLI tooling: `argparse` or `click` for DBA scripts that need parameters

**Answer outline:**
- Example: automated bloat report script
  - Connects to all PostgreSQL instances from a config file
  - Queries `pg_stat_user_tables` and `pg_class` for bloat estimation
  - Generates a report showing tables above a bloat threshold
  - Sends results to Slack via webhook if bloat exceeds threshold
- Error handling:
  - `try/except psycopg2.OperationalError` if a database server is unreachable - log and continue to next server
  - `try/except psycopg2.DatabaseError` for query errors - log full traceback, skip that database
  - Never swallow exceptions silently
- Use `with psycopg2.connect(...) as conn:` to ensure connections are closed even on exceptions

**Lab exercise:** cbus lab - Python script that connects to PostgreSQL, runs health checks, and writes results to a log file.

---

## Question 14: Columnar Data Formats (Parquet, Iceberg)

**Question:** Voleon stores ML feature data in Parquet and Apache Iceberg. What do DBAs need to know about these formats, and how do they interact with PostgreSQL?

**Why Voleon asks this:** The DBA needs to support data engineers and ML engineers who work with these formats. Understanding columnar storage is increasingly important for infrastructure DBAs.

**Key points to cover:**
- Parquet is columnar: all values for a column are stored together. This makes column-selective reads extremely fast, but row-level updates are not supported.
- Parquet vs PostgreSQL row store: PostgreSQL is row-oriented (all columns for a row stored together), optimized for OLTP. Parquet is column-oriented, optimized for OLAP/scan workloads.
- Apache Iceberg adds a metadata layer on top of Parquet: table schema, partition spec, snapshot history (time travel), manifest files tracking which Parquet files belong to the table
- Interaction with PostgreSQL: PostgreSQL might write CSV/JSON that gets converted to Parquet, or PostgreSQL might use `parquet_fdw` to query Parquet files directly
- DBAs responsibility: ensure the export pipeline from PostgreSQL to Parquet is reliable, monitor for failures, understand schema evolution compatibility

**Answer outline:**
- Parquet basics: row groups, column chunks, dictionary encoding, Snappy/Zstd compression
- Why ML teams prefer it: a training job reading 100 columns from a 1000-column feature table only reads those 100 columns from disk - massive I/O reduction
- Iceberg table format: adds what RDBMS takes for granted (schema evolution, ACID writes, time travel) to Parquet files in a data lake
- PostgreSQL integration patterns:
  - Nightly COPY to CSV -> Python ETL -> Parquet on Lustre/S3
  - `parquet_fdw` foreign data wrapper for querying Parquet directly in SQL
  - Apache Arrow flight for in-memory columnar data exchange between PostgreSQL and Python
- DBA concern: schema changes in PostgreSQL must be coordinated with Parquet consumers - column renames or type changes break downstream readers

**Lab exercise:** cbus lab - export PostgreSQL data to Parquet using Python and Pandas, inspect the file with `parquet-tools`.

---

## Question 15: Incident Response

**Question:** You get paged at 2am - the primary PostgreSQL database is down. Walk me through your incident response process from alert to resolution.

**Why Voleon asks this:** Financial systems run 24/7. Incident response skill directly impacts RTO and the firm's trading operations.

**Key points to cover:**
- Assess before acting: don't make changes without understanding the failure mode
- Check the obvious first: is the process running, is disk full, is the network reachable?
- PostgreSQL logs are the primary diagnostic tool
- Failover decision: is there a healthy streaming replica? What is its lag?
- Communication: keep stakeholders informed - do not go silent during an incident
- Runbook: the best incident response is following a pre-written runbook, not improvising
- Post-mortem: every P1 incident gets a written post-mortem with timeline and action items

**Answer outline:**
- Receive alert, acknowledge in PagerDuty to stop escalation
- Check: `ssh dbhost`, `sudo systemctl status postgresql`, `sudo journalctl -u postgresql -n 100`
- Common failures:
  - OOM kill: check `dmesg | grep -i oom`, reduce `shared_buffers` or `work_mem`, restart
  - Disk full: `df -h`, identify largest files (WAL accumulation?), clear space, restart
  - Ceph OSD failure: check Ceph health, coordinate with storage team if `pg_wal/` is on affected volume
  - Corrupted data files: do NOT restart, get pgBackRest restore running
- If restart fails or data corruption suspected: initiate failover to replica
  - Verify replica lag with `pg_stat_replication` (must have been near-zero before failure)
  - Promote standby: `pg_ctl promote` or `touch /tmp/promote_trigger`
  - Update DNS or load balancer to point to new primary
  - Notify application teams
- After recovery: write incident timeline, identify root cause, add monitoring to catch it earlier

**Lab exercise:** cbus lab - simulate a crash (kill -9 the PostgreSQL process), observe recovery, practice the diagnostic workflow.

---

## Question 16: Capacity Planning

**Question:** How do you approach capacity planning for a PostgreSQL database that is growing by 50GB per month?

**Why Voleon asks this:** Voleon ingests large volumes of market data continuously. Disk space exhaustion is a preventable crisis that requires proactive planning.

**Key points to cover:**
- Current growth rate: track `pg_database_size()` over time (store in InfluxDB/Prometheus)
- Table-level growth: `pg_total_relation_size()` per table to find which tables are growing fastest
- Data retention: does the data need to be retained forever, or can old data be archived or deleted?
- Partitioning: time-based partitioning allows dropping old partitions cleanly (no bloat, instant delete)
- Storage provisioning lead time: Ceph RBD volume expansion requires coordination with storage team - plan 4+ weeks ahead
- Autovacuum and bloat: a table that looks like it is growing may actually have excessive bloat - vacuum first before expanding storage
- Index growth: indexes grow proportionally with table data - account for them in capacity estimates

**Answer outline:**
- Establish a baseline: query `pg_database_size()` daily, plot the trend in Grafana
- Identify the top 5 tables by size and growth rate using `pg_total_relation_size()`
- Project: at 50GB/month, current free space lasts how long? Alert when 60 days of growth remain.
- Evaluate data lifecycle: market data older than X years - does it need to be in PostgreSQL or can it go to Parquet on Lustre?
- Implement partitioning on large growing tables (time-based by month or year)
- Work with storage team to schedule Ceph volume expansion before the alert threshold is hit
- Set up `max_wal_size` and archiving to prevent `pg_wal/` from growing unboundedly

**Lab exercise:** cbus lab - query pg_table_size and pg_relation_size, create a partitioned table, drop an old partition.

---

## Question 17: Terraform and IaC for Database Infrastructure

**Question:** How would you use Terraform to provision a PostgreSQL database server? What resources would you define and what configuration would you manage outside of Terraform?

**Why Voleon asks this:** IaC is in the JD. Voleon provisions infrastructure repeatably - a DBA who manages servers by hand is a liability at scale.

**Key points to cover:**
- Terraform manages infrastructure: VMs, disks, network interfaces, DNS records, security groups
- Configuration inside the OS (postgresql.conf, pg_hba.conf) is managed by Ansible, not Terraform
- Terraform state: the state file tracks what exists; locking prevents concurrent modifications
- Remote state: store in S3 or a backend with locking (DynamoDB for AWS)
- Sensitive values: passwords do not go in Terraform code - use Vault or AWS Secrets Manager, reference with data source
- Terraform modules: reusable blocks for "PostgreSQL server" that your team can call with parameters

**Answer outline:**
- Terraform resources for a PostgreSQL server:
  - `openstack_compute_instance_v2` (or AWS `aws_instance`) for the VM
  - `openstack_blockstorage_volume_v3` for the Ceph RBD volume
  - `openstack_compute_volume_attach_v2` to attach the volume
  - DNS record pointing at the instance IP
  - Security group rule allowing port 5432 from application subnet
- After Terraform creates the VM: Ansible takes over for OS configuration, PostgreSQL installation, `postgresql.conf` deployment
- What does NOT go in Terraform: database passwords (use Vault), application-level schemas (use Liquibase/Flyway), per-table permissions (Ansible)
- `terraform plan` always before `terraform apply` on production

**Lab exercise:** cbus lab - write a Terraform configuration for a local VM or Docker container representing the database server, plan and apply it.

---

## Question 18: Linux Systems Skills

**Question:** A PostgreSQL server is showing high I/O wait. Walk me through diagnosing the issue on a Linux system.

**Why Voleon asks this:** DBAs at Voleon are infrastructure engineers. They are expected to diagnose OS-level issues, not just database-level issues.

**Key points to cover:**
- `iostat -x 1` - per-device I/O statistics (await, %util, r/s, w/s)
- `iotop` - per-process I/O consumption
- `vmstat 1` - shows wa% (CPU time spent waiting for I/O)
- PostgreSQL processes: `bgwriter`, `checkpointer`, `walwriter` are common I/O sources
- LVM: is the volume on a thin pool? Is the pool overcommitted?
- `blktrace` / `blkparse` for deep block I/O tracing
- SELinux: `ausearch -m avc` if permission denials might be causing I/O retry loops
- Ceph-specific: `ceph osd perf` and `rbd status` to check if the backend is the bottleneck

**Answer outline:**
- Start with `vmstat 1` - if `wa` column is consistently above 10-20%, I/O is a bottleneck
- `iostat -x 1` - identify which device has high `await` (milliseconds per I/O operation)
- `iotop` - identify which process is generating the most I/O
- If PostgreSQL `checkpointer` is the culprit: tune `checkpoint_completion_target`, check `shared_buffers`
- If `walwriter` is the culprit: check `synchronous_commit` settings, check WAL volume growth
- Check LVM: `lvdisplay --maps` to see if the volume has space, `vgdisplay` to see free extents
- If on Ceph: `ceph osd perf` to check if any OSD has high latency; check for rebalancing with `ceph status`

**Lab exercise:** cbus lab - `iostat`, `iotop`, `vmstat` during a checkpoint-heavy workload.

---

## Question 19: Database Networking

**Question:** What network considerations are important when deploying and operating PostgreSQL in a data center environment?

**Why Voleon asks this:** The DBA works with the networking team at Voleon. Understanding ports, latency, and network topology is expected.

**Key points to cover:**
- Default port 5432 for PostgreSQL, 6432 for PgBouncer - these must be open between application servers and DB servers
- Firewall rules: use application-level firewall (iptables/nftables) or network-level ACLs to restrict access to database port
- Latency: even 1ms of added network latency matters for high-frequency transaction workloads
- Jumbo frames: 9000 MTU frames reduce overhead for large sequential reads (backups, bulk loads)
- Network bonding/teaming: database servers should have bonded NICs for bandwidth and redundancy
- Replication traffic: streaming replication uses the same port as client connections (5432) - consider a separate NIC for replication traffic on high-throughput systems
- SSL overhead: enabling SSL adds CPU and latency - acceptable for application traffic, consider impact on replication

**Answer outline:**
- Firewall: allow 5432 only from application subnet, PgBouncer host, monitoring host, and backup server
- DNS: use a stable DNS name for the primary database - easier than updating all application configs during failover
- Latency: benchmark with `pg_test_timing` and `pg_test_fsync` after any network changes
- Replication considerations: if replication lag is a concern, bind the replication connection to a specific interface
- PgBouncer placement: on the application server (reduces one network hop) vs on the database server (centralizes connection management)
- Monitoring: track network I/O on database servers in Grafana - unexpected spikes may indicate backup processes, bulk loads, or runaway queries

**Lab exercise:** cbus lab - configure `pg_hba.conf` to allow connections only from specific IPs, verify with `psql` from an allowed vs denied host.

---

## Question 20: Working in a Quantitative Finance Environment

**Question:** What is different about being a DBA in a quantitative finance firm compared to a typical tech company? How does the nature of the data and the business affect your priorities?

**Why Voleon asks this:** This is a culture and judgment question. Voleon wants someone who understands that the data they manage directly affects financial decisions worth hundreds of millions of dollars.

**Key points to cover:**
- Data integrity is paramount: wrong data in the feature store means wrong model training means wrong signals means bad trades
- Auditability: every change to the database needs to be logged and attributable - who changed what and when
- Reproducibility: ML models trained on historical data must be reproducible - the database must support point-in-time queries
- Regulatory requirements: financial firms have regulatory obligations around data retention, access control, and audit trails
- Low-latency expectations: the scoring pipeline that generates signals has latency budgets measured in milliseconds
- Change management: database schema changes have downstream impact on ML pipelines - a column rename breaks Python code that was working fine
- On-call severity: a database outage at a hedge fund during market hours is a severity-1 incident with real financial impact
- Confidentiality: market data, trading strategies, and position data are among the most confidential information in the firm

**Answer outline:**
- Data correctness over availability: if data is corrupted, it is better to halt than to serve bad data to the trading systems
- Schema changes require coordination: work with ML engineers and data engineers before any DDL change - no "I'll just rename this column quickly"
- Audit everything: use `pgaudit` for DDL logging, maintain a change log, never make undocumented changes
- Test PITR quarterly: the ability to restore to any point in time is not just a best practice - it may be required to reconstruct positions or audit a trading decision
- Performance matters differently: in a consumer web app, a 100ms query is annoying; at Voleon, a 100ms increase in signal generation latency could mean missed execution windows
- Access controls: the DBA themselves should not have standing access to production position data - use role escalation with audit trail for break-glass access
- Understand the business: ask the ML team how the data you manage flows into their models. When you understand that a specific table feeds a specific signal, you prioritize its health differently.

**Lab exercise:** No specific lab exercise - this is a communication and experience question. Prepare a 2-minute story from your own experience where data integrity, auditability, or availability had real business stakes.

---

## Quick Reference: JD Requirement to Question Mapping

| JD Requirement                       | Question Numbers  |
|--------------------------------------|-------------------|
| PostgreSQL internals                 | 1, 2              |
| Replication and HA                   | 3, 9              |
| Backup and recovery                  | 4                 |
| Performance tuning                   | 5, 6, 10          |
| Ceph / distributed storage           | 5                 |
| Containerized databases              | 6                 |
| Ansible / config management          | 7, 17             |
| Redis caching                        | 8                 |
| Connection pooling                   | 9                 |
| Monitoring (Prometheus, Grafana)     | 10                |
| Security                             | 11                |
| Multi-database (MySQL, Oracle, MSSQL)| 12                |
| Python scripting                     | 13                |
| Data formats (Parquet, Iceberg)      | 14                |
| Incident response                    | 15                |
| Capacity planning                    | 16                |
| Terraform / IaC                      | 17                |
| Linux systems                        | 18                |
| Networking                           | 19                |
| Quant finance domain awareness       | 20                |

---

## Interview Format Notes

Voleon's typical technical interview format:
- Round 1: hiring manager screen - background, experience breadth, culture fit
- Round 2: technical deep dive - PostgreSQL internals, one of the first 5 questions almost guaranteed
- Round 3: systems interview - Linux, storage, networking (questions 5, 18, 19)
- Round 4: practical exercise - given a PostgreSQL instance with performance problems, diagnose and tune
- Final: team fit, working style, incident response philosophy

For the practical exercise: bring up `pg_stat_activity`, `pg_stat_statements`, and `EXPLAIN ANALYZE` immediately. Do not guess at performance problems - measure first.
