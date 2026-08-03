# Concepts: Backup Strategies for Aurora PostgreSQL
## Module 06 - Backup, Recovery, and Lifecycle

Read this before starting any BUILD guide. These concepts explain the "why" behind every backup and recovery command you will run.

---

## 1. Automated Backups - The Foundation

Aurora PostgreSQL continuously backs up your database to Amazon S3. Unlike standard RDS, Aurora does NOT take a single daily snapshot. Instead, it continuously streams data to S3 using the underlying Aurora storage layer.

```
How Aurora Automated Backups Work
==================================

Traditional RDS:
  Day 1           Day 2           Day 3
  [FULL SNAP] --- [FULL SNAP] --- [FULL SNAP]
       |               |               |
  WAL streams to S3 between snapshots
  (one big snapshot per day, WAL fills the gaps)

Aurora:
  Continuous backup - no discrete daily snapshots
  Every change is written to 6 copies across 3 AZs
  AND streamed to S3 continuously

  [Data]-->[6 copies in 3 AZs]-->[S3 continuous backup]

  Result: you can restore to any second within your retention window
  without waiting for a "daily snapshot + WAL replay" cycle.
```

Key facts about Aurora automated backups:
- Backups are continuous and incremental - there is no "backup window" that causes performance impact
- Backup retention period: 1 to 35 days (default is 1 day)
- Setting retention to 0 is NOT allowed for Aurora clusters - backups cannot be fully disabled
- Deleting the Aurora cluster deletes all automated backups unless you take a final snapshot
- Backups are stored in S3 managed by AWS - you cannot see or access the bucket directly

### Backup Retention Period

The retention period controls how far back you can recover using point-in-time recovery (PITR). Longer retention means more recovery options but slightly higher S3 storage cost.

```
Retention Period and Recovery Window
======================================

Retention = 7 days
Today is June 9, 2026

You can recover to ANY second between:
  June 2, 2026 00:00:00 UTC  <--- 7 days ago
       |
       |  [any second in this window is recoverable]
       |
  June 9, 2026 14:37:22 UTC  <--- latest restorable time

Everything older than 7 days is permanently gone from automated backups.
```

Recommendations by workload:
- Development / testing: 1-3 days (minimize cost)
- Staging: 7 days (catch issues before production)
- Production: 14-35 days (maximize recovery options)
- Compliance workloads: 35 days automated + monthly manual snapshots

---

## 2. Manual Snapshots (Cluster Snapshots)

A manual snapshot is a user-triggered backup of an Aurora cluster. It is NOT deleted when the cluster is deleted. It persists indefinitely until you explicitly delete it.

```
Automated Backups vs Manual Snapshots
========================================

AUTOMATED BACKUP                    MANUAL SNAPSHOT
- Continuous, AWS-managed           - Triggered by you anytime
- Deleted with cluster              - Survives cluster deletion
- Retention: 1-35 days              - Retention: indefinite
- Used for PITR                     - Used for restore to that exact point
- No extra cost within retention    - Costs ~$0.021/GB-month (Aurora storage)
- Cannot share across accounts*     - Can copy across regions/accounts

* Automated backup snapshots can be shared but require a copy first
```

### When to Take Manual Snapshots

Take a manual snapshot before any of these events:
- Major version upgrades (e.g., PostgreSQL 15 to 16)
- Large data migrations or schema changes
- Changing cluster parameters (especially static ones)
- Before deleting a cluster (as a "final snapshot")
- Monthly for compliance retention beyond 35 days
- Before holiday or peak traffic periods

### Manual Snapshot Naming

Use a consistent naming convention:

```
{cluster-name}-{purpose}-{date}

Examples:
  devops-lab-cluster-pre-upgrade-20260609
  devops-lab-cluster-monthly-20260601
  devops-lab-cluster-pre-migration-20260609
```

---

## 3. Point-in-Time Recovery (PITR)

PITR lets you recover your Aurora cluster to any specific second within the backup retention window. This is the primary recovery tool for accidental data loss.

### How PITR Works in Aurora

Aurora PITR works differently from standard RDS because of Aurora's continuous backup architecture:

```
Aurora PITR Recovery Mechanics
================================

Your target: Tuesday 14:37:22 UTC

Aurora does NOT need to:
  - Find the "last daily snapshot"
  - Replay hours of WAL

Aurora DOES:
  - Identify the correct S3 backup data at the target time
  - Create a new cluster with data state at exactly 14:37:22
  - This is typically faster than RDS PITR because Aurora
    does not need to replay WAL sequentially

Recovery time: Usually 10-20 minutes for small clusters,
               30-60 minutes for large clusters.
```

### What PITR Creates

PITR always creates a NEW Aurora cluster. It does NOT modify your existing cluster.

```
PITR Creates a New Cluster
============================

BEFORE PITR:
  [devops-lab-cluster] - running, has corrupted/deleted data

AFTER PITR:
  [devops-lab-cluster]          - still running, untouched
  [devops-lab-cluster-restored] - NEW cluster, data from target time

YOUR JOB:
  1. Verify restored cluster has the right data
  2. Export specific tables with pg_dump and import to original
     OR update application connection string to new cluster
  3. Delete the cluster you no longer need
```

### Latest Restorable Time

The "latest restorable time" is the most recent second you can recover to. It lags a few minutes behind real-time because Aurora needs to finish writing backup data to S3.

```
Latest Restorable Time Lag
============================

Real time:            14:42:00 UTC
Latest restorable:    14:39:22 UTC
                      ^
                      |
                 ~2-5 minute lag
                 (backup data still being committed to S3)

You CANNOT recover to anything in the last 2-5 minutes.
Always check the latest restorable time before setting your target.
```

---

## 4. Cross-Region Backup

Copying snapshots to another region creates geographic disaster recovery. If your entire primary region goes down, you can restore from the copy in the secondary region.

### How Cross-Region Copy Works

```
Cross-Region Snapshot Copy Flow
=================================

us-east-1                          us-west-2
+-----------------------+          +-----------------------+
| Manual Snapshot       |  ------> | Copy of Snapshot      |
| devops-lab-cluster-   |  copy    | devops-lab-cluster-   |
|  monthly-20260601     |          |  monthly-20260601     |
|                       |          | (independent copy)    |
+-----------------------+          +-----------------------+

Network cost: Data transfer out of source region
Storage cost: Full snapshot size in destination region
Time: Depends on snapshot size (GB to TB can take hours)
```

### Cross-Region Copy vs Aurora Global Database

```
Cross-Region Comparison
=========================

                    SNAPSHOT COPY           AURORA GLOBAL DATABASE
Time to failover    30-60 minutes           ~1 minute
RPO                 At snapshot time        Typically < 1 second
Cost                Storage only            Full cluster in secondary
Automation          Manual or scheduled     Continuous, automatic
Best for            Compliance copies       True multi-region DR
                    Archival                Real-time failover
```

For the DevOps DBA Training Track, we focus on snapshot copies. Aurora Global Database is covered in advanced modules.

---

## 5. Cross-Account Snapshot Sharing

You can share a manual snapshot with another AWS account. The receiving account must then copy the snapshot into their own account before restoring.

```
Cross-Account Sharing Flow
=============================

Account A (123456789012)         Account B (987654321098)
+--------------------------+     +--------------------------+
| Manual Snapshot          |     | Cannot access yet        |
| "devops-lab-snap"        |     |                          |
|                          |     |                          |
| Modify permissions:      | --> | Can now see the shared   |
| + Add account B          |     | snapshot                 |
+--------------------------+     |                          |
                                 | Account B copies it to   |
                                 | own account, then        |
                                 | restores from the copy   |
                                 +--------------------------+
```

Use cases for cross-account sharing:
- Disaster recovery team in a separate account
- Development team needs production data (sanitized first)
- Regulatory: auditors need database access in their own account
- Multi-account architecture with separate prod/dev accounts

---

## 6. Backup Costs

Understanding backup costs helps you design a cost-effective strategy:

```
Aurora Backup Cost Model
==========================

Automated backups (within retention window):
  - Free up to the total size of your Aurora storage
  - Example: 100 GB cluster with 7-day retention
    First 100 GB of backups: $0.00
    Additional backup storage: $0.021/GB-month

Manual snapshots:
  - $0.021/GB-month for all manual snapshot storage
  - A 100 GB snapshot costs ~$2.10/month

Cross-region copies:
  - Same storage cost in destination region
  - PLUS data transfer out: ~$0.02/GB (varies by region pair)

Aurora vs RDS comparison:
  - Aurora backup storage is cheaper per GB
  - Aurora does NOT have a separate "backup storage" metric
  - RDS charges $0.095/GB-month for snapshot storage beyond free tier
```

---

## 7. Backup Strategy Decision Framework

Use this framework when designing backup strategies for real workloads:

```
BACKUP STRATEGY DECISION TREE
================================

Step 1: What is the RPO (Recovery Point Objective)?
  < 5 minutes   -> PITR required, verify latest restorable time is current
  5-60 minutes  -> PITR sufficient, standard retention
  > 60 minutes  -> Daily snapshots may be enough

Step 2: What is the RTO (Recovery Time Objective)?
  < 5 minutes   -> Aurora Global Database (not covered here)
  5-30 minutes  -> PITR for small-medium clusters
  30-60 minutes -> PITR or snapshot restore
  > 60 minutes  -> Snapshot restore for any size

Step 3: Compliance retention requirement?
  <= 35 days    -> Automated backups cover it
  > 35 days     -> Add monthly manual snapshots (indefinite retention)
  Cross-border  -> Snapshots must stay in specific regions (GDPR, etc.)

Step 4: Geographic redundancy needed?
  Single region  -> Standard automated backups
  Multi-region   -> Weekly cross-region snapshot copies
  Real-time DR   -> Aurora Global Database

Step 5: Cost tolerance?
  Low    -> 7-day retention, no manual snapshots, no cross-region
  Medium -> 14-day retention, weekly manual snapshots
  High   -> 35-day retention, daily manual snapshots, cross-region copies
```

---

## 8. RTO and RPO - A Quick Reference

```
RTO and RPO on a Timeline
===========================

    Last backup          Failure occurs          Service restored
         |                    |                        |
         v                    v                        v
[--------RPO---------][------RTO-----------------------]
  ^                     ^                               ^
  |                     |                               |
Data you lose       Downtime starts              App is back online

RPO = Maximum acceptable data loss (measured in time)
RTO = Maximum acceptable downtime to restore service
```

### Typical RPO/RTO by Workload

```
WORKLOAD                        RPO             RTO
Internal tools                  24 hours        4 hours
SaaS product (standard)         5 minutes       30 minutes
SaaS product (enterprise SLA)   1 minute        15 minutes
Financial transactions          0 (zero loss)   5 minutes
Healthcare/regulatory           5 minutes       1 hour
```

---

## Key Takeaways

1. Aurora automated backups are continuous - no daily snapshot window, no performance impact
2. Manual snapshots survive cluster deletion - always take one before destructive operations
3. PITR creates a NEW cluster - it never modifies the original
4. Latest restorable time lags 2-5 minutes behind real-time
5. Cross-region copies protect against regional failures but add cost
6. Retention period = 35 days max for automated - use manual snapshots for longer compliance needs
7. Design your backup strategy around RPO and RTO, not around what tools are available
