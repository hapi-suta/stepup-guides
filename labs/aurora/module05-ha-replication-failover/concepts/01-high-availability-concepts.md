# High Availability Concepts
## Module 05 | DevOps DBA Training Track - Aurora PostgreSQL

Work through all sections before starting the BUILD labs. Each concept maps directly to a hands-on exercise.

---

## 5.1 RPO and RTO - The Two Numbers That Define Your HA Strategy

Before you design any high availability architecture, you must understand two numbers. Every HA decision you make comes back to these.

### RPO - Recovery Point Objective

RPO answers: "How much data can I afford to lose?"

It is measured in time. An RPO of 5 minutes means you accept losing up to 5 minutes of committed transactions after a failure.

```
Timeline of writes:

  10:00    10:05    10:10    10:15    10:20
    |        |        |        |        |
  [Write] [Write] [Write] [FAILURE]
                              ^
                     Last backup was at 10:10

  RPO = 5 minutes (data from 10:10 to 10:15 is lost)
```

Common RPO targets:

| RPO Target | What It Means | How You Achieve It |
|-----------|---------------|-------------------|
| 0 (zero) | No data loss ever | Synchronous replication (Multi-AZ) |
| < 1 second | Near-zero loss | Aurora Global Database |
| < 5 minutes | Minimal loss | Frequent automated backups + WAL archiving |
| < 1 hour | Acceptable loss | Hourly snapshots |
| < 24 hours | Large loss OK | Daily backups |

---

### RTO - Recovery Time Objective

RTO answers: "How long can the database be down?"

It is measured in time. An RTO of 2 minutes means your application can tolerate up to 2 minutes of database unavailability.

```
Timeline of an incident:

  10:15:00  Failure occurs
  10:15:05  CloudWatch detects failure
  10:15:10  Failover begins
  10:16:30  New primary is ready
  10:16:35  Application reconnects

  RTO = 1 minute 35 seconds (10:15:00 to 10:16:35)
```

Common RTO targets:

| RTO Target | What It Means | How You Achieve It |
|-----------|---------------|-------------------|
| < 30 seconds | Near-zero downtime | Aurora with failover tiers |
| < 2 minutes | Brief interruption | RDS Multi-AZ Instance |
| < 5 minutes | Short outage | Manual failover with scripts |
| < 1 hour | Planned recovery | Restore from snapshot |
| < 24 hours | Extended outage OK | Restore from backup in another region |

---

### How RPO and RTO Work Together

They are independent. You can have:
- RPO=0, RTO=30s (Aurora Multi-AZ - no data loss, fast recovery)
- RPO=1hr, RTO=5min (hourly backups with scripted restore)
- RPO=0, RTO=4hrs (synchronous replication but slow manual promotion)

The tighter your RPO and RTO, the more expensive your architecture.

```
Cost vs Recovery:

  $$$$ |                                    * Aurora Global DB
       |                              * Aurora Cluster
  $$$  |                        * RDS Multi-AZ
       |                  * RDS + Read Replica
  $$   |            * RDS Single-AZ + Backups
       |      * Manual snapshots
  $    | * No backups (hope for the best)
       +----+----+----+----+----+----+----+-->
            24h  4h   1h  30m  5m  30s  0s
                       <-- RTO (faster) -->
```

---

## 5.2 Multi-AZ Deployment Model

### What Is an Availability Zone?

An Availability Zone (AZ) is a physically separate data center within an AWS Region. Each AZ has independent power, cooling, and networking. A failure in one AZ - a power outage, a network cut, a fire - does not affect other AZs.

```
AWS Region: us-east-1

  +-------------------+  +-------------------+  +-------------------+
  | AZ: us-east-1a    |  | AZ: us-east-1b    |  | AZ: us-east-1c    |
  | [Data Center]     |  | [Data Center]     |  | [Data Center]     |
  | Independent power |  | Independent power |  | Independent power |
  | Independent net   |  | Independent net   |  | Independent net   |
  +-------------------+  +-------------------+  +-------------------+
         |                        |                        |
         +------------------------+------------------------+
                    Low-latency private network
                    (sub-millisecond between AZs)
```

---

### RDS Multi-AZ Instance (Original Model)

One primary instance. One standby instance in a different AZ. Synchronous replication over a dedicated network link. The standby is NOT readable - it exists only for failover.

```
                    [Your Application]
                           |
                     [DNS Endpoint]
                     (same hostname always)
                           |
           +---------------------------------+
           |                                 |
     [AZ us-east-1a]               [AZ us-east-1b]
     PRIMARY (r/w)   ---sync--->   STANDBY (no reads)
     EBS gp3 volume               EBS gp3 volume
```

**What happens during failover:**

1. AWS detects primary failure (network, host, storage, or manual trigger)
2. The standby is promoted to primary
3. DNS endpoint is updated to point to the new primary IP
4. DNS TTL expires (60-120 seconds)
5. Applications reconnect using the same hostname
6. The old primary becomes the new standby after recovery

**Key facts:**
- Failover time: 60-120 seconds typically
- RPO: 0 (synchronous replication - no data loss)
- The standby cannot serve reads
- Costs roughly 2x a single instance (you pay for two instances)
- Supported on all RDS engine types and instance classes

---

### Aurora Multi-AZ (Built-In)

Aurora handles availability differently. When you add Aurora replicas in different AZs, you get Multi-AZ protection automatically. There is no separate "enable Multi-AZ" toggle like RDS.

```
                    [Your Application]
                           |
                +----------+----------+
                |                     |
         [Writer Endpoint]    [Reader Endpoint]
                |                     |
     [AZ-1: Writer]    [AZ-2: Reader-1]    [AZ-3: Reader-2]
          \                |                   /
           +----------+----+-----------+------+
                      |
              [Aurora Shared Storage]
              [6 copies across 3 AZs]
```

**Key differences from RDS Multi-AZ:**
- Readers ARE accessible for read queries (not passive like RDS standby)
- Failover is faster: 20-35 seconds (vs 60-120 for RDS)
- DNS TTL is 5 seconds (vs 60 for RDS)
- Up to 15 replicas (vs 1 standby for RDS Multi-AZ Instance)
- Storage is shared - no per-instance EBS volumes

---

## 5.3 Aurora Failover Mechanics

### How Aurora Failover Works (The DNS Flip)

When the Aurora writer fails, the recovery process is:

1. Aurora detects the writer is unhealthy (health check every 5 seconds)
2. Aurora selects the reader with the highest failover priority (lowest tier number)
3. The selected reader is promoted to writer
4. The cluster endpoint DNS record is updated (TTL = 5 seconds)
5. The old writer is demoted to a reader after recovery
6. Applications reconnect to the same cluster endpoint hostname

```
Before failover:

  Cluster endpoint DNS --> 10.0.1.23 (Writer in AZ-1)
  Reader endpoint DNS  --> 10.0.2.45, 10.0.3.67 (Readers in AZ-2, AZ-3)


During failover (20-35 seconds):

  Writer (AZ-1) fails
  Aurora promotes Reader-1 (AZ-2, tier 0) to Writer
  DNS record updated: cluster endpoint --> 10.0.2.45


After failover:

  Cluster endpoint DNS --> 10.0.2.45 (new Writer, was Reader-1)
  Reader endpoint DNS  --> 10.0.3.67, 10.0.1.23 (Reader-2, old Writer now Reader)
```

**Why Aurora failover is faster than RDS:**

| Step | RDS Multi-AZ | Aurora |
|------|-------------|--------|
| Detect failure | 5-15 seconds | 5 seconds |
| Promote standby | 10-30 seconds | Near-instant (shared storage) |
| DNS update | 60-second TTL | 5-second TTL |
| Apply WAL backlog | Possible delay | No WAL - shared storage |
| **Total** | **60-120 seconds** | **20-35 seconds** |

The key reason Aurora is faster: replicas share the same storage layer. There is no WAL to stream, no data to copy, no backlog to apply. The reader just becomes the writer and starts accepting writes immediately.

---

### Failover Priority Tiers

Each Aurora replica has a failover priority from 0 (highest) to 15 (lowest). When the writer fails, Aurora promotes the replica with the lowest tier number.

```
Writer fails - which reader becomes the new writer?

Tier 0: Reader-A (db.r6g.xlarge, AZ-2)  <-- promoted FIRST
Tier 1: Reader-B (db.r6g.large, AZ-3)   <-- promoted if A is unavailable
Tier 2: Reader-C (db.r6g.4xlarge, AZ-1) <-- analytics reader, never promoted
                                              unless A and B both fail
```

If two replicas share the same tier, Aurora promotes the one with the larger instance class. If those are also equal, Aurora picks one arbitrarily.

**Best practice:** Set your preferred failover target to tier 0. Set your analytics or dedicated readers to tier 15 so they are never promoted under normal circumstances.

---

## 5.4 How Aurora Replication Differs from Streaming Replication

### Traditional PostgreSQL Streaming Replication (Used by RDS)

In standard PostgreSQL and RDS, the primary sends WAL (Write-Ahead Log) records to replicas over a network connection. Each replica must receive, write, and apply these WAL records independently.

```
RDS Read Replica (streaming replication):

  [Primary]
      |
      |-- WAL stream (async) --> [Replica 1] applies WAL to its own EBS volume
      |
      |-- WAL stream (async) --> [Replica 2] applies WAL to its own EBS volume
```

Each replica has its own complete copy of the data on its own EBS volume. If the primary writes 1 GB of data, each replica must receive and apply that same 1 GB.

**Limitations:**
- Lag increases under heavy writes (replicas fall behind applying WAL)
- Each replica needs its own full storage (expensive at scale)
- Maximum 5 replicas per primary
- Cross-region replicas have higher lag (WAL travels over the internet)

---

### Aurora Replication (Shared Storage)

Aurora does NOT use streaming replication. All instances in a cluster share the same distributed storage layer. The writer sends only cache invalidation messages to readers - not WAL.

```
Aurora replication:

  [Writer]     [Reader-1]     [Reader-2]
      \             |              /
       +------------+-------------+
                    |
        [Aurora Shared Storage Layer]
        [6 copies across 3 AZs]
        [Distributed, log-structured]
```

When the writer commits a transaction:
1. The writer sends redo log records to the storage layer
2. The storage layer applies the redo and stores the data
3. The writer sends a "cache invalidation" message to all readers
4. Readers re-read the changed pages from shared storage

**Readers never apply WAL.** They just read the latest data from the same storage. This is why Aurora replica lag is typically under 20 milliseconds.

---

### Side-by-Side Comparison

| Feature | RDS Streaming Replication | Aurora Shared Storage |
|---------|--------------------------|----------------------|
| Data copies | Each replica has its own full copy | One shared storage layer |
| Replication method | WAL stream over network | Cache invalidation messages |
| Replica lag | 100ms - seconds | Typically < 20ms |
| Max replicas | 5 | 15 |
| Failover speed | 60-120 seconds | 20-35 seconds |
| Storage cost per replica | Full EBS volume per replica | No additional storage cost |
| `pg_stat_replication` | Shows active WAL connections | Shows no rows (no WAL streaming) |
| Cross-region | WAL streaming (higher lag) | Global Database (storage-level) |

---

### The 6-Copy, 3-AZ Storage Model

Aurora stores every piece of data across 6 storage nodes in 3 Availability Zones (2 nodes per AZ).

```
AZ us-east-1a:  [Node 1]  [Node 2]
AZ us-east-1b:  [Node 3]  [Node 4]
AZ us-east-1c:  [Node 5]  [Node 6]
```

Aurora uses a quorum system for reads and writes:
- **Write quorum:** 4 of 6 nodes must acknowledge a write
- **Read quorum:** 3 of 6 nodes must respond for a read

This means:
- Aurora can lose an entire AZ (2 nodes) and still read AND write
- Aurora can lose 3 nodes (across AZs) and still read (but not write)
- Only losing 4+ nodes causes a full outage (extremely unlikely)

You cannot change this. The 6-copy model is built into Aurora and cannot be reduced or increased. You pay for the storage once - not 6 times.

---

## 5.5 Aurora Endpoints - The Four Types

Aurora provides four endpoint types. Understanding them is critical for building resilient applications.

### 1. Cluster Endpoint (Writer Endpoint)

Always points to the current writer instance. Use this for ALL writes and for reads that must see the latest data.

```
Format:  devops-lab-cluster.cluster-[id].us-east-1.rds.amazonaws.com
```

During failover, the DNS record updates within 5 seconds. Applications that respect the short TTL reconnect to the new writer automatically.

### 2. Reader Endpoint

Load balances connections across all reader instances using DNS round-robin. Use for read-only queries.

```
Format:  devops-lab-cluster.cluster-ro-[id].us-east-1.rds.amazonaws.com
```

If no readers exist, the reader endpoint falls back to the writer. Never design your application to write to the reader endpoint - it will break when you add readers.

### 3. Instance Endpoint

Points to one specific instance by its identifier. Use only for DBA diagnostics - never for application connections.

```
Format:  devops-lab-writer.cxyz1234abcd.us-east-1.rds.amazonaws.com
```

After failover, the instance endpoint still resolves to the same instance - which may now be a reader, not the writer. Applications using instance endpoints will silently break after failover.

### 4. Custom Endpoint

You create this yourself to route specific workloads to specific instances. Use for analytics, reporting, or workload isolation.

```
Format:  my-analytics.cluster-custom-[id].us-east-1.rds.amazonaws.com
```

Example architecture with custom endpoints:

```
[OLTP App]     --> [Writer Endpoint]     --> [Writer instance]
[API reads]    --> [Reader Endpoint]     --> [Reader-1, Reader-2]
[BI Dashboard] --> [Custom Endpoint]     --> [Reader-3 (large instance)]
```

---

## 5.6 Choosing the Right Architecture

Use this decision tree when designing your Aurora HA strategy:

```
What do you need?
      |
      +-- Survive a single AZ failure?
      |        |
      |        +-- Budget-sensitive --> RDS Multi-AZ Instance
      |        +-- Need readable standby --> Aurora with 1+ reader
      |
      +-- Read scaling (high read traffic)?
      |        |
      |        +-- Same region --> Aurora Replicas (up to 15)
      |        +-- Cross-region --> Aurora Global Database
      |
      +-- Failover under 30 seconds?
      |        |
      |        +-- Yes --> Aurora (not RDS)
      |
      +-- Cross-region disaster recovery?
      |        |
      |        +-- Yes --> Aurora Global Database
      |
      +-- Variable/unpredictable traffic?
               |
               +-- Yes --> Aurora Serverless v2
```

---

## Key Terms

| Term | Definition |
|------|-----------|
| RPO | Recovery Point Objective - maximum acceptable data loss measured in time |
| RTO | Recovery Time Objective - maximum acceptable downtime measured in time |
| Multi-AZ | Deploying standby instances in separate Availability Zones for failover |
| Failover | Automatic promotion of a standby/replica to become the new primary |
| DNS flip | Updating the DNS record to point to the new primary after failover |
| Quorum | Minimum number of storage nodes that must agree for a read or write to succeed |
| Replica lag | Time difference between the primary committing data and the replica seeing it |
| WAL | Write-Ahead Log - records every change before it is applied to data files |
| Cluster endpoint | DNS name that always points to the current Aurora writer |
| Reader endpoint | DNS name that load-balances across Aurora reader instances |
