# Scaling Strategies
## Module 05 | DevOps DBA Training Track - Aurora PostgreSQL

Work through all sections before starting the BUILD labs on scaling. Each concept maps to a hands-on exercise.

---

## 5.7 Read Replicas for Read Scaling

### The Problem: Write Traffic Is Fixed, Read Traffic Grows

Most applications are read-heavy. A typical web app does 80-90% reads and 10-20% writes. When traffic grows, reads grow faster than writes. You cannot scale the writer infinitely - eventually you need to distribute reads across multiple instances.

```
Before read replicas:

  [100% of traffic] --> [Single Writer]
                         CPU: 85%
                         Connections: 450/500

After adding 2 readers:

  [Writes 20%]   --> [Writer]        CPU: 35%
  [Reads 80%]    --> [Reader-1]      CPU: 40%
                     [Reader-2]      CPU: 40%
```

---

### Aurora Replicas vs RDS Read Replicas

| Feature | RDS Read Replica | Aurora Replica |
|---------|-----------------|----------------|
| Storage | Own EBS volume (full copy) | Shared Aurora storage (no extra cost) |
| Replication method | WAL streaming (async) | Cache invalidation (shared storage) |
| Typical lag | 100ms - seconds | < 20ms |
| Max replicas | 5 per primary | 15 per cluster |
| Automatic failover target | No (must manually promote) | Yes (automatic via failover tiers) |
| Cross-region | Yes (WAL over internet) | Via Global Database only |
| Cost | Full instance + full storage | Instance only (storage shared) |

Aurora replicas are cheaper (no extra storage), faster (less lag), and more integrated (automatic failover). Use Aurora replicas unless you specifically need RDS for engine compatibility.

---

### Reader Endpoint Load Balancing

The Aurora reader endpoint distributes new connections across all readers using DNS round-robin.

```
Application opens connection #1:
  DNS resolves reader endpoint --> 10.0.2.45 (Reader-1)

Application opens connection #2:
  DNS resolves reader endpoint --> 10.0.3.67 (Reader-2)

Application opens connection #3:
  DNS resolves reader endpoint --> 10.0.2.45 (Reader-1)
```

**Important limitations:**
- DNS round-robin distributes connections, not queries
- Existing connections are NOT rebalanced
- If one reader handles a long query, it is not offloaded to another
- With connection pooling, long-lived connections may stay on one reader

For more sophisticated load balancing, use RDS Proxy or application-level routing.

---

## 5.8 Aurora Auto-Scaling Policies

### What Is Aurora Auto-Scaling?

Aurora Auto Scaling automatically adds or removes Aurora replicas based on a CloudWatch metric (usually CPU utilization or connection count). You define a target value and Aurora adjusts the number of readers to maintain that target.

```
Auto-scaling with target CPU = 50%:

Traffic low:
  [Writer] [Reader-1]               CPU per reader: 30%
                                     Action: none (below target)

Traffic growing:
  [Writer] [Reader-1]               CPU per reader: 60%
                                     Action: add Reader-2

After scale-out:
  [Writer] [Reader-1] [Reader-2]   CPU per reader: 40%
                                     Action: none (below target)

Traffic drops:
  [Writer] [Reader-1] [Reader-2]   CPU per reader: 15%
                                     Action: remove Reader-2 (cooldown)
```

---

### How It Works

Aurora Auto Scaling uses AWS Application Auto Scaling with target tracking policies. You set:

1. **Target metric** - what to optimize for (CPU, connections, or custom)
2. **Target value** - the desired utilization level (e.g., 50% CPU)
3. **Minimum replicas** - never go below this (e.g., 1)
4. **Maximum replicas** - never go above this (e.g., 5)
5. **Cooldown periods** - wait time between scale actions

Aurora handles the rest: it watches the metric, adds replicas when utilization exceeds the target, and removes replicas when utilization drops below it.

---

### Scale-Out vs Scale-Up

| Strategy | What It Does | When To Use |
|----------|-------------|-------------|
| Scale out (add replicas) | More instances sharing the read load | Read-heavy workloads with variable traffic |
| Scale up (bigger instance) | More CPU/RAM per instance | Write-heavy workloads, large queries needing more RAM |

Aurora Auto Scaling handles scale-out. For scale-up, you modify the instance class manually (or use Serverless v2 which scales up automatically).

---

## 5.9 Aurora Serverless v2 - Automatic Vertical Scaling

### What Is Serverless v2?

Aurora Serverless v2 is an auto-scaling compute mode. Instead of choosing a fixed instance class (like db.r6g.large), you set a minimum and maximum capacity range in ACUs (Aurora Capacity Units). Aurora scales the compute up and down within that range based on actual demand.

**ACU (Aurora Capacity Unit):**
- 1 ACU = approximately 2 GB RAM + proportional CPU and network
- Scales in 0.5 ACU increments
- Scaling happens in seconds, not minutes

```
Traffic pattern over 24 hours:

ACU:
 16 |                        ####
 12 |                   #####    ####
  8 |          ########              #####
  4 | #########                           ########
  1 | ##                                          ##
    +--+----+----+----+----+----+----+----+----+---> time
     00:00 03:00 06:00 09:00 12:00 15:00 18:00 21:00
      idle  idle  ramp  peak  peak  peak  wind  idle
```

---

### Scale to Zero - The Truth

**Aurora Serverless v2 does NOT scale to zero.** The minimum is 0.5 ACU. Your cluster is always running and always costs at least 0.5 ACU per hour.

The original Aurora Serverless v1 could scale to zero, but v1 is being deprecated and had significant limitations (25-45 second cold start, limited feature support).

If you need true scale-to-zero for cost savings, Serverless v2 is not the answer. Consider stopping/starting the cluster on a schedule instead.

---

### Mixed Clusters - The Production Pattern

You can combine provisioned and Serverless v2 instances in the same Aurora cluster. This is the recommended production pattern for read-heavy workloads:

```
Pattern: Provisioned writer + Serverless v2 readers

  [db.r6g.xlarge Writer]     <-- Fixed cost, predictable performance for writes
       |
  [db.serverless Reader-1]   <-- Auto-scales 0.5-16 ACU based on read traffic
  [db.serverless Reader-2]   <-- Auto-scales independently
```

**Why mixed clusters work well:**
- The writer handles predictable write load at fixed cost (no scaling delay)
- Readers auto-scale based on variable read traffic
- During off-hours, readers scale down to 0.5 ACU (minimal cost)
- During peak, readers scale up to handle spikes

---

### When Serverless v2 Saves Money vs When It Does Not

**Saves money:**
- Dev/test environments that sit idle most of the day
- Workloads with large traffic spikes (business hours only, flash sales)
- New applications where you do not know the right instance size yet
- Variable read replicas

**Does NOT save money:**
- Steady, predictable 24/7 workloads at high ACU levels
- Workloads that average more than 50% of their peak ACU continuously

**Break-even example:**
- Serverless v2 at sustained 8 ACU = $0.96/hr (at $0.12/ACU-hr)
- Provisioned db.r6g.xlarge (similar to 8 ACU) = $0.48/hr
- Serverless v2 costs 2x at sustained load
- But if your average is 3 ACU with peaks to 8, Serverless v2 wins

---

## 5.10 Global Databases - Cross-Region Replication

### What Is a Global Database?

An Aurora Global Database spans multiple AWS Regions. One region is the primary (read-write). Other regions are secondaries (read-only). Data replicates from primary to secondary using Aurora's storage-level replication - not WAL streaming.

```
Region: us-east-1 (PRIMARY)
  [Writer]  [Reader-1]  [Reader-2]
       \         |          /
        +--------+----------+
                 |
        [Aurora Storage]
                 |
                 | Storage-level replication
                 | (sub-second lag, typically < 1 second)
                 v
Region: us-west-2 (SECONDARY)
  [Reader-3]  [Reader-4]
       \          /
        +--------+
                 |
        [Aurora Storage - read-only copy]
```

---

### Cross-Region Replication Lag

Global Database replication is storage-level, not WAL-level. The primary region's storage nodes send redo log records directly to the secondary region's storage nodes.

Typical lag: 100-500 milliseconds between regions. AWS guarantees under 1 second for normal conditions.

This is much better than RDS cross-region read replicas which use WAL streaming over the internet and can have 1-5 seconds of lag.

---

### Planned Failover (Switchover)

When you want to change which region is primary - for planned maintenance or migration:

```
Step 1: Replication catches up to zero lag
Step 2: Primary (us-east-1) becomes read-only
Step 3: Secondary (us-west-2) is promoted to primary
Step 4: DNS endpoints are updated
Step 5: Applications in us-west-2 get read-write access
Step 6: Old primary (us-east-1) becomes the secondary

Duration: 5-20 minutes
Data loss: ZERO (planned, controlled process)
```

CLI command: `aws rds switchover-global-cluster`

---

### Unplanned Failover (Region Failure)

If the primary region becomes unavailable (a real disaster), you must manually intervene:

```
Step 1: Detect primary region is down (CloudWatch alarms, Route 53 health checks)
Step 2: Run: aws rds remove-from-global-cluster (detach secondary)
Step 3: Secondary becomes an independent read-write cluster
Step 4: Update application configuration to point to new primary
Step 5: When old primary recovers, re-attach it as a secondary

Duration: 3-10 minutes (depends on your automation)
Data loss: Possible (RPO = last replicated transaction, typically < 1 second)
```

**There is no automatic unplanned failover** in Aurora Global Database. AWS designed it this way intentionally to prevent "split-brain" scenarios where both regions think they are the primary.

---

### Write Forwarding

Write forwarding allows applications in a secondary region to send writes to the secondary endpoint. Aurora forwards those writes to the primary region automatically.

```
Without write forwarding:
  [App in eu-west-1] --writes--> [primary endpoint in us-east-1]
                                  (app must know primary region)

With write forwarding:
  [App in eu-west-1] --writes--> [secondary endpoint in eu-west-1]
                                         |
                                   [Aurora forwards]
                                         |
                                         v
                                  [primary in us-east-1]
```

**Trade-offs:**
- Simplifies application code (no need to know the primary region)
- Adds latency to writes (cross-region round trip: 100-200ms per write)
- Not suitable for high-frequency writes
- Good for occasional writes from secondary regions

---

## 5.11 Connection Management with RDS Proxy

### The Connection Problem

PostgreSQL creates a new operating system process for every client connection. Each connection uses 5-10 MB of RAM. At 500 connections, that is 2.5-5 GB of RAM just for connection overhead.

```
Without connection pooling:

  [Lambda Function 1] --> connection --> [Aurora Writer]
  [Lambda Function 2] --> connection -->
  [Lambda Function 3] --> connection -->
  ...
  [Lambda Function 500] --> connection -->

  Result: 500 OS processes, 5 GB RAM used for connections alone
```

Lambda functions and microservices make this worse because each invocation may open a new connection.

---

### What RDS Proxy Does

RDS Proxy sits between your application and the Aurora cluster. It pools and shares database connections, reducing the load on the database.

```
With RDS Proxy:

  [Lambda Function 1] --> [RDS Proxy]  --> [Aurora Writer]
  [Lambda Function 2] -->    (pools     --> (sees only 20
  [Lambda Function 3] -->  connections)     connections)
  ...                  -->
  [Lambda Function 500] -->

  500 application connections --> 20 database connections
```

---

### Key Benefits for HA

RDS Proxy helps with availability in addition to performance:

1. **Faster failover recovery:** RDS Proxy detects failover and reconnects to the new writer automatically. Applications see a brief error but do not need to manage DNS TTL or connection retry logic.

2. **Connection draining:** During failover, Proxy gracefully drains existing connections instead of hard-dropping them.

3. **Multiplexing:** Proxy reuses database connections across multiple application connections, reducing the load on the new writer after failover.

4. **IAM authentication:** Proxy supports IAM database authentication, eliminating the need to store database passwords in application code.

---

### When to Use RDS Proxy

**Good fit:**
- Lambda functions connecting to Aurora (bursty, many short-lived connections)
- Microservices with many replicas (each opens its own connection pool)
- Applications that need faster failover recovery
- Workloads exceeding 500 concurrent database connections

**Not needed:**
- Applications with a stable connection pool (e.g., one backend server with 20 connections)
- Direct DBA access for diagnostics
- Batch jobs that use a single long-lived connection

---

## 5.12 Summary: Scaling Strategy Decision Guide

| Traffic Pattern | Recommended Strategy |
|-----------------|---------------------|
| Read-heavy, predictable | Add Aurora replicas (auto-scaling optional) |
| Read-heavy, variable | Aurora Serverless v2 readers |
| Write-heavy, predictable | Scale up the writer instance class |
| Variable reads + writes | Mixed cluster (provisioned writer + Serverless readers) |
| Multi-region reads | Aurora Global Database |
| Multi-region writes | Global Database with write forwarding |
| Many short-lived connections | RDS Proxy |
| Bursty Lambda workload | RDS Proxy + Serverless v2 |
| Dev/test with idle periods | Serverless v2 (min ACU = 0.5) |

---

## Key Terms

| Term | Definition |
|------|-----------|
| ACU | Aurora Capacity Unit - approximately 2 GB RAM plus proportional CPU |
| Auto Scaling | Automatically adding/removing Aurora replicas based on a CloudWatch metric |
| Target tracking | Auto-scaling policy that maintains a target metric value (e.g., 50% CPU) |
| Serverless v2 | Aurora compute mode that auto-scales between min and max ACU |
| Mixed cluster | Aurora cluster with both provisioned and Serverless v2 instances |
| Global Database | Aurora deployment spanning multiple AWS Regions |
| Write forwarding | Routing writes from secondary region through to primary region |
| RDS Proxy | Managed connection pooler that sits between applications and Aurora |
| Connection pooling | Reusing database connections across multiple application requests |
| Scale out | Adding more instances to distribute load |
| Scale up | Using a larger instance class for more CPU/RAM |
| DNS round-robin | Load balancing by returning different IPs for the same hostname |
| Cooldown period | Wait time between auto-scaling actions to prevent flapping |
