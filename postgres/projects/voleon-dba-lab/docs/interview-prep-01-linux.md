# Interview Prep - Linux & Systems Fundamentals

- **Date:** Monday, June 22, 2026, 6:00-7:00 PM EDT
- **Interviewer:** Lukasz Mucha, Senior DevOps Engineer - The Voleon Group
- **Format:** 1 hour Zoom
- **You:** Happy Afopezi, Lead DBA (10+ years, 20+ companies, 15,000+ databases)

---

## 1. What Lukasz Will Likely Focus On

Lukasz is a Senior DevOps Engineer, not a DBA. He does not care how well you write SQL. He wants to know:

- **Can you operate at the OS level?** He manages the infrastructure PostgreSQL runs on. He needs a DBA who speaks his language - processes, memory, I/O, kernel parameters - not just `pg_stat_activity`.
- **Can you troubleshoot a sick Linux box?** Expect scenario-based questions. "The database is slow" means "walk me through the OS-level diagnosis before you even open psql."
- **Do you understand the storage stack?** Voleon runs PostgreSQL on Ceph RBD. He will probe whether you understand the I/O path from PostgreSQL's `fsync()` call down through the kernel, block device, and into Ceph.
- **Can you work with infrastructure tooling?** systemd, containers, kernel tuning, networking. He wants a DBA who can read a Kubernetes pod spec and not panic.
- **Are you safe to hand root access to?** He needs to trust that you won't blindly run commands from Stack Overflow on a production box.

**Key areas to expect:** process management, memory (shared memory, hugepages, OOM), I/O subsystem, filesystem choices, networking between nodes, systemd service management, kernel tuning (sysctl), and capacity planning.

---

## 2. Top 15 Questions and Answer Outlines

### Q1: "Walk me through diagnosing high I/O wait on a database server"

- Start with `top` or `vmstat 1` - look at `%wa` column to confirm I/O wait
- Use `iostat -xz 1` to identify which device is saturated (`%util`, `await`, `avgqu-sz`)
- Use `iotop -aoP` to find which PID is generating the I/O
- Correlate PID back to PostgreSQL - is it a checkpoint, vacuum, a runaway query, or WAL write?
- Check if the underlying storage (Ceph RBD in Voleon's case) is the bottleneck vs. local saturation

### Q2: "How do you tune Linux kernel parameters for PostgreSQL?"

- `vm.dirty_ratio` / `vm.dirty_background_ratio` - control when the kernel flushes dirty pages; lower background ratio spreads writes out, avoids flush storms during checkpoints
- `vm.overcommit_memory = 2` with appropriate `vm.overcommit_ratio` - prevents the kernel from overcommitting memory and OOM-killing PostgreSQL
- `vm.swappiness = 1` - minimize swap usage but don't disable it entirely (OOM killer gets aggressive with 0)
- `kernel.shmmax` / `kernel.shmall` - shared memory limits for PostgreSQL's shared buffers
- `vm.zone_reclaim_mode = 0` on NUMA systems - prevents the kernel from reclaiming memory from local zones before using remote ones

### Q3: "Explain how memory management works on Linux and how PostgreSQL uses it"

- Linux uses virtual memory with page tables mapping virtual addresses to physical pages (4KB default)
- PostgreSQL allocates shared memory at startup (shared_buffers) - this is a System V or POSIX shared memory segment visible to all backends
- Each backend also has private memory (work_mem, maintenance_work_mem, temp_buffers) allocated per-operation
- The kernel's page cache sits between PostgreSQL and disk - PostgreSQL does buffered I/O by default, so data exists in both shared_buffers and page cache (double buffering)
- `free -h` output: "available" is the real number, not "free" - the kernel will reclaim page cache under pressure

### Q4: "What happens when a process gets OOM-killed? How do you prevent it for PostgreSQL?"

- OOM killer activates when the system runs out of physical memory and swap; it scores processes by memory consumption and kills the highest-scored one
- If the postmaster gets killed, all connections drop. If a backend gets killed, the postmaster restarts all backends (brief outage either way)
- Prevention: set `vm.overcommit_memory = 2`, tune `vm.overcommit_ratio` so the kernel refuses allocations it can't back
- Set `oom_score_adj = -1000` for the postmaster process (via systemd unit file `OOMScoreAdjust=-1000`)
- Right-size `shared_buffers` (typically 25% of RAM) and cap `max_connections` to limit total backend memory

### Q5: "How do you troubleshoot network connectivity issues between database nodes?"

- Layer 1-3 first: `ping`, `traceroute`, check `ip a` and `ip route` for correct interface/route
- Layer 4: `ss -tlnp` to verify PostgreSQL is listening on the expected port and interface, not just localhost
- Test the specific port: `nc -zv <host> 5432` or `pg_isready -h <host>`
- Check firewalls: `iptables -L -n` / `nft list ruleset` / security groups if cloud
- For replication issues, check `pg_stat_replication` and correlate with network latency (`ping -c 100` and look at jitter) - on a 100Gbps fabric like Voleon's, latency should be sub-millisecond

### Q6: "Explain the PostgreSQL process model - what processes do you see and what do they do?"

- **postmaster** - parent process, listens for connections, forks backends
- **backend** - one per client connection, handles query parsing, planning, execution
- **background writer** - writes dirty shared buffers to disk gradually to keep free buffers available
- **checkpointer** - periodic full flush of dirty buffers to disk, ensures crash recovery point
- **WAL writer** - flushes WAL buffers to disk; `walwriter` process handles async commits
- **autovacuum launcher + workers** - reclaims dead tuples, updates statistics, prevents wraparound
- **stats collector** (pre-15) / stats subsystem (15+) - aggregates activity statistics
- Use `ps auxf | grep postgres` to see the process tree; each process has a descriptive title

### Q7: "How does storage I/O path work with Ceph RBD?"

- PostgreSQL calls `write()` and `fsync()` - these go into the kernel's VFS layer
- The kernel writes to the block device, which for Ceph RBD is `/dev/rbdN` - a virtual block device backed by the `rbd` kernel module
- The rbd module sends I/O over the network to Ceph OSDs using the CRUSH algorithm to determine placement
- Ceph replicates writes to N OSDs before acknowledging - this adds latency to every `fsync()` (WAL commits)
- Impact: WAL write latency is now network-bound, not disk-bound. `wal_sync_method`, `commit_delay`, and group commit behavior become critical tuning points
- Monitor with `ceph osd perf` and `rbd perf image iostat` alongside Linux-level `iostat`

### Q8: "What filesystem do you use for PostgreSQL and why?"

- **ext4** - reliable default, well-tested with PostgreSQL, good performance with `data=ordered` journaling
- **XFS** - better for large files, parallel I/O on multi-core, handles large `shared_buffers` well, default on RHEL/CentOS
- Both support `O_DIRECT` and reliable `fsync()` - the two things PostgreSQL cares about most
- Avoid ZFS/Btrfs in production unless you deeply understand the copy-on-write implications with PostgreSQL's own WAL
- Mount options matter: `noatime`, `nobarrier` only if hardware RAID with BBU (never on Ceph - barriers are essential)

### Q9: "How do you manage services with systemd?"

- PostgreSQL ships a systemd unit file; `systemctl start/stop/restart/reload postgresql-16`
- `reload` sends SIGHUP (re-reads postgresql.conf without downtime); `restart` is a full stop/start
- Customize via drop-in overrides: `systemctl edit postgresql-16` creates `/etc/systemd/system/postgresql-16.service.d/override.conf`
- Key overrides: `OOMScoreAdjust=-1000`, `LimitNOFILE=65536`, `TimeoutStartSec=300` for large recovery
- `journalctl -u postgresql-16 -f` for live log tailing; `systemctl status` for quick health check
- `systemctl enable` for boot persistence, `systemctl is-failed` for monitoring integration

### Q10: "What's your approach to SELinux in a database environment?"

- Never disable SELinux in production - set it to enforcing with proper policies
- PostgreSQL has well-maintained SELinux policies in RHEL/CentOS (`semanage`, `restorecon`)
- Common issue: custom data directories or tablespace paths need `postgresql_db_t` context
- Use `audit2allow` to analyze denials in `/var/log/audit/audit.log` and create targeted policy modules
- If a migration or config change breaks things, temporarily set to permissive (`setenforce 0`), fix the policy, then re-enable - never leave it off

### Q11: "How do you size memory for a PostgreSQL server?"

- **shared_buffers:** start at 25% of total RAM, cap around 32-64GB (diminishing returns beyond that due to double buffering with page cache)
- **effective_cache_size:** ~75% of total RAM (tells the planner how much cache to expect, doesn't allocate anything)
- **work_mem:** total exposure = `work_mem x max_connections x sort_nodes_per_query`; start conservative (32-64MB), increase for analytical workloads
- **maintenance_work_mem:** 1-2GB for vacuum/index builds; higher = faster maintenance
- Leave ~25% of RAM free for the OS page cache, OS overhead, and other processes
- On a 256GB server: shared_buffers=64GB, effective_cache_size=192GB, work_mem=64MB, maintenance_work_mem=2GB

### Q12: "Explain hugepages and why they matter for databases"

- Default Linux page size is 4KB; page tables for 64GB of shared_buffers = millions of entries consuming GBs of non-swappable kernel memory
- Hugepages (2MB or 1GB) reduce page table entries by 512x or more, reducing TLB misses and page table overhead
- Calculate: `shared_buffers (bytes) / hugepage_size + small_buffer` - set `vm.nr_hugepages` in sysctl
- PostgreSQL 11+ has `huge_pages = try` (default) or `on` (fail if unavailable)
- Hugepages are pinned in memory (never swapped), which also protects shared_buffers from swap pressure
- Check allocation: `grep -i huge /proc/meminfo`

### Q13: "Walk me through what happens at the OS level when PostgreSQL does a checkpoint"

- The checkpointer process iterates through all dirty buffers in shared memory
- For each dirty buffer, it calls `write()` - this copies data from userspace to the kernel page cache (may or may not trigger immediate disk I/O depending on dirty ratios)
- After writing all dirty buffers, the checkpointer calls `fsync()` on each file that was written - this forces the kernel to flush page cache to persistent storage
- During this time, `iostat` will show elevated write throughput and increased `%util` on the data device
- `vm.dirty_background_ratio` controls when the kernel starts flushing in the background; spreading writes out prevents the "checkpoint spike" pattern
- `checkpoint_completion_target` (0.9 default) spreads PostgreSQL's writes across the checkpoint interval

### Q14: "How do you debug a process that's consuming too much CPU?"

- `top -p <PID>` or `pidstat -p <PID> 1` to confirm CPU usage and whether it's user or system time
- High user time: the process is doing computation - for PostgreSQL, likely a bad query plan (hash join on huge table, sort without index)
- High system time: excessive syscalls - use `strace -cp <PID>` to count syscalls, look for tight loops of `read()`/`write()` or `lseek()`
- `perf top -p <PID>` for CPU profiling - shows which functions are hot (e.g., `_bt_compare` = index scan thrashing)
- Correlate PID to PostgreSQL query: `SELECT pid, query FROM pg_stat_activity WHERE pid = <PID>`

### Q15: "Describe your approach to capacity planning at the OS level"

- **CPU:** track `%idle` over time, plan for growth; PostgreSQL scales well to ~48 cores before lock contention matters
- **Memory:** monitor `pg_stat_bgwriter` (buffers_alloc vs buffers_backend) - if backends are allocating buffers instead of finding them in cache, you need more RAM
- **Storage:** track IOPS and throughput (not just space) - WAL volume drives IOPS needs; use `pg_stat_wal` (PG14+) to project WAL generation rate
- **Connections:** each backend consumes ~5-10MB base; at 500+ connections, consider pgbouncer to reduce memory footprint
- Build capacity models from actual metrics (Prometheus/Grafana), not guesses - project 6-12 months out with growth curves

---

## 3. "Tell Me About a Time..." Stories

### Story 1: Production Incident - OOM Killer Took Out a Primary

**Situation:** A client's primary PostgreSQL server went down during business hours. All connections dropped. The monitoring system showed the postmaster process disappeared.

**Task:** Identify root cause and restore service, then prevent recurrence.

**Action:** Checked `dmesg` and found the OOM killer had targeted the postmaster. The server had `vm.overcommit_memory = 0` (default) and an analytics team had started running heavy `work_mem`-intensive queries that blew past physical memory. I restarted PostgreSQL, then immediately set `vm.overcommit_memory = 2`, tuned `overcommit_ratio` to 80, added `OOMScoreAdjust=-1000` to the systemd unit, and reduced `work_mem` from 512MB to 64MB while routing analytical queries through pgbouncer with a separate pool.

**Result:** Zero OOM incidents since. Added kernel parameter audits to the onboarding checklist for all new database servers.

### Story 2: Performance Optimization - Checkpoint Spikes on a High-Write System

**Situation:** A client's PostgreSQL instance serving a real-time data pipeline had periodic 10-second latency spikes every 5 minutes. Application team blamed "the database."

**Task:** Identify and eliminate the periodic latency spikes.

**Action:** Ran `iostat -xz 1` during the spike window and saw the data volume hitting 100% utilization for ~8 seconds every 5 minutes - perfectly aligned with `checkpoint_timeout`. The server had `vm.dirty_ratio = 20` (default) and `vm.dirty_background_ratio = 10` (default), causing the kernel to hold dirty pages until the checkpoint's `fsync()` storm flushed them all at once. Tuned `dirty_background_ratio` to 3 and `dirty_ratio` to 10, increased `checkpoint_completion_target` to 0.9, spread `max_wal_size` wider, and configured hugepages to reduce TLB pressure during the flush.

**Result:** Write latency spikes dropped from 10 seconds to under 200ms. The application team's p99 latency improved by 40x during checkpoint windows.

### Story 3: Capacity Planning - Migrating 200+ Databases Off a Dying SAN

**Situation:** A client's SAN was end-of-life with no vendor support. It hosted 200+ PostgreSQL databases across 15 servers. The replacement hardware had a different I/O profile (NVMe vs spinning disk).

**Task:** Plan and execute the migration without downtime, ensuring the new storage could handle the aggregate workload.

**Action:** Profiled every server with `iostat`, `sar`, and `pg_stat_wal` for two weeks to capture peak and baseline I/O patterns. Built a capacity model mapping each database's IOPS and throughput needs to the new NVMe topology. Used `pg_basebackup` with streaming replication to pre-stage data, then did controlled switchovers during maintenance windows - 10 servers per weekend. Validated each cutover with synthetic load testing using `pgbench` calibrated to the production I/O profile.

**Result:** All 200+ databases migrated over 3 weekends with zero unplanned downtime. I/O latency improved 5x on the new storage, and the capacity model identified 3 servers that could be consolidated, saving the client $18K/year in licensing.

---

## 4. Questions to Ask Lukasz

1. **Infrastructure challenges:** "PostgreSQL on Ceph RBD is an interesting architecture choice. What were the biggest operational challenges you hit with WAL write latency, and how did you tune around them?"

2. **Team structure:** "How is the boundary drawn between what DevOps owns and what the DBA owns? For example, if a Ceph OSD fails and it impacts database performance, who responds first?"

3. **On-call expectations:** "What does on-call look like for this role? Is the DBA paged for OS-level issues on database hosts, or only for PostgreSQL-specific alerts?"

4. **Storage strategy:** "Are you running one RBD image per PostgreSQL instance, or do you separate WAL and data onto different RBD images or pools for I/O isolation?"

5. **Container strategy:** "Are your production PostgreSQL instances running in Kubernetes pods, or bare metal / VMs with Ceph RBD mapped directly? What drove that decision?"

---

## 5. Quick Command Cheat Sheet

### Process Management
```
ps auxf | grep postgres          # Process tree with hierarchy
top -c -p $(pgrep -d, postgres)  # Monitor only PostgreSQL processes
pidstat -p <PID> 1               # Per-process CPU/IO stats every second
strace -cp <PID>                 # Syscall summary for a process
kill -HUP <postmaster_PID>       # Reload config (same as pg_reload_conf())
pgrep -a postgres                # List all PostgreSQL processes with args
```

### Memory
```
free -h                          # Memory overview (check "available")
cat /proc/meminfo                # Detailed memory breakdown
grep -i huge /proc/meminfo       # Hugepage allocation status
slabtop                          # Kernel slab cache usage
pmap -x <PID>                    # Memory map of a specific process
ipcs -m                          # Shared memory segments (shared_buffers)
cat /proc/<PID>/oom_score_adj    # OOM killer score adjustment
```

### Storage & I/O
```
iostat -xz 1                     # Device I/O stats every second
iotop -aoP                       # I/O by process (accumulated)
lsblk -f                         # Block devices with filesystem info
df -hT                           # Filesystem usage with type
mount | grep <device>            # Mount options for a device
hdparm -Tt /dev/sdX              # Quick disk benchmark (read)
blktrace -d /dev/rbdN -o-        # Block-level I/O tracing (Ceph RBD)
```

### Network
```
ss -tlnp                         # Listening TCP sockets with process
ss -tnp | grep 5432              # Active PostgreSQL connections
ip a                             # Interface addresses
ip route                         # Routing table
ping -c 5 <replica_host>         # Basic connectivity + latency
nc -zv <host> 5432               # Test PostgreSQL port connectivity
ethtool <iface>                  # NIC speed/duplex (check 100Gbps)
```

### Kernel Tuning
```
sysctl -a | grep vm.dirty        # Current dirty page settings
sysctl -a | grep vm.overcommit   # Overcommit settings
sysctl -a | grep vm.swappiness   # Swap tendency
sysctl -a | grep kernel.shm      # Shared memory limits
cat /proc/sys/vm/nr_hugepages    # Hugepage count
numactl --hardware               # NUMA topology
lscpu                            # CPU topology (sockets, cores, NUMA)
```

### systemd
```
systemctl status postgresql-16   # Service health + recent logs
systemctl edit postgresql-16     # Create drop-in override
journalctl -u postgresql-16 -f   # Tail logs
journalctl -u postgresql-16 --since "1 hour ago"
systemctl cat postgresql-16      # Show full unit file + overrides
systemctl list-dependencies postgresql-16  # Service dependency tree
```

---

## 6. Voleon-Specific Talking Points

### Ceph RBD I/O Path and WAL Fsync Latency

Every PostgreSQL commit calls `fsync()` on the WAL. With Ceph RBD, that `fsync()` travels: PostgreSQL userspace -> kernel VFS -> rbd kernel module -> network -> primary OSD -> replica OSDs -> ack back. On spinning disk Ceph clusters, this can add 2-5ms per commit. On all-NVMe Ceph with a 100Gbps fabric, you can get it under 500us. Key tuning: `synchronous_commit = on` (non-negotiable for durability), `commit_delay` to batch multiple commits into one fsync, and Ceph-side `bluestore_min_alloc_size` tuning.

### Container vs Bare Metal for Production Databases

You've run PostgreSQL both ways. Bare metal gives you direct NUMA control, hugepage pinning, and no cgroup overhead. Containers give you deployment consistency and easier orchestration. The right answer for Voleon likely depends on whether their Kubernetes scheduler can guarantee NUMA-aware placement and whether they can tolerate the ~2-5% overhead from cgroup memory accounting. Ask about their approach - this shows you think about the tradeoffs, not just one "right" answer.

### HPC (Slurm) Burst Patterns and Database Connections

Voleon runs Slurm HPC clusters for ML model training. When a large job dispatches across hundreds of nodes, those nodes may all hit the database simultaneously for feature data. This creates connection storms that can overwhelm `max_connections`. Talk about pgbouncer/pgcat for connection pooling, `idle_in_transaction_session_timeout` to reclaim abandoned connections, and the importance of separating OLTP (trading) from OLAP (model training) workloads - possibly with read replicas dedicated to the HPC cluster.

### 100Gbps Fabric and Synchronous Replication

On a typical 10Gbps network, synchronous replication adds 0.5-1ms per commit. On 100Gbps with RDMA-capable NICs, network latency drops to 10-50us, making synchronous replication nearly free. This means Voleon can run `synchronous_commit = remote_apply` (strongest guarantee) without meaningful performance impact. Mention that this changes the calculus on multi-node consistency - you can afford stronger durability guarantees that most shops avoid because of latency cost.

### NUMA Considerations for Database Servers

Modern servers have 2-4 NUMA nodes. If PostgreSQL's shared_buffers span NUMA nodes without proper interleaving, remote memory access adds ~100ns latency per access. Two approaches: (1) `numactl --interleave=all` when starting PostgreSQL to spread shared memory evenly, or (2) pin PostgreSQL to a single NUMA node if the instance fits. On Voleon's likely high-memory servers, approach 1 is standard. Check current status with `numastat -p <postmaster_PID>`. Mention `vm.zone_reclaim_mode = 0` to prevent the kernel from aggressively reclaiming local memory.

---

## Final Reminders

- Lead with OS-level thinking, not PostgreSQL internals. Lukasz wants a DBA who can `strace` a process, not one who only knows `EXPLAIN ANALYZE`.
- Use specific numbers from your experience. "I reduced checkpoint spikes from 10 seconds to 200ms" hits harder than "I tuned checkpoint parameters."
- Show curiosity about Ceph and Kubernetes. You don't need to be an expert - you need to show you'll collaborate with DevOps, not fight them.
- If you don't know something, say "I haven't worked with that directly, but here's how I'd approach it" and walk through your reasoning.
- Close strong. Your 15,000+ databases across 11 datacenters is a rare breadth of experience. Make sure Lukasz understands you've seen failure modes most DBAs only read about.
