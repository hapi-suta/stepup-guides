# Interview Questions: Cloud Database Services

**Module 03 - Cloud Database Services**
**5 questions covering RDS, Aurora, backup, monitoring, and cost optimization**

---

## Question 1: RDS Multi-AZ vs Aurora Architecture

**Question:** Explain the architectural difference between RDS Multi-AZ and Aurora. How does this affect failover time and cost?

**What they are looking for:** Understanding of the fundamental storage architecture difference, not just feature comparison.

**Strong Answer:**

RDS Multi-AZ uses traditional PostgreSQL streaming replication under the hood. The primary has its own EBS volume, and the standby has a separate EBS volume in a different Availability Zone. Every write goes to the primary's EBS first, then is synchronously replicated to the standby's EBS before being acknowledged. Failover requires promoting the standby, which includes applying any pending WAL and updating the DNS endpoint. This takes 60-120 seconds.

Aurora separates compute from storage entirely. Both the writer and reader instances point to the same distributed storage layer, which replicates data 6 ways across 3 Availability Zones at the storage level. There is no streaming replication between instances. When the writer fails, a reader simply becomes the new writer - it already has access to all the data. This takes about 30 seconds.

The cost implication: RDS Multi-AZ doubles your instance cost because you are running two full instances with two separate storage volumes. Aurora's HA is built into the storage layer (6-way replication is the default), so adding a reader costs one more instance but not double the storage.

**Red flags in weak answers:**
- Saying both use "replication" without distinguishing the mechanisms
- Not knowing that Aurora readers share storage with the writer
- Not mentioning the failover time difference

---

## Question 2: PITR in RDS vs Self-Managed

**Question:** How does Point-in-Time Recovery work in RDS compared to self-managed PostgreSQL? What is a key operational difference a DBA needs to know?

**Strong Answer:**

In self-managed PostgreSQL, PITR requires three things: a base backup (from pg_basebackup or pgBackRest), continuous WAL archiving (configured via archive_command), and a recovery target (set in postgresql.conf or recovery.conf as recovery_target_time). You restore the base backup, point PostgreSQL at the WAL archive, set the target time, and start the server. The recovery happens in-place - you overwrite the existing data directory.

In RDS, the mechanism is the same - AWS takes daily snapshots (the base backup) and continuously archives WAL to S3 (you never see this). You specify a target time via the CLI or console. The key operational difference: **RDS always restores to a NEW instance.** You cannot restore in-place. This means your recovery workflow changes:

1. You restore to a new instance
2. You verify the data on the new instance
3. You redirect your application to the new instance (DNS change or instance rename)
4. You delete the old instance

This has implications for RTO (Recovery Time Objective). The restore itself takes 30-60 minutes, but the DNS propagation and application reconnection add time. In self-managed, you restore in-place and the application reconnects to the same endpoint.

Another difference: RDS limits PITR to 1-35 days of retention. In self-managed, you can keep WAL archives for as long as you want (limited only by storage cost).

---

## Question 3: RDS CPU at 95%

**Question:** Your RDS instance CPU is at 95%. Walk through your troubleshooting approach.

**Strong Answer:**

I would follow this progression from least disruptive to most disruptive:

**Step 1: Identify the workload (Performance Insights or pg_stat_statements)**

First, check Performance Insights to see which queries are consuming CPU. If Performance Insights is not enabled, connect with psql and query pg_stat_statements:

```sql
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Also check for active sessions:

```sql
SELECT pid, state, wait_event_type, wait_event, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

**Step 2: Determine if this is normal growth or a sudden spike**

Check CloudWatch CPU history. If CPU gradually climbed over weeks, it is likely organic growth - you need to optimize queries or upsize. If it spiked suddenly, look for:
- A new deployment that introduced a bad query
- A batch job that normally runs off-hours running during peak
- Missing indexes after a schema change
- Autovacuum running aggressively due to bloat

**Step 3: Quick wins**
- Kill any long-running queries that are not critical
- If a specific query is the culprit, check its execution plan with EXPLAIN ANALYZE
- Look for sequential scans on large tables - add indexes
- Check if autovacuum is consuming CPU (check pg_stat_progress_vacuum)

**Step 4: Medium-term fixes**
- Optimize the top CPU-consuming queries
- Add read replicas and route read traffic to them
- Tune work_mem and effective_cache_size if queries are spilling to disk

**Step 5: If nothing else works**
- Scale up to a larger instance class
- Consider Aurora if you need more than 5 read replicas

**Red flags in weak answers:**
- Jumping straight to "upsize the instance" without investigating the root cause
- Not mentioning pg_stat_statements or Performance Insights
- Not checking for sudden changes vs gradual growth

---

## Question 4: Self-Managed vs RDS/Aurora

**Question:** When would you choose self-managed PostgreSQL over RDS or Aurora?

**Strong Answer:**

I would choose self-managed PostgreSQL in these specific situations:

**1. Custom or unsupported extensions**
If the application requires extensions not available in RDS/Aurora (like custom C extensions, specific versions of PostGIS, or pg_cron on standard RDS), self-managed is the only option. I have seen this with geospatial workloads that need bleeding-edge PostGIS features.

**2. OS-level control requirements**
If I need specific kernel tuning (huge pages configuration, custom sysctl settings), specific filesystem choices (ZFS for compression), or custom monitoring agents that require root access.

**3. Cost optimization at scale**
For very large deployments (dozens of instances), self-managed on EC2 with Reserved Instances can be 30-50% cheaper than RDS. The trade-off is higher operational overhead, which you need a team to handle.

**4. Regulatory or compliance requirements**
Some compliance frameworks require full audit trails of OS-level changes, or restrict data to specific hardware. Self-managed gives you the documentation trail and hardware control.

**5. Specific replication topologies**
If you need multi-master replication (BDR), custom cascading replication, or logical replication configurations that RDS does not support.

**When I would NOT choose self-managed:**
- Small team without dedicated DBA capacity for on-call
- Standard OLTP workloads with no exotic requirements
- When time-to-market matters more than infrastructure cost
- When the company does not have expertise in Linux administration, backup management, and HA setup

The decision comes down to: do you have the team and the need? If your team is 2-3 people and you are building a SaaS product, RDS or Aurora saves hundreds of hours per year in operational work.

---

## Question 5: Aurora Cost Estimation

**Question:** How do you estimate costs for an Aurora PostgreSQL cluster? Walk through the components.

**Strong Answer:**

Aurora pricing has four main components, and I would estimate each separately:

**1. Compute (instance hours)**
- Identify the instance class needed based on CPU and memory requirements
- Writer instance runs 24/7: hourly_rate x 730 hours/month
- Reader instances: same calculation per reader
- Example: db.r6g.xlarge writer ($0.58/hr) + 1 reader ($0.58/hr) = $846/month

**2. Storage ($0.10/GB-month)**
- Aurora storage is based on ACTUAL data stored, not provisioned size
- It auto-grows - you do not allocate upfront
- Include indexes, WAL, and system overhead (typically 1.5-2x your logical data size)
- Example: 500 GB actual usage = $50/month

**3. I/O ($0.20 per million requests)**
- This is the tricky one. Every read and write to the storage layer counts.
- A rough estimate: OLTP workloads with moderate throughput generate 50-200 million I/Os per month per 100 GB of active data
- Monitoring I/O in CloudWatch (`VolumeReadIOPs` + `VolumeWriteIOPs`) gives you real numbers after the first week
- Example: 100 million I/Os = $20/month

**4. Backup storage ($0.021/GB-month beyond free tier)**
- Free tier: equal to your cluster volume size
- Additional backup storage is charged
- Example: 500 GB cluster with 600 GB of backups = 100 GB charged = $2.10/month

**Total example estimate:**
- Compute: $846
- Storage: $50
- I/O: $20
- Backup: $2.10
- **Total: ~$918/month**

**Cost optimization tips I would mention:**
- Use Graviton (ARM) instances for 10-20% savings
- Use Reserved Instances for predictable workloads (30-50% savings on compute)
- Aurora Serverless v2 for dev/test (scales to near-zero when idle)
- Monitor I/O costs - they can surprise you on write-heavy workloads
- Compare to RDS Multi-AZ + read replica pricing - Aurora is often cheaper for HA setups because RDS doubles the instance cost for Multi-AZ
