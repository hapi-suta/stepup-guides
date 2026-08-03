# Tier 4 Interview Questions - Availability and Replication
## AWS RDS and Aurora PostgreSQL

Graduated difficulty: Junior -> Mid -> Senior -> Principal.

Use these for self-testing, mock interviews, or whiteboard practice.

---

## Topic 1: RDS Multi-AZ

### Junior

**Q1.** What is the purpose of RDS Multi-AZ? What problem does it solve?

> **Answer:** Multi-AZ keeps a standby copy of your database in a second Availability Zone. If the primary instance fails (hardware failure, AZ outage, OS crash), AWS automatically promotes the standby. The DNS endpoint stays the same - applications reconnect to the same hostname. It solves the single point of failure problem for RDS instances.

**Q2.** Can you read from the Multi-AZ standby instance?

> **Answer:** For Multi-AZ Instance (the original, common type), NO - the standby is completely passive and does not accept connections. For Multi-AZ DB Cluster (the newer type), YES - both reader instances accept read connections. Many people confuse these two.

**Q3.** What is the expected downtime during a Multi-AZ failover?

> **Answer:** For Multi-AZ Instance: typically 60-120 seconds. This includes time for AWS to detect the failure, update DNS, and wait for the standby to start accepting connections. The DNS TTL for RDS is 60 seconds which is part of this window. For Multi-AZ DB Cluster: typically under 35 seconds.

### Mid

**Q4.** How do you trigger a Multi-AZ failover using the CLI? What flag is required?

> **Answer:** `aws rds reboot-db-instance --db-instance-identifier [id] --force-failover`. The `--force-failover` flag is required - without it, a reboot just restarts the primary in place. With `--force-failover`, the reboot forces traffic to the standby, simulating a real failover.

**Q5.** After a Multi-AZ failover, what changes and what stays the same?

> **Answer:** Changes: The Availability Zone of the primary (it moves to the old standby's AZ). The IP address that the DNS endpoint resolves to. The `pg_postmaster_start_time()` value (the new primary has a recent start time). Stays the same: The DNS endpoint hostname. The database contents. The connection string used by applications. The database parameter groups and security groups.

**Q6.** A developer asks: "We have Multi-AZ, so we have no downtime during failover, right?" How do you respond?

> **Answer:** Not exactly. Multi-AZ reduces downtime to 60-120 seconds, but it does not eliminate it. During that window, connections fail and applications will get errors. The hostname stays the same, but your application must retry the connection after DNS updates. Applications without connection retry logic will show errors to users. "No downtime" is only achievable with Aurora (which is faster and has a reader endpoint) combined with proper application retry logic.

### Senior

**Q7.** Explain the difference between Multi-AZ Instance and Multi-AZ DB Cluster. When would you choose one over the other?

> **Answer:** Multi-AZ Instance: one primary, one passive standby (not readable), 60-120 second failover, supported on all instance classes including t3.micro, all RDS engines. Multi-AZ DB Cluster: one writer, two readers (readable), under 35 second failover, requires r-series or m-series instances, PostgreSQL and MySQL only, uses shared cluster storage. Choose Multi-AZ Instance for cost-sensitive or non-PostgreSQL workloads. Choose Multi-AZ DB Cluster for PostgreSQL where you want faster failover, readable standbys, and can afford the larger instance class minimum.

**Q8.** What happens to the old primary after a Multi-AZ failover? Does AWS delete it?

> **Answer:** The old primary is not deleted. AWS converts it to the new standby. After recovery, it is synchronized with the new primary (which was the old standby) and starts operating as a passive standby in the original AZ. This means your Multi-AZ setup is restored automatically. You can optionally trigger another failover to switch back to the original AZ if you want.

---

## Topic 2: RDS Read Replicas

### Junior

**Q1.** What is the difference between a read replica and a Multi-AZ standby?

> **Answer:** A Multi-AZ standby: passive, not readable, exists only for failover, in the same region. A read replica: active, readable, serves read traffic, can be in the same region or a different region. You use replicas to scale reads and for cross-region DR. You use Multi-AZ for HA and failover protection.

**Q2.** How does replication work between an RDS primary and a read replica?

> **Answer:** RDS uses PostgreSQL streaming replication. The primary continuously sends WAL (Write-Ahead Log) records to the replica. The replica applies these WAL records to stay in sync. The replication is asynchronous - the primary does not wait for the replica to confirm before committing a transaction. This is why replica lag exists.

**Q3.** How do you check if you are connected to a replica vs the primary?

> **Answer:** Run `SELECT pg_is_in_recovery();`. Returns `t` (true) on a replica, `f` (false) on the primary. Replicas are in "recovery mode" because they continuously replay WAL from the primary.

### Mid

**Q4.** What causes replica lag? How do you measure it?

> **Answer:** Causes: heavy write load on the primary (replica has more WAL to apply), large transactions (replica must process the entire transaction before it is visible), network issues between primary and replica (especially for cross-region replicas), slow I/O on the replica instance. Measurement: SQL: `SELECT now() - pg_last_xact_replay_timestamp()` on the replica. CloudWatch: `ReplicaLag` metric in seconds for RDS. `AuroraReplicaLag` in milliseconds for Aurora.

**Q5.** A cross-region read replica is created using `--source-db-instance-identifier`. What value do you use for cross-region replicas vs same-region?

> **Answer:** Same-region: you can use just the instance identifier (e.g., `my-postgres`). Cross-region: you MUST use the full ARN (e.g., `arn:aws:rds:us-east-1:123456789012:db:my-postgres`). The ARN is needed because AWS must uniquely identify the source across regions. The AWS CLI also needs to be targeting the DESTINATION region when creating the replica.

**Q6.** What does "promote a read replica" mean? Is it reversible?

> **Answer:** Promoting a replica makes it a standalone read-write database. It stops receiving replication from the primary. It no longer has any connection to the original primary. It is NOT reversible - you cannot re-attach it to the primary. After promotion, it is a completely independent database. Use promotion for: DR when the primary is gone, migration to a new region, splitting databases.

### Senior

**Q7.** An application performs a write, then immediately reads the same row. It sometimes sees stale data. What is happening and how do you fix it?

> **Answer:** The application wrote to the primary and then read from a read replica. Due to async replication lag, the replica has not yet received and applied that write. Solutions: (1) Read from the writer endpoint for post-write reads. (2) Use Aurora with `SET aurora_replica_read_consistency = 'SESSION'` which ensures the reader waits for the replica to catch up to your session's LSN before serving the read. (3) Add a short sleep before reading (fragile, not recommended). (4) Use a session-level flag in the application to route post-write reads to the writer.

**Q8.** What is the maximum number of read replicas for RDS PostgreSQL vs Aurora?

> **Answer:** RDS PostgreSQL: maximum 5 read replicas per primary. Aurora: maximum 15 Aurora replicas per cluster. However, for Aurora Global Database, the secondary region can have up to 16 readers. The practical limit is usually cost and diminishing returns from read distribution.

---

## Topic 3: Aurora Storage Architecture

### Junior

**Q1.** How is Aurora storage different from RDS storage?

> **Answer:** RDS uses Amazon EBS volumes - each instance has its own separate volume. You provision a fixed size (e.g., 20 GB). Aurora uses a distributed, shared storage layer. All instances in the cluster share one storage volume. You do not choose a size - it grows automatically in 10 GB increments. Aurora storage is maintained by AWS outside of any EC2 instance.

**Q2.** How many copies of your data does Aurora keep? Where are they stored?

> **Answer:** Aurora keeps 6 copies across 3 Availability Zones - 2 copies per AZ. This is automatic and cannot be changed. You pay for the storage used, not the copies. You cannot see or access the individual storage nodes.

**Q3.** What does it mean that Aurora is "log-structured"?

> **Answer:** Aurora only writes redo log records to storage, not full data pages. When a page is needed, the storage layer applies the redo log records to reconstruct it. This is different from traditional PostgreSQL which writes full pages to disk. The benefit is faster writes (less data to write over the network) and near-instant crash recovery (no WAL replay needed on the instance after a crash).

### Mid

**Q4.** How many storage node failures can Aurora survive without losing data access?

> **Answer:** Write quorum requires 4 of 6 nodes. If 2 nodes fail (including the case where one entire AZ is lost), Aurora can still write (4 of 6 remaining). If 3 nodes fail, Aurora can still read (read quorum = 3 of 6) but cannot write. If more than 3 nodes fail, Aurora may be unavailable. In practice, losing a full AZ (2 nodes) is the most common failure scenario and Aurora handles it transparently.

**Q5.** Why does `pg_stat_replication` show no rows on an Aurora writer with readers?

> **Answer:** `pg_stat_replication` shows active WAL streaming connections. Aurora replicas do not use WAL streaming - they read directly from the shared storage layer. There is no WAL sender process on the writer and no WAL receiver on the readers. Instead, the writer sends "cache invalidation" messages to replicas to tell them "data changed at LSN X, re-read it." This is why Aurora replica lag is near-zero and why Aurora handles up to 15 replicas efficiently.

**Q6.** What is the maximum storage size for an Aurora cluster?

> **Answer:** 128 TB (tebibytes). Aurora storage grows in 10 GB increments automatically. There is no shrink - once space is allocated, it stays allocated (internally the space can be reused for new data, but the volume size number does not decrease). You can check remaining space with the CloudWatch `AuroraVolumeBytesLeftTotal` metric.

### Senior

**Q7.** Explain "redo offload" in Aurora and why it matters for performance.

> **Answer:** In standard PostgreSQL, the database instance must: (1) write WAL records, (2) apply WAL to buffer pages, (3) eventually flush dirty pages from buffer to disk. This causes "checkpoint storms" - periods of heavy I/O when PostgreSQL flushes many dirty pages. In Aurora, the instance only writes redo log records to the storage layer. The storage layer applies the redo log and serves pages. The instance never needs to flush dirty pages - there are no checkpoints causing I/O spikes. This means Aurora has more consistent I/O performance and can handle write-heavy workloads better than standard PostgreSQL on EBS.

---

## Topic 4: Aurora Replicas and Failover Tiers

### Junior

**Q1.** What is a failover tier in Aurora? What is the valid range?

> **Answer:** A failover tier (promotion tier) is a priority number (0-15) assigned to each Aurora reader. When the writer fails, Aurora promotes the reader with the lowest tier number first. Tier 0 = highest priority. Tier 15 = lowest priority. If two readers have the same tier, Aurora promotes the one with the larger instance class.

**Q2.** How much replica lag do Aurora replicas typically have vs RDS read replicas?

> **Answer:** Aurora replicas: typically under 100 milliseconds, often under 20ms. RDS read replicas: typically 100-500ms at low load, can be seconds under heavy write load. Aurora is faster because replicas share storage and do not need to receive and apply WAL. They just see the latest changes in shared storage.

### Mid

**Q3.** If you have 3 Aurora replicas at tiers 0, 1, 2, and the writer fails, which one becomes the new writer?

> **Answer:** The replica at tier 0 becomes the new writer (highest priority = lowest tier number). If the tier-0 reader is unavailable, Aurora tries tier-1. If that is also unavailable, tier-2. If all named priorities fail, Aurora will promote whatever reader is available.

**Q4.** After an Aurora failover, what happens to the original writer?

> **Answer:** The original writer becomes a reader. It is automatically re-added to the cluster as a reader instance. The cluster retains all instances - no instance is deleted. The old writer starts serving reads from the reader endpoint. You can trigger another failover back to the original writer if desired.

### Senior

**Q5.** How would you configure Aurora replicas for a workload where you have a large analytics reader and two small OLTP readers, and you want the analytics reader to NEVER become the writer during failover?

> **Answer:** Set the two OLTP readers to tier 0 and tier 1. Set the analytics reader to tier 15 (lowest priority). During failover, Aurora will promote the OLTP readers first. The analytics reader becomes writer only if BOTH OLTP readers are also unavailable simultaneously - an extremely unlikely scenario. Additionally, consider using a custom endpoint for the analytics reader so its connection routing is independent of the writer/reader endpoints.

---

## Topic 5: Aurora Endpoints

### Junior

**Q1.** Name the four types of Aurora endpoints. What is each used for?

> **Answer:** (1) Cluster endpoint (Writer endpoint) - always points to the current writer. Use for all writes. (2) Reader endpoint - load balances across all readers. Use for reads. Falls back to writer if no readers exist. (3) Instance endpoint - points to a specific instance by ID. Use for DBA diagnostics only. (4) Custom endpoint - you define which instances it includes. Use for routing specific workloads (analytics, reporting) to specific instances.

**Q2.** What is the DNS TTL for Aurora endpoints? Why does it matter?

> **Answer:** 5 seconds. It matters because after a failover, the endpoint DNS record is updated to point to the new writer. Applications that respect the 5-second TTL will reconnect to the new writer within 5 seconds. Applications that cache DNS longer (common in Java without JVM flags) will still try to connect to the old instance (which is now a reader) for longer, causing errors or misdirected writes.

### Mid

**Q3.** Can an application use the reader endpoint for writes if there are no readers in the cluster?

> **Answer:** The reader endpoint falls back to the writer if no readers exist. So technically yes, writes "work." But this is dangerous design. The reader endpoint is marked as read-only in Aurora's routing logic. When you add readers, writes to the reader endpoint will suddenly fail. Never design an application to write to the reader endpoint, even if it appears to work.

**Q4.** You create a custom endpoint pointing to `reader-2`. During a failover, `reader-2` gets promoted to writer. What happens to your custom endpoint?

> **Answer:** The custom endpoint becomes unavailable. Custom endpoints with static members (specific instances) do not automatically swap to a different instance. Since `reader-2` is now the writer and no longer a reader, the READER-type custom endpoint cannot serve it. The endpoint goes offline until you update its membership to include a valid reader instance.

### Senior

**Q5.** How would you use Aurora endpoints to implement a "poor man's pgBouncer" - routing different application services to different reader instances?

> **Answer:** Create one custom endpoint per service type: (1) Custom endpoint A: `--static-members reader-1,reader-2` for the main API service. (2) Custom endpoint B: `--static-members reader-3` for the reporting service. (3) Custom endpoint C: `--static-members reader-4` for the analytics service. Each service connects to its designated custom endpoint. This provides workload isolation without a connection pooler. The limitation vs pgBouncer: no connection pooling, no statement routing within a session, and custom endpoints are vulnerable to failover if their member instances are promoted.

---

## Topic 6: Aurora Global Database

### Junior

**Q1.** What is an Aurora Global Database and why would you use it?

> **Answer:** An Aurora Global Database spans multiple AWS regions. One region is the primary (read-write). Other regions are secondaries (read-only, with near-zero lag). Use cases: (1) Serve reads with low latency to users in multiple regions. (2) Disaster recovery - if the primary region fails, promote a secondary. (3) Compliance - keep a copy of data in a specific region.

**Q2.** Is Aurora Global Database failover automatic or manual?

> **Answer:** Manual. Unlike single-cluster Aurora failover (which is automatic), Global Database requires a human to initiate the failover. For planned failovers, use `aws rds switchover-global-cluster`. For unplanned (region outage), use `aws rds remove-from-global-cluster` to detach the secondary and promote it. AWS designed it this way to avoid automatic "split-brain" scenarios where both regions might think they are the primary.

**Q3.** What is the typical replication lag for Aurora Global Database?

> **Answer:** Under 1 second (typically 100-500ms) for cross-region replication. AWS guarantees less than 1 second under normal conditions. This is much better than RDS cross-region read replicas which can have 1-5 seconds of lag. Aurora's storage-level replication is more efficient than WAL streaming across regions.

### Mid

**Q4.** What is write forwarding in Aurora Global Database? When would you use it?

> **Answer:** Write forwarding allows applications in the secondary region to send writes to the secondary's endpoint. Aurora automatically forwards those writes to the primary region for execution. Use it when: your application in the secondary region needs to write occasionally, and you do not want to update application code to connect to the primary region for writes. Do NOT use it for high-frequency writes because each write incurs the cross-region round-trip latency (100-500ms added to each write operation).

**Q5.** Explain the difference between `switchover-global-cluster` and `remove-from-global-cluster`.

> **Answer:** `switchover-global-cluster` - planned, non-destructive. The primary waits for replication to reach zero lag, then demotes to secondary. The selected secondary is promoted to primary. Both regions remain in the Global Database but with roles reversed. Zero data loss. Takes 5-20 minutes. Use for planned maintenance or migration. `remove-from-global-cluster` - used for unplanned failures or when the primary is unreachable. Detaches the secondary cluster. It becomes an independent read-write cluster immediately. The global database relationship is broken. Some data may be lost (RPO = last replication timestamp). Use for real DR situations.

### Senior

**Q6.** Design a Global Database architecture for a financial application that must have RPO near-zero and RTO under 5 minutes for a regional failure. What are the gaps between this requirement and what Aurora Global Database provides?

> **Answer:** Architecture: Primary in us-east-1 (db.r6g.xlarge), secondary in us-west-2 (db.r6g.large for reads). Planned failover script tested and documented. RPO assessment: Sub-1-second replication lag in normal conditions means RPO is near-zero for a sudden outage. However, if the primary suffers data corruption before failing, that corruption may replicate. RPO is technically "last good replication point" which may be seconds before failure. Gaps: (1) RTO: Manual failover process. Even a scripted `remove-from-global-cluster` + application reconfiguration takes 3-5 minutes minimum. AWS does not guarantee sub-5-minute RTO. (2) Application failover: the app must also switch endpoints, which requires DNS change or Route 53 failover. (3) No automatic detection: you must detect the regional failure before you can start failover. CloudWatch alarms + SNS to oncall is needed. Recommended: Script the entire DR procedure, test quarterly, include application endpoint update in the script, and set CloudWatch alarms that page oncall within 1 minute of regional connectivity loss.

---

## Topic 7: Aurora Serverless v2

### Junior

**Q1.** What is an ACU? How much RAM does 1 ACU represent?

> **Answer:** ACU = Aurora Capacity Unit. 1 ACU = approximately 2 GB of RAM plus proportional CPU and network resources. So 4 ACU = ~8 GB RAM, 8 ACU = ~16 GB RAM, 16 ACU = ~32 GB RAM. You pay per ACU-hour for Serverless v2.

**Q2.** Can Aurora Serverless v2 scale to zero when there are no connections?

> **Answer:** No. The minimum is 0.5 ACU. Serverless v2 cannot scale to zero. The original Aurora Serverless v1 could scale to zero (after a period of inactivity), but v1 is being deprecated. If you need scale-to-zero, v1 is the only Aurora option, but it has significant trade-offs (cold start delay of 25+ seconds, limited features).

**Q3.** What instance class do you specify when creating a Serverless v2 instance?

> **Answer:** `db.serverless`. This is a special class name that enables Serverless v2 scaling. The actual capacity (min/max ACU) is configured at the cluster level with `--serverless-v2-scaling-configuration`. The instance class itself just says "this instance uses serverless scaling."

### Mid

**Q4.** What is a mixed cluster in Aurora Serverless v2? Give a production use case.

> **Answer:** A mixed cluster has both provisioned and Serverless v2 instances in the same Aurora cluster. Example: provisioned writer (db.r6g.2xlarge) + Serverless v2 readers. Use case: an e-commerce platform where the write load is predictable and steady (good for provisioned - no scaling delays) but read traffic spikes during sales (good for Serverless v2 - auto-scales to handle traffic). The writer has predictable cost and performance. The readers auto-scale from 1 ACU at night to 12 ACU during sale events.

**Q5.** When is Serverless v2 NOT cost-effective compared to provisioned instances?

> **Answer:** When load is steady and high. At sustained 8 ACU, Serverless v2 costs $0.96/hr (at $0.12/ACU-hr in us-east-1). A db.r6g.xlarge (4 vCPU, 32 GB, ~16 ACU equivalent) costs $0.48/hr - half the cost for more capacity. Break-even for Serverless v2 is when your average ACU is much lower than your peak ACU (high variance workloads). Rule of thumb: if your workload averages more than 50% of its peak ACU consistently, provisioned is cheaper.

### Senior

**Q6.** A Serverless v2 cluster is at its MaxCapacity and queries are queuing. Walk through your diagnosis and fix.

> **Answer:** Diagnosis: (1) Check CloudWatch `ServerlessDatabaseCapacity` - if Average = Maximum for 5+ minutes, you have hit the ceiling. (2) Check `DatabaseConnections` - high connection count confirms queuing. (3) Connect and run `SELECT COUNT(*) FROM pg_stat_activity WHERE wait_event IS NOT NULL` to count waiting connections. (4) Check `CPUUtilization` - if consistently 100%, CPU-bound workload is driving the ACU need. Immediate fix: `aws rds modify-db-cluster --serverless-v2-scaling-configuration MinCapacity=X,MaxCapacity=Y --apply-immediately`. The cluster begins scaling within 1-2 minutes. Root cause: (1) MaxCapacity was set too low. (2) A new query pattern appeared (bad query using full table scans). (3) Traffic grew beyond the original capacity plan. Prevention: Set CloudWatch alarm at 80% of MaxCapacity, not 100%.

**Q7.** Compare the cold start behavior of Serverless v2 vs Serverless v1 and explain the operational implications.

> **Answer:** Serverless v1 cold start: when traffic comes in after an idle period (scale-to-zero), the cluster takes 25-45 seconds to start up. Connections timeout during this period. Application must handle "cold start errors" with retry logic. Serverless v2 cold start: no cold start in the traditional sense. Minimum is 0.5 ACU, always running. Scale-up from 0.5 to a higher ACU takes seconds (not 45 seconds). The initial scale-up may cause a brief latency spike as CPU warms up. Operational implication: v2 is better for latency-sensitive production workloads. v1 cold starts are acceptable for dev/test environments that can tolerate 45-second delays. If you use v2 and need fast response from a mostly-idle cluster, set a higher minimum ACU (e.g., 2 ACU instead of 0.5) to keep the cluster warm.

**Q8.** A client wants to use Serverless v2 for their Aurora Global Database secondary region. Is this supported? What are the trade-offs?

> **Answer:** Yes, this is supported. You can have Serverless v2 instances in a Global Database secondary cluster. Trade-offs: Benefits: the secondary region auto-scales its read capacity based on actual demand. Cost savings if secondary region reads are variable. The secondary can use a lower MaxACU than the primary since it serves only reads plus needs headroom for potential promotion. Risks: If the secondary is promoted to primary (DR scenario), the Serverless v2 configuration must handle write load. If the secondary's MaxCapacity is too low, write performance after promotion will be poor. Recommendation: Set the secondary's MaxCapacity to match or exceed the primary's expected write load during peak, even though the secondary is normally serving reads. This ensures a smooth promotion with adequate write capacity.

---

## Bonus: Scenario-Based Questions

**Scenario A:** An application connects to the Aurora reader endpoint but sometimes gets a "cannot execute INSERT in a read-only transaction" error, even though no writes are going to the reader endpoint. Why?

> **Answer:** The reader endpoint falls back to the writer when no readers are available. After a failover, there may be a brief period where the old writer has stepped down but the new replicas have not yet joined the reader endpoint pool. During this window, the reader endpoint serves the writer. Writes appear to succeed. But when the replicas join the pool, future connections land on replicas where writes fail. Fix: never write to the reader endpoint, even in fallback scenarios. Design the application to use the writer endpoint exclusively for writes.

**Scenario B:** Your RTO for an Aurora cluster is 30 seconds. You configure one reader with failover tier 0. After a planned failover test, you measure 45 seconds of downtime. What could be causing the extra time?

> **Answer:** Several possibilities: (1) Application DNS caching - the app is cached to the old IP longer than Aurora's 5-second TTL. Check JVM DNS cache settings (`-Dnetworkaddress.cache.ttl`). (2) Connection pool does not retry quickly enough - the pool may wait longer before retrying after a disconnect. Tune the connection timeout and retry settings. (3) The reader at tier 0 is on a heavily loaded instance - Aurora first needs to detect the writer failure, then the reader needs to apply any pending changes. If the reader had some backlog even with near-zero lag, this adds time. (4) AWS detection time - AWS uses health checks to detect writer failure. This can add 10-15 seconds before failover starts.

**Scenario C:** You need to migrate your production database from us-east-1 to us-west-2 with under 5 minutes of downtime. Design the migration plan using Aurora Global Database.

> **Answer:** (1) Create Aurora Global Database with us-east-1 as primary. (2) Add us-west-2 as secondary. (3) Wait for replication lag to stabilize under 1 second. (4) Schedule a maintenance window. (5) Put the application in read-only mode or maintenance page. (6) Confirm lag drops to zero. (7) Run `aws rds switchover-global-cluster --target-db-cluster-identifier [us-west-2 ARN]`. This is a planned switchover - no data loss. (8) Wait for switchover to complete (5-20 min). (9) Update application connection strings to us-west-2 endpoints. (10) Remove read-only mode. (11) Verify application is healthy in us-west-2. (12) Optionally remove us-east-1 as a secondary or keep it for DR. Total downtime: only steps 5-10 require downtime. Steps 7-10 take roughly 5-10 minutes. With scripting and pre-staging the connection string change, downtime can be under 5 minutes.
