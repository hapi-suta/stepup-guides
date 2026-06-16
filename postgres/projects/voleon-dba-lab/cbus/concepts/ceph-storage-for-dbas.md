# Ceph Storage for DBAs

## What Is Ceph

Ceph is an open-source, self-managed distributed storage system. It stores data across a cluster of commodity servers (or purpose-built storage nodes), provides redundancy automatically, and presents that storage through multiple interfaces: block devices, filesystems, and object storage.

The key idea is that there is no single storage controller. Every node in the cluster is equal. This eliminates single points of failure and allows horizontal scaling - you add more nodes to get more capacity and more bandwidth.

---

## Core Components

### RADOS - The Foundation

RADOS (Reliable Autonomic Distributed Object Store) is the storage engine underneath everything in Ceph. All data - whether stored as a block device, file, or object - gets broken into objects and stored in RADOS. You never interact with RADOS directly, but it is the layer that handles replication, healing, and distribution.

### OSD - Object Storage Daemon

An OSD runs on each disk (or per storage node). It stores data objects, participates in replication, and reports its health to the monitors. When you write a 1GB database page, RADOS breaks it into objects and spreads them across OSDs according to the CRUSH map.

A typical Ceph cluster has dozens to hundreds of OSDs.

### MON - Monitor

Monitors maintain the cluster map: the CRUSH map (which OSD holds which data), the OSD map (which OSDs are up/down), and the cluster state. Clients and OSDs talk to monitors to get current maps before performing I/O.

You need an odd number of monitors (3 or 5) for quorum. If monitors lose quorum, I/O halts - the entire cluster becomes unavailable. This is the highest-severity failure mode for a DBA to understand.

### MDS - Metadata Server

MDS is only needed for CephFS (the filesystem interface). It handles directory structure, permissions, and metadata. For RBD block storage (what databases use), MDS is not involved.

---

## RBD - RADOS Block Device

RBD is how databases consume Ceph storage. It presents a virtual block device - it looks exactly like a physical disk to the operating system. The DBA formats it with ext4 or XFS, mounts it, and points PostgreSQL's data directory at it.

### How It Works Under the Hood

1. The administrator creates an RBD image: `rbd create --size 500G pg-data-vol --pool ssd-pool`
2. The image is mapped to the OS: `rbd map ssd-pool/pg-data-vol` - this creates `/dev/rbd0`
3. Format with XFS: `mkfs.xfs /dev/rbd0`
4. Mount it: `mount /dev/rbd0 /pgdata`
5. PostgreSQL's `data_directory` points to `/pgdata`

From PostgreSQL's perspective, `/pgdata` is just a directory on a disk. It has no idea the disk is distributed across 20 storage nodes.

### Replication

By default, Ceph replicates data 3x across OSDs. Every write must be acknowledged by all replica OSDs before it is considered committed (depending on the pool configuration). This means a single write to PostgreSQL results in multiple writes inside Ceph across multiple physical nodes.

This replication is what makes Ceph safe - you can lose a node, an OSD, or even an entire rack (with proper CRUSH rules) without data loss.

### Thin Provisioning

RBD images are thin provisioned by default. A 1TB RBD image that only has 100GB of data written to it only consumes 100GB of physical space in the cluster. This allows overcommitting storage - useful for dev/test instances.

Production databases should account for actual usage, not provisioned size, in capacity planning.

### Snapshots

RBD supports copy-on-write snapshots at the block level. A snapshot is taken in milliseconds and captures the state of the entire volume at that instant. This is extremely valuable for database backups:

```bash
# freeze I/O at the database level (PostgreSQL)
psql -c "SELECT pg_start_backup('ceph-snap-$(date +%F)');"

# take the snapshot
rbd snap create ssd-pool/pg-data-vol@2025-06-15

# resume I/O
psql -c "SELECT pg_stop_backup();"
```

The snapshot can then be cloned or exported to object storage for offsite retention.

---

## Performance Characteristics

### Latency Comparison

| Storage Type      | Write Latency (fsync) | Notes                                      |
|-------------------|-----------------------|--------------------------------------------|
| Local NVMe        | 0.05 - 0.1ms          | Best possible, no network hop              |
| Local SSD (SATA)  | 0.1 - 0.5ms           | Good for most workloads                    |
| Ceph RBD (NVMe OSDs, 100Gbps) | 1 - 2ms | Network adds latency even on fast fabric   |
| Ceph RBD (HDD OSDs) | 5 - 15ms           | HDD seek time dominates                    |
| EBS gp3 (AWS)     | 1 - 3ms               | Similar to Ceph RBD                        |
| EBS io2 (provisioned IOPS) | 0.5 - 1ms   | Better, but expensive                      |
| NFS/NAS           | 1 - 10ms              | Highly variable, avoid for primary data    |

The key takeaway: Ceph RBD adds 1-5ms of latency compared to local storage. For PostgreSQL, this matters most for:
- WAL commits (`fsync` of WAL files)
- Checkpoint writes (bulk page writes)
- `pg_stat_bgwriter`: watch for slow checkpoints

### Throughput

On a 100Gbps network with NVMe OSDs, Ceph RBD can deliver:
- Sequential read: 5-10 GB/s (limited by network or OSD count)
- Sequential write: 2-5 GB/s (replication overhead reduces write throughput)
- Random IOPS: 50,000-200,000+ depending on OSD count and pool configuration

For most database workloads, the throughput is not the limiting factor. Latency is.

---

## Impact on PostgreSQL Specifically

### WAL Write Latency

PostgreSQL writes WAL synchronously on every transaction commit (when `synchronous_commit = on`). Each commit calls `fsync()` on the WAL file. On local NVMe, this is 0.1ms. On Ceph RBD, this is 1-3ms.

If your application commits 1,000 transactions per second, each one waiting 2ms, the WAL becomes a bottleneck. Solutions:
- Use `wal_buffers` generously (64MB) to batch WAL writes
- Consider `synchronous_commit = local` for workloads where slight data loss risk is acceptable
- Use `commit_delay` and `commit_siblings` to batch commits
- Use `group commit` patterns in the application (batch multiple rows per transaction)

### Checkpoint I/O Patterns

PostgreSQL periodically writes dirty pages from shared_buffers to disk (checkpoints). On Ceph RBD, checkpoint I/O follows the same network path as regular I/O, but the volume is much higher - potentially hundreds of MB per checkpoint.

`checkpoint_completion_target = 0.9` (default is 0.5) spreads checkpoint writes over 90% of the checkpoint interval, reducing peak I/O bursts. This is even more important on Ceph RBD where burst I/O causes more latency variance.

### fsync Behavior

PostgreSQL relies on `fsync()` guaranteeing that data is on durable storage. With Ceph RBD, `fsync()` must traverse the network and be acknowledged by replica OSDs before returning. This is safe (data is durable) but slower than local storage.

Never set `fsync = off` on a production PostgreSQL instance, regardless of storage type. The durability guarantee is fundamental.

### Recommended PostgreSQL Settings for Ceph RBD

```ini
# WAL settings
wal_buffers = 64MB                  # larger buffer reduces individual fsyncs
checkpoint_completion_target = 0.9  # spread I/O over more time
checkpoint_timeout = 15min          # allow longer between checkpoints

# Memory
shared_buffers = 25% of RAM         # standard, cache more to reduce I/O
effective_cache_size = 75% of RAM

# I/O tuning
random_page_cost = 2.0              # lower than default 4.0 - Ceph has no seek time
effective_io_concurrency = 200      # Ceph handles parallel I/O well

# Consider for write-heavy workloads where some data loss is tolerable
# synchronous_commit = local        # DO NOT set this without understanding the tradeoff
```

---

## Our Lab Simulation

The cbus lab does not have a real Ceph cluster. Instead, we simulate the I/O indirection using a loopback device and LVM:

1. A file on the host filesystem acts as a block device: `losetup /dev/loop0 /tmp/ceph-sim.img`
2. LVM creates a logical volume on top of it: `lvcreate -L 2G -n pg-data vg-ceph`
3. PostgreSQL uses that logical volume as its data directory

This simulates the key DBA-relevant behavior:
- I/O indirection (writes go through an abstraction layer, not directly to bare metal)
- LVM snapshot capability (simulating Ceph RBD snapshots)
- Separate volume management from the OS disk
- Ability to resize, snapshot, and restore the volume independently

The latency characteristics are different (loopback is actually faster than Ceph in this case), but the operational workflows - volume management, snapshots, monitoring - are directly transferable.

---

## Comparison with Other Storage Options

| Storage         | Latency   | Throughput   | HA Built-in | Snapshot | Best For                        |
|-----------------|-----------|--------------|-------------|----------|---------------------------------|
| Local NVMe      | 0.1ms     | 10+ GB/s     | No          | LVM      | Production primary, highest perf|
| Ceph RBD        | 1-5ms     | 5-10 GB/s    | Yes (3x rep)| Yes      | VMs, K8s, distributed workloads |
| Lustre          | 0.5-2ms   | 100+ GB/s    | Yes         | Limited  | HPC parallel reads/writes       |
| GPFS            | 0.5-2ms   | 100+ GB/s    | Yes         | Yes      | HPC, financial data lake        |
| EBS gp3 (AWS)   | 1-3ms     | 1 GB/s       | Yes         | Yes      | Cloud primary (moderate perf)   |
| SAN (Fibre Ch.) | 0.1-0.5ms | 4-16 GB/s    | Yes         | Yes      | Enterprise on-prem, legacy      |
| NFS/NAS         | 1-10ms    | 1-5 GB/s     | Varies      | Limited  | Shared reads, never PG primary  |

---

## Ceph Maintenance Operations DBAs Should Know

### OSD Rebalancing

When an OSD is added, removed, or fails, Ceph moves data around to maintain the replication factor and CRUSH distribution. This rebalancing generates heavy background I/O across the cluster.

**Impact on databases:** During rebalancing, storage latency increases. Checkpoints take longer. WAL commits slow down. Replication lag on PostgreSQL standbys may increase.

**What to do:** Coordinate with the storage team. Ask for `recovery_op_priority` to be lowered during business hours. Monitor `pg_stat_replication.write_lag` during Ceph rebalancing events.

### OSD Recovery

When an OSD comes back up after a failure, it receives a backfill of all objects it missed. Similar to rebalancing in terms of I/O impact.

### CRUSH Maps

The CRUSH (Controlled Replication Under Scalable Hashing) map defines how data is distributed across OSDs. A well-designed CRUSH map ensures:
- Replicas land on different physical nodes (not just different OSDs on the same node)
- Replicas land in different racks or failure domains (for rack-level failure tolerance)
- The primary OSD for database volumes is on the fastest OSDs (NVMe, not HDD)

DBAs should review CRUSH rules when a new Ceph pool is created for a database volume. Ask the storage team: "Are all three replicas for this pool on separate physical nodes in separate racks?"

### Pool Configuration

Ceph pools have configurable replication factor and minimum_size (minimum replicas required for I/O to proceed):

```bash
ceph osd pool get ssd-pool size          # replication factor (e.g., 3)
ceph osd pool get ssd-pool min_size      # minimum for I/O (e.g., 2)
```

If `min_size` replicas are unavailable (e.g., 2 out of 3 are down), the pool goes into a degraded state and I/O is blocked. PostgreSQL will hang at this point. This is the Ceph equivalent of a storage array going offline.

### Monitoring Ceph Health

```bash
ceph health detail       # current health status
ceph osd stat            # OSD count and status
ceph df                  # pool usage
ceph pg stat             # placement group status
rbd info ssd-pool/pg-data-vol  # info about a specific RBD image
```

An on-call DBA should know these commands and understand what `HEALTH_WARN` vs `HEALTH_ERR` means for database availability.
