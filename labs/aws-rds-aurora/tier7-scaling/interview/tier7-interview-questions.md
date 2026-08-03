# Tier 7 - Scaling, Integration, and Modern Patterns: Interview Questions

Questions graduated by experience level. Use for self-assessment or mock interviews.

---

## Topic 1: Vertical Scaling and Storage Autoscaling

### Junior Level

1. **Q:** What is the difference between vertical scaling and horizontal scaling for a database?
   **What they're looking for:** Understanding that vertical = bigger machine, horizontal = more machines.
   **Strong answer:** Vertical scaling means upgrading the instance to a larger size - more CPU, RAM, and network bandwidth on a single node. Horizontal scaling means adding more nodes, such as read replicas. For RDS, vertical scaling involves changing the instance class. Horizontal scaling involves adding replicas. The two approaches address different bottlenecks: vertical helps when the primary is CPU or memory bound, horizontal helps when read volume is the constraint.

2. **Q:** What happens to your application during an RDS instance class change with Multi-AZ enabled?
   **What they're looking for:** Understanding of the failover sequence and that there is still a brief interruption.
   **Strong answer:** With Multi-AZ, AWS upgrades the standby instance first, then promotes it to primary - that promotion causes a brief connection drop (typically 20-60 seconds). Then AWS upgrades the old primary in the background. Your application sees one failover event. Without Multi-AZ, the instance reboots directly - downtime is longer (1-5 minutes typically).

3. **Q:** What does RDS storage autoscaling do, and what does it not do?
   **What they're looking for:** Clear understanding of the feature's scope and limits.
   **Strong answer:** Storage autoscaling monitors free space and automatically expands allocated storage when free space drops below 10% (and stays there for 5+ minutes). It increases in increments - the larger of 5 GiB or 10% of current size - up to a maximum you set. What it does NOT do: it cannot shrink storage back down, it does not help with IOPS limits (you need to change storage type or provision IOPS separately), and it has a 6-hour cooldown between scaling events.

### Mid Level

4. **Q:** Your RDS instance has storage autoscaling enabled with a 1 TiB maximum. The instance is at 950 GiB and growing 20 GiB per day. Walk me through what happens over the next week.
   **What they're looking for:** Application of the 10% threshold, increment calculation, and ceiling logic.
   **Strong answer:** At 950 GiB, free space is 1024 - 950 = 74 GiB (roughly 7.7% of 950 GiB). That is already below the 10% threshold, so autoscaling may have already triggered or will trigger soon. When it fires, it scales by the larger of 5 GiB or 10% of 950 GiB = 95 GiB, bringing allocated to about 1,045 GiB. But the maximum is 1,024 GiB (1 TiB), so it can only scale to 1,024 GiB. After that, storage can no longer autoscale. At 20 GiB/day growth rate, the database fills the remaining ~74 GiB in less than 4 days and becomes read-only. The fix: raise the autoscaling maximum before this happens, AND investigate why the growth rate is so high.

5. **Q:** You need to resize an RDS instance from db.r6g.2xlarge to db.r6g.8xlarge. What information do you need before scheduling the change, and what is your process?
   **What they're looking for:** A disciplined pre-change process, not just "click modify."
   **Strong answer:** Before scheduling: verify Multi-AZ is enabled (to minimize downtime), check the current maintenance window and whether it overlaps with low-traffic periods, confirm the target class is available in the region and AZ, and check application connection pool settings (some pools fail to reconnect after failover without configuration changes). Also run `pg_stat_statements` to establish a CPU baseline you can compare after the change. The process: schedule for a low-traffic window, notify stakeholders, monitor `DatabaseConnections` and `CPUUtilization` during and after the change, and have a rollback plan (which is just reverting the instance class, though this means another failover).

6. **Q:** What is the difference between gp2 and gp3 storage in RDS, and when would you choose gp3?
   **What they're looking for:** Technical understanding of the storage type differences and practical judgment.
   **Strong answer:** gp2 ties IOPS to volume size at 3 IOPS/GiB with a minimum of 100 IOPS and burst up to 3,000 IOPS. The problem is that getting more IOPS requires buying more storage, even if you do not need the space. gp3 decouples IOPS and throughput from size: you get 3,000 baseline IOPS and 125 MB/s regardless of volume size, and you can provision additional IOPS and throughput independently. gp3 is almost always the better choice for new databases - it is cheaper for equivalent performance and more flexible. The only reason to stay on gp2 is if you are at very large storage sizes where gp2's IOPS/GiB ratio exceeds what gp3 provides at the same price point.

### Senior Level

7. **Q:** You inherit a production RDS database running on gp2 storage at 500 GiB with 1,500 IOPS provisioned. The application is complaining of write latency spikes. How do you diagnose and address this?
   **What they're looking for:** Systematic diagnosis using metrics, understanding of gp2 burst behavior, and migration approach.
   **Strong answer:** First, check `WriteIOPS` against the baseline IOPS for gp2 at 500 GiB. At 500 GiB, gp2 provides 1,500 IOPS (3 IOPS/GiB) with burst to 3,000. If `WriteIOPS` is consistently near 1,500 IOPS, the disk is saturated. Check `BurstBalance` metric - if it is depleting, the database is exhausting its I/O burst credits. To fix: migrate to gp3 (can provision 3,000 IOPS baseline for lower cost than gp2 at this size, and can provision more independently), or if the write volume genuinely requires >3,000 IOPS, provision io2 with the required IOPS. Migration is online - modify the instance storage type with no downtime.

8. **Q:** A developer asks why they cannot see their storage usage directly on RDS. Explain the RDS storage model, including the difference between allocated storage, used storage, and what affects each.
   **What they're looking for:** Deep understanding of how RDS storage is reported versus managed.
   **Strong answer:** RDS exposes `AllocatedStorage` (what you are billed for) and `FreeStorageSpace` (unused bytes within the allocated volume). `UsedStorage = AllocatedStorage - FreeStorageSpace`. What takes up used storage: actual database files (base, WAL, temp files), system files, and the PostgreSQL WAL directory. Logical replication slots that are not consumed cause WAL to accumulate, which directly consumes storage even though no table data is growing. After a large DELETE, storage does not shrink immediately - VACUUM reclaims space within PostgreSQL's page cache but does not return it to the OS until VACUUM FULL runs (which requires exclusive locks). Aurora works differently - it allocates storage in 10 GiB chunks up to 128 TiB automatically.

### Principal/Staff Level

9. **Q:** Design a storage capacity management strategy for a fleet of 50 RDS databases across five applications. What policies, automation, and governance would you put in place?
   **What they're looking for:** Org-level thinking about capacity, automation, and prevention rather than reactive one-off fixes.
   **Strong answer:** Three layers: monitoring, automation, and governance. Monitoring: standardized CloudWatch dashboards and alarms for every database - `FreeStorageSpace` at 30% and 20% thresholds (not 10%). Alarm naming convention includes environment and application owner. Automation: EventBridge rule triggers a Lambda when storage alarms fire. Lambda enriches the event with context (application, owner, DBA contact) and posts to PagerDuty with severity. Separately, a weekly Lambda job exports storage metrics to a central observability tool and calculates 90-day growth trend per database - databases where the trend shows filling within 90 days generate a Jira ticket proactively. Governance: each database has a documented storage sizing decision (initial size, max autoscaling ceiling, justification). Any change to storage ceiling requires a comment in the Terraform or CloudFormation template explaining why. Autoscaling is enabled for all databases - manually-managed storage is prohibited unless there is a documented exception.

---

## Topic 2: Aurora Serverless v2 Capacity Design

### Junior Level

1. **Q:** What is an Aurora Capacity Unit (ACU), and what resources does it represent?
   **What they're looking for:** Basic understanding of the unit of measure.
   **Strong answer:** An ACU is the unit of compute capacity for Aurora Serverless v2. One ACU represents approximately 2 GiB of memory with proportional CPU and network bandwidth. The minimum is 0.5 ACU (about 1 GiB RAM). Serverless v2 charges per ACU-hour consumed.

2. **Q:** What is the difference between minimum ACU and maximum ACU in Aurora Serverless v2?
   **What they're looking for:** Understanding of the scaling range and what each boundary means operationally.
   **Strong answer:** Minimum ACU is the floor - the cluster never scales below this. It determines your idle cost and your cold-start latency. Setting minimum to 0 (or 0.5) allows the cluster to pause during inactivity - essentially zero cost when idle, but the first query after an idle period takes extra time to warm up. Maximum ACU is the ceiling - the cluster cannot scale above this even under extreme load. If load exceeds maximum ACU, you will see latency increase and queries queue. Maximum ACU is also your cost ceiling: you know the worst-case hourly cost.

3. **Q:** When is Aurora Serverless v2 a poor choice compared to a provisioned instance?
   **What they're looking for:** Understanding the trade-offs, not just the marketing pitch.
   **Strong answer:** Serverless v2 is a poor choice when: the workload is steady and sustained (ASv2 costs more per ACU-hour than equivalent provisioned compute when running at high utilization constantly), when you need the absolute lowest query latency (scaling even a fraction of an ACU takes a few seconds), or when the workload is CPU-bound rather than memory-bound (ACU sizing is memory-centric). It also has fewer options for advanced instance tuning compared to provisioned.

### Mid Level

4. **Q:** Your Serverless v2 cluster has min=1, max=4. During a traffic spike, queries are timing out. You check CloudWatch and see `ACUUtilization` at 100%. What do you do?
   **What they're looking for:** Immediate action and root cause investigation.
   **Strong answer:** Immediate: raise the maximum ACU without restarting anything. `aws rds modify-db-cluster --serverless-v2-scaling-configuration MinCapacity=1,MaxCapacity=16 --apply-immediately`. Maximum ACU changes take effect quickly (usually within a minute). This immediately allows the cluster to scale above 4 ACU. Then investigate: is this a legitimate traffic spike (increase max permanently), a query regression (fix the query), or a connection leak (check `DatabaseConnections` and fix the application)? Raising max is mitigation, not remediation.

5. **Q:** Explain the Serverless v2 cost model and how you would calculate the break-even point versus a db.r6g.large instance.
   **What they're looking for:** Ability to do the math and reason about cost trade-offs.
   **Strong answer:** ASv2 charges per ACU-hour. At $0.12/ACU-hour in us-east-1 (actual rates vary), a db.r6g.large at $0.26/hr is equivalent to 0.26/0.12 = 2.17 ACU-hours continuously. If your average ACU is below 2.17, ASv2 is cheaper. If above, provisioned is cheaper. The calculation must use average ACU over a representative time window (at least a week, preferably a month) because high daily peaks with overnight lows average out significantly. Use `ServerlessDatabaseCapacity` CloudWatch metric with Average statistic over 30 days to get the real number.

6. **Q:** A Serverless v2 cluster has minimum set to 0.5 ACU. Users report the first query of the morning takes 3-5 seconds. What is causing this and how do you fix it?
   **What they're looking for:** Understanding of cold-start behavior and the minimum ACU trade-off.
   **Strong answer:** The cluster has scaled down to or near 0.5 ACU overnight due to inactivity. The first morning query triggers a scale-up. Scaling from 0.5 ACU requires allocating more memory and CPU, which takes a few seconds. The fix depends on the requirement: if the 3-5 second delay is unacceptable, raise minimum to 2 or 4 ACU so the instance is always warm enough to respond immediately (at higher idle cost). If cost is more important than cold-start latency, add a keepalive query to the application's health check or cron job that runs every 30-60 seconds to prevent the cluster from scaling below the threshold. For development databases where the delay is acceptable, leave it as-is.

### Senior Level

7. **Q:** You have 20 small Aurora Serverless v2 databases, each for a different microservice. Average utilization per database is 0.3 ACU during business hours, 0 overnight. What do you recommend?
   **What they're looking for:** Economics of Serverless at scale and awareness of alternatives.
   **Strong answer:** At 0.3 average ACU during business hours (12 hours) with 0 overnight: 0.3 * $0.12 * 12 = $0.43/database/day = $13/month per database. For 20 databases: $260/month. Compare to 20 db.t3.micro instances ($0.020/hr): $0.020 * 730 = $14.60/month each, $292/month total. Serverless v2 is slightly cheaper and provides burst capacity. But there is a bigger opportunity: consider whether 20 separate databases are necessary, or whether schema-based multi-tenancy in fewer databases with row-level security would serve the use case. Also evaluate whether these could share a Serverless v2 cluster using different databases within the same Aurora cluster - a single cluster with multiple databases reduces cluster overhead while keeping data isolated.

8. **Q:** What are the operational implications of Serverless v2 from a monitoring perspective? How does your CloudWatch setup differ from provisioned instances?
   **What they're looking for:** Awareness that standard metrics have different interpretations for serverless workloads.
   **Strong answer:** Key differences: `CPUUtilization` on a Serverless v2 instance represents CPU usage relative to the current ACU level, not a fixed capacity. A 90% CPU reading on a provisioned instance is alarming; on Serverless v2 it may mean the cluster is about to scale up (normal behavior). The critical metric unique to Serverless v2 is `ACUUtilization` - this shows what percentage of the maximum ACU is in use. `ACUUtilization` at 80-90% is a strong signal to raise the maximum. Also monitor `ServerlessDatabaseCapacity` to understand actual scaling behavior over time. For cost monitoring, calculate average ACU using `ServerlessDatabaseCapacity` with Average statistic over 30 days and multiply by the hourly rate.

### Principal/Staff Level

9. **Q:** An organization is considering migrating all production databases to Aurora Serverless v2 to "eliminate over-provisioning." Evaluate this proposal. What would you recommend?
   **What they're looking for:** Critical thinking about blanket technology decisions and ability to articulate when serverless is and is not appropriate.
   **Strong answer:** This is the wrong frame. The question is not "Serverless v2 vs provisioned" globally but "which databases benefit from Serverless v2 based on their workload characteristics." Serverless v2 is well-suited for: databases with significant variability (development, staging, low-traffic APIs, multi-tenant SaaS with variable per-tenant usage). It is poorly suited for: high-throughput transactional databases running at sustained high load (cost exceeds provisioned), databases requiring specific instance-level tuning, and latency-sensitive workloads where even occasional scaling delays are unacceptable. The right recommendation is a workload classification: run the same analysis I described for break-even ACU calculation across all databases, categorize them, and migrate the ones where Serverless v2 genuinely saves money or reduces operational burden. A blanket migration creates hidden costs for the high-utilization databases and does not guarantee savings.

---

## Topic 3: Zero-ETL and RDS Data API

### Junior Level

1. **Q:** What problem does Zero-ETL integration solve compared to a traditional ETL pipeline?
   **What they're looking for:** Understanding of the operational burden Zero-ETL eliminates.
   **Strong answer:** A traditional ETL pipeline requires building and maintaining: extraction jobs that query the source database, transformation logic, loading code that writes to the destination, scheduling, error handling, and schema change management. Zero-ETL replaces all of this for the common case of replicating operational data to Redshift for analytics. AWS manages the extraction (via transaction logs), the transfer, and schema synchronization automatically. The main limitation is that Zero-ETL does not handle complex transformations - you still need dbt or SQL for that.

2. **Q:** What is the RDS Data API, and why would you use it instead of a traditional database connection?
   **What they're looking for:** Understanding of the stateless, HTTP-based nature of the Data API.
   **Strong answer:** The RDS Data API provides HTTP-based SQL access to Aurora Serverless databases. Instead of establishing a persistent TCP connection (which requires a connection pool, a database driver, and VPC access), you call an HTTPS endpoint and get JSON back. It is designed for Lambda functions and other stateless compute environments that cannot maintain long-lived connections. The trade-offs are higher latency per query (HTTP overhead) and a 45-second query timeout. Use it for infrequent, ad-hoc queries from Lambda. Use direct connections for high-throughput applications.

### Mid Level

3. **Q:** Zero-ETL requires tables to have primary keys. Why? What happens to tables without primary keys?
   **What they're looking for:** Understanding of how Zero-ETL tracks changes and why primary keys are required.
   **Strong answer:** Zero-ETL replicates changes by reading the transaction log (WAL for Aurora PostgreSQL). To correctly apply UPDATE and DELETE operations on the Redshift side, it needs to identify which specific row was updated or deleted. Without a primary key, there is no reliable way to identify a unique row in Redshift to update or delete. Tables without primary keys are silently skipped - they do not replicate at all. This is a critical constraint to check before enabling Zero-ETL: run `SELECT tablename FROM pg_tables WHERE schemaname='public'` and cross-reference against `SELECT tablename FROM pg_indexes WHERE indexname LIKE '%pkey%'` to find tables without primary keys.

4. **Q:** You are building a Lambda function that needs to query an Aurora Serverless database occasionally (once per minute, simple SELECT). Should you use the Data API or a direct connection? Justify your answer.
   **What they're looking for:** Ability to apply the trade-off framework to a concrete scenario.
   **Strong answer:** For once-per-minute queries from Lambda, use the Data API. The reasons: Lambda functions do not maintain state between invocations, so a direct connection would be opened and closed every minute. Opening a PostgreSQL connection has overhead (TCP handshake, TLS negotiation, authentication, session setup) - for once-per-minute queries, this overhead per invocation is significant. The Data API maintains an internal connection pool, so you avoid this overhead. The 45-second timeout is not a concern for simple SELECTs. The HTTP overhead (20-100ms) is acceptable for once-per-minute queries. If the Lambda needed to run 100 queries per second or run complex multi-statement transactions, direct connections with RDS Proxy would be the right choice.

### Senior Level

5. **Q:** You want to set up Zero-ETL from Aurora to Redshift, but you discover that 30% of your tables lack primary keys. How do you approach this migration?
   **What they're looking for:** A pragmatic, risk-aware approach to a real constraint.
   **Strong answer:** Three approaches, ranked by preference: First, add primary keys to all tables that should have them - this is the correct fix for most tables. Most tables without primary keys are missing them due to oversight, not intentional design. Use `ALTER TABLE ... ADD PRIMARY KEY` where the natural key is obvious. Second, for tables where adding a primary key is not possible without schema changes (highly contested tables, tables with no obvious natural key), add surrogate keys: `ALTER TABLE legacy_table ADD COLUMN id BIGSERIAL PRIMARY KEY` - this is low-risk. Third, for tables where even a surrogate key is problematic (logging tables, insert-only append logs), these are candidates for direct S3 export + Redshift COPY instead of Zero-ETL. Audit the 30% to understand which category each table falls into before deciding on a blanket approach.

6. **Q:** Explain the security model of the RDS Data API. How does authentication work, and what are the IAM implications?
   **What they're looking for:** Security awareness around the Data API's credentials model.
   **Strong answer:** The Data API uses two layers of authentication. The caller (Lambda, application, CLI) must have IAM permission for `rds-data:ExecuteStatement` and related actions on the cluster ARN. The database credentials themselves are stored in AWS Secrets Manager - the Data API accepts a Secrets Manager ARN rather than inline credentials. This means: no database passwords in application code or environment variables, IAM controls who can call the API (not who can connect to the database directly), and every Data API call appears in CloudTrail. The implication is that Secrets Manager must be accessible from wherever the Data API is called. For Lambda, the function's IAM role needs `rds-data:ExecuteStatement` and `secretsmanager:GetSecretValue`. The security posture is generally better than hardcoded credentials because secrets rotation in Secrets Manager automatically applies without code changes.

---

## Topic 4: Lambda from RDS and S3 Integration

### Junior Level

1. **Q:** What does the aws_lambda PostgreSQL extension do, and what is required for it to work?
   **What they're looking for:** Basic understanding of the extension and its IAM dependency.
   **Strong answer:** The `aws_lambda` extension allows Aurora PostgreSQL to invoke AWS Lambda functions directly using SQL. You call `aws_lambda.invoke()` from a trigger or function. For it to work, the Aurora cluster needs an IAM role attached with `lambda:InvokeFunction` permission, and that role must be associated with the cluster using `add-role-to-db-cluster` with the feature name `Lambda`. The Lambda function must be in the same region as the Aurora cluster.

2. **Q:** What is the difference between synchronous and asynchronous Lambda invocation from PostgreSQL? Which should you use in triggers?
   **What they're looking for:** Understanding of the operational implications of each mode.
   **Strong answer:** Synchronous (`RequestResponse`) invocation blocks the PostgreSQL function until Lambda returns. The database transaction waits for Lambda to complete (up to Lambda's execution timeout - potentially 15 minutes). Asynchronous (`Event`) invocation fires the Lambda call and returns immediately - PostgreSQL does not wait for Lambda to finish. In triggers, always use asynchronous (`Event`) invocation. Synchronous calls in triggers mean that any Lambda slowdown or timeout directly holds your database transaction open, accumulating connections and potentially blocking rows. Async invocation means Lambda failures do not affect the database transaction at all - the trade-off is that you cannot get Lambda's return value and errors are silent from the database's perspective.

### Mid Level

3. **Q:** You need to import 500 million rows from S3 into an RDS table. The data is in one 80 GiB CSV file. How do you approach this?
   **What they're looking for:** Understanding of S3 import, parallelism, and practical large-file handling.
   **Strong answer:** Do not import the 80 GiB file as a single S3 object using `aws_s3.table_import_from_s3`. That is sequential and will take many hours. Instead: split the file into smaller chunks (e.g., 1,000 chunks of ~80 MB each) using tools like `split` on a Linux machine or Amazon EMR. Upload all chunks to S3. Then run parallel import sessions - one psql session per chunk, running simultaneously. This distributes the I/O and allows PostgreSQL to use multiple CPUs for the COPY operations. Also: disable indexes before the import and rebuild them afterward (faster than updating indexes row-by-row), and temporarily disable autovacuum on the target table during the load (`ALTER TABLE ... SET autovacuum_enabled = false`), re-enabling it after with a manual ANALYZE.

4. **Q:** A PostgreSQL trigger calls Lambda asynchronously. The Lambda function fails due to a permissions error. What happens to the database transaction?
   **What they're looking for:** Understanding of async error handling - the database does not know Lambda failed.
   **Strong answer:** Nothing happens to the database transaction. Asynchronous Lambda invocation from PostgreSQL is fire-and-forget. The database queues the Lambda invocation with AWS and returns. Whether Lambda succeeds or fails, the database transaction commits normally. The failure appears only in Lambda's CloudWatch logs and Lambda's dead-letter queue (if configured). This is both a feature and a risk: the application data is committed to the database, but the downstream notification or action triggered by Lambda never happened. To handle async Lambda failures, configure a Lambda DLQ (dead-letter queue) pointing to an SQS queue or SNS topic. A separate process monitors the DLQ and handles or alerts on failures. Do not rely on the database trigger to catch these errors.

### Senior Level

5. **Q:** You are designing a system where PostgreSQL triggers call Lambda for real-time event processing. What architectural concerns would you raise with the engineering team?
   **What they're looking for:** Holistic thinking about reliability, coupling, and failure modes.
   **Strong answer:** Four concerns: First, coupling - the database is now coupled to Lambda's availability and configuration. Lambda region availability, IAM policy changes, or code deployments affect the database trigger behavior. Second, error visibility - async Lambda failures are invisible to the database and to the application. You need explicit failure monitoring via DLQ and alerting. Third, ordering guarantees - Lambda invocations are not guaranteed to be processed in order, and high-throughput triggers may invoke Lambda faster than Lambda can process them, leading to out-of-order event processing. For ordering-sensitive workloads, use an outbox pattern with ordered consumption instead. Fourth, testing complexity - triggers that call Lambda are harder to test in isolation. Local development environments cannot easily simulate the Lambda integration. Consider whether the Lambda call could be moved to the application layer (after a successful database write) where it is easier to test, retry, and observe.

---

## Topic 5: Logical Replication and CDC

### Junior Level

1. **Q:** What is the difference between logical replication and physical replication (streaming replication) in PostgreSQL?
   **What they're looking for:** Clear distinction between the two mechanisms.
   **Strong answer:** Physical replication copies WAL bytes at the block level - it is a byte-for-byte copy of the database. The replica is identical to the primary at the storage level and must be on the same PostgreSQL major version. Logical replication decodes WAL changes into row-level events (INSERT, UPDATE, DELETE) and ships those events. The subscriber can be on a different major version, a different schema layout, or a completely different database system. Physical replication is simpler and replicates everything; logical replication is selective (specific tables) but more complex to manage.

2. **Q:** What is a replication slot, and why is it important to monitor them?
   **What they're looking for:** Understanding of WAL retention and the operational risk of slots.
   **Strong answer:** A replication slot is a mechanism on the source database that tracks how far a subscriber has consumed WAL. The source retains WAL until the subscriber acknowledges it has been applied. This guarantees the subscriber can always catch up even if it goes offline. The operational risk: if a subscriber goes offline or falls behind, the slot prevents WAL cleanup. WAL accumulates on the source indefinitely until the slot is consumed. In RDS, WAL accumulation consumes storage space directly. An unconsumed slot with high write volume can fill the disk and cause the database to go read-only. This is why monitoring `OldestReplicationSlotLag` is critical for any database using logical replication.

### Mid Level

3. **Q:** A logical replication subscriber reports errors: "ERROR: cannot update table orders because it does not have a replica identity." What is happening and how do you fix it?
   **What they're looking for:** Understanding of replica identity and its role in logical replication.
   **Strong answer:** PostgreSQL needs to identify which specific row to update on the subscriber when it processes an UPDATE or DELETE from the publisher. By default, it uses the primary key for this (the DEFAULT replica identity). If a table has no primary key, the subscriber cannot determine which row to update and throws this error. Fixes in order of preference: Add a primary key to the table (`ALTER TABLE orders ADD PRIMARY KEY (id)`) - this is the correct fix. Alternatively, set `REPLICA IDENTITY FULL` on the table (`ALTER TABLE orders REPLICA IDENTITY FULL`) - this tells PostgreSQL to log the entire old row in WAL so the subscriber can match by all column values. FULL is reliable but significantly increases WAL size for UPDATE/DELETE-heavy tables.

4. **Q:** You are setting up logical replication and need to create a dedicated replication user. What permissions does this user need, and why?
   **What they're looking for:** Security-aware thinking about replication credentials.
   **Strong answer:** The replication user needs: the `REPLICATION` attribute (required to establish replication connections - `CREATE USER replicator WITH REPLICATION LOGIN PASSWORD '...'`), `USAGE` on the schemas containing the tables to replicate, and `SELECT` on all tables in the publication (needed for the initial data copy when the subscription is created). Do NOT use the RDS master user for replication - it has far more privileges than needed. Use principle of least privilege: the replication user should not be able to modify data, create objects, or access tables outside the replication publication. In RDS, note that the `SUPERUSER` role is not available - use the `rds_replication` role instead for any user that needs replication privileges.

5. **Q:** Your logical replication subscriber has fallen 10 hours behind due to a network partition. The slot is still active. How do you assess the situation and decide between catching up vs. re-initializing the subscription?
   **What they're looking for:** Judgment about recovery paths for a degraded replication relationship.
   **Strong answer:** First, check how much WAL is retained for the slot and whether the source has enough storage to sustain the lag while the subscriber catches up. Second, estimate catch-up time: at current throughput, how long will it take for the subscriber to consume 10 hours of changes? If the replication throughput is roughly equal to the write rate, catch-up will not complete - the subscriber will stay perpetually behind. If throughput exceeds the write rate, catch-up will complete. Third, check what downstream systems depend on the subscriber - is there an application or analytics tool reading from the subscriber that is 10 hours out of date? What is the business impact? Decision: if WAL accumulation is manageable and catch-up is feasible (e.g., 2-4 hours of lag can be consumed in < 1 hour), let it catch up. If catch-up is not feasible or disk risk is high, drop the subscription and slot, re-initialize from scratch (accepting the data loss from the gap), and set up the subscription fresh.

### Senior Level

6. **Q:** Design a CDC architecture for an e-commerce platform where order changes must be published to a Kafka topic for downstream microservices. The database is Aurora PostgreSQL.
   **What they're looking for:** End-to-end architectural thinking including the tool choice, failure modes, and operational considerations.
   **Strong answer:** Architecture: deploy Debezium on EKS (or use Amazon MSK Connect if available). Debezium connects to Aurora PostgreSQL using a logical replication slot with the `pgoutput` plugin. Debezium consumes WAL changes, converts them to Debezium event format (before/after images with metadata), and publishes to MSK (Kafka). Downstream microservices consume from MSK topics using their preferred Kafka clients. Key design decisions: use a dedicated replication user (`CREATE USER debezium WITH REPLICATION LOGIN`), monitor `OldestReplicationSlotLag` with a 1 GiB alert threshold, set Kafka topic retention to 7 days for replay capability, use exactly-once semantics in Debezium where possible (though exactly-once from logical replication has nuances). Operational concerns: if Debezium goes down, the slot accumulates WAL - a 6-hour Debezium outage on a high-write database can fill gigabytes. Have a runbook for: dropping and re-initializing the slot if lag is unrecoverable, and for re-playing events from Kafka if a downstream service missed events.

### Principal/Staff Level

7. **Q:** Your company is moving toward event-driven microservices and wants to use the database as the "source of truth" for all events. How would you evaluate this approach, and what architectural guidance would you give?
   **What they're looking for:** Balanced evaluation of event sourcing from databases, including trade-offs and failure modes.
   **Strong answer:** Using the database as the event source via CDC is a valid and often underrated pattern - the "Outbox Pattern" is the cleanest implementation. Each service writes events to an outbox table in the same transaction as its state changes (eliminating dual-write inconsistency). A CDC consumer (Debezium) reads the outbox and publishes to Kafka. This guarantees that an event is published if and only if the state change committed. The architectural guidance: First, commit to the outbox pattern - ad-hoc triggers calling external APIs are fragile. Second, define event schemas explicitly - do not just serialize entire table rows. Use event types with versioned schemas registered in a schema registry. Third, establish CDC infrastructure as a platform concern, not each team's responsibility - the Debezium/Kafka pipeline is shared infrastructure. Fourth, plan for event replay - Kafka's retention policy must accommodate your replay requirements. Fifth, define exactly which tables are "event sources" - not every table change should be an event. Establish criteria (domain events vs. technical implementation details). The failure to watch for: teams start treating the outbox as a general-purpose event store and put business logic in CDC consumers, creating tight coupling between schema changes and consumer behavior.

---

## Topic 6: Migration Strategies

### Junior Level

1. **Q:** What is the difference between AWS DMS "full load" mode and "full load + CDC" mode?
   **What they're looking for:** Understanding of migration phases.
   **Strong answer:** Full load only copies existing data from source to target - a point-in-time snapshot. When it completes, the target is current as of when the full load started, but any changes made to the source during the load are not replicated. Full load + CDC starts with the full load, then immediately switches to CDC mode: it begins capturing changes from the source (starting from before the full load began, to not miss anything) and applies them to the target. This keeps the target continuously synchronized, enabling a minimal-downtime cutover - you stop writes to the source, wait for the CDC lag to reach zero, then switch the application to the target.

2. **Q:** Why would you use pg_dump `-Fc` (custom format) instead of plain SQL format?
   **What they're looking for:** Practical knowledge of pg_dump formats.
   **Strong answer:** Custom format (`-Fc`) is compressed (saves storage space and speeds up transfer), can be restored in parallel using `pg_restore -j [N]` (dramatically faster on multi-CPU targets), and allows selective restore (you can restore specific tables, schemas, or objects without restoring everything). Plain SQL format is a single large text file that must be processed sequentially by psql. For any database over a few GiB, custom format with parallel restore is significantly faster. Plain SQL format is only useful when you need a human-readable dump or need to pipe it to another tool that cannot handle the binary format.

### Mid Level

3. **Q:** You are using DMS to migrate a 500 GiB database. After the full load completes, the CDC lag is stuck at 2 hours and not decreasing. What is happening and what do you do?
   **What they're looking for:** Understanding of DMS bottlenecks and how to address them.
   **Strong answer:** CDC lag stuck at 2 hours means the DMS task is applying changes to the target at the same rate (or slower) than changes are arriving from the source. The task is not catching up. Root causes: replication instance is undersized (the most common cause - CPU or network is saturated), target instance cannot absorb changes fast enough (target IOPS or CPU is the bottleneck), or there is a specific table or operation that is slow to apply (look for large UPDATE or DELETE operations). Diagnostics: check DMS replication instance CPU in CloudWatch, check target RDS `WriteIOPS` and `CPUUtilization`. Fix: upgrade the replication instance class, optimize target storage (increase IOPS if on gp2, or switch to gp3/io2), or investigate and optimize the specific operations that are slow to apply.

4. **Q:** What are three things that DMS does NOT migrate that you must handle separately?
   **What they're looking for:** Awareness of DMS limitations in production migrations.
   **Strong answer:** Sequences: DMS migrates data but not sequence current values. After migration, sequences on the target may start from 1 again, causing primary key conflicts when the application inserts new rows. Fix: after DMS full load, for each serial/identity column, run `SELECT setval('sequence_name', (SELECT MAX(id) FROM table))`. DDL (schema objects): DMS handles data migration, not schema migration. Triggers, functions, views, indexes, extensions, and custom types must be migrated separately using `pg_dump --schema-only`. Start this before DMS runs. PostgreSQL-specific features: DMS has limited support for partial indexes, expression indexes, custom data types, and stored procedures with complex logic. Test these specifically after migration.

5. **Q:** Walk me through the Blue/Green Deployment switchover. What exactly happens during the "downtime window"?
   **What they're looking for:** Step-by-step understanding of the switchover mechanics.
   **Strong answer:** When you initiate switchover: RDS drops all new connections to the blue (current primary) database. Existing connections that are idle are dropped. Active transactions are allowed to complete (with a short timeout). The green database, which has been kept in sync via logical replication, receives any remaining changes from blue and waits until the replication lag reaches zero. Once caught up, RDS promotes green as the new primary. The endpoint DNS name (which was pointing to blue) is updated to point to green. The application's connection pool detects dropped connections and reconnects - because the endpoint DNS has switched, they now connect to green. Total time from connection drop to endpoint switch is typically 20-60 seconds. Applications must handle connection loss gracefully (retry logic, connection pool that reconnects on error) for this to be truly minimal downtime.

### Senior Level

6. **Q:** A 2 TiB PostgreSQL 12 database on EC2 needs to migrate to Aurora PostgreSQL 16. Maximum downtime is 2 hours. Design the migration strategy.
   **What they're looking for:** End-to-end migration design for a large, version-crossing migration with a tight downtime window.
   **Strong answer:** Blue/Green is only available for RDS/Aurora, not EC2. So the approach is DMS with full load + CDC, then a controlled cutover. Phase 1 (weeks before cutover): Create the target Aurora PostgreSQL 16 cluster. Run `pg_dump --schema-only` from the EC2 source and restore to Aurora (handling any PostgreSQL 12-to-16 incompatibilities). Create DMS replication instance, endpoints, and task in full-load-and-CDC mode. Start the DMS task - full load of 2 TiB will take many hours. Phase 2 (days before cutover): DMS is in CDC mode. Measure the sustained CDC lag. If lag is < 30 seconds consistently, you are ready. Run validation queries to compare source and target. Phase 3 (cutover, within the 2-hour window): Enable maintenance mode on the application (read-only or maintenance page). Wait for DMS lag to reach 0 seconds. Run final row count validation. Update application connection config to point to Aurora 16. Restart application services. Run smoke tests. If smoke tests pass (within 30 minutes), decommission DMS task. If they fail, roll back to EC2 source immediately. Total switchover is 15-30 minutes; the 2-hour window gives ample buffer.

7. **Q:** You executed a Blue/Green switchover. 30 minutes after, the application reports that new records are getting primary key conflicts. What happened and how do you fix it?
   **What they're looking for:** Diagnosing the sequence drift problem and knowing the fix.
   **Strong answer:** This is the sequence drift problem. Sequences are not included in logical replication. During the Blue/Green preparation period, the green database's sequences were set when the green environment was created - they were not continuously synchronized. If the blue database inserted rows from sequence value 50,000 to 60,000 during the preparation period, the green database's sequence might still be at 50,000. After switchover, the application starts inserting on green from sequence 50,000 - colliding with rows that were replicated from blue. The fix: immediately after switchover, for each table with a serial/identity column, run: `SELECT setval(pg_get_serial_sequence('[table]', '[id_column]'), (SELECT MAX([id_column]) FROM [table]));`. This resets the sequence to the current maximum, above all existing rows. Run this for every affected table before resuming writes, or do it as part of the post-switchover validation checklist.

### Principal/Staff Level

8. **Q:** You are the DBA responsible for a fleet migration: 200 RDS databases across 15 applications need to upgrade from PostgreSQL 13 to 16. Design the governance and execution plan.
   **What they're looking for:** Program-level thinking, risk tiers, tooling, and governance.
   **Strong answer:** Four phases. Assessment: inventory all 200 databases using the RDS API, classify by criticality (production vs. non-production), size, and application. Run `pg_upgrade --check` equivalent (test upgrade in staging) for each major application to identify compatibility issues (functions, extensions, deprecated syntax). Tooling: build or adapt a migration pipeline using AWS Step Functions or an internal tool that: creates the Blue/Green deployment, waits for lag to reach zero, runs application-specific smoke tests, and executes switchover on approval. All parameters stored in a central config repo. Execution order: development databases first (lowest risk, finds issues), then staging, then production tier by tier. Non-production runs can be automated. Production requires a human approval gate before each switchover. Communications: establish a Slack channel and runbook per application. Each application team must confirm their smoke tests and rollback criteria before their database is added to the schedule. Rollback policy: any smoke test failure auto-rolls back. After rollback, a post-mortem is required before re-attempting. Success metrics: track time-to-complete per database, rollback rate by application, and any post-cutover incidents. A rollback rate above 10% is a signal to revisit the smoke test quality, not to proceed faster.
