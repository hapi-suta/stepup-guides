# Tier 0 - Foundations
## Guide 02: RDS for PostgreSQL vs Aurora PostgreSQL

**Objective:** Understand the architectural differences between Amazon RDS for PostgreSQL and Amazon Aurora PostgreSQL so you can make an informed choice between them for any given workload.
**Time:** 25 minutes
**Prerequisites:** Guide 01 (Managed Databases and the Shared Responsibility Model)
**Infrastructure:** None required (conceptual)

---

## 1. The Key Thing to Know Up Front

RDS for PostgreSQL and Aurora PostgreSQL both speak the PostgreSQL protocol. Your application connects to either one the same way. Your SQL works on both. Your `psql` client works with both. Your `pg_dump` backups are compatible with both.

The difference is entirely **below the SQL layer** - in how storage is built and how replication works.

This is important because many people assume they are completely different products. They are not. Aurora PostgreSQL is AWS's reimplementation of the storage and replication layer underneath a PostgreSQL-compatible engine. The SQL you write does not change.

---

## 2. How RDS for PostgreSQL Stores Data

RDS for PostgreSQL works the same way a standard PostgreSQL server works at the storage level:

1. PostgreSQL writes data pages to disk.
2. "Disk" in RDS is an AWS EBS (Elastic Block Store) volume attached to the instance.
3. You choose the volume type: `gp3` (general purpose) or `io1`/`io2` (provisioned IOPS for high-throughput workloads).
4. The EBS volume lives in one Availability Zone.
5. If you enable Multi-AZ, AWS maintains a standby instance in a second AZ with its own EBS volume. PostgreSQL streaming replication keeps the standby in sync.

**What this means for you:**

- Storage is attached to a specific instance in a specific AZ.
- Storage capacity is what you provision. You can enable autoscaling to let it grow, but it does not shrink.
- IOPS (read/write throughput) is determined by your volume type and size. For `gp3`, you configure baseline IOPS separately from storage size.
- A failover to the standby involves promoting the replica - which takes 60-120 seconds typically.
- Read replicas each have their own EBS volumes and use PostgreSQL streaming replication to stay in sync with the primary.

Think of RDS storage like a hard drive attached to a server. Fast, reliable, but tied to that one server.

---

## 3. How Aurora PostgreSQL Stores Data

Aurora takes a fundamentally different approach. Instead of attaching a volume to an instance, Aurora uses a **distributed storage system** that is separate from the compute instances.

Here is how it works:

1. Your Aurora PostgreSQL compute instance (the database engine) connects to the Aurora storage layer over the network.
2. The storage layer automatically replicates your data **6 ways across 3 Availability Zones** - 2 copies per AZ.
3. Aurora can tolerate losing 2 copies (out of 6) without losing data, and losing 3 copies without losing write availability.
4. All Aurora read replicas (up to 15) connect to the **same shared storage layer** - they do not each maintain their own copy of the data.
5. Storage grows automatically in 10 GB increments as your data grows. You do not provision a size upfront.

**What this means for you:**

- Storage is decoupled from compute. You can add or remove read replicas without copying data.
- Failover is faster - typically under 30 seconds - because a replica is already connected to the same storage. There is no need to set up or catch up a new primary.
- You do not configure storage IOPS separately. Aurora manages this internally.
- You cannot choose `gp3` vs `io1` - Aurora handles the storage tier for you.
- Storage billed per GB consumed, not per GB provisioned.

Think of Aurora storage like a distributed database built into the cloud - shared, durable, and automatically redundant.

---

## 4. Replication Compared

This is where the two products differ most in day-to-day operations.

### RDS for PostgreSQL Replication

RDS uses standard PostgreSQL streaming replication. This is the same replication mechanism you would set up manually on an EC2 instance.

- The primary writes WAL (Write-Ahead Log) records.
- WAL records stream over the network to each replica.
- Each replica applies those records to its own EBS-backed copy of the data.
- Replicas can fall behind if WAL generates faster than the replica can apply it.
- You can have up to 5 read replicas.
- Each replica costs the same as a standalone instance (compute + storage).

### Aurora PostgreSQL Replication

Aurora replicas share the same storage layer as the primary. Replication is not about copying data - the data is already there.

- The primary writes to the shared storage layer.
- Aurora replicas only need to receive small "cache invalidation" messages to know which pages have changed.
- Replica lag is typically under 100 milliseconds - often in single-digit milliseconds.
- You can have up to 15 Aurora Replicas.
- Adding a replica is fast and cheap because no data needs to be copied.
- Failover promotes one of the existing replicas to primary - sub-30-second failovers are common.

---

## 5. Feature Comparison at a Glance

| Feature | RDS for PostgreSQL | Aurora PostgreSQL |
|---------|-------------------|-------------------|
| PostgreSQL compatibility | Full | Near-full (some extensions differ) |
| Storage type | EBS (gp3, io1, io2) | Aurora distributed storage |
| Storage redundancy | 1 copy (replicated by EBS internally) | 6 copies across 3 AZs |
| Storage growth | Manual or autoscaling (provisioned) | Automatic, pay for what you use |
| Max read replicas | 5 | 15 |
| Replication method | Streaming replication (WAL-based) | Shared storage (cache invalidation) |
| Replica lag | Can vary (seconds to minutes under load) | Typically under 100ms |
| Multi-AZ failover time | 60-120 seconds typical | Under 30 seconds typical |
| Global replication | RDS Cross-Region Read Replicas | Aurora Global Database (sub-1s RPO) |
| Serverless option | No | Aurora Serverless v2 |
| Cost (generally) | Lower base cost | Higher base cost, lower replica cost |
| `pg_dump` compatible | Yes | Yes |
| PostgreSQL extensions | Most standard extensions | Most, with some exceptions |
| Direct OS access | No | No |
| Maximum storage | 64 TB | 128 TB |

---

## 6. What Aurora Cannot Do That Standard PostgreSQL Can

Because Aurora modifies the storage layer, a small number of PostgreSQL behaviors differ:

- **Some extensions are not supported** - for example, extensions that require direct filesystem access may not work. Check the Aurora documentation for the specific PostgreSQL version you need.
- **`pg_basebackup` does not work** against Aurora - Aurora uses its own snapshot mechanism.
- **WAL behavior differs internally** - Aurora does not stream WAL the same way. This matters if you are trying to connect a logical replication subscriber to Aurora (logical replication works, but physical slot behavior differs).
- **The `aurora_stat_*` family of functions** are Aurora-specific and provide storage-level insight not available in RDS.

For most applications, none of these differences are blocking. But it is worth verifying extension compatibility before committing to Aurora for a specific workload.

---

## 7. Cost Considerations

RDS for PostgreSQL is generally cheaper for simple single-instance deployments. You pay for:
- Instance compute hours
- EBS storage provisioned (even unused space)
- IOPS if using io1/io2
- Backup storage beyond free tier
- Data transfer

Aurora PostgreSQL costs more per instance but the economics shift when you add replicas. Because Aurora replicas share storage, you pay for compute only - not another full copy of the data. For workloads that need multiple read replicas, Aurora can actually be cheaper in total.

Aurora also has Aurora Serverless v2, which scales compute up and down in fractions of an Aurora Capacity Unit (ACU). This is useful for variable workloads or development environments where you do not need constant capacity.

**Rule of thumb:** If you need predictable workload, simple architecture, and lowest cost per instance - start with RDS. If you need fast failover, many read replicas, or near-zero replica lag - Aurora is the better fit.

---

## 8. Decision Framework: RDS or Aurora?

Work through these questions in order:

**Step 1: Do you need sub-30-second failover?**
- Yes - Aurora
- No - continue to Step 2

**Step 2: Do you need more than 5 read replicas?**
- Yes - Aurora
- No - continue to Step 3

**Step 3: Do you need replica lag under 100ms consistently?**
- Yes - Aurora
- No - continue to Step 4

**Step 4: Do you need serverless (auto-scaling compute)?**
- Yes - Aurora Serverless v2
- No - continue to Step 5

**Step 5: Do you have a very small database (under 100 GB) with simple architecture?**
- Yes - RDS (lower cost, simpler)
- No - evaluate cost difference at your expected instance size

**Step 6: Do any required extensions conflict with Aurora's supported list?**
- Yes - RDS
- No - either option works; default to Aurora for production at scale

---

## 9. Exercise: Choose RDS or Aurora

For each scenario below, decide whether you would recommend RDS for PostgreSQL or Aurora PostgreSQL. Write your reasoning before reading the suggested answers.

**Scenario A:** A startup is building a new SaaS product. They have a single developer, expect moderate traffic, need to minimize monthly AWS costs, and have no specific HA requirements beyond nightly backups.

**Scenario B:** A fintech company processes payments and requires database failover within 20 seconds when the primary instance fails. They have 4 read replicas serving reporting dashboards and replica lag must stay under 50ms.

**Scenario C:** A data team runs a PostgreSQL database used primarily for batch ETL jobs that run overnight. The database is idle for 16 hours per day and must keep costs low during idle time.

---

**Suggested Answers:**

**Scenario A - RDS for PostgreSQL**
The startup has no strict HA requirements and cost matters most. A single RDS instance with automated backups is simple, cheaper, and more than adequate. Starting with Aurora would over-engineer the solution and increase the monthly bill without clear benefit.

**Scenario B - Aurora PostgreSQL**
Failover under 20 seconds rules out standard RDS (which takes 60-120 seconds). The low replica lag requirement (under 50ms) matches Aurora's shared storage replication model. The number of read replicas (4) is within both limits, but Aurora's replica economics make it a better choice at that scale.

**Scenario C - Aurora Serverless v2**
Batch-only workloads with long idle periods are exactly what Serverless v2 is designed for. Aurora Serverless v2 can scale down to minimum ACUs during idle hours, saving significantly on compute costs. This is a case where Aurora is cheaper than RDS despite the higher base pricing.

---

## Summary

- Both products speak PostgreSQL - your SQL, tools, and drivers work with both.
- RDS uses EBS volumes (standard block storage attached to an instance). Replication is PostgreSQL streaming replication.
- Aurora uses a distributed storage layer with 6 copies across 3 AZs. Replicas share the storage; only compute differs.
- Aurora offers faster failover (under 30 seconds), lower replica lag (under 100ms), more replicas (up to 15), and larger maximum storage (128 TB).
- RDS is simpler and cheaper for small, single-instance deployments.
- Aurora is the better choice when you need high availability, many replicas, or near-zero lag.
- Aurora Serverless v2 is ideal for variable or idle-heavy workloads.
- Use the decision framework to pick the right option for each workload.

**Next:** [Guide 03 - AWS Account, IAM Users, Roles, and Regions](./03-aws-account-iam-regions.md)
