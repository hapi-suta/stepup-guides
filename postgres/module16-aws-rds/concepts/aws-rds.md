# Concepts - AWS RDS and Aurora PostgreSQL

## Overview

Amazon RDS (Relational Database Service) is a managed database service that handles provisioning, patching, backups, and replication. Aurora is Amazon's cloud-native database engine compatible with PostgreSQL, offering higher performance and availability. This document covers the core concepts you need as a DBA.

---

## RDS vs Aurora Architecture

### Standard RDS PostgreSQL

Standard RDS runs PostgreSQL on an EC2 instance with an attached EBS volume:

```
┌──────────────────────┐
│     RDS Instance     │
│  (EC2 + PostgreSQL)  │
│                      │
│  ┌────────────────┐  │
│  │   EBS Volume   │  │
│  │  (gp3 / io2)   │  │
│  └────────────────┘  │
└──────────────────────┘
```

Key characteristics:
- Single EBS volume stores all data
- Storage is tied to the instance (not shared)
- Read replicas use PostgreSQL streaming replication (WAL shipping)
- Max storage: 64 TB
- Storage type affects IOPS directly

### Aurora PostgreSQL

Aurora separates compute from storage:

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Writer  │  │ Reader 1 │  │ Reader 2 │
│ Instance │  │ Instance │  │ Instance │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     └─────────────┼─────────────┘
                   │
     ┌─────────────┴─────────────┐
     │   Shared Distributed      │
     │   Storage Volume          │
     │   (6 copies across 3 AZs) │
     └───────────────────────────┘
```

Key characteristics:
- Storage is shared across all instances
- Data is replicated 6 ways across 3 AZs automatically
- Readers do not need streaming replication - they read from shared storage
- Max storage: 128 TB (auto-scaling)
- Storage grows automatically in 10 GB increments
- Replication lag is typically under 20ms (vs seconds for standard RDS)

### When to use which

| Use Case | Choose |
|----------|--------|
| Small databases under 100 GB | Standard RDS (cheaper) |
| Dev/test environments | Standard RDS (cheaper) |
| High-availability production | Aurora |
| Read-heavy workloads (5+ replicas) | Aurora |
| Sub-second replication lag required | Aurora |
| Backtrack (time travel) needed | Aurora |
| Cross-region active-active | Aurora Global Database |

---

## Multi-AZ vs Read Replicas

These are two different features that are often confused.

### Multi-AZ Deployment

Purpose: **High availability** (automatic failover)

```
AZ-a                    AZ-b
┌────────────┐         ┌────────────┐
│  Primary   │ ──sync──│  Standby   │
│  (active)  │  repli  │ (passive)  │
│            │  cation │            │
└────────────┘         └────────────┘
```

- Synchronous replication (no data loss)
- Standby is NOT readable (pure standby)
- Automatic failover in 60-120 seconds (standard RDS) or under 30 seconds (Aurora)
- Same endpoint before and after failover
- One standby only (standard RDS) or multiple (Aurora)
- You pay for the standby instance

### Read Replicas

Purpose: **Read scaling** (distribute read queries)

```
┌────────────┐
│  Primary   │──async──┌────────────┐
│  (writes)  │  repli  │  Replica 1 │ (reads)
│            │  cation │            │
└────────────┘    │    └────────────┘
                  │
                  └────┌────────────┐
                       │  Replica 2 │ (reads)
                       │            │
                       └────────────┘
```

- Asynchronous replication (slight lag)
- Replicas ARE readable
- No automatic failover (manual promotion only)
- Each replica has its own endpoint
- Can be in same region or cross-region
- Up to 5 replicas (standard RDS) or 15 (Aurora)

### Combining Both

You can have Multi-AZ AND read replicas:

```
AZ-a                    AZ-b
┌────────────┐         ┌────────────┐
│  Primary   │ ──sync──│  Standby   │
│  (active)  │         │ (failover) │
└─────┬──────┘         └────────────┘
      │ async
      └──────────────── ┌────────────┐
                        │  Replica   │ (reads)
                        └────────────┘
```

---

## Parameter Groups

### Standard RDS Parameter Groups

One type only: DB parameter group. Contains all PostgreSQL parameters.

### Aurora Parameter Groups

Two types:

| Type | Applies To | Example Parameters |
|------|-----------|-------------------|
| Cluster parameter group | All instances in the cluster | shared_preload_libraries, log_statement |
| DB parameter group | Individual instances | work_mem (can override per reader) |

Cluster parameters override instance parameters for most settings. Use cluster parameter groups for settings that should be consistent across all instances. Use instance parameter groups only when a reader needs different settings than the writer.

### Static vs Dynamic Parameters

| Type | Reboot Required | Examples |
|------|----------------|---------|
| Dynamic | No - applies immediately | work_mem, log_statement, log_min_duration_statement |
| Static | Yes - needs reboot | shared_buffers, shared_preload_libraries, max_connections |

Always check `ApplyType` before modifying a parameter. Rebooting a production instance during business hours is not ideal.

---

## Backup Architecture

### Automated Backups

RDS takes daily snapshots and continuously captures transaction logs.

```
Day 1        Day 2        Day 3        Day 4
  │            │            │            │
  ▼            ▼            ▼            ▼
[Snap]       [Snap]       [Snap]       [Snap]
  └──WAL──────WAL──────WAL──────WAL──────┘
              (continuous transaction log backup)
```

- Daily snapshot during your configured backup window
- Transaction logs captured every 5 minutes
- Retained for 0-35 days (configurable, default 7)
- Deleted when the instance is deleted (unless you keep final snapshot)

### Manual Snapshots

- Created by you on demand
- Kept until you explicitly delete them
- Survive instance deletion
- Can be copied cross-region
- Can be shared with other AWS accounts

### PITR (Point-in-Time Recovery)

PITR combines the daily snapshot with transaction logs to reconstruct the database at any second.

```
Daily Snap (3:00 AM)         Restore Point (2:15 PM)
     │                            │
     ▼                            ▼
   [Snap] ──WAL──WAL──WAL──WAL──[RESTORE HERE]──WAL──WAL
```

Process:
1. RDS finds the most recent snapshot before your target time
2. Replays transaction logs from that snapshot to your target time
3. Creates a NEW instance at that exact point
4. The new instance gets a new endpoint

**Important**: PITR creates a new instance. It never modifies the original.

### Aurora Backtrack

Aurora has an additional option: backtrack. Unlike PITR, backtrack rewinds the EXISTING cluster in place.

| Feature | PITR | Backtrack |
|---------|------|-----------|
| Creates new instance | Yes | No |
| Speed | 10-30 minutes | Seconds |
| Cost | Instance running costs | Small per-change fee |
| Availability during operation | Original stays up | Brief outage (under 1 min) |
| Data affected | Only new instance | Entire cluster rewound |

---

## Performance Insights Architecture

Performance Insights collects three layers of data:

```
Layer 1: DB Load (Average Active Sessions)
  └── Layer 2: Wait Events (what sessions are waiting on)
       └── Layer 3: Top SQL (which queries are causing the waits)
```

### Average Active Sessions (AAS)

AAS is the primary metric. It measures how many sessions are actively doing work at any given time.

- AAS = 1.0 means on average, 1 session is active
- AAS = number of vCPUs means the database is fully utilizing compute
- AAS > number of vCPUs means sessions are queuing (overloaded)

### Wait Events

Every active session is either running on CPU or waiting for something:

| Category | Wait Events | Meaning |
|----------|------------|---------|
| CPU | CPU | Query executing on CPU (healthy) |
| IO | DataFileRead, WALWrite | Disk I/O (may need more RAM or faster storage) |
| Lock | transactionid, relation | Row or table locks (application contention) |
| LWLock | BufferMapping, WALWrite | Internal PostgreSQL locks (tuning needed) |
| Client | ClientRead, ClientWrite | Waiting for the application (network or app issue) |

### Free vs Paid Tier

| Feature | Free | Paid |
|---------|------|------|
| Retention | 7 days | 2 years (731 days) |
| Cost | $0 | ~$0.07/vCPU/month |

---

## IAM Authentication Flow

Standard authentication uses a password stored in the database. IAM authentication replaces the password with a temporary token.

```
1. Application requests token from AWS STS
   App ──────────────────────────> AWS IAM
                                     │
2. AWS returns signed token           │
   App <──────────────────────────────┘
       (token valid for 15 minutes)

3. Application connects to RDS using token as password
   App ─── psql host=... password=TOKEN ──> RDS
                                              │
4. RDS validates token with IAM                │
   RDS ──────────────────────────────> AWS IAM
                                         │
5. IAM confirms: this user has rds-db:connect
   RDS <─────────────────────────────────┘
       (connection established)
```

Requirements for IAM auth:
1. Instance has IAM auth enabled
2. Database user has `rds_iam` role granted
3. IAM policy allows `rds-db:connect` for the specific instance and user
4. Connection uses SSL (required)
5. Token is under 15 minutes old

Advantages:
- No passwords to manage or rotate
- IAM policies control access centrally
- CloudTrail logs every token generation
- Token expiry limits blast radius of credential theft

---

## Cost Optimization Tips

### Right-sizing Instances

Check actual CPU and memory usage before choosing an instance class:

| If you see... | Consider... |
|---------------|-------------|
| CPU always under 20% | Downsize the instance class |
| CPU always above 70% | Upsize or add read replicas |
| Freeable memory always above 75% | Downsize the instance class |
| ReplicaLag growing | Upsize the replica |

### Storage Cost Reduction

- Use gp3 instead of io2 (gp3 baseline IOPS are often sufficient)
- Enable storage autoscaling instead of over-provisioning
- Delete old manual snapshots
- Set backup retention to the minimum needed (not always 35 days)

### Reserved Instances

| Payment | Discount |
|---------|----------|
| No upfront (1 year) | ~30% |
| Partial upfront (1 year) | ~40% |
| All upfront (1 year) | ~42% |
| All upfront (3 year) | ~55% |

Reserve instances you know will run for 1+ years.

### Aurora Serverless v2

For variable workloads, Aurora Serverless v2 scales compute automatically:
- Minimum: 0.5 ACU (approximately 1 GB RAM)
- Maximum: 128 ACU (approximately 256 GB RAM)
- Scales in 0.5 ACU increments
- Pay per ACU-hour consumed

Good for: dev environments, variable traffic, overnight low usage.

---

## Common Migration Patterns

### On-Prem to RDS

| Method | Downtime | Data Size | Complexity |
|--------|----------|-----------|------------|
| pg_dump/pg_restore | Hours (full dump) | Under 100 GB | Low |
| AWS DMS | Minutes (CDC) | Any size | Medium |
| Logical replication | Seconds (cutover) | Any size | High |

### Typical Migration Steps

1. **Assessment**: Run AWS Schema Conversion Tool (SCT) to identify incompatibilities
2. **Baseline**: Create RDS instance with matching version
3. **Initial Load**: Use pg_dump or DMS full load
4. **Ongoing Replication**: DMS CDC (Change Data Capture) or logical replication
5. **Validation**: Compare row counts, checksums, and query results
6. **Cutover**: Stop writes to source, wait for replication to catch up, switch application

### Things That Change on RDS

| Feature | On-Prem | RDS |
|---------|---------|-----|
| Superuser access | Full | No (rds_superuser role instead) |
| File system access | Full | None (no SSH) |
| Extensions | Install any | Only supported list |
| pg_hba.conf | Direct edit | Use parameter groups |
| WAL archiving | Custom scripts | Automated by RDS |
| Replication setup | Manual | Managed (read replicas) |
| OS patching | Your responsibility | Managed by AWS |

---

## Key Things a DBA Should Know

1. **You do not have superuser on RDS.** You have `rds_superuser`, which is powerful but cannot access the file system or modify pg_hba.conf directly.

2. **You cannot SSH into RDS.** All administration is through SQL, AWS CLI, or the console.

3. **Endpoint DNS names do not change after failover.** The IP behind them changes, but the hostname stays the same. This is why you should always connect by hostname, never by IP.

4. **Storage can only go up.** You cannot shrink an RDS volume. Plan accordingly.

5. **Restores always create new instances.** PITR and snapshot restores never overwrite the original. Budget time for the restore and endpoint update.

6. **Parameter group changes may need a reboot.** Check ApplyType before modifying parameters in production.

7. **Aurora replicas are much faster than RDS replicas.** Aurora replication is at the storage level (milliseconds). Standard RDS replication is at the WAL level (seconds).

8. **Automated backups are deleted when you delete the instance** (unless you configure retention). Manual snapshots persist.

9. **The free tier covers db.t3.micro for 12 months.** After that, you pay standard rates.

10. **CloudWatch basic metrics are free.** Enhanced Monitoring and Performance Insights (paid tier) cost extra but are worth it for production.
