# Module 05 Interview Prep - HA, Replication, and Failover
## Aurora PostgreSQL - DevOps DBA Training Track

Graduated difficulty: Junior -> Mid -> Senior -> Principal.

Use these for self-testing, mock interviews, or whiteboard practice.

---

## Topic 1: Aurora Multi-AZ and Shared Storage

### Junior

**Q1.** How many copies of your data does Aurora keep, and where are they stored?

> **Answer:** Aurora keeps 6 copies across 3 Availability Zones - 2 copies per AZ. This is automatic and cannot be changed. You do not provision or manage these copies. Aurora's storage layer handles replication transparently. You pay for the storage used, not for the copies.

**Q2.** What is the difference between Aurora's storage model and standard RDS (EBS-based) storage?

> **Answer:** RDS uses Amazon EBS volumes - each instance has its own separate volume. You provision a fixed size (e.g., 100 GB). Aurora uses a distributed, shared storage layer. All instances in the cluster share one storage volume. You do not choose a size - it grows automatically in 10 GB increments up to 128 TB. Aurora storage is maintained by AWS outside of any EC2 instance.

**Q3.** What happens to your data if one entire Availability Zone goes down?

> **Answer:** Aurora continues operating normally. With 6 copies across 3 AZs, losing one AZ means losing 2 copies. Aurora needs 4 of 6 copies for writes and 3 of 6 for reads. With 4 copies remaining, both reads and writes continue without interruption. The storage layer automatically repairs the missing copies when the AZ recovers.

### Mid

**Q4.** Aurora is "log-structured." What does that mean and why does it matter for performance?

> **Answer:** Aurora only writes redo log records to storage, not full data pages. The storage layer applies redo logs to reconstruct pages when needed. This is different from standard PostgreSQL which writes full pages to disk, causing "checkpoint storms" - periods of heavy I/O when PostgreSQL flushes dirty pages. Aurora has no checkpoints, which means more consistent I/O performance and faster crash recovery (no WAL replay needed on the instance).

**Q5.** Why does `pg_stat_replication` show no rows on an Aurora writer even when readers are active?

> **Answer:** Aurora replicas do not use WAL streaming replication. There is no WAL sender on the writer and no WAL receiver on the readers. Instead, replicas read directly from the shared storage layer. The writer sends "cache invalidation" messages to replicas saying "data changed at LSN X, re-read it." This is why `pg_stat_replication` is empty and why Aurora handles up to 15 replicas efficiently without adding replication overhead to the writer.

---

## Topic 2: Aurora Failover

### Junior

**Q6.** How long does an Aurora failover typically take? What happens during that time?

> **Answer:** Aurora failover typically takes 20-35 seconds. During that time: (1) the old writer stops accepting connections, (2) Aurora promotes the highest-priority reader, (3) DNS is updated (TTL is 5 seconds), (4) the new writer starts accepting connections. Applications see connection errors during this window and must reconnect.

**Q7.** What is a failover tier? What is the valid range?

> **Answer:** A failover tier (promotion tier) is a priority number (0-15) assigned to each Aurora reader. When the writer fails, Aurora promotes the reader with the lowest tier number first. Tier 0 = highest priority (promoted first). Tier 15 = lowest priority (promoted last). If two readers have the same tier, Aurora promotes the one with the larger instance class.

### Mid

**Q8.** You have 3 Aurora readers: a large analytics reader and two small OLTP readers. How do you configure failover tiers so the analytics reader never becomes the writer?

> **Answer:** Set the two OLTP readers to tier 0 and tier 1. Set the analytics reader to tier 15 (lowest priority). During failover, Aurora promotes tier 0 first, then tier 1. The analytics reader at tier 15 only becomes writer if BOTH OLTP readers are unavailable simultaneously - an extremely unlikely scenario. Additionally, use a custom endpoint for the analytics reader to keep its traffic separate.

**Q9.** After an Aurora failover, what happens to the original writer instance?

> **Answer:** The original writer becomes a reader. It is automatically re-added to the cluster as a reader instance. No instance is deleted. The old writer starts serving reads from the reader endpoint. You can trigger another failover back to the original writer if desired. This is different from RDS Multi-AZ where the old primary becomes the new standby (passive, not readable).

### Senior

**Q10.** A developer says "We tested failover and it took 45 seconds, but our RTO target is 30 seconds." What could be causing the extra time?

> **Answer:** Several possibilities: (1) Application DNS caching - the app resolves the old IP longer than Aurora's 5-second TTL. Check JVM DNS cache settings (`-Dnetworkaddress.cache.ttl=1`). (2) Connection pool retry is too slow - the pool waits too long before retrying after a disconnect. Tune retry intervals. (3) The reader at tier 0 was heavily loaded - Aurora needs a moment for the reader to apply pending changes. (4) AWS detection time adds 10-15 seconds before failover starts. Solutions: use RDS Proxy (detects failover faster), tune connection pool settings, set DNS TTL correctly in the application.

---

## Topic 3: Aurora Endpoints

### Junior

**Q11.** Name the four types of Aurora endpoints. What is each used for?

> **Answer:** (1) Cluster endpoint (Writer endpoint) - always points to the current writer. Use for all writes and critical reads. (2) Reader endpoint - load balances across all readers using DNS round-robin. Use for read traffic. Falls back to writer if no readers exist. (3) Instance endpoint - points to a specific instance by ID. Use for DBA diagnostics only, never in application code. (4) Custom endpoint - you define which instances it includes. Use for routing specific workloads (analytics, reporting) to specific instances.

**Q12.** What is the DNS TTL for Aurora endpoints and why does it matter?

> **Answer:** 5 seconds. After a failover, the endpoint DNS record is updated to point to the new writer. Applications that respect the 5-second TTL reconnect to the new writer within 5 seconds. Applications that cache DNS longer (common in Java without JVM flags) will still try to connect to the old instance, causing errors. Always verify your application respects short DNS TTLs.

### Mid

**Q13.** An application connects to the reader endpoint but sometimes gets "cannot execute INSERT in a read-only transaction." No writes are going to the reader endpoint. What is happening?

> **Answer:** The reader endpoint falls back to the writer when no readers are available. After a failover, there may be a brief period where the old writer stepped down but new replicas have not yet joined the reader endpoint pool. During this window, the reader endpoint serves the writer, and writes appear to succeed. But when replicas join, future connections land on replicas where writes fail. Fix: never write to the reader endpoint, even if it appears to work.

---

## Topic 4: Replica Lag

### Junior

**Q14.** What causes replica lag on Aurora? How do you measure it?

> **Answer:** Causes: heavy write load on the writer (more changes for replicas to pick up), large transactions, network issues between storage and replicas. Measurement: SQL: `SELECT now() - pg_last_xact_replay_timestamp()` on the reader. CloudWatch: `AuroraReplicaLag` metric in milliseconds. Aurora replica lag is typically under 100ms (often under 20ms) because replicas share storage and do not need to receive and apply WAL like RDS replicas.

### Mid

**Q15.** A user updates their profile, and the confirmation page shows old data. What is happening and how do you fix it?

> **Answer:** The application wrote to the writer endpoint and immediately read from the reader endpoint. Due to async replication lag (even a few milliseconds), the reader has not yet picked up the change. This is the "read-your-own-writes" problem. Solutions: (1) Route post-write reads to the writer endpoint temporarily. (2) Use Aurora's `SET aurora_replica_read_consistency = 'SESSION'` which makes the reader wait until it catches up to your session's LSN. (3) Add application logic that routes post-write reads to the writer for a short window (e.g., 2 seconds).

---

## Topic 5: Aurora Global Database

### Junior

**Q16.** What is an Aurora Global Database? When would you use it?

> **Answer:** An Aurora Global Database spans multiple AWS regions. One region is the primary (read-write). Other regions are secondaries (read-only, with sub-second replication lag). Use cases: (1) Low-latency reads for users in multiple regions. (2) Disaster recovery - if the primary region fails, promote a secondary. (3) Compliance - keep data in a specific geographic region.

### Mid

**Q17.** What is the difference between `switchover-global-cluster` and `remove-from-global-cluster`?

> **Answer:** `switchover-global-cluster` - planned, non-destructive. The primary waits for replication lag to reach zero, then demotes to secondary. The selected secondary promotes to primary. Both regions remain in the Global Database with roles reversed. Zero data loss. Takes 5-20 minutes. Use for planned maintenance or migration. `remove-from-global-cluster` - used for unplanned failures. Detaches the secondary cluster. It becomes an independent read-write cluster immediately. The Global Database relationship is broken. Some data may be lost (RPO = replication lag at time of failure). Use for real DR situations.

**Q18.** Why does Aurora Global Database NOT automatically fail over to another region?

> **Answer:** By design, AWS prevents automatic cross-region failover to avoid "split-brain" scenarios. If network connectivity between regions is lost, automatic failover could cause both regions to become primary independently, leading to conflicting writes and data corruption. Manual failover forces a human to confirm that the primary region is truly down before promoting the secondary. This is a safety feature, not a limitation.

### Senior

**Q19.** Design a Global Database architecture for a financial application with RPO near-zero and RTO under 5 minutes. What are the gaps?

> **Answer:** Architecture: Primary in us-east-1 (db.r6g.xlarge), secondary in us-west-2 (db.r6g.large). Scripted DR procedure tested quarterly. RPO assessment: Sub-1-second replication lag normally means near-zero data loss for sudden outage. But if primary suffers data corruption before failing, that corruption replicates. Gaps: (1) RTO: Manual `remove-from-global-cluster` plus application reconfiguration takes 3-5 minutes minimum. (2) Application failover: the app must switch endpoints. Use Route 53 failover routing. (3) No automatic detection: you must detect the failure first. Need CloudWatch alarms plus SNS to on-call. Recommendation: Script the entire procedure, include endpoint updates, test quarterly.

---

## Topic 6: Aurora Serverless v2

### Junior

**Q20.** What is an ACU and how much RAM does 1 ACU represent?

> **Answer:** ACU = Aurora Capacity Unit. 1 ACU = approximately 2 GB of RAM plus proportional CPU and network. So 4 ACU = ~8 GB RAM, 8 ACU = ~16 GB RAM, 16 ACU = ~32 GB RAM. You pay per ACU-hour. The minimum is 0.5 ACU.

**Q21.** Can Aurora Serverless v2 scale to zero?

> **Answer:** No. The minimum is 0.5 ACU. Serverless v2 cannot scale to zero. It is always running and always costs at least 0.5 ACU-hours. The original Serverless v1 could scale to zero but had a 25-45 second cold start and is being deprecated.

### Mid

**Q22.** When is Serverless v2 NOT cost-effective compared to provisioned instances?

> **Answer:** When load is steady and high. At sustained 8 ACU, Serverless v2 costs approximately $0.96/hr (at $0.12/ACU-hr in us-east-1). A db.r6g.xlarge (4 vCPU, 32 GB, roughly 16 ACU equivalent) costs about $0.48/hr - half the cost for more capacity. Rule of thumb: if your workload averages more than 50% of its peak ACU consistently, provisioned is cheaper. Serverless v2 saves money when you have high variance between peak and idle (e.g., 1 ACU at night, 12 ACU during business hours).

**Q23.** What is a mixed cluster in Aurora and when would you use it?

> **Answer:** A mixed cluster has both provisioned and Serverless v2 instances in the same Aurora cluster. Example: provisioned writer (db.r6g.2xlarge) for predictable write load, plus Serverless v2 readers for variable read traffic. Use case: e-commerce platform where writes are steady but read traffic spikes during sales events. The writer has fixed cost and consistent performance. The readers auto-scale from 1 ACU at night to 12 ACU during peak.

### Senior

**Q24.** A Serverless v2 cluster is at MaxCapacity and queries are queuing. Walk through your diagnosis and fix.

> **Answer:** Diagnosis: (1) Check CloudWatch `ServerlessDatabaseCapacity` - if Average equals Maximum for 5+ minutes, you have hit the ceiling. (2) Check `DatabaseConnections` - high count confirms queuing. (3) Connect and check `pg_stat_activity` for waiting connections. (4) Check configured MaxCapacity with `describe-db-clusters`. Immediate fix: `aws rds modify-db-cluster --serverless-v2-scaling-configuration MinCapacity=X,MaxCapacity=Y --apply-immediately`. The cluster scales within 1-2 minutes. Root cause: MaxCapacity set too low, new query patterns, or traffic growth. Prevention: CloudWatch alarm at 80% of MaxCapacity, load test before production, add 50% headroom above peak.

---

## Topic 7: RDS Proxy and Connection Management

### Mid

**Q25.** What problem does RDS Proxy solve? When would you use it?

> **Answer:** RDS Proxy solves connection management problems: (1) Connection pooling - holds a pool of database connections and multiplexes application connections over them. Reduces connection overhead on the database. (2) Faster failover - detects writer failure and redirects connections to the new writer faster than DNS-based failover. (3) IAM authentication - applications authenticate to the proxy with IAM, the proxy authenticates to the database with Secrets Manager credentials. Use it when: your application has many short-lived connections (Lambda), you need faster failover, or you want to centralize credential management.

### Senior

**Q26.** How does RDS Proxy improve failover time compared to connecting directly to Aurora?

> **Answer:** Without proxy: application detects connection failure, resolves DNS (waits for TTL), connects to new writer. Total: 20-35 seconds plus application retry time. With proxy: proxy detects writer failure immediately (it monitors the cluster), routes new queries to the new writer within seconds. Existing connections get an error on the next query, but the proxy routes them to the new writer on retry. The application does not need to resolve DNS or manage reconnection. Total perceived downtime: under 5 seconds for most queries.

---

## Scenario-Based Questions

**Scenario A:** Your Aurora cluster has 1 writer and 2 readers. During a failover test, you measure 45 seconds of downtime. Your team says "Aurora failover should be 30 seconds." Diagnose the gap.

> **Answer:** Check these in order: (1) Application DNS caching - verify DNS TTL is 5 seconds and the application is not caching longer (Java defaults to 30 seconds). Set `-Dnetworkaddress.cache.ttl=1`. (2) Connection pool settings - check how quickly the pool detects dead connections and retries. Some pools wait 30+ seconds. (3) Health check interval - if using a load balancer, it may take extra time to mark the old endpoint unhealthy. (4) Reader tier configuration - verify the target reader is at tier 0. Higher tiers may add detection time. (5) Consider RDS Proxy for sub-5-second failover.

**Scenario B:** Your application writes to Aurora and immediately reads the same data. 5% of reads return stale data. The team wants to "fix" this by removing read replicas. What is your response?

> **Answer:** Removing read replicas is the wrong fix - it eliminates read scaling. The real problem is the application is reading from the reader endpoint after writing to the writer endpoint. Fix the application routing: (1) For critical "read-your-own-writes" paths, read from the writer endpoint for 2-3 seconds after a write. (2) Use Aurora's `aurora_replica_read_consistency = 'SESSION'` to make readers wait for the session's LSN. (3) Implement a session-level flag in the application that routes post-write reads to the writer. This preserves read scaling while solving the consistency problem.

**Scenario C:** A client wants to migrate from us-east-1 to us-west-2 with under 5 minutes of downtime. Design the plan using Aurora Global Database.

> **Answer:** (1) Create Aurora Global Database with us-east-1 as primary. (2) Add us-west-2 as secondary. (3) Wait for replication lag to stabilize under 1 second. (4) Schedule maintenance window. (5) Put application in read-only or maintenance mode. (6) Confirm lag drops to zero. (7) Run `aws rds switchover-global-cluster` targeting us-west-2. (8) Wait for switchover to complete (5-20 minutes). (9) Update application connection strings to us-west-2. (10) Remove maintenance mode. Total downtime: steps 5-10, approximately 5-10 minutes. With pre-staged connection strings and scripted switchover, downtime can be under 5 minutes.

---

## Quick Reference Card

| Concept | Key Number |
|---------|-----------|
| Aurora storage copies | 6 copies across 3 AZs |
| Aurora max storage | 128 TB |
| Aurora failover time | 20-35 seconds |
| Aurora DNS TTL | 5 seconds |
| Aurora max readers | 15 per cluster |
| Aurora replica lag | Under 100ms typical |
| Failover tier range | 0 (highest priority) to 15 (lowest) |
| Write quorum | 4 of 6 storage nodes |
| Read quorum | 3 of 6 storage nodes |
| Serverless v2 min ACU | 0.5 |
| Serverless v2 max ACU | 128 |
| 1 ACU | ~2 GB RAM |
| Global DB replication lag | Under 1 second typical |
| RDS Proxy failover | Under 5 seconds |
