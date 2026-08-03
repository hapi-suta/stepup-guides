# Module 10 - Interview Prep: Production-Ready Aurora Stack

**Level:** Senior / Staff DBA and DevOps Engineer
**Format:** 20 questions with detailed answers
**Focus:** Architecture design, production operations, incident response, cost optimization

---

## Question 1: Architecture Design

**Q: You are designing an Aurora PostgreSQL stack for a fintech application processing 5,000 TPS with 99.99% availability. Walk me through your architecture from VPC to monitoring.**

**A:** I would design this in layers:

**Network layer:** Multi-AZ VPC with 3 AZs. Private subnets for Aurora (no internet route), private subnets for application servers (NAT for outbound), public subnets for ALB and bastion only. VPC endpoints for Secrets Manager, CloudWatch, S3, and KMS so the database subnet has zero internet dependency.

**Compute layer:** Aurora PostgreSQL 16.x with db.r6g.2xlarge (8 vCPU, 64 GB RAM) - sized for the working set plus headroom. One writer in AZ-a, two readers across AZ-b and AZ-c. Same instance class on all instances for predictable failover behavior. Failover priority tier 0 on both readers.

**Security layer:** Storage encrypted with a customer-managed KMS key. SSL forced via `rds.force_ssl=1`. IAM database authentication for applications. Secrets Manager managing the master password with 30-day rotation. pgaudit logging DDL, role changes, and write operations. Security groups referencing other security groups, not CIDRs.

**Monitoring layer:** CloudWatch alarms on CPU (>70%), connections (>80% of max), FreeableMemory (<1GB), AuroraReplicaLag (>100ms), write/read latency (>10ms). Performance Insights with CMK encryption. Enhanced Monitoring at 15-second intervals. Log metric filters for deadlocks, auth failures, and wraparound warnings. Dashboard with all critical metrics.

**DR layer:** 14-day automated backup retention. Cross-region snapshot copy to us-west-2 every 6 hours. KMS multi-region key for cross-region restores. Quarterly DR drills. RPO: 0 for AZ failure (synchronous), 6 hours for region failure (snapshot interval). RTO: <60s for AZ failure, 2-4 hours for region failure.

For 99.99% availability, I would also consider Aurora Global Database for cross-region read replicas with <1 second replication lag and <1 minute cross-region failover.

---

## Question 2: Failover Mechanics

**Q: Explain exactly what happens during an Aurora failover - from the moment the writer fails to the moment the application reconnects.**

**A:** The sequence is:

1. **Detection (0-5 seconds):** Aurora's health monitoring detects the writer is unresponsive. The detection mechanism uses heartbeats at the storage layer, not just instance health checks.

2. **Promotion decision (5-10 seconds):** Aurora selects the failover target based on promotion tier (0 = highest priority). If multiple readers share the same tier, Aurora picks the one with the least replica lag.

3. **Writer demotion (10-15 seconds):** The old writer is fenced off from storage to prevent split-brain. Any in-flight transactions on the old writer are rolled back.

4. **Reader promotion (15-30 seconds):** The selected reader is promoted to writer. It replays any remaining WAL from shared storage. Since Aurora uses a shared storage volume (not streaming replication), this replay is typically instant.

5. **DNS update (30-35 seconds):** The cluster endpoint DNS record is updated to point to the new writer. Aurora uses a 5-second DNS TTL.

6. **Application reconnection (35-60 seconds):** Applications that use the cluster endpoint resolve the new DNS, open new connections, and resume operations. Applications using instance endpoints are broken until manually updated.

The critical application-side requirements are: (a) use the cluster endpoint, never instance endpoints; (b) set DNS TTL to 5 seconds or less in the application's DNS resolver; (c) implement connection retry with exponential backoff; (d) handle transient connection errors gracefully.

Total failover time is typically 30-60 seconds for Aurora PostgreSQL.

---

## Question 3: Storage Architecture

**Q: How does Aurora storage differ from standard RDS PostgreSQL? What are the implications for backup, recovery, and performance?**

**A:** Aurora storage is fundamentally different from standard RDS:

**Architecture:** Aurora uses a distributed, fault-tolerant storage layer that replicates data 6 ways across 3 AZs. The storage is shared between all instances in the cluster - the writer and all readers read from the same storage volume. This is unlike standard RDS where each replica has its own EBS volume with streaming replication.

**Write path:** The writer sends only redo log records to the storage layer, not full data pages. The storage nodes apply the log records asynchronously. This reduces write amplification significantly - Aurora writes approximately 1/6th the data of standard PostgreSQL for the same workload.

**Backup:** Aurora takes continuous incremental backups to S3. There is no backup window performance impact because backups happen at the storage layer without affecting the database process. PITR granularity is 5 minutes (the log position Aurora stores), but in practice you can restore to any second within the backup retention period.

**Recovery:** Crash recovery is fast because Aurora does not need to replay the WAL sequentially. The storage nodes already have the latest data. Instance restart after a crash typically takes 10-30 seconds, compared to minutes or hours for standard PostgreSQL with a large WAL.

**Performance implications:** Read replicas have near-zero replication lag (typically <20ms) because they read from the same storage. There is no replica lag from network-based replication. However, the reader's buffer cache may lag behind the writer's cache, causing additional I/O on the reader for recently written data.

**Scaling:** Storage auto-scales from 10 GB to 128 TB. You never provision storage or worry about running out of disk space (though you should still monitor growth rate for cost planning).

---

## Question 4: Cost Optimization

**Q: Your Aurora cluster costs $2,500/month. Walk me through how you would analyze and reduce this cost.**

**A:** I would approach this systematically:

**Step 1: Break down the bill.** Use Cost Explorer filtered to RDS. Look at usage type breakdown: compute (instance hours), storage, I/O, backup, data transfer. Identify the top 3 cost drivers.

**Step 2: Right-size compute.** Pull 30 days of CloudWatch data for CPUUtilization, FreeableMemory, and DatabaseConnections. If average CPU <30% and memory usage <50%, the instance is over-provisioned. Downsize by one step (e.g., db.r6g.xlarge to db.r6g.large) and monitor for 2 weeks.

**Step 3: Evaluate storage type.** If on Aurora Standard, check `Aurora:StorageIOUsage` in Cost Explorer. If I/O charges >25% of total Aurora cost, switch to I/O-Optimized (zero I/O charges, 2.25x storage price). The crossover math: if I/O cost > 1.25x the additional storage premium, I/O-Optimized saves money.

**Step 4: Reserved Instances.** For stable workloads running 24/7, purchase 1-year All Upfront RIs for 37% savings. For the two-instance cluster: On-Demand $350/month vs RI $200/month = $150/month savings. Payback period: 7 months.

**Step 5: Graviton migration.** If using Intel instances (r5, r6i), migrate to Graviton (r6g, r7g) for 10-20% better price-performance. Use Blue/Green deployment for zero-downtime migration.

**Step 6: Evaluate Serverless v2.** If the workload is highly variable (high traffic during business hours, near-zero at night), Serverless v2 can save 30-50% by scaling down during low-traffic periods. Model the cost: average ACU x $0.12/ACU-hour x 730 hours.

**Step 7: Trim waste.** Delete old manual snapshots, remove unused parameter groups, close dev/test clusters after hours.

Typical outcome: 35-50% cost reduction without performance impact.

---

## Question 5: Security Incident Response

**Q: You discover that database credentials may have been leaked in a public GitHub repository. What do you do in the first 30 minutes?**

**A:** This is a P1 security incident. The first 30 minutes:

**Minutes 0-5 (Contain):**
1. Rotate the leaked credentials immediately. If it is the master password, use `aws secretsmanager rotate-secret`. If it is an application user, `ALTER ROLE app_user WITH PASSWORD 'new_password'` and update the application config.
2. If using IAM auth, revoke the IAM access key that was leaked.

**Minutes 5-10 (Assess):**
3. Check `pg_stat_activity` for active sessions from unknown IPs.
4. Check CloudWatch Logs for authentication failures and successes from unexpected sources.
5. Check CloudTrail for RDS API calls from unfamiliar IAM principals.

**Minutes 10-20 (Investigate):**
6. Query pgaudit logs to determine what data was accessed.
7. Check for new database users, role changes, or privilege escalations.
8. Verify no data was exfiltrated (check for large `SELECT` queries or `COPY TO` commands).

**Minutes 20-30 (Remediate):**
9. Lock any suspicious database accounts (`ALTER ROLE suspicious_user NOLOGIN`).
10. Tighten security group rules if any CIDR-based access was used.
11. Enable additional pgaudit logging (`pgaudit.log = all`) temporarily for enhanced monitoring.
12. Notify the security team and initiate the formal incident response process.

After 30 minutes: document the timeline, assess data exposure scope, determine notification requirements (GDPR, HIPAA), and conduct a post-incident review.

---

## Question 6: Parameter Tuning

**Q: A developer asks you to tune PostgreSQL parameters for their high-throughput OLTP workload on Aurora. What parameters do you focus on and why?**

**A:** Aurora manages many parameters automatically (shared_buffers, effective_cache_size, wal-related parameters). I focus on what I CAN control:

**Connection management:**
- `max_connections`: Set based on instance class. Aurora default is usually fine, but if using connection pooling, lower it.
- `idle_in_transaction_session_timeout = 300000` (5 minutes): Kill sessions that leave transactions open. These hold locks and prevent autovacuum.
- `statement_timeout = 60000` (60 seconds): Kill runaway queries before they consume all resources.

**Query performance:**
- `shared_preload_libraries = pg_stat_statements,pgaudit`: Essential for performance analysis and audit.
- `pg_stat_statements.track = all`: Track all statements including nested ones.
- `work_mem = 64MB` (adjust based on available memory / max_connections): Controls sort and hash operations in memory vs spilling to disk.
- `random_page_cost = 1.1`: Aurora storage is SSD-based, so random reads are nearly as fast as sequential. This encourages the planner to use indexes.

**Logging:**
- `log_min_duration_statement = 1000`: Log queries over 1 second.
- `log_lock_waits = 1`: Surface contention issues.
- `log_temp_files = 0`: Identify queries spilling to disk.
- `log_autovacuum_min_duration = 0`: Track autovacuum performance.

**Safety:**
- `rds.force_ssl = 1`: Non-negotiable for production.
- `pgaudit.log = ddl,role,write`: Audit compliance.

I would NOT change: `shared_buffers`, `effective_cache_size`, `wal_buffers`, `checkpoint_*` - Aurora manages these internally and overriding them can cause issues.

---

## Question 7: Monitoring Strategy

**Q: What are the 5 most important metrics to monitor on an Aurora PostgreSQL cluster, and what does each tell you?**

**A:**

1. **db.load (Performance Insights):** The most important metric. Shows how many sessions are actively running at any given time. If db.load > vCPU count, the database is overloaded. The breakdown by wait type tells you WHY: CPU means compute-bound, I/O means storage-bound, Lock means contention, Client means the application is slow to fetch results.

2. **CPUUtilization:** Percentage of allocated CPU used. Sustained >80% indicates need to scale up or optimize queries. Spikes are normal during batch jobs; sustained high CPU is a problem.

3. **DatabaseConnections:** Active connections vs max_connections. When connections approach max, new connections are rejected. This is often the first symptom visible to users. Root cause is usually missing connection pooling.

4. **AuroraReplicaLag:** Milliseconds of replication delay between writer and reader. Aurora typically maintains <20ms lag. Lag >100ms indicates heavy write load overwhelming replication. Lag >1 second means read-after-write consistency is at risk.

5. **FreeableMemory:** Available memory on the instance. When this drops below the buffer cache size, PostgreSQL starts evicting cached pages, causing more disk reads. Sustained low memory means the instance class is too small or there is a memory leak (often from too many connections each consuming `work_mem`).

Honorable mentions: WriteLatency (I/O health), DiskQueueDepth (I/O saturation), Deadlocks (application logic issues), BufferCacheHitRatio (cache effectiveness - should be >95%).

---

## Question 8: Schema Migration Safety

**Q: You need to add a NOT NULL column to a table with 100 million rows in production during business hours. How do you do this safely?**

**A:** The safe approach is a multi-step migration:

**Step 1: Add the column as nullable with a default.**
```sql
SET lock_timeout = '5s';
ALTER TABLE orders ADD COLUMN region TEXT DEFAULT 'us-east-1';
```
In PostgreSQL 11+, adding a column with a non-volatile DEFAULT is instant (no table rewrite). The default is stored in the catalog. The `lock_timeout` prevents blocking if there is a long-running transaction holding a conflicting lock.

**Step 2: Backfill existing rows (if needed, in batches).**
```sql
UPDATE orders SET region = 'us-east-1' WHERE region IS NULL AND id BETWEEN 1 AND 1000000;
```
Batch to avoid holding a long transaction and to allow autovacuum to work between batches.

**Step 3: Add the NOT NULL constraint.**
```sql
ALTER TABLE orders ALTER COLUMN region SET NOT NULL;
```
In PostgreSQL 12+, if all rows already satisfy the constraint, this is instant (metadata-only change). In earlier versions, this scans the entire table.

**What NOT to do:**
- `ALTER TABLE orders ADD COLUMN region TEXT NOT NULL` - This requires a table rewrite on older PostgreSQL versions, holding an ACCESS EXCLUSIVE lock for the entire duration.
- Run it without `lock_timeout` - If a long query is running, the ALTER waits for it AND blocks all subsequent queries.
- Run it in a single transaction with the UPDATE - Holds locks for the duration of the entire backfill.

---

## Question 9: Disaster Recovery

**Q: Your Aurora cluster in us-east-1 is down due to a regional AWS outage. Walk me through your DR procedure.**

**A:** Assuming we have cross-region snapshots (not Aurora Global Database):

**Phase 1 - Detection and Decision (0-15 minutes):**
- Verify the outage is regional (check AWS Health Dashboard, try other services in us-east-1)
- Check cross-region monitoring alarms (CloudWatch in us-west-2 watching us-east-1 health)
- Decision: If estimated recovery time exceeds our RTO (4 hours), initiate DR failover
- Notify stakeholders that DR procedure is starting

**Phase 2 - Restore (15-90 minutes):**
- Identify the latest available snapshot in us-west-2
- Calculate RPO: time between snapshot creation and outage start = data loss window
- Restore cluster from snapshot in us-west-2 (10-15 minutes for a 500 GB cluster)
- Create writer + reader instances (10-15 minutes per instance)
- Wait for instances to reach `available` status

**Phase 3 - Validate (90-120 minutes):**
- Connect to the restored cluster
- Run data integrity checks (row counts, latest timestamps, checksum critical tables)
- Verify schema matches expected state (Flyway version table)
- Create the application database user if it was not in the snapshot

**Phase 4 - Cutover (120-180 minutes):**
- Update DNS (Route 53 failover record or manual CNAME update)
- Update application connection strings (if not using DNS)
- Deploy application in us-west-2 (if not already running there)
- Verify end-to-end application functionality
- Monitor for errors

**Phase 5 - Post-Recovery:**
- Continue monitoring the DR cluster
- When us-east-1 recovers, plan failback
- Document the incident: timeline, RPO achieved, RTO achieved, lessons learned

With Aurora Global Database, this entire process is reduced to: (1) promote the secondary region cluster, (2) update DNS. Total time: <5 minutes.

---

## Question 10: Connection Pooling

**Q: Your application opens 2,000 connections to Aurora but `max_connections` is 1,000. How do you solve this?**

**A:** The solution is connection pooling - either RDS Proxy or PgBouncer.

**RDS Proxy (managed):**
- Sits between the application and Aurora
- Multiplexes thousands of application connections into a much smaller pool of database connections
- Handles failover transparently (applications do not need retry logic)
- Supports IAM authentication
- Managed service, no infrastructure to maintain
- Cost: per-vCPU pricing, approximately $20-40/month for small clusters

**PgBouncer (self-managed):**
- Open-source connection pooler, runs on EC2 or ECS
- Transaction pooling mode: releases the server connection after each transaction
- Session pooling mode: releases after session ends (less efficient)
- Lower cost (EC2 only), but requires operations overhead
- Does not handle failover - need additional tooling

**Configuration for RDS Proxy:**
- Max connections: 100 (proxy to database)
- Max connections per pool: match your instance's max_connections
- Idle timeout: 5 minutes
- Connection borrow timeout: 120 seconds
- Target group: both writer and reader

**Why not just increase `max_connections`?**
Each PostgreSQL connection consumes approximately 10-15 MB of RAM. 2,000 connections = 20-30 GB just for connection overhead, leaving insufficient RAM for shared_buffers and work_mem. Connection pooling is always more efficient than raising max_connections.

---

## Question 11: Performance Investigation

**Q: A developer reports their query takes 30 seconds. How do you investigate?**

**A:**

**Step 1: Get the query.** Ask for the exact SQL and the table sizes involved.

**Step 2: Check pg_stat_statements.**
```sql
SELECT query, calls, mean_exec_time, stddev_exec_time, rows
FROM pg_stat_statements
WHERE query LIKE '%their_table%'
ORDER BY mean_exec_time DESC
LIMIT 5;
```
This tells me if the 30-second execution is typical or an outlier.

**Step 3: Run EXPLAIN ANALYZE.**
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) <their_query>;
```
Look for: sequential scans on large tables, nested loop joins on large result sets, sort operations that spill to disk (`Sort Method: external merge`), and bitmap heap scans with high recheck rates.

**Step 4: Check for missing indexes.** Look at the execution plan for sequential scans on filtered columns. If the plan shows `Seq Scan` with a filter that eliminates 99% of rows, an index on the filter column would help.

**Step 5: Check for lock contention.** Query `pg_stat_activity` for the session running the slow query. If `wait_event_type = Lock`, the query is waiting for another transaction to release a lock.

**Step 6: Check for bloat.** If the table has high dead tuple count, the sequential scan is reading dead rows. Run `VACUUM ANALYZE` on the table.

**Step 7: Check for parameter issues.** Verify `work_mem` is sufficient for the sort/hash operations in the query. Verify `random_page_cost` is set correctly for SSD storage.

---

## Question 12: IaC for Database Infrastructure

**Q: What should and should not be managed by Terraform for an Aurora stack?**

**A:**

**Should be in Terraform:**
- VPC, subnets, route tables, NAT gateways
- Security groups and rules
- KMS keys and aliases
- IAM roles and policies
- Aurora cluster and instances
- Parameter groups
- DB subnet groups
- CloudWatch alarms and dashboards
- SNS topics and subscriptions
- VPC endpoints

**Should NOT be in Terraform:**
- Database users and roles (manage with Flyway or a secrets management tool)
- Schema objects (tables, indexes, functions) - manage with migration tools
- Data (obviously)
- Secrets Manager secret values (Terraform would store them in state)
- Manual snapshots (create ad-hoc, not part of infrastructure lifecycle)

**Gray area:**
- CloudWatch Logs metric filters - can be in Terraform, but often iterated on frequently
- AWS Config rules - Terraform-managed but reviewed separately
- Budget alerts - often managed by a finance/platform team, not the DBA

The key principle: Terraform manages infrastructure lifecycle (create, update, destroy). Application-level concerns (schema, data, users) are managed by application-level tools (Flyway, CI/CD pipelines).

---

## Question 13: Encryption Strategy

**Q: Explain encryption at rest and in transit for Aurora. What are the key management considerations?**

**A:**

**At rest:** Aurora encrypts all data in the storage layer using AES-256. This includes the cluster volume, automated backups, manual snapshots, and read replicas. Encryption is set at cluster creation and cannot be changed later.

Key management options:
1. **Default `aws/rds` key:** Managed by AWS, shared across all RDS instances in the account. Cannot be rotated on your schedule, cannot be audited independently, cannot be shared across accounts.
2. **Customer-managed key (CMK):** You control the key policy, rotation schedule, and audit trail. Can be multi-region for cross-region snapshot restores.

I always recommend CMK because: (a) key policies restrict who can decrypt your data, (b) CloudTrail logs every key usage, (c) you can rotate the key on your schedule, (d) multi-region keys simplify DR.

**In transit:** PostgreSQL supports TLS natively. Set `rds.force_ssl = 1` to reject unencrypted connections. Applications should use `sslmode=verify-full` and validate the RDS CA certificate to prevent MITM attacks.

**Key rotation:** With CMK, enable automatic rotation. AWS creates a new backing key annually. Old data remains readable because the key ID does not change - AWS internally maps the key ID to the correct backing key version. No downtime or re-encryption required.

**Cross-account/cross-region:** For cross-region snapshots, the target region needs access to the encryption key. Use multi-region KMS keys or re-encrypt the snapshot with a key in the target region during the copy operation.

---

## Question 14: Aurora vs Standard RDS

**Q: When would you choose standard RDS PostgreSQL over Aurora PostgreSQL?**

**A:** Aurora is not always the right choice. Choose standard RDS when:

1. **Cost sensitivity on small workloads:** Aurora's minimum instance is db.t3.medium ($50/month). Standard RDS supports db.t3.micro ($12/month). For dev/test with <5 GB storage, standard RDS is significantly cheaper.

2. **Specific PostgreSQL extensions:** Aurora supports most extensions but not all. If you need an unsupported extension (check the AWS docs), standard RDS is the option.

3. **Logical replication to external targets:** Aurora's logical replication has some limitations compared to standard RDS. If you need logical replication to non-AWS targets, verify compatibility.

4. **Predictable I/O costs:** Aurora Standard charges per I/O operation, which can be unpredictable. Standard RDS uses provisioned IOPS (gp3 or io2) with fixed pricing.

5. **Multi-AZ without readers:** Standard RDS Multi-AZ provides a synchronous standby without additional compute cost. Aurora requires a separate reader instance for HA.

Choose Aurora when:
- You need read scaling (multiple readers, reader endpoint)
- You want faster failover (<60 seconds vs 1-2 minutes)
- Storage auto-scaling is important (no provisioning)
- You need Performance Insights and shared storage
- Your workload benefits from the write amplification reduction

---

## Question 15: Autovacuum Tuning

**Q: How do you tune autovacuum for a high-write Aurora PostgreSQL table?**

**A:** First, understand what autovacuum does: it reclaims space from dead tuples (rows that were updated or deleted) and updates table statistics for the query planner.

For a high-write table (millions of updates/deletes per day):

**Monitor first:**
```sql
SELECT relname, n_dead_tup, n_live_tup,
  last_autovacuum, last_autoanalyze,
  autovacuum_count, autoanalyze_count
FROM pg_stat_user_tables
WHERE relname = 'high_write_table';
```

**Key parameters (set per-table):**
```sql
ALTER TABLE high_write_table SET (
  autovacuum_vacuum_threshold = 1000,
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_threshold = 500,
  autovacuum_analyze_scale_factor = 0.005,
  autovacuum_vacuum_cost_delay = 2
);
```

- `autovacuum_vacuum_scale_factor = 0.01`: Trigger vacuum when 1% of rows are dead (default 20% is too high for large tables - on a 100M row table, default waits for 20M dead tuples)
- `autovacuum_vacuum_threshold = 1000`: Minimum dead tuples before considering vacuum
- `autovacuum_vacuum_cost_delay = 2`: Reduce delay between vacuum I/O operations (default 2ms, lower = more aggressive vacuum but more I/O)

**On Aurora specifically:**
- Aurora handles WAL and checkpoint differently, so `autovacuum_vacuum_cost_limit` has less impact than on standard PostgreSQL
- Monitor `log_autovacuum_min_duration = 0` to see every vacuum run in CloudWatch Logs
- Watch for "wraparound" warnings - these indicate autovacuum cannot keep up

---

## Question 16: Blue/Green Deployments

**Q: How do Blue/Green deployments work for Aurora, and when would you use them?**

**A:** Blue/Green creates a copy of your production cluster (Green) alongside the existing cluster (Blue). Changes are applied to the Green environment while Blue continues serving traffic. When ready, a switchover redirects traffic from Blue to Green.

**How it works:**
1. Create Blue/Green deployment - Aurora creates a Green cluster that replicates from Blue via logical replication
2. Apply changes to Green (instance class change, engine upgrade, parameter changes)
3. Wait for Green to catch up (replication lag = 0)
4. Initiate switchover - Aurora briefly blocks writes, waits for final replication sync, updates endpoints
5. Switchover completes in <30 seconds typically

**When to use:**
- Major version upgrades (PostgreSQL 15 -> 16)
- Instance class changes (Intel -> Graviton)
- Parameter group changes that require reboot
- Testing changes before committing

**When NOT to use:**
- Minor version upgrades (use maintenance window)
- Parameter changes that do not require reboot
- Emergency fixes (too slow to set up)

**Limitations:**
- Both Blue and Green consume compute resources during the deployment
- Logical replication has restrictions on DDL during the sync phase
- Not all parameter changes are supported

---

## Question 17: Compliance and Audit

**Q: How do you ensure your Aurora cluster meets SOC 2 Type II compliance requirements?**

**A:** SOC 2 focuses on five trust principles: security, availability, processing integrity, confidentiality, and privacy. For Aurora:

**Security:**
- Encryption at rest with CMK (documented key management policy)
- Encryption in transit with forced SSL
- Network isolation (private subnets, security groups, no public access)
- IAM authentication, least-privilege database roles
- pgaudit logging all DDL, role changes, and writes
- CloudTrail logging all API calls

**Availability:**
- Multi-AZ deployment with automatic failover
- Documented RTO and RPO
- Quarterly DR drills with documented results
- Backup retention >= 35 days (SOC 2 common requirement)
- Monitoring and alerting on all critical metrics

**Processing Integrity:**
- Schema migrations through CI/CD with approval gates
- Change management process documented
- Post-deployment validation

**Confidentiality:**
- Data classification tags on all resources
- Access logs (pgaudit, CloudTrail) with 1-year retention
- Secrets Manager for credential storage
- Regular access reviews

**Evidence collection:**
- AWS Config rules for continuous compliance monitoring
- CloudTrail logs stored in S3 with versioning
- pgaudit logs in CloudWatch Logs with retention policy
- Monthly compliance reports from AWS Artifact

The auditor will ask for evidence that these controls are: (1) designed (documented), (2) implemented (running), and (3) effective (tested/monitored). The monitoring, alerting, and logging setup from this capstone provides most of the required evidence.

---

## Question 18: Capacity Planning

**Q: How do you forecast when your Aurora cluster will need to scale up?**

**A:** I use three methods:

**1. Trend analysis (weekly):** Pull 90 days of CloudWatch data for CPU, memory, connections, and storage. Plot the trend line and extrapolate. If CPU is growing 2% per month and you are at 60%, you have approximately 10 months before hitting 80%.

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=cluster-name \
  --start-time $(date -u -v-90d '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 604800 --statistics Average
```

**2. Business-driven forecasting:** Talk to the product team. If they are launching a feature that will 3x the user base, model the database impact: 3x connections, 3x TPS, 3x storage growth. Scale proactively before the launch.

**3. Load testing:** Run pgbench or a realistic load test against a staging cluster with the same instance class. Find the breaking point (where latency exceeds SLA). Compare current production load to the breaking point - the gap is your headroom.

**Key metrics to track:**
- Storage growth rate (GB/month) - linear extrapolation
- Connection count peak (growing? stable?)
- p99 query latency trend (increasing = approaching capacity)
- Buffer cache hit ratio (dropping = needs more memory)

**Action triggers:**
- CPU average >70% for 1 week: plan scale-up within 2 weeks
- Connections >80% of max_connections: deploy connection pooling immediately
- Storage growth will exceed budget in 3 months: discuss archival strategy
- p99 latency increased 50% month-over-month: investigate queries, then scale if needed

---

## Question 19: Terraform State Management

**Q: Your team uses Terraform for Aurora. Someone accidentally ran `terraform destroy` on the production cluster. How do you prevent this and recover?**

**A:**

**Prevention (must be in place BEFORE this happens):**
1. `deletion_protection = true` on the Aurora cluster - prevents API-level deletion
2. `lifecycle { prevent_destroy = true }` in Terraform - prevents `terraform destroy` from planning the deletion
3. Remote state with S3 versioning - allows state recovery
4. DynamoDB state locking - prevents concurrent operations
5. IAM policy: deny `rds:DeleteDBCluster` for all roles except a break-glass admin role
6. Separate Terraform workspaces for production and development
7. CI/CD pipeline with plan review - no one runs `terraform apply` locally against production

**Recovery if it happens:**
1. If deletion protection was on: the destroy failed. No damage.
2. If deletion protection was off but `skip_final_snapshot = false`: a final snapshot was created. Restore from it.
3. If a snapshot exists: `aws rds restore-db-cluster-from-snapshot`
4. If no snapshot: restore from automated backup (PITR) to the latest restorable time
5. Re-import the restored cluster into Terraform state

**State recovery:**
1. If using S3 versioning: restore the previous state version
2. If using local state with `.tfstate.backup`: restore from backup
3. If no backup: `terraform import` each resource manually

The most important lesson: deletion protection and `prevent_destroy` are not optional for production resources. They are the database equivalent of a seatbelt.

---

## Question 20: Production Readiness Assessment

**Q: You are reviewing a colleague's Aurora stack before go-live. What are the top 10 things you check?**

**A:** In order of criticality:

1. **Encryption at rest enabled** - Cannot be added after creation. If it is off, the cluster must be recreated. Check first.

2. **SSL/TLS forced** - `rds.force_ssl = 1`. Without this, credentials travel in plaintext.

3. **No public access** - Every instance must have `PubliclyAccessible = false`. A publicly accessible database is a security incident waiting to happen.

4. **Multi-AZ with matching instance classes** - Writer and failover target must use the same class. Mismatched classes cause performance degradation after failover.

5. **Backup retention >= 7 days** - Shorter retention means shorter PITR window. For production, 14-35 days is standard.

6. **CloudWatch alarms configured** - At minimum: CPU, connections, memory, replica lag. Alarms must have notification actions (not fire silently).

7. **Performance Insights and Enhanced Monitoring enabled** - Without these, performance investigation is guesswork.

8. **Deletion protection on** - One-line safety net against accidental destruction.

9. **Log export to CloudWatch** - Without logs, incident investigation hits a dead end.

10. **Secrets Manager for credentials** - No hardcoded passwords in Terraform state, CI/CD, or application config.

If any of items 1-3 fail, the stack is not production-ready. Items 4-6 are critical but fixable without recreation. Items 7-10 are important but can be addressed in the first week after launch.

This is exactly the checklist we built in the Concepts guide - and the reason it exists. Production readiness is a gate, not a suggestion.
