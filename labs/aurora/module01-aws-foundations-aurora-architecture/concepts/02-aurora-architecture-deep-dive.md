# Aurora Architecture Deep Dive

## Module 01 - Concept 02 | DevOps DBA Training Track

---

## What You Will Learn

By the end of this concept doc, you will understand:

- How Aurora's architecture differs from traditional PostgreSQL
- How the 6-copy, 3-AZ storage model keeps your data safe
- The difference between Writer and Reader instances
- What endpoints are and which one to use for different workloads
- How Aurora storage works - auto-growing, no pre-allocation, 128 TB max
- The real-world performance story (marketing claims vs reality)
- When to choose Aurora Serverless v2 vs Provisioned instances

---

## Traditional PostgreSQL vs Aurora PostgreSQL

To understand why Aurora exists, you need to understand the problem it solves.

### How Traditional PostgreSQL Works

In a traditional PostgreSQL setup (on EC2 or on-premises), every instance manages its own
storage. When the primary writes data, it:

1. Writes to its local disk (WAL - Write-Ahead Log)
2. Ships the WAL to the standby over the network
3. The standby replays the WAL and writes to its own local disk

```
Traditional PostgreSQL Replication

  +------------------+       WAL stream        +------------------+
  |    PRIMARY       | ---------------------->  |    STANDBY       |
  | +------+------+  |       (network)          | +------+------+  |
  | | CPU  | RAM  |  |                          | | CPU  | RAM  |  |
  | +------+------+  |                          | +------+------+  |
  | | Local Storage|  |                          | | Local Storage|  |
  | |  (EBS/Disk)  |  |                          | |  (EBS/Disk)  |  |
  | +--------------+  |                          | +--------------+  |
  +------------------+                          +------------------+

  Each instance stores ALL data locally. Replication = WAL shipping.
```

**Problems with this approach:**

- Each instance stores a full copy of the data (expensive, wasteful)
- Replication lag can be seconds or minutes under heavy write load
- Failover requires the standby to finish replaying WAL
- Adding read replicas means more WAL shipping (more network traffic)
- Storage is fixed-size - you must pre-allocate and resize manually

### How Aurora PostgreSQL Works

Aurora separates **compute** (the PostgreSQL engine) from **storage** (where data lives).
The storage layer is a shared, distributed system managed entirely by AWS.

```
Aurora PostgreSQL Architecture

  +------------------+                          +------------------+
  |  WRITER INSTANCE |                          | READER INSTANCE  |
  | +------+------+  |                          | +------+------+  |
  | | CPU  | RAM  |  |                          | | CPU  | RAM  |  |
  | +------+------+  |                          | +------+------+  |
  +--------|--------+                          +--------|--------+
           |        Shared Storage Layer                |
           |   +------------------------------------+   |
           +-> |   Aurora Distributed Storage       | <-+
               |   +--------+ +--------+ +--------+|
               |   |  AZ-1  | |  AZ-2  | |  AZ-3  ||
               |   | Copy 1 | | Copy 3 | | Copy 5 ||
               |   | Copy 2 | | Copy 4 | | Copy 6 ||
               |   +--------+ +--------+ +--------+|
               |   6 copies across 3 AZs            |
               |   Auto-growing: 10 GB to 128 TB    |
               +------------------------------------+

  Writer and Reader share the SAME storage. No WAL shipping.
  Readers see new data in ~10-20 milliseconds.
```

### What Changed and Why It Matters

| Aspect                 | Traditional PostgreSQL     | Aurora PostgreSQL          |
|------------------------|---------------------------|---------------------------|
| Storage                | Local to each instance    | Shared, distributed       |
| Data copies            | 1 per instance            | 6 copies across 3 AZs    |
| Replication method     | WAL shipping over network | Shared storage (no WAL ship)|
| Replication lag        | Seconds to minutes        | ~10-20 milliseconds       |
| Failover time          | Minutes (WAL replay)      | ~30 seconds               |
| Storage management     | Manual resize             | Auto-growing              |
| Max storage            | Limited by disk size      | 128 TB                    |
| Adding read replicas   | More WAL shipping load    | Just add compute          |

The compute-storage separation is the single most important concept in Aurora. When you
add a Reader instance, you are adding compute power only - no data copying, no WAL shipping.
You can scale reads without increasing write load on the primary.

---

## The 6-Copy, 3-AZ Replication Model

Every piece of data you write is automatically copied 6 times across 3 Availability Zones.

### What Is an Availability Zone (AZ)?

An Availability Zone is a physically separate data center within an AWS Region. Each AZ
has its own power, cooling, and network. They are connected with high-speed links but far
enough apart that a disaster in one AZ will not affect the others.

```
AWS Region: us-east-1 (N. Virginia)

  +------------------+    +------------------+    +------------------+
  |   AZ: us-east-1a|    |   AZ: us-east-1b|    |   AZ: us-east-1c|
  |  +----+ +----+  |    |  +----+ +----+  |    |  +----+ +----+  |
  |  | C1 | | C2 |  |    |  | C3 | | C4 |  |    |  | C5 | | C6 |  |
  |  +----+ +----+  |    |  +----+ +----+  |    |  +----+ +----+  |
  +------------------+    +------------------+    +------------------+

  C1-C6 = 6 copies of your data, 2 per AZ
```

### The Quorum Model

Aurora uses a quorum-based system for reads and writes:

- **Writes succeed when 4 of 6 copies acknowledge** (quorum of 4)
- **Reads succeed when 3 of 6 copies respond** (quorum of 3)

What does this mean in practice?

```
Failure Scenarios

  Scenario 1: Lose 1 AZ (2 copies gone) - 4 remain
  Can WRITE (need 4)? YES | Can READ (need 3)? YES
  Result: No data loss. No downtime.

  Scenario 2: Lose 1 AZ + 1 extra copy - 3 remain
  Can WRITE (need 4)? NO  | Can READ (need 3)? YES
  Result: Reads work. Writes paused until repair.

  Scenario 3: Lose 2 full AZs (4 copies gone) - 2 remain
  Can WRITE (need 4)? NO  | Can READ (need 3)? NO
  Result: Regional disaster. Multi-region setups needed.
```

### Why This Matters

You never set up replication manually with Aurora. AWS handles all 6 copies transparently.
But you need to understand this model so you can answer questions from [TEAM NAME] like
"what happens if an AZ goes down?" with confidence.

---

## Writer vs Reader Instances

Aurora clusters have two types of compute instances.

### Writer Instance (Primary)

- Exactly **one** Writer instance per cluster
- Handles all **INSERT, UPDATE, DELETE** operations
- Also handles **SELECT** queries (but offload reads to Readers)
- If the Writer fails, Aurora automatically promotes a Reader

### Reader Instances (Replicas)

- **0 to 15** Reader instances per cluster
- Handle **SELECT** queries only - cannot write
- Share the same storage as the Writer - no data copying
- Replication lag is typically **10-20 milliseconds**
- Can be different instance sizes than the Writer (cost optimization)

```
Aurora Cluster

  +-----------+   +-----------+   +-----------+
  |  WRITER   |   | READER 1  |   | READER 2  |
  | Reads +   |   | Reads     |   | Reads     |
  | Writes    |   | only      |   | only      |
  | db.r6g.xl |   | db.r6g.lg |   | db.r6g.lg |
  +-----------+   +-----------+   +-----------+
       |               |               |
  =====|===============|===============|=======
  |          Shared Storage Layer             |
  |    6 copies, 3 AZs, auto-growing         |
  ============================================
```

### Failover Process

When the Writer crashes or becomes unhealthy:

1. Aurora detects the failure (usually within 10-15 seconds)
2. Aurora promotes the Reader with the lowest replication lag
3. The DNS endpoint updates to point to the new Writer
4. Total failover time: typically **under 30 seconds**

You can set **failover priority** (tier 0-15) on each Reader to control which one gets
promoted first. Tier 0 is highest priority.

### Why This Matters

In production at [COMPANY], you will configure your application to send writes to the
cluster (writer) endpoint and reads to the reader endpoint. This distributes load across
instances and keeps your database responsive under heavy traffic.

---

## Endpoints - How Your Application Connects

Aurora provides multiple endpoints so your application connects to the right instance.

### Types of Endpoints

| Endpoint Type   | Example DNS                                              | Use For                          |
|-----------------|----------------------------------------------------------|----------------------------------|
| **Cluster** (Writer) | mydb-cluster.cluster-abc123.us-east-1.rds.amazonaws.com | INSERT, UPDATE, DELETE, DDL. Follows failover automatically. |
| **Reader**      | mydb-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com | SELECT queries. Load-balances across all Readers (round-robin). |
| **Instance**    | mydb-instance-1.abc123.us-east-1.rds.amazonaws.com      | Debugging, testing a specific instance. NOT for production. |
| **Custom**      | mydb-analytics.cluster-custom-abc123.us-east-1.rds...    | You choose which instances are included. Separates workloads. |

### How to Use Endpoints in Practice

Your application's database configuration should look something like this:

```
# Application database config
WRITE_DB_HOST=mydb-cluster.cluster-abc123.us-east-1.rds.amazonaws.com
READ_DB_HOST=mydb-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=myapp
DB_USER=app_user
```

- All writes (INSERT, UPDATE, DELETE) go to `WRITE_DB_HOST`
- All reads (SELECT) go to `READ_DB_HOST`

### Custom Endpoint Example

Say [COMPANY] runs both a customer-facing app and a heavy analytics dashboard:

```
Workload Isolation with Custom Endpoints

  App traffic -----> Reader Endpoint -----> Reader 1 (small)
                                    -----> Reader 2 (small)

  Analytics -------> Custom Endpoint ----> Reader 3 (large)

  Writes ----------> Cluster Endpoint ---> Writer
```

A heavy analytics query does not slow down your customer-facing app.

### Why This Matters

Using the wrong endpoint is a common beginner mistake. Sending all traffic to the cluster
(writer) endpoint means your Readers sit idle. Sending writes to the reader endpoint causes
errors. Getting endpoints right is day-one production knowledge.

---

## Aurora Storage - How It Works

### Auto-Growing Storage

- Starts at **10 GB**, grows automatically in **10 GB increments**
- Maximum size: **128 TB**
- You **never pre-allocate** or manually resize
- You only pay for what you use

Compare this to standard RDS where you must choose a storage size upfront, pay for all of
it even if mostly empty, and manually increase when you run out.

### How Data Is Organized

Aurora breaks your data into **10 GB segments** called protection groups. Each segment is
replicated 6 times across 3 AZs. This means:

- Repairs happen at the segment level (10 GB), not the full database
- A 1 TB database has 100 segments, each independently replicated
- If one copy of one segment is lost, only that 10 GB needs repair

```
Storage Segmentation - Your 30 GB Database:

  +----------+----------+----------+
  | Segment 1| Segment 2| Segment 3|
  |  10 GB   |  10 GB   |  10 GB   |
  +----------+----------+----------+
  Each segment: 6 copies across 3 AZs
  You pay for 30 GB (logical size), not the 180 GB physical total
```

### Backup and Point-in-Time Recovery

- Continuous, incremental backups to S3 - not nightly dumps
- Retention period: **1 to 35 days** (you choose)
- Point-in-time recovery: restore to **any second** within retention
- Backups do not impact database performance (happens at the storage layer)

### Why This Matters

In a traditional setup, a DBA might spend hours planning storage capacity, resizing volumes,
and managing backup windows. With Aurora, all of this is automatic.

---

## Performance - Marketing vs Reality

AWS claims Aurora is "up to 5x faster than standard PostgreSQL." Let's be honest about
what that means.

### The Reality

| Workload Type               | Aurora Advantage | Notes                              |
|-----------------------------|------------------|------------------------------------|
| High write throughput       | 2-3x faster      | Aurora's sweet spot - fewer I/Os   |
| Read-heavy with replicas    | Similar           | Both benefit from read replicas    |
| Single complex query        | Similar           | CPU-bound, not storage-bound       |
| Mixed OLTP                  | 1.5-2x faster     | Noticeable but not 5x              |
| Small database, low traffic | No advantage      | Overhead may actually slow it down |
| Failover speed              | Much faster       | 30 seconds vs several minutes      |

### Where Aurora Actually Shines

1. **Write-heavy workloads** - Aurora writes only the WAL (redo log) to storage, not full
   data pages. This reduces I/O by 4-6x compared to standard PostgreSQL.
2. **Large databases (100+ GB)** - Distributed storage handles large datasets gracefully.
3. **High availability** - Sub-30-second failover is genuinely hard to achieve otherwise.
4. **Scaling reads** - Adding Readers is instant (no data copying), minimal lag.

### Where Standard RDS PostgreSQL Might Be Better

- Small databases (under 20 GB) with low traffic
- Cost-sensitive projects (Aurora has a price premium)
- Workloads needing specific PostgreSQL extensions not supported by Aurora
- Development and testing environments

### Why This Matters

When someone at [COMPANY] asks "should we use Aurora or standard RDS?", give an honest
answer based on the workload. The 5x claim is a best-case scenario. Real-world improvements
are typically 1.5-3x - still significant, but setting the right expectations matters.

---

## Aurora Serverless v2 vs Provisioned

Aurora offers two deployment models. Choosing the right one depends on your workload.

### Provisioned Instances

- You choose a specific instance size (db.r6g.large, db.r6g.xlarge, etc.)
- Runs 24/7 at that size - you pay for the full instance even at 3 AM
- Best for: **predictable, steady workloads**

### Aurora Serverless v2

- You set a **minimum** and **maximum** ACU (Aurora Capacity Units) range
- Auto-scales compute up and down based on demand
- 1 ACU is roughly 2 GB RAM, scales in **0.5 ACU** increments
- Minimum: **0.5 ACU** (always running) - Maximum: **256 ACU**
- Best for: **variable, unpredictable workloads**

```
Serverless v2 Auto-Scaling

  Capacity
  (ACUs)
    32 |                              ****
       |                           ***    ***
    16 |            ****     **  **          **
       |          **    ** **                  ***
     4 |  ***   **        *                       ***
       | *                                           *
     0 +------------------------------------------------>
       12am  3am  6am  9am  12pm  3pm  6pm  9pm  12am

  Scales automatically. You set min and max ACU.
  Pay only for ACUs consumed each second.
```

### Comparison Table

| Feature                 | Provisioned              | Serverless v2              |
|-------------------------|--------------------------|----------------------------|
| Pricing model           | Per instance-hour        | Per ACU-second             |
| Scaling                 | Manual (change instance) | Automatic (seconds)        |
| Minimum cost            | Full instance 24/7       | 0.5 ACU always running     |
| Best for                | Steady traffic           | Spiky or unpredictable     |
| Scale to zero           | No                       | No (minimum 0.5 ACU)       |
| Performance consistency | Very predictable         | Brief latency during scale-up|

**Mix and match:** You can run a Provisioned Writer with Serverless v2 Readers - predictable
write performance with auto-scaling read capacity.

### Why This Matters

Get this choice wrong and you either overpay (provisioned instance idle 18 hours a day) or
get inconsistent performance (serverless scaling during peak load). This track teaches you
how to analyze workload patterns and make the right call.

---

## Key Takeaways

1. **Aurora separates compute from storage.** Writer and Readers connect to a shared
   distributed storage layer - no WAL shipping, no data copying between instances.

2. **6 copies across 3 AZs** - Aurora survives losing an entire AZ and still handles
   reads and writes. This durability is automatic.

3. **Writer handles writes, Readers handle reads.** Use the cluster endpoint for writes
   and the reader endpoint for reads. Never send all traffic to the Writer.

4. **Endpoints matter.** Cluster, reader, custom, and instance endpoints each serve a
   different purpose. Using the wrong one causes errors or wasted resources.

5. **Storage auto-grows from 10 GB to 128 TB.** No pre-allocation, no manual resizing.

6. **The "5x faster" claim is a best-case number.** Real-world improvements are 1.5-3x.

7. **Provisioned for steady workloads, Serverless v2 for variable ones.** You can mix
   both in the same cluster.

---

## What Is Next?

In the next concept doc, we explore the DevOps DBA role - how it differs from a traditional
DBA, what skills you need, and what your day-to-day work looks like. We will also cover
the job market, salary ranges, and the certifications that matter most.

---

*Module 01 - Concept 02 | DevOps DBA Training Track*
*[COMPANY] - [TEAM NAME]*
