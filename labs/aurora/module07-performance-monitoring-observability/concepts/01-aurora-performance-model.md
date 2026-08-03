# Concepts: Aurora Performance Model

**Module 07 - Performance, Monitoring and Observability**
**Quick reference for how Aurora PostgreSQL performance differs from standard PostgreSQL and RDS PostgreSQL.**

---

## Aurora Architecture vs Standard PostgreSQL

Standard PostgreSQL writes data to local disk. Every write goes through the buffer cache, gets written to WAL (Write-Ahead Log), and eventually gets flushed to data files on disk. The disk is directly attached to the server - either a local SSD or a network-attached volume like EBS.

Aurora is fundamentally different. It separates compute from storage. The database instance (compute) does not write data files to local disk. Instead, it sends WAL records across the network to a distributed storage layer that spans 3 Availability Zones. The storage layer applies those WAL records and maintains 6 copies of your data.

```
Standard PostgreSQL / RDS PostgreSQL:
  Application
      |
  [DB Instance]
      |
  [Local or EBS Disk]
      - Data files
      - WAL files
      - Temp files


Aurora PostgreSQL:
  Application
      |
  [DB Instance (compute only)]
      |  sends WAL records over network
      v
  [Aurora Distributed Storage Layer]
      - 6 copies across 3 AZs
      - Storage applies WAL records
      - No data file writes from compute
```

### What This Means for Performance

1. **Writes are faster** - Aurora writes only the WAL record to storage, not the full data page. Standard PostgreSQL writes both WAL and data pages. This reduces write amplification by roughly 6x compared to mirrored EBS.

2. **Reads go through a shared buffer cache first** - just like standard PostgreSQL. Cache misses go to the Aurora storage layer over the network, not to a local disk. Network latency to storage is typically 1-3ms.

3. **No checkpoints** - Standard PostgreSQL flushes dirty pages from shared_buffers to disk during checkpoints. Aurora does not need this because the storage layer already has the data. This eliminates checkpoint-related I/O spikes.

4. **No VACUUM I/O on storage** - When Aurora vacuums, it marks pages as dead in the storage layer. The storage layer handles space reclamation asynchronously. VACUUM still needs to scan the table on the compute side, but the I/O pattern is different.

---

## Storage I/O in Aurora

### How Aurora Handles Reads

When a query needs a page that is not in shared_buffers, Aurora fetches it from the storage layer. The read path looks like this:

```
Query requests page
    |
    v
Check shared_buffers (RAM)
    |
    +-- HIT: return page immediately (microseconds)
    |
    +-- MISS: fetch from Aurora storage layer
              |
              v
         Network request to storage node (1-3ms typical)
              |
              v
         Page returned and cached in shared_buffers
```

**Key difference from EBS:** On standard RDS with EBS, a cache miss reads from the EBS volume over the network. The latency is 0.5-2ms for gp3 and io2 volumes. Aurora storage latency is similar, but Aurora's storage is replicated across 3 AZs, which means reads can be served from the closest storage node.

### How Aurora Handles Writes

Aurora's write path is dramatically different from standard PostgreSQL:

```
Standard PostgreSQL write path:
  1. Modify page in shared_buffers (mark dirty)
  2. Write WAL record to WAL buffer
  3. Flush WAL buffer to disk (fsync)
  4. During checkpoint: flush dirty pages to disk (fsync)
  Total disk writes per modified page: ~2x (WAL + data file)

Aurora PostgreSQL write path:
  1. Modify page in shared_buffers (mark dirty)
  2. Write WAL record to WAL buffer
  3. Send WAL record to Aurora storage (network)
  4. Storage acknowledges when 4 of 6 copies are written
  5. No checkpoint flush needed
  Total network writes per modified page: 1x (WAL only)
```

**Write amplification comparison:**

| Operation | Standard RDS (EBS mirrored) | Aurora |
|-----------|---------------------------|--------|
| WAL write | 2x (primary + mirror) | 6x (6 copies) |
| Data page write | 2x (primary + mirror) | 0x (storage handles it) |
| Full-page image in WAL | Yes (after checkpoint) | Yes (but fewer checkpoints) |
| Total I/O per page modify | ~4x | ~1x WAL record |
| Effective amplification | Higher | Lower overall |

Despite writing 6 copies of each WAL record, Aurora's total I/O is lower because it never writes full data pages from compute to storage.

### Aurora I/O Pricing Models

Aurora charges for storage I/O. There are two pricing models:

**Standard I/O:**
- Pay per I/O operation: $0.20 per million I/Os (us-east-1)
- Pay per GB of storage: $0.10/GB-month
- Best for: workloads with moderate I/O (less than ~25% of storage cost in I/O charges)

**I/O-Optimized:**
- No per-I/O charge
- Higher storage price: $0.125/GB-month (+25%)
- Best for: I/O-heavy workloads where I/O charges exceed 25% of storage charges

```
Break-even example:
  Database: 500 GB
  Standard storage cost: 500 * $0.10 = $50/month
  I/O-Optimized storage cost: 500 * $0.125 = $62.50/month
  Extra cost for I/O-Optimized: $12.50/month

  If your monthly I/O cost exceeds $12.50 (62.5 million I/Os), switch to I/O-Optimized.
  Most production OLTP databases exceed this easily.
```

---

## Memory in Aurora

### shared_buffers

Aurora uses shared_buffers the same way as standard PostgreSQL - it is an in-memory cache of data pages. The default on Aurora is approximately 75% of the instance's RAM divided by 8KB per page.

However, Aurora has an important difference: because there are no checkpoint flushes, dirty pages in shared_buffers can stay dirty longer. The buffer manager evicts pages using a clock-sweep algorithm, and evicted dirty pages generate WAL records to the storage layer.

**Rule of thumb for Aurora:** Leave shared_buffers at the default (which RDS sets automatically based on instance size). Do not increase it beyond 40% of RAM.

### Aurora Tiered Cache (Optimized Reads)

On instance families with local NVMe storage (r6gd, r7gd), Aurora can use the NVMe as a second-tier cache:

```
Memory hierarchy on Aurora with Optimized Reads:

Tier 1: shared_buffers (RAM)
    - Size: ~25% of instance RAM
    - Latency: microseconds
    - Managed by: PostgreSQL buffer manager

Tier 2: NVMe local SSD (tiered cache)
    - Size: up to 3-4x the size of RAM
    - Latency: ~0.1ms
    - Managed by: Aurora storage engine

Tier 3: Aurora distributed storage
    - Size: unlimited (up to 128 TB)
    - Latency: 1-3ms
    - Managed by: Aurora storage layer
```

When a page is evicted from shared_buffers, it can be stored in the NVMe tier. The next time it is needed, it comes from NVMe (~0.1ms) instead of distributed storage (~1-3ms). This is a 10-30x latency improvement for cache misses.

**Enable tiered cache:**
```
aurora_tiered_cache_enabled = 1  (parameter group)
```

No instance restart is required.

### work_mem

work_mem behaves identically to standard PostgreSQL. Each sort or hash operation uses up to work_mem of RAM. Excess spills to temporary files.

**On Aurora without NVMe instances:** Temp files go to Aurora's local storage, which uses EBS. Temp file I/O competes with other operations.

**On Aurora with NVMe instances (Optimized Reads):** Temp files go to the local NVMe SSD. This is 10-100x faster than EBS for sequential I/O. Queries that spill to disk see significant improvement.

### effective_cache_size

On Aurora, set effective_cache_size to approximately 75% of instance RAM. This is a planner hint, not a memory allocation. It tells the query planner how much data it can expect to find cached. A higher value makes the planner more likely to choose index scans over sequential scans.

---

## CPU in Aurora

### vCPU and DB Load

Each Aurora instance has a fixed number of vCPUs based on the instance class:

| Instance Class | vCPUs | RAM |
|----------------|-------|-----|
| db.r6g.large | 2 | 16 GB |
| db.r6g.xlarge | 4 | 32 GB |
| db.r6g.2xlarge | 8 | 64 GB |
| db.r6g.4xlarge | 16 | 128 GB |
| db.r6g.8xlarge | 32 | 256 GB |
| db.r6g.16xlarge | 64 | 512 GB |

The vCPU count is the maximum number of queries that can execute simultaneously on CPU. Performance Insights uses this as the "DB Load" target line. When DB Load exceeds vCPU count, queries are queuing.

### CPU-Bound vs I/O-Bound Workloads

```
CPU-bound workload:
  - DB Load above vCPU line
  - Dominant "wait" is CPU (meaning sessions are active on CPU)
  - Performance Insights shows no specific wait event
  - Cause: complex calculations, large aggregations, missing indexes
  - Fix: add indexes, optimize queries, scale up instance

I/O-bound workload:
  - DB Load may or may not exceed vCPU line
  - Dominant wait is IO:DataFileRead, IO:WALWrite, or IO:BufFileRead
  - Cause: cache misses, large sequential scans, temp file spills
  - Fix: increase shared_buffers, add indexes, use Optimized Reads
```

### Aurora-Specific CPU Considerations

1. **No checkpoint CPU spikes** - Standard PostgreSQL uses significant CPU during checkpoints (sorting dirty buffers, writing them, fsync). Aurora eliminates this.

2. **Replication is handled by storage** - In standard PostgreSQL, the primary sends WAL to replicas, which replay it. This uses CPU on both primary and replicas. In Aurora, replication is handled at the storage layer. Readers access the same storage - they do not replay WAL. This means Aurora readers use less CPU for replication than standard PostgreSQL replicas.

3. **Crash recovery is instant** - Standard PostgreSQL replays WAL on startup after a crash. Aurora's storage layer already has the data applied, so crash recovery is nearly instant (typically under 30 seconds).

---

## Network in Aurora

### Compute-to-Storage Network

All data exchange between the Aurora instance and storage goes over the network. This means network bandwidth is a critical resource.

Aurora instances have dedicated network bandwidth to storage that scales with instance size:

```
Instance size     Network to storage
db.r6g.large      Up to 10 Gbps
db.r6g.xlarge     Up to 10 Gbps
db.r6g.2xlarge    Up to 10 Gbps
db.r6g.4xlarge    Up to 10 Gbps
db.r6g.8xlarge    10 Gbps
db.r6g.16xlarge   25 Gbps
```

**When network becomes a bottleneck:** If your write throughput or read cache-miss rate is high enough to saturate the network, you will see increased read latency and write latency. This is visible in CloudWatch as `ReadLatency` and `WriteLatency` increasing together.

### Replication Network

Aurora readers connect to the same storage layer as the writer. There is no WAL streaming between writer and readers. Instead, when the writer sends WAL to storage, the storage layer notifies readers that new data is available. Readers invalidate their cached pages and fetch the new version on next access.

```
Standard PostgreSQL replication:
  Primary --WAL stream--> Replica (replay WAL on replica)
  Lag = time to send + time to replay

Aurora replication:
  Writer --WAL--> Storage Layer --invalidation--> Reader
  Reader fetches new pages on next access
  Lag = typically < 20ms (sometimes < 10ms)
```

Aurora replica lag is much lower than standard PostgreSQL because there is no WAL replay. The lag is just the time for the storage layer to propagate invalidations.

---

## Performance Comparison Summary

| Aspect | Standard RDS PostgreSQL | Aurora PostgreSQL |
|--------|------------------------|-------------------|
| Write path | WAL + data pages to EBS | WAL only to storage layer |
| Read cache miss | EBS read (0.5-2ms) | Storage layer read (1-3ms) |
| Checkpoints | Periodic flushes cause I/O spikes | No checkpoints |
| Crash recovery | WAL replay (minutes to hours) | Near-instant (< 30 seconds) |
| Replica lag | Seconds to minutes | Typically < 20ms |
| Storage limit | 64 TB (EBS) | 128 TB |
| Connection limit | Instance RAM dependent | Instance RAM dependent |
| VACUUM I/O | Reads and writes data pages | Reads pages, storage reclaims |
| Temp files | On EBS | On EBS (or NVMe with Optimized Reads) |
| I/O pricing | EBS IOPS provisioned | Per-I/O or I/O-Optimized flat rate |

---

## When Aurora Performs Better Than RDS

- **Write-heavy workloads** - Less write amplification, no checkpoint I/O spikes
- **Read replica-heavy architectures** - Near-zero replica lag, no WAL replay CPU
- **Large databases (> 10 TB)** - Storage scales automatically, no EBS volume management
- **High availability requirements** - Faster failover (30s vs 60-120s), automatic storage repair

## When Standard RDS May Perform Better

- **Single small database** - Aurora has a minimum storage charge and higher per-hour compute cost
- **Consistent low-latency reads** - Local NVMe on RDS (db.r6gd) can be faster than Aurora storage for some read patterns
- **Workloads that fit entirely in RAM** - If your entire dataset fits in shared_buffers, Aurora's storage advantages do not matter

---

## Key Metrics to Watch on Aurora

| Metric | What It Tells You | Aurora-Specific Notes |
|--------|-------------------|----------------------|
| CPUUtilization | Compute saturation | No checkpoint spikes |
| DatabaseConnections | Connection count | Same as RDS |
| FreeableMemory | Available RAM | Includes reclaimable cache |
| ReadLatency | Storage read time | Measures network to storage layer |
| WriteLatency | WAL commit time | Measures WAL send to storage |
| ReadIOPS / WriteIOPS | Storage operations | Affects I/O cost in Standard mode |
| AuroraReplicaLag | Reader lag in ms | Should be < 20ms normally |
| VolumeReadIOPs | Storage layer reads | Aurora-specific metric |
| VolumeBytesUsed | Total storage used | Aurora-specific metric |
| BufferCacheHitRatio | shared_buffers hit rate | Aurora-specific, should be > 99% |
| CommitLatency | Average commit time | Aurora-specific, measures 4/6 quorum write |
| CommitThroughput | Commits per second | Aurora-specific |
