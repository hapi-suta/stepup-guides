# Concepts: AWS Monitoring Stack for Aurora

**Module 07 - Performance, Monitoring and Observability**
**Quick reference for CloudWatch, Performance Insights, Enhanced Monitoring, and RDS Events.**

---

## The Four Layers of AWS Database Monitoring

AWS provides four distinct monitoring layers for RDS and Aurora. Each layer answers different questions:

```
Layer 4: RDS Events (operational changes)
    "What changed? Who changed it? When?"

Layer 3: Performance Insights (database internals)
    "What SQL is running? What are sessions waiting on?"

Layer 2: Enhanced Monitoring (OS-level metrics)
    "What processes are using CPU? How is memory broken down?"

Layer 1: CloudWatch Metrics (hypervisor-level metrics)
    "What are the headline numbers? CPU, connections, storage?"
```

Each layer has different data sources, granularity, retention, and cost.

---

## Layer 1: CloudWatch Metrics

### What It Is

CloudWatch Metrics is the baseline monitoring for every RDS and Aurora instance. Metrics are collected at the hypervisor level - the layer between your DB instance and the underlying hardware. These metrics are published automatically. You do not need to enable them.

### Key Metrics Reference

**Compute metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| CPUUtilization | Percent | CPU usage across all vCPUs | > 80% sustained for 5+ min |
| CPUCreditBalance | Count | T-instance burst credits remaining | Approaching 0 |
| CPUCreditUsage | Count | T-instance credits consumed per minute | Consistently maxed |

**Connection metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| DatabaseConnections | Count | Open TCP connections to the instance | > 80% of max_connections |

**Memory metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| FreeableMemory | Bytes | RAM available for use | < 10% of total RAM |
| SwapUsage | Bytes | Swap space used | > 0 consistently |

**Storage metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| FreeStorageSpace | Bytes | Unused allocated disk | < 10 GB or < 20% of total |
| VolumeBytesUsed | Bytes | Aurora storage consumed | Growth rate unsustainable |
| VolumeReadIOPs | Count | Aurora storage read operations | Baseline comparison |
| VolumeWriteIOPs | Count | Aurora storage write operations | Baseline comparison |

**Latency metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| ReadLatency | Seconds | Average read I/O latency | > 20ms average |
| WriteLatency | Seconds | Average write I/O latency | > 10ms average |
| CommitLatency | Milliseconds | Average time per commit (Aurora) | > 20ms average |
| CommitThroughput | Count/sec | Commits per second (Aurora) | Sudden drop from baseline |

**Replication metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| AuroraReplicaLag | Milliseconds | Reader lag behind writer | > 100ms sustained |
| AuroraReplicaLagMaximum | Milliseconds | Maximum lag across readers | > 200ms |
| AuroraReplicaLagMinimum | Milliseconds | Minimum lag across readers | > 100ms |

**Transaction metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| MaximumUsedTransactionIDs | Count | Highest XID age across databases | > 1,000,000,000 warning, > 1,500,000,000 critical |
| TransactionLogsDiskUsage | Bytes | WAL retained on disk (RDS) | Growing continuously |

**Aurora-specific metrics:**

| Metric | Unit | What It Measures | Alert When |
|--------|------|------------------|------------|
| BufferCacheHitRatio | Percent | shared_buffers cache hit rate | < 99% for OLTP |
| Deadlocks | Count/sec | Deadlock detection rate | Any sustained increase |
| DiskQueueDepth | Count | Outstanding I/O requests | > 10 sustained |
| EngineUptime | Seconds | Time since last restart | Unexpected reset to 0 |

### CloudWatch Metric Resolution

| Type | Resolution | Cost |
|------|-----------|------|
| Basic monitoring | 60-second periods | Included |
| Detailed monitoring | 1-second periods | Additional charge |
| Custom metrics | 1-second minimum | Per-metric charge |

For most production databases, the default 60-second resolution is sufficient for alerting. Use Enhanced Monitoring or Performance Insights for sub-minute diagnosis.

### Metric Math

CloudWatch Metric Math lets you combine metrics into derived values directly in the console or via API:

```
Useful metric math expressions:

Cache hit ratio (Aurora):
  Expression: m1 (BufferCacheHitRatio)
  Already provided as a percentage by Aurora.

Connection utilization:
  Expression: m1 / METRICS("max_conn")
  Where m1 = DatabaseConnections
  Note: max_connections is not a CloudWatch metric.
  You need to create a custom metric or use a static threshold.

IOPS utilization (Aurora):
  Expression: m1 + m2
  Where m1 = VolumeReadIOPs, m2 = VolumeWriteIOPs
  Compare against instance limits.

Read/Write ratio:
  Expression: m1 / (m1 + m2) * 100
  Where m1 = VolumeReadIOPs, m2 = VolumeWriteIOPs
```

### CloudWatch Dashboards

Dashboards give you a single-pane view. Organize them by function:

```
Recommended dashboard layout for Aurora:

Row 1: Overview (4 widgets)
  [CPU Utilization]  [Connections]  [Freeable Memory]  [Replica Lag]

Row 2: Storage (4 widgets)
  [Read IOPS]  [Write IOPS]  [Read Latency]  [Write Latency]

Row 3: Aurora-specific (4 widgets)
  [Commit Latency]  [Commit Throughput]  [Buffer Cache Hit Ratio]  [Deadlocks]

Row 4: Safety (4 widgets)
  [TXID Age]  [Volume Bytes Used]  [Disk Queue Depth]  [Engine Uptime]
```

### CloudWatch Alarms

Alarms evaluate a metric against a threshold over a defined period.

**Alarm components:**

| Component | What It Controls |
|-----------|-----------------|
| Metric | Which metric to evaluate |
| Statistic | How to aggregate (Average, Maximum, Minimum, Sum, p99) |
| Period | Time window for each evaluation (60s, 300s, etc.) |
| Evaluation periods | How many consecutive periods must breach threshold |
| Threshold | The value that triggers the alarm |
| Comparison operator | GreaterThanThreshold, LessThanThreshold, etc. |
| Alarm actions | What happens when alarm fires (SNS topic) |
| OK actions | What happens when alarm clears (optional SNS topic) |

**Alarm states:**

| State | Meaning |
|-------|---------|
| OK | Metric is within threshold |
| ALARM | Metric has breached threshold for the required evaluation periods |
| INSUFFICIENT_DATA | Not enough data points to evaluate (new alarm, or metric not reporting) |

---

## Layer 2: Enhanced Monitoring

### What It Is

Enhanced Monitoring runs a lightweight agent inside the database instance's operating system. It reports OS-level metrics at up to 1-second granularity. This data goes to CloudWatch Logs (not CloudWatch Metrics), which is an important distinction.

### Enhanced Monitoring vs CloudWatch Metrics

```
CloudWatch Metrics                Enhanced Monitoring
----------------------------      ----------------------------
Source: hypervisor                 Source: OS agent inside instance
Granularity: 60 seconds           Granularity: 1, 5, 10, 15, 30, or 60 seconds
CPU: single aggregate %           CPU: per-process breakdown
Memory: FreeableMemory only       Memory: active, buffers, cached, dirty, free, swap
Disk: aggregate IOPS              Disk: per-device I/O
Network: aggregate throughput     Network: per-interface stats
Process list: none                Process list: full OS process table
Cost: included                    Cost: CloudWatch Logs ingestion ($0.50/GB)
Destination: CloudWatch Metrics   Destination: CloudWatch Logs (RDSOSMetrics)
```

### What Enhanced Monitoring Shows

**CPU breakdown by process:**
- Which PostgreSQL backend processes are consuming CPU
- Whether autovacuum workers are using significant CPU
- Whether the WAL writer or checkpointer is busy
- System processes vs PostgreSQL processes

**Memory breakdown:**

| Memory Category | What It Means |
|----------------|---------------|
| Active | Memory currently in use by processes |
| Buffers | Memory used for block device I/O buffers |
| Cached | Memory used for file system cache (OS page cache) |
| Dirty | Memory with modified pages not yet written to disk |
| Free | Completely unused memory |
| Swap | Memory pages swapped to disk |

**Key insight:** FreeableMemory in CloudWatch includes Cached + Free. This is why FreeableMemory can be high even when "Free" is low - the OS page cache is reclaimable.

**Disk I/O per device:**
- Read/write operations per device
- Read/write bytes per device
- Average queue size
- Average service time

**Network per interface:**
- Receive/transmit bytes
- Receive/transmit packets
- Errors and drops

### When to Use Enhanced Monitoring

- **CPU diagnosis:** CloudWatch shows 80% CPU but you do not know which process. Enhanced Monitoring shows you the process list.
- **Memory diagnosis:** CloudWatch shows low FreeableMemory but you do not know if it is shared_buffers, OS cache, or a memory leak. Enhanced Monitoring breaks it down.
- **I/O diagnosis:** You need to see which device is saturated or the queue depth at sub-minute granularity.
- **Autovacuum impact:** You want to see how much CPU and I/O autovacuum workers are consuming.

### Granularity and Cost

| Granularity | Data per minute | Monthly cost (approx) |
|-------------|----------------|----------------------|
| 60 seconds | 1 data point | ~$0.50-1.00 |
| 30 seconds | 2 data points | ~$1.00-2.00 |
| 15 seconds | 4 data points | ~$2.00-4.00 |
| 10 seconds | 6 data points | ~$3.00-6.00 |
| 5 seconds | 12 data points | ~$6.00-12.00 |
| 1 second | 60 data points | ~$30.00-60.00 |

**Recommendation:** Use 60-second granularity for most instances. Use 1-5 second granularity only during active performance investigations, then revert.

---

## Layer 3: Performance Insights

### What It Is

Performance Insights (PI) is a database performance monitoring feature that provides a dashboard and API for analyzing database activity. It samples the database engine every second and records what queries were running and what each session was waiting on.

### DB Load - The Core Metric

DB Load measures Average Active Sessions (AAS) - the average number of sessions that were actively executing or waiting at any given second.

```
DB Load = Average Active Sessions (AAS)

DB Load = 1.0  -->  On average, 1 session was active every second
DB Load = 4.0  -->  On average, 4 sessions were active every second
DB Load = 16.0 -->  On average, 16 sessions were active every second
```

The PI dashboard draws a horizontal line at your vCPU count. This is the saturation point. When DB Load exceeds vCPU count, the database has more work than it can handle simultaneously. Sessions start queuing.

```
Healthy: DB Load below vCPU line
  |####            |
  |####            |
  |####            |  <-- DB Load = 3, vCPUs = 8
  +--- vCPU line --+

Saturated: DB Load above vCPU line
  |################|
  |################|  <-- DB Load = 12, vCPUs = 8
  |################|
  +--- vCPU line --+
  |####            |
```

### Wait Events

The DB Load graph is color-coded by wait event type. Each color tells you what sessions are spending time on:

| Color | Wait Category | What It Means | Common Events |
|-------|--------------|---------------|---------------|
| Blue | CPU | Actively computing on CPU | (no specific wait) |
| Red | IO | Waiting for disk/storage I/O | DataFileRead, WALWrite, BufFileRead |
| Orange | Lock | Waiting for a lock | relation, tuple, transactionid |
| Yellow | LWLock | Waiting for a lightweight lock | buffer_mapping, WALWrite |
| Purple | Client | Waiting for the client | ClientRead, ClientWrite |
| Green | IPC | Inter-process communication | various |
| Gray | Other | Miscellaneous | various |

### Wait Event Interpretation

| Wait Event | Category | Root Cause | Action |
|------------|----------|-----------|--------|
| IO:DataFileRead | IO | Cache miss - data not in shared_buffers | Increase instance size, add indexes, check shared_buffers |
| IO:WALWrite | IO | WAL commit bottleneck | Check storage IOPS, reduce commit frequency |
| IO:BufFileRead | IO | Temp file read (sort/hash spill) | Increase work_mem, use Optimized Reads |
| Lock:relation | Lock | Table-level lock contention | Find blocking query, use CONCURRENTLY |
| Lock:tuple | Lock | Row-level lock contention | Check long-running transactions |
| Lock:transactionid | Lock | Waiting for another transaction to commit | Check for long transactions |
| LWLock:buffer_mapping | LWLock | Shared buffer lookup contention | Increase shared_buffers, reduce connections |
| CPU | CPU | Active computation | Check for seq scans, missing indexes |
| Client:ClientRead | Client | Waiting for client to send data | Network latency, slow application |

### Top SQL

The Top SQL tab ranks queries by their DB Load contribution. Each query shows:
- Load (average active sessions contributed by this query)
- Executions per minute
- Average latency per execution
- Wait event breakdown

**Key insight:** The query with the highest DB Load is not always the slowest individual query. A fast query executed thousands of times per minute can contribute more DB Load than a slow query running once.

```
Query A: 10,000 calls/min * 2ms each = 20,000ms total = 333ms of DB Load per second
Query B: 1 call/min * 30,000ms = 30,000ms total = 500ms of DB Load per second

Query B has higher individual latency, but Query A's total impact
depends on call frequency. Both contribute significant DB Load.
```

### Performance Insights Retention

| Retention | Cost |
|-----------|------|
| 7 days | Free |
| 1 month | $0.02 per vCPU per hour |
| Up to 2 years | $0.02 per vCPU per hour |

**Recommendation:**
- 7 days for development and staging
- 1 month minimum for production
- 2 years for databases where you need to compare seasonal performance patterns

### Performance Insights API

PI data is accessible via the `pi` API. Key operations:

| API Call | What It Returns |
|----------|----------------|
| `GetResourceMetrics` | DB Load, counter metrics over time |
| `DescribeDimensionKeys` | Top SQL, top waits, top users, top hosts |
| `GetDimensionKeyDetails` | Full SQL text for a normalized query |
| `ListAvailableResourceDimensions` | Available grouping dimensions |
| `ListAvailableResourceMetrics` | Available metrics |

Use the API to build automated performance reports, regression detection, and custom dashboards.

---

## Layer 4: RDS Events

### What It Is

RDS Events report operational changes to your database instances, clusters, parameter groups, and snapshots. They are not performance metrics - they are event notifications about state changes.

### Event Categories

| Category | Example Events |
|----------|---------------|
| availability | Instance restarted, failover occurred, instance stopped/started |
| backup | Automated backup started/completed, snapshot created |
| configuration change | Parameter group modified, instance class changed |
| creation | Instance created, cluster created |
| deletion | Instance deleted, snapshot deleted |
| failover | Failover started, failover completed |
| failure | Instance failure, storage failure |
| maintenance | Maintenance window started, patch applied |
| notification | Certificate rotation, engine version deprecation |
| recovery | Instance recovery started/completed |

### Event Subscriptions

You can subscribe to specific event categories via SNS:

```
RDS Event Source (instance, cluster, parameter group, snapshot)
    |
    v
Event Subscription (filter by category)
    |
    v
SNS Topic
    |
    +-- Email notification
    +-- Lambda function (automated response)
    +-- SQS queue (for processing)
    +-- HTTP/S endpoint (webhook)
```

**Recommended event subscriptions for production:**

| Subscription | Categories | Why |
|-------------|-----------|-----|
| Critical | availability, failover, failure | Immediate awareness of outages |
| Changes | configuration change | Audit trail for parameter changes |
| Maintenance | maintenance, backup | Awareness of scheduled activities |

---

## Putting It All Together

### Incident Investigation Workflow

When a performance problem occurs, use the layers in this order:

```
Step 1: CloudWatch Metrics (60-second view)
    "Is the database healthy at a high level?"
    Check: CPU, connections, memory, replica lag
    |
    v
Step 2: Performance Insights (1-second view)
    "What queries are responsible? What are they waiting on?"
    Check: DB Load, top SQL, top wait events
    |
    v
Step 3: Enhanced Monitoring (OS-level view)
    "Is this a database problem or an OS/infrastructure problem?"
    Check: Process list, memory breakdown, disk I/O
    |
    v
Step 4: RDS Events (operational view)
    "Did something change that triggered this?"
    Check: Parameter changes, failovers, maintenance events
```

### Monitoring Setup Checklist

```
For every production Aurora instance:

[ ] CloudWatch Metrics - enabled (automatic)
[ ] CloudWatch Dashboard - created with 16 panels
[ ] CloudWatch Alarms - 8 minimum (CPU, connections, memory, storage,
    read latency, write latency, replica lag, TXID wraparound)
[ ] Enhanced Monitoring - enabled at 60-second granularity
[ ] Performance Insights - enabled with 1-month retention minimum
[ ] pg_stat_statements - loaded via shared_preload_libraries
[ ] track_io_timing - set to ON
[ ] RDS Event Subscriptions - critical + changes + maintenance
[ ] SNS Topic - with verified email recipients
[ ] Alarm escalation - SNS to PagerDuty/Slack for critical alarms
```
