# Module 01 - AWS Foundations and Aurora Architecture
## Guide 03: RDS vs Aurora Comparison

**Objective:** Understand the key differences between Amazon RDS for PostgreSQL and Amazon Aurora PostgreSQL - including storage architecture, failover behavior, cost, and performance - so you can make informed decisions about which to use for a given workload.
**Time:** 20 minutes
**Prerequisites:** Basic understanding of what a managed database is (Guide 01 covers this). No AWS resources needed.
**Infrastructure:** None required - this guide is conceptual. No provisioning, no cost.

---

## 1. The Two Managed PostgreSQL Options on AWS

AWS offers two managed PostgreSQL services:

- **Amazon RDS for PostgreSQL** - a managed service that runs standard PostgreSQL on a single EC2 instance with EBS storage attached.
- **Amazon Aurora PostgreSQL** - a managed service that runs a PostgreSQL-compatible engine on a custom-built, distributed storage layer designed by AWS.

Both services run PostgreSQL-compatible SQL. Your `psql` commands, your `CREATE TABLE` statements, your application connection strings - they all work the same way on either service. The differences are under the hood: how storage works, how failover happens, and how performance scales.

---

## 2. Side-by-Side Comparison

| Feature | RDS for PostgreSQL | Aurora PostgreSQL |
|---------|-------------------|-------------------|
| **Engine** | Standard open-source PostgreSQL | PostgreSQL-compatible (AWS-modified) |
| **Storage type** | Amazon EBS (single volume) | Distributed Aurora storage (6 copies across 3 AZs) |
| **Max storage** | 64 TB | 128 TB |
| **Storage scaling** | Manual or autoscaling (step increases) | Automatic (grows in 10 GB increments, no downtime) |
| **Read replicas** | Up to 15 (asynchronous, separate EBS each) | Up to 15 (share the same storage layer) |
| **Replication lag** | Seconds to minutes | Typically under 100ms |
| **Failover time** | 60-120 seconds (Multi-AZ) | Usually under 30 seconds |
| **Backup** | EBS snapshots | Continuous to S3 (no performance impact) |
| **Point-in-time recovery** | 5-minute granularity | 1-second granularity |
| **Multi-AZ** | Synchronous standby (separate EBS copy) | Built into storage (6 copies across 3 AZs by default) |
| **Instance types** | Full range of RDS instance types | Full range of Aurora instance types |
| **Serverless option** | No | Yes (Aurora Serverless v2) |
| **Free tier eligible** | Yes (db.t3.micro, 750 hrs/month) | No |
| **Pricing model** | Instance + storage + I/O | Instance + storage + I/O (I/O is higher) |

---

## 3. Storage Architecture - The Biggest Difference

This is where RDS and Aurora fundamentally diverge. Understanding storage architecture is critical because it affects everything - performance, durability, failover speed, and backup behavior.

### RDS Storage: EBS Volumes

```
                    ┌──────────────────────┐
                    │    RDS Instance       │
                    │   (PostgreSQL 16)     │
                    │                       │
                    └──────────┬────────────┘
                               │
                    ┌──────────▼────────────┐
                    │    EBS Volume          │
                    │   (gp3 or io1/io2)    │
                    │                       │
                    │   Single volume       │
                    │   Single AZ           │
                    └───────────────────────┘
```

With RDS, your database writes to a single Amazon EBS (Elastic Block Store) volume. That volume lives in one Availability Zone. If you enable Multi-AZ, AWS maintains a synchronous standby in a different AZ with its own separate EBS volume - but the write path still goes to a single volume.

Key characteristics:
- Storage and compute are tightly coupled to one AZ
- The EBS volume must be provisioned at a specific size (you choose it at creation)
- Autoscaling can grow the volume, but it happens in steps and can take minutes
- Backups are EBS snapshots - a point-in-time copy of the entire volume

### Aurora Storage: Distributed and Shared

```
                ┌─────────────┐     ┌─────────────┐
                │   Writer    │     │  Reader(s)   │
                │  Instance   │     │  Instance(s) │
                └──────┬──────┘     └──────┬───────┘
                       │                   │
                       ▼                   ▼
    ┌──────────────────────────────────────────────────┐
    │            Aurora Shared Storage Layer            │
    │                                                  │
    │  ┌────────┐  ┌────────┐  ┌────────┐             │
    │  │ Copy 1 │  │ Copy 2 │  │ Copy 3 │   AZ-a      │
    │  └────────┘  └────────┘  └────────┘             │
    │  ┌────────┐  ┌────────┐  ┌────────┐             │
    │  │ Copy 4 │  │ Copy 5 │  │ Copy 6 │   AZ-b      │
    │  └────────┘  └────────┘  └────────┘             │
    │  (spread across 3 AZs in 10GB chunks)  AZ-c     │
    │                                                  │
    └──────────────────────────────────────────────────┘
```

Aurora uses a completely different approach. The storage layer is separated from the compute layer and distributed across 3 Availability Zones. Your data is automatically replicated 6 times - 2 copies in each of 3 AZs.

Key characteristics:
- Storage and compute are decoupled. The storage layer is a shared, distributed system
- Aurora writes to the storage layer, which handles replication automatically
- Reader instances read from the same shared storage - they do not maintain their own copies
- Storage grows automatically in 10 GB increments as your data grows. No provisioning, no downtime
- Aurora can lose 2 copies of your data and still write. It can lose 3 copies and still read
- Backups are continuous to S3 with no performance impact on the database

### Why This Matters

The distributed storage architecture gives Aurora several practical advantages:

1. **Faster failover** - when the writer fails, a reader can be promoted quickly because it already has access to the same storage. No data copying needed.
2. **No replication lag for storage** - reader instances see the same storage. The sub-100ms "lag" is just the time to apply redo log records.
3. **Automatic storage growth** - you never run out of disk space unexpectedly. Aurora grows as needed.
4. **Better durability** - 6 copies across 3 AZs is more durable than a single EBS volume (even with Multi-AZ replication).

---

## 4. Failover Behavior

### RDS Multi-AZ Failover

When you enable Multi-AZ on RDS, AWS maintains a synchronous standby instance in a different AZ. If the primary fails:

1. AWS detects the failure (monitoring checks every 5 seconds)
2. AWS flips the DNS endpoint to point at the standby
3. The standby becomes the new primary
4. Total failover time: **60-120 seconds**

During this window, your application cannot write to the database. Reads also fail because the DNS is changing. Applications with retry logic will recover automatically once DNS resolves to the new primary.

### Aurora Failover

Aurora handles failover differently because of the shared storage architecture:

1. AWS detects the writer failure
2. If a reader replica exists, Aurora promotes it to writer. The reader already has access to the shared storage - no data needs to be copied.
3. AWS updates the cluster endpoint DNS
4. Total failover time: **usually under 30 seconds** (often 15-20 seconds with a reader available)

If no reader replica exists, Aurora creates a new writer instance, which takes longer (several minutes).

The takeaway: Aurora failover is faster because the promotion step does not involve copying data. The new writer just starts writing to the shared storage layer.

---

## 5. Cost Comparison

Cost depends heavily on your workload, but here are some general patterns.

### Small Workloads (Dev/Test)

| Component | RDS (db.t3.medium) | Aurora (db.t3.medium) |
|-----------|-------------------|----------------------|
| Instance (on-demand, monthly) | ~$50 | ~$58 |
| Storage (50 GB, gp3) | ~$5 | ~$5 |
| I/O | Included in gp3 | ~$0.20 per million requests |
| Backup storage | Free (up to DB size) | Free (up to DB size) |
| **Estimated monthly** | **~$55** | **~$65** |

> **Important:** Aurora is not eligible for the AWS Free Tier. RDS for PostgreSQL is (db.t3.micro, 750 hours/month for 12 months). If cost is your primary concern for learning, start with RDS.

### Medium Workloads (Production, single writer + 1 reader)

| Component | RDS (db.r6g.large) | Aurora (db.r6g.large) |
|-----------|-------------------|----------------------|
| Writer instance (monthly) | ~$175 | ~$200 |
| Reader instance (monthly) | ~$175 (separate EBS) | ~$200 (shared storage) |
| Storage (500 GB) | ~$50 (gp3) | ~$50 |
| I/O | Included in gp3 | $0.20/million (varies) |
| Multi-AZ standby | +$175 (another instance) | Built into storage |
| **Estimated monthly** | **~$575** | **~$450-500** |

At this scale, Aurora can actually be cheaper because you do not need a separate Multi-AZ standby - Aurora's storage is already spread across 3 AZs. Your reader replica doubles as your failover target.

### Large Workloads (High I/O Production)

At large scale, Aurora's I/O costs can become significant. If your workload does millions of I/O requests per second, Aurora I/O charges can add up quickly. AWS offers **Aurora I/O-Optimized** pricing for these workloads - a higher instance price but no per-I/O charges.

> **Cost tip:** Always estimate your I/O costs before choosing Aurora. Use the AWS Pricing Calculator at https://calculator.aws/ to model your specific workload.

---

## 6. When to Use RDS vs Aurora - Decision Tree

Use this decision tree when choosing between the two services.

```
Start here: "I need a managed PostgreSQL database on AWS"
│
├── Is cost the primary concern AND workload is small?
│   ├── YES -> RDS for PostgreSQL (Free Tier eligible)
│   └── NO -> Continue
│
├── Do I need fast failover (under 30 seconds)?
│   ├── YES -> Aurora
│   └── NO -> Continue
│
├── Do I need multiple read replicas with minimal lag?
│   ├── YES -> Aurora (shared storage = sub-100ms lag)
│   └── NO -> Continue
│
├── Do I need automatic storage scaling with zero downtime?
│   ├── YES -> Aurora
│   └── NO -> Continue
│
├── Is my workload unpredictable / spiky?
│   ├── YES -> Aurora Serverless v2 (auto-scales compute)
│   └── NO -> Continue
│
├── Do I need standard, unmodified PostgreSQL?
│   ├── YES -> RDS (runs vanilla PostgreSQL)
│   └── NO -> Continue
│
├── Am I migrating from an existing self-managed PostgreSQL
│   and want minimal changes?
│   ├── YES -> RDS (closest to standard PostgreSQL)
│   └── NO -> Aurora (more features, better performance)
│
└── Default recommendation for new production workloads:
    -> Aurora PostgreSQL
```

### Quick Rules of Thumb

- **Learning / dev / test on a budget** - use RDS (Free Tier)
- **Production with HA requirements** - use Aurora
- **Read-heavy workloads** - use Aurora (shared storage, more efficient replicas)
- **Write-heavy, high-I/O workloads** - use Aurora I/O-Optimized or cost-model carefully
- **Compliance requires unmodified PostgreSQL** - use RDS
- **Variable / unpredictable traffic** - use Aurora Serverless v2

---

## 7. What Aurora Is NOT

A few common misconceptions to clear up:

**Aurora is not a different database engine.** It runs PostgreSQL-compatible SQL. Your queries, your tools (psql, pgAdmin, DBeaver), your application drivers - they all work the same way. The difference is in the storage and replication layer underneath.

**Aurora is not always faster than RDS.** For simple, single-instance workloads with low I/O, RDS and Aurora perform similarly. Aurora's advantages show up at scale - with multiple readers, high availability requirements, and large datasets.

**Aurora is not free.** There is no Free Tier for Aurora. Every minute your Aurora cluster is running costs money. You will learn cost management in Guide 05.

**Aurora is not self-managed PostgreSQL.** You still cannot SSH into an Aurora instance. You still do not have OS-level access. The shared responsibility model from RDS applies to Aurora as well.

---

## Summary

- RDS for PostgreSQL runs standard PostgreSQL with EBS storage - one volume, one AZ (unless Multi-AZ is enabled).
- Aurora PostgreSQL uses a custom distributed storage layer - 6 copies across 3 AZs by default.
- Aurora's storage architecture enables faster failover (under 30 seconds), automatic storage scaling, and minimal replication lag.
- RDS is eligible for the AWS Free Tier. Aurora is not.
- For small/dev workloads, RDS is often cheaper. For production with HA requirements, Aurora is often the better value because you do not need a separate Multi-AZ standby.
- Aurora is not a different database - your SQL, tools, and application code work the same on both services.
- For this training track, you will use Aurora PostgreSQL because the DevOps DBA role requires understanding distributed storage, fast failover, and production-grade HA.

**Next:** [Guide 04 - PostgreSQL Refresher](./04-postgresql-refresher.md)
