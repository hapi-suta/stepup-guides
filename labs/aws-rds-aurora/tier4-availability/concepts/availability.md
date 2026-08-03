# Availability and Replication - Concepts
## Tier 4 | AWS RDS and Aurora PostgreSQL

Work through all seven sections before starting the BUILD labs. Each concept maps directly to a lab.

---

## T4.1 RDS Multi-AZ: Instance vs DB Cluster

### What Is Multi-AZ?

Multi-AZ means AWS keeps a standby copy of your database in a second Availability Zone. If the primary fails, AWS automatically promotes the standby. Your application reconnects using the same DNS endpoint - the IP changes, but the hostname stays the same.

> **Concept:** An Availability Zone (AZ) is a physically separate data center within an AWS Region. Power, networking, and cooling are independent. A failure in one AZ does not affect another.

---

### Multi-AZ Instance (Original Model)

One primary instance. One standby instance. Synchronous replication over a dedicated network link. The standby is NOT readable - it only exists for failover.

```
                        [Your Application]
                               |
                         [DNS Endpoint]
                               |
               +---------------------------------+
               |                                 |
         [AZ us-east-1a]               [AZ us-east-1b]
         PRIMARY (r/w)   ---sync--->   STANDBY (no reads)
         EBS gp3 volume               EBS gp3 volume
```

Failover steps:
1. AWS detects primary failure (network, host, storage)
2. DNS TTL expires (60-120 seconds)
3. Standby is promoted to primary
4. Old primary becomes new standby after recovery
5. Total downtime: 60-120 seconds typically

---

### Multi-AZ DB Cluster (Newer Model, 2022+)

One writer instance. Two reader instances in different AZs. Uses a shared cluster volume (similar to Aurora). Readers ARE accessible for reads. Failover is faster because a reader just needs to be promoted.

```
                        [Your Application]
                               |
                    +----------+----------+
                    |                     |
             [Writer Endpoint]    [Reader Endpoint]
                    |                     |
         [AZ-1: Writer]    [AZ-2: Reader1]    [AZ-3: Reader2]
              |                  |                   |
              +------ Shared Cluster Volume ----------+
                        (3 AZs, replicated)
```

Failover steps:
1. AWS detects writer failure
2. One reader is promoted to writer
3. DNS updates
4. Total downtime: typically under 35 seconds

---

### Key Differences

| Feature | Multi-AZ Instance | Multi-AZ DB Cluster |
|---------|-------------------|---------------------|
| Standby readable? | No | Yes |
| Number of standbys | 1 | 2 |
| Failover time | 60-120 sec | < 35 sec |
| Storage | Per-instance EBS | Shared cluster volume |
| Engines | All RDS engines | MySQL, PostgreSQL only |
| Cost | ~2x single instance | ~3x single instance |

---

## T4.2 RDS Read Replicas

### What Are Read Replicas?

A read replica is a separate RDS instance that receives changes from the primary using PostgreSQL's built-in streaming replication. It is readable. The primary sends WAL (Write-Ahead Log) records to the replica continuously.

> **Concept:** WAL (Write-Ahead Log) is a file that records every change made to the database before it is applied to the actual data files. PostgreSQL uses WAL for crash recovery and replication.

```
     [Primary RDS]
          |
          |--- WAL stream (async) --->  [Replica 1: same region]
          |
          |--- WAL stream (async) --->  [Replica 2: different region]
          |
          |--- WAL stream (async) --->  [Replica 3: same region]
```

---

### Replication Lag

Because the replication is asynchronous, the replica can fall behind the primary. This is called replica lag.

```
Time --->

Primary:  [Write A] [Write B] [Write C] [Write D]
                                               ^-- NOW

Replica:  [Write A] [Write B]
                           ^-- Replica is HERE (lag = time of C + D)
```

You measure lag with:
```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replica_lag;
```

Or in CloudWatch: `ReplicaLag` metric (in seconds).

---

### Cross-Region Read Replicas

You can create a replica in a completely different AWS Region. The WAL stream travels over the internet (encrypted). Cross-region replicas have higher lag than same-region replicas because of network distance.

Use cases:
- Disaster recovery in another region
- Serve reads closer to users in that region
- Data residency requirements

---

### Promoting a Replica

Promotion makes the replica a standalone read-write database. This is a one-way, destructive operation:
- The replica stops receiving WAL from the primary
- It becomes an independent database
- You cannot re-attach it to the primary

Use promotion for:
- Disaster recovery (primary is gone)
- Migrating to a different region
- Splitting a database into two independent databases

```
Before:  [Primary] ---WAL---> [Replica]
After:   [Primary]            [Promoted DB] (now independent)
```

---

## T4.3 Aurora Storage Architecture

### The Fundamental Difference

RDS uses Amazon EBS volumes attached to EC2 instances. Each instance has its own volume. Aurora does not work this way.

Aurora uses a distributed, log-structured storage system that is shared across all instances in the cluster. The storage is not attached to any one instance.

```
RDS (EBS model):
  [Instance 1]      [Instance 2]
       |                  |
  [EBS Vol 1]        [EBS Vol 2]
  (separate)         (separate copy)

Aurora (shared storage model):
  [Writer]    [Reader 1]    [Reader 2]
       \           |           /
        +----------+-----------+
                   |
        [Aurora Storage Layer]
        [Distributed across 6 storage nodes]
        [Spanning 3 Availability Zones]
        [2 copies per AZ]
```

---

### 6 Copies Across 3 AZs

Aurora writes every data block to 6 storage nodes. Two nodes are in each of 3 AZs.

```
AZ-1: [Node 1] [Node 2]
AZ-2: [Node 3] [Node 4]
AZ-3: [Node 5] [Node 6]
```

Aurora can:
- Lose 1 AZ entirely (2 nodes gone) and still READ and WRITE
- Lose 2 nodes in different AZs and still READ and WRITE
- Lose 3 nodes and still READ (but not write)

This is a quorum system:
- Write quorum: 4 of 6 nodes must acknowledge
- Read quorum: 3 of 6 nodes must respond

---

### Log-Structured Storage

Aurora does not write full data pages to storage. It only writes log records (redo log entries). The storage layer applies the redo log to reconstruct pages on demand. This is called "redo offload."

Traditional RDS/PostgreSQL write path:
```
[Write] --> WAL file --> Buffer --> Data Page on disk
```

Aurora write path:
```
[Write] --> Redo log record --> Aurora storage (applies redo to reconstruct pages)
```

Benefits:
- The database instance does less I/O work
- Writes are faster because only log records go over the network
- No checkpoint storms (no need to flush dirty pages periodically)
- Crash recovery is near-instant (no redo log replay needed on the instance)

---

### Storage Auto-Scaling

Aurora storage grows automatically in 10 GB increments. You never provision storage size. There is no shrinking - storage only grows. You pay for what you use.

---

## T4.4 Aurora Replicas, Reader Endpoint, Failover Tiers

### Aurora Replicas vs RDS Read Replicas

| Feature | RDS Read Replica | Aurora Replica |
|---------|-----------------|----------------|
| Storage | Separate EBS | Shared Aurora storage |
| Replication lag | Milliseconds to seconds | Typically < 100ms |
| Failover target? | Yes (after promote) | Yes (automatic, no promote needed) |
| Number allowed | 5 | Up to 15 |
| Cross-region? | Yes | Via Global Database only |

Because Aurora replicas share the same storage, they do not need to receive WAL and apply it. They just need to be told "a change happened at this LSN" and they read the latest data from the shared storage.

---

### Reader Endpoint

Aurora provides a single reader endpoint DNS name that load balances connections across all available replicas.

```
[App reads] --> [reader.cluster-xxxx.us-east-1.rds.amazonaws.com]
                         |
              +----------+----------+
              |          |          |
          [Replica 1] [Replica 2] [Replica 3]
```

The load balancing is done by DNS round-robin. Each connection gets a different replica. Existing connections are not moved.

---

### Failover Tiers and Priority

Each Aurora replica has a failover priority tier from 0 (highest priority) to 15 (lowest). When the writer fails, Aurora promotes the replica with the lowest tier number.

```
Writer fails:

Tier 0: Replica A  <-- promoted first
Tier 1: Replica B
Tier 2: Replica C  <-- promoted last (if A and B unavailable)
```

If two replicas have the same tier, Aurora promotes the one with the largest instance size. If size is also the same, Aurora chooses arbitrarily.

Use tiers to ensure your best-spec replica becomes writer during failover.

---

## T4.5 Aurora Endpoints Deep Dive

Aurora provides four types of endpoints:

### 1. Cluster Endpoint (Writer Endpoint)

Points to the current writer instance. Always use this for writes.

```
Format: [cluster-name].cluster-[id].[region].rds.amazonaws.com
Example: mydb.cluster-abc123.us-east-1.rds.amazonaws.com
```

During failover, this DNS name is updated to point to the new writer. TTL is 5 seconds for Aurora endpoints (faster than RDS Multi-AZ).

---

### 2. Reader Endpoint

Points to the reader load balancer. Use for read-only queries.

```
Format: [cluster-name].cluster-ro-[id].[region].rds.amazonaws.com
Example: mydb.cluster-ro-abc123.us-east-1.rds.amazonaws.com
```

If there are no replicas, the reader endpoint falls back to the writer. Never use the reader endpoint for writes even if it works - it will break when replicas exist.

---

### 3. Instance Endpoint

Points to a specific instance by ID. Use only for diagnostic work or when you need to target one specific instance.

```
Format: [instance-name].[id].[region].rds.amazonaws.com
Example: mydb-instance-1.abc123.us-east-1.rds.amazonaws.com
```

---

### 4. Custom Endpoint

You create this yourself. You choose which instances to include. Use for routing specific workloads to specific instances.

```
Format: [custom-name].cluster-custom-[id].[region].rds.amazonaws.com
```

Example use case - Analytics workload:

```
[OLTP App]  --> [Writer Endpoint]   --> [Writer]
[BI Tool]   --> [Custom Endpoint]   --> [Large replica r5.4xlarge]
[API reads] --> [Reader Endpoint]   --> [Small replicas r5.large x3]
```

---

### Endpoint Behavior During Failover

```
Normal:
  Cluster endpoint --> Writer (AZ-1)
  Reader endpoint  --> Replica-1 (AZ-2), Replica-2 (AZ-3)

Failover triggered:
  Old writer (AZ-1) fails
  Replica-1 (AZ-2) is promoted to writer (Tier 0)

After failover:
  Cluster endpoint --> Replica-1 (now writer, AZ-2)
  Reader endpoint  --> Replica-2 (AZ-3) [only one reader now]
  Custom endpoint  --> depends on configuration
```

Custom endpoints that included the old writer may break during failover if you do not manage membership carefully.

---

## T4.6 Aurora Global Database

### What Is a Global Database?

A Global Database spans multiple AWS Regions. One region is the primary. Other regions are secondaries. Data is replicated from primary to secondary regions using Aurora's storage-level replication.

```
Region: us-east-1 (PRIMARY)
  [Writer]  [Reader 1]  [Reader 2]
       \         |          /
        +--------+----------+
                 |
        [Aurora Storage]
                 |
                 | Storage-level replication
                 | (sub-second lag, typically < 1 second)
                 v
Region: eu-west-1 (SECONDARY)
  [Reader]
       |
  [Aurora Storage - read-only copy]
```

---

### How Replication Works

Global Database replication is done at the storage layer, not the database layer. The storage nodes in the secondary region receive redo log records directly. This means:

- The secondary database instances do not need to apply WAL
- Replication lag is typically under 1 second
- The secondary can have up to 16 reader instances

---

### Managed Planned Failover

When you want to switch which region is primary (for planned maintenance or region migration), you use a managed failover:

1. Aurora replication catches up to zero lag
2. Primary region is demoted to secondary
3. Secondary region is promoted to primary
4. DNS endpoints are updated
5. Applications reconnect

This is non-destructive. No data loss. The old primary becomes a secondary.

---

### Unplanned Failover (Region Failure)

If the primary region becomes unavailable:

1. You manually initiate "Detach and promote" on the secondary cluster
2. The secondary becomes a standalone read-write cluster
3. The old primary region is isolated (no automatic recovery)
4. When the old primary recovers, you must re-attach it as a secondary

There is no automatic unplanned failover in Global Databases. You must trigger it manually.

---

### Write Forwarding

Normally, reads go to the secondary and writes must go to the primary region. Write forwarding allows applications in the secondary region to send writes to the secondary endpoint - Aurora forwards them to the primary region automatically.

```
Without write forwarding:
  [App in eu-west-1] --writes--> [primary endpoint in us-east-1] (high latency)

With write forwarding:
  [App in eu-west-1] --writes--> [secondary endpoint in eu-west-1]
                                         |
                                   [Aurora forwards] --> [primary in us-east-1]
```

Write forwarding adds latency (the write still goes to us-east-1). It simplifies application code because the app does not need to know the primary region's endpoint.

---

## T4.7 Aurora Serverless v2

### What Is Serverless v2?

Aurora Serverless v2 is an auto-scaling capacity mode for Aurora. Instead of choosing an instance class (like db.r6g.large), you set a minimum and maximum capacity range in ACUs (Aurora Capacity Units).

> **Concept:** An ACU (Aurora Capacity Unit) is approximately 2 GB of RAM plus proportional CPU and network. 1 ACU = ~2 GB RAM. A db.r6g.large has ~16 GB RAM = 8 ACUs equivalent.

---

### Scaling Behavior

Serverless v2 scales up and down in increments of 0.5 ACU. Scaling happens in seconds, not minutes.

```
Traffic pattern:

Time:    00:00   06:00   09:00   12:00   18:00   22:00
Load:    low     medium  high    peak    medium  low

ACU:
 16 |                        ####
 12 |                   #####    ####
  8 |          ########              #####
  4 | #########                           ########
  1 |
      --------------------------------------------------> time
```

Scaling is triggered by CPU usage, connections, or memory pressure.

---

### Scale to Zero

Serverless v2 does NOT scale to zero. Minimum is 0.5 ACU.

> Note: The original Aurora Serverless v1 could scale to zero. Serverless v2 cannot. If you need scale-to-zero, you must use Serverless v1 (which is being deprecated) or accept the 0.5 ACU minimum cost.

---

### Mixed Clusters

You can combine provisioned and Serverless v2 instances in the same Aurora cluster. Common patterns:

```
Pattern 1: Serverless writer + serverless readers
  [Serverless v2 writer]  -->  [Serverless v2 reader 1]
                               [Serverless v2 reader 2]

Pattern 2: Provisioned writer + serverless readers
  [db.r6g.2xlarge writer]  -->  [Serverless v2 reader 1]
  (stable, predictable)         [Serverless v2 reader 2]
  (for production OLTP)         (auto-scale for variable reads)

Pattern 3: Serverless writer + provisioned analytics reader
  [Serverless v2 writer]  -->  [db.r6g.4xlarge reader]
                               (dedicated large instance for BI queries)
```

---

### Cost Comparison

Rough comparison for us-east-1 (prices change - always check AWS pricing page):

| Option | Spec | Approx $/hr |
|--------|------|-------------|
| db.t3.medium | 2 vCPU, 4 GB | $0.068 |
| db.r6g.large | 2 vCPU, 16 GB | $0.24 |
| Serverless v2 at 0.5 ACU | ~1 GB | $0.06 |
| Serverless v2 at 4 ACU | ~8 GB | $0.48 |
| Serverless v2 at 16 ACU | ~32 GB | $1.92 |

Serverless v2 is cost-effective for variable workloads. For steady predictable load, provisioned instances are cheaper.

---

## Summary: Choosing the Right Architecture

```
Your requirements
      |
      +-- Need HA in same region?
      |        |
      |        +-- Simple / budget --> Multi-AZ Instance
      |        +-- Want readable standby --> Multi-AZ DB Cluster or Aurora
      |
      +-- Need read scaling?
      |        |
      |        +-- Same region --> RDS Read Replicas or Aurora Replicas
      |        +-- Different region --> Cross-region replica or Aurora Global DB
      |
      +-- Need sub-second failover?
      |        |
      |        +-- Yes --> Aurora (not RDS)
      |
      +-- Need cross-region HA?
      |        |
      |        +-- Yes --> Aurora Global Database
      |
      +-- Need variable/unpredictable load?
               |
               +-- Yes --> Aurora Serverless v2
```
