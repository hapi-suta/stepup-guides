# Build Guide 09: Linux & Systems Fundamentals Mastery

| | |
|---|---|
| **Time** | 90 minutes |
| **Servers** | pg-primary (100.26.54.122), pg-replica (54.144.241.128), pg-container (34.228.73.232), pg-ops (34.228.32.17) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Lukasz Mucha - Senior DevOps Engineer, The Voleon Group |

## Why This Matters

At The Voleon Group, PostgreSQL runs on Linux servers that power AI/ML trading models. When a query slows down or a server misbehaves, Lukasz will expect you to dig into Linux-level diagnostics - not just SQL. A DBA who understands process trees, memory allocation, kernel tuning, and storage I/O can pinpoint problems that never show up in `pg_stat_activity`.

This guide walks you through every Linux skill a DBA needs, using your actual lab servers with live PostgreSQL processes.

## What You'll Learn

- How to inspect PostgreSQL processes and trace their system calls
- How Linux manages memory and how PostgreSQL interacts with it
- How to read disk and I/O metrics to find storage bottlenecks
- How to tune kernel parameters for PostgreSQL performance
- How systemd manages PostgreSQL services
- How to diagnose network issues affecting database connections
- How SELinux impacts PostgreSQL and how to troubleshoot it
- How to combine all of these skills in real troubleshooting scenarios

## Prerequisites

- Completed BUILD-01 through BUILD-08
- SSH key at `~/.ssh/id_ed25519` with access to all four servers
- PostgreSQL 17 running on pg-primary and pg-replica

---

## Section 1: Process Management for DBAs

PostgreSQL runs as a collection of cooperating processes. Understanding this process tree is fundamental to diagnosing performance issues and answering interview questions about PostgreSQL internals.

### Step 1.1: View the PostgreSQL Process Tree

On **pg-primary**, as **ec2-user**:

```bash
ps auxf | grep postgres
```

`ps` shows running processes. The `a` flag shows all users' processes, `u` adds the username column, `x` includes processes without a terminal, and `f` draws a tree showing parent-child relationships. We pipe through `grep postgres` to filter for only PostgreSQL-related processes.

Expected output (yours will differ):
```
postgres   1234  0.0  1.2 456789 12345 ?   Ss   Jun17   0:01 /usr/pgsql-17/bin/postmaster -D /var/lib/pgsql/17/data/
postgres   1240  0.0  0.1 456789  1234 ?   Ss   Jun17   0:00  \_ postgres: checkpointer
postgres   1241  0.0  0.1 456789  1234 ?   Ss   Jun17   0:00  \_ postgres: background writer
postgres   1243  0.0  0.1 456789  1234 ?   Ss   Jun17   0:02  \_ postgres: walwriter
postgres   1244  0.0  0.1 456789  1234 ?   Ss   Jun17   0:00  \_ postgres: autovacuum launcher
postgres   1245  0.0  0.1 456789  1234 ?   Ss   Jun17   0:00  \_ postgres: logical replication launcher
postgres   1250  0.0  0.2 456789  2345 ?   Ss   Jun17   0:05  \_ postgres: walsender ...
...
```

Here is what each background process does:

- **postmaster** - The main PostgreSQL process. It listens for new connections and spawns child processes. If this dies, the whole database goes down.
- **checkpointer** - Periodically writes dirty shared buffer pages to disk. This prevents the database from having to replay too much WAL on crash recovery.
- **background writer** (bgwriter) - Writes dirty pages to disk in small batches between checkpoints. This smooths out I/O so checkpoints are not giant spikes.
- **walwriter** - Flushes WAL (Write-Ahead Log) buffers to disk. Every committed transaction must have its WAL written to disk first - this is how PostgreSQL guarantees durability.
- **autovacuum launcher** - Spawns autovacuum worker processes that clean up dead rows and update table statistics. Without this, tables bloat and queries slow down.
- **logical replication launcher** - Manages logical replication workers if you have logical replication subscriptions.
- **walsender** - Sends WAL data to standby servers for streaming replication. You should see one of these because pg-replica is connected.

### Step 1.2: Watch a Specific PostgreSQL Process with top

On **pg-primary**, as **ec2-user**:

First, get the postmaster PID:

```bash
head -1 /var/lib/pgsql/17/data/postmaster.pid
```

This file is created by PostgreSQL at startup and its first line contains the postmaster's process ID.

Expected output (yours will differ):
```
1234
```

Now use that PID with `top`. Replace `1234` with your actual PID:

```bash
top -p 1234
```

`top` shows a live-updating view of system resource usage. The `-p` flag restricts it to a single process so you can watch its CPU and memory usage without noise from other processes.

Press `q` to exit top.

### Step 1.3: Trace walwriter System Calls with strace

On **pg-primary**, as **ec2-user**:

First, find the walwriter PID:

```bash
ps aux | grep "walwriter" | grep -v grep
```

The first `grep` finds the walwriter process. The second `grep -v grep` removes the grep command itself from the results.

Expected output (yours will differ):
```
postgres   1243  0.0  0.1 456789  1234 ?   Ss   Jun17   0:02 postgres: walwriter
```

Now trace its system calls. Replace `1243` with your actual walwriter PID:

```bash
sudo strace -p 1243 -e trace=write -c
```

`strace` attaches to a running process and records every system call it makes. The `-p` flag specifies the PID. The `-e trace=write` flag filters to only show `write` syscalls (when the process writes data to a file). The `-c` flag shows a summary count instead of printing every individual call.

Let it run for about 10 seconds, then press `Ctrl+C` to stop it.

Expected output (yours will differ):
```
strace: Process 1243 attached
^Cstrace: Process 1243 detached
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00    0.000234           4        52           write
------ ----------- ----------- --------- --------- ----------------
100.00    0.000234                    52           total
```

This tells you how many `write` calls the walwriter made and how long they took. In an interview, you might use this to prove that WAL writes are fast (microseconds per call) or to identify a slow disk.

### Step 1.4: See Who Is Connected to PostgreSQL

On **pg-primary**, as **ec2-user**:

```bash
sudo lsof -i :5432
```

`lsof` stands for "list open files." In Linux, network connections are treated as files. The `-i :5432` flag filters for anything using port 5432 (PostgreSQL's default port).

Expected output (yours will differ):
```
COMMAND    PID     USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
postmaste 1234 postgres    7u  IPv4  12345      0t0  TCP *:postgresql (LISTEN)
postmaste 1234 postgres    8u  IPv6  12346      0t0  TCP *:postgresql (LISTEN)
postmaste 1250 postgres   10u  IPv4  12400      0t0  TCP pg-primary:postgresql->pg-replica:45678 (ESTABLISHED)
...
```

You can see the postmaster listening on port 5432, and established connections from the replica (walsender).

### Step 1.5: See All Files the Postmaster Has Open

On **pg-primary**, as **ec2-user**:

Replace `1234` with your actual postmaster PID:

```bash
sudo lsof -p 1234 | head -30
```

This shows every file the postmaster process has open - data files, WAL segments, Unix sockets, shared memory segments, and more. We pipe through `head -30` to show just the first 30 lines.

Expected output (yours will differ):
```
COMMAND    PID     USER   FD   TYPE   DEVICE SIZE/OFF    NODE NAME
postmaste 1234 postgres  cwd    DIR    259,1     4096  123456 /var/lib/pgsql/17/data
postmaste 1234 postgres    5u   REG    259,1     8192  123460 /var/lib/pgsql/17/data/global/pg_control
postmaste 1234 postgres    7u  IPv4    12345      0t0     TCP *:postgresql (LISTEN)
postmaste 1234 postgres    9u  unix   0x0000    0t0   12350 /var/run/postgresql/.s.PGSQL.5432
...
```

### Step 1.6: Check Memory Details via /proc

On **pg-primary**, as **ec2-user**:

Replace `1234` with your actual postmaster PID:

```bash
sudo cat /proc/1234/status | grep -E "^(Name|VmSize|VmRSS|VmSwap|Threads|Hugepages)"
```

The `/proc` filesystem is a virtual filesystem that Linux uses to expose kernel and process information. Every running process has a directory under `/proc/<PID>/`. The `status` file contains detailed information about the process. We filter for the most relevant fields.

Expected output (yours will differ):
```
Name:   postmaster
VmSize:   456789 kB
VmRSS:     12345 kB
VmSwap:        0 kB
Threads:       1
```

- **VmSize** - Total virtual memory allocated (includes shared libraries, mapped files - not all of this is in RAM)
- **VmRSS** - Resident Set Size - the amount of physical RAM this process is actually using right now
- **VmSwap** - How much of this process's memory has been moved to swap disk. For PostgreSQL, you want this to be 0.

---

## Section 2: Memory Management

PostgreSQL's performance depends heavily on how Linux manages memory. A DBA must understand buffers, cache, hugepages, and overcommit settings.

### Step 2.1: Check Overall Memory Usage

On **pg-primary**, as **ec2-user**:

```bash
free -h
```

`free` shows memory usage in a human-readable summary. The `-h` flag formats numbers with units like GB and MB instead of raw kilobytes.

Expected output (yours will differ):
```
               total        used        free      shared  buff/cache   available
Mem:           3.7Gi       1.2Gi       512Mi       234Mi       2.0Gi       2.1Gi
Swap:          2.0Gi          0B       2.0Gi
```

Key things to understand:

- **total** - Total physical RAM in the server
- **used** - Memory actively used by processes
- **free** - Memory not used at all (not even for cache)
- **buff/cache** - Memory Linux is using to cache disk data. This is a good thing - Linux uses spare RAM to speed up disk reads. This memory is automatically released when applications need it.
- **available** - How much memory is actually available for new processes. This is the number you care about most. It includes free memory plus cache memory that can be reclaimed.
- **Swap** - Disk space used as overflow memory. For a database server, swap usage should be near zero.

### Step 2.2: Deep Dive into /proc/meminfo

On **pg-primary**, as **ec2-user**:

```bash
cat /proc/meminfo | head -20
```

This file has more detail than `free`. We look at the first 20 lines.

Expected output (yours will differ):
```
MemTotal:        3878196 kB
MemFree:          524288 kB
MemAvailable:    2198456 kB
Buffers:           65432 kB
Cached:          1876543 kB
SwapCached:            0 kB
Active:          1234567 kB
Inactive:         987654 kB
...
Dirty:              1234 kB
Writeback:             0 kB
...
```

Important fields:

- **Dirty** - Pages in memory that have been modified but not yet written to disk. High dirty values mean the OS is holding a lot of data in RAM that still needs to be flushed to disk. If the server crashes, this data could be lost (PostgreSQL protects against this with WAL).
- **Writeback** - Pages currently being written to disk. If this is persistently high, your disks are not keeping up.
- **Buffers** - Memory used for raw block device I/O metadata (like filesystem directory entries)
- **Cached** - Memory used for caching file contents. PostgreSQL reads go through the OS page cache even after they leave shared_buffers.

### Step 2.3: Check Current Hugepages Configuration

On **pg-primary**, as **ec2-user**:

```bash
cat /proc/meminfo | grep -i huge
```

Expected output (yours will differ):
```
AnonHugePages:         0 kB
ShmemHugePages:        0 kB
FileHugePages:         0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
```

**Why hugepages matter for PostgreSQL**: Linux normally manages memory in 4 KB pages. When PostgreSQL allocates a large `shared_buffers` (say 1 GB), that is 262,144 pages. Each page needs an entry in the page table, which consumes CPU and memory. Hugepages use 2 MB pages instead, reducing the page count to 512 - a 500x reduction in page table overhead.

If `HugePages_Total` is 0, hugepages are not configured. For a production server with large `shared_buffers`, you would set this up.

### Step 2.4: Check PostgreSQL's Hugepage Usage

On **pg-primary**, as **ec2-user**:

First, get the postmaster PID:

```bash
head -1 /var/lib/pgsql/17/data/postmaster.pid
```

Then check if that process is using hugepages. Replace `1234` with your actual PID:

```bash
sudo grep -i huge /proc/1234/status
```

Expected output (yours will differ):
```
HugetlbPages:          0 kB
```

If this shows 0, PostgreSQL is not using hugepages. In a production setup, you would configure the `huge_pages` parameter in `postgresql.conf` and allocate hugepages in the kernel.

### Step 2.5: Check Overcommit and Swappiness Settings

On **pg-primary**, as **ec2-user**:

```bash
sysctl vm.overcommit_memory
```

`sysctl` reads and writes kernel parameters at runtime. `vm.overcommit_memory` controls how Linux handles memory allocation requests.

Expected output (yours will differ):
```
vm.overcommit_memory = 0
```

- **0** (default) - The kernel uses heuristics to decide whether to allow memory allocation. It might allow more allocation than physical RAM.
- **2** - The kernel only allows allocation up to swap + (RAM * overcommit_ratio). This is the recommended setting for PostgreSQL because it prevents the OOM killer from terminating the postmaster.

```bash
sysctl vm.overcommit_ratio
```

Expected output (yours will differ):
```
vm.overcommit_ratio = 50
```

When `overcommit_memory = 2`, the system allows total committed memory up to: swap size + (physical RAM * overcommit_ratio / 100). With 4 GB RAM and ratio of 50, that is swap + 2 GB.

```bash
sysctl vm.swappiness
```

Expected output (yours will differ):
```
vm.swappiness = 30
```

`vm.swappiness` controls how aggressively Linux moves memory pages to swap. The range is 0-100. DBAs typically set this to 1 (not 0, which can cause issues in some kernels). A value of 1 tells Linux: "only swap when absolutely necessary." For a database server, you want data to stay in RAM as long as possible.

### Step 2.6: How shared_buffers Relates to OS Memory

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -c "SHOW shared_buffers;"
```

Expected output (yours will differ):
```
 shared_buffers
----------------
 128MB
(1 row)
```

```bash
exit
```

The `shared_buffers` setting controls how much RAM PostgreSQL reserves for its own internal buffer cache. This is separate from the OS page cache. A common guideline is to set `shared_buffers` to 25% of total RAM (but no more than 8 GB on most systems). The remaining RAM should be left for the OS page cache, which PostgreSQL also benefits from for read-heavy workloads.

---

## Section 3: Storage, Filesystems & I/O

Database performance is often bottlenecked by disk I/O. A DBA must be able to identify which disks are slow and understand the filesystem layout.

### Step 3.1: Check Filesystem Types and Usage

On **pg-primary**, as **ec2-user**:

```bash
df -hT
```

`df` shows disk space usage. The `-h` flag makes the output human-readable (GB/MB instead of blocks). The `-T` flag adds a column showing the filesystem type.

Expected output (yours will differ):
```
Filesystem     Type      Size  Used Avail Use% Mounted on
/dev/xvda1     xfs        20G   8G   12G  40% /
devtmpfs       devtmpfs  1.9G     0  1.9G   0% /dev
tmpfs          tmpfs     1.9G     0  1.9G   0% /dev/shm
...
```

Look for the filesystem type where PostgreSQL data lives. XFS is preferred for PostgreSQL because it handles concurrent writes better than ext4 and has superior crash recovery.

### Step 3.2: View Block Device Layout

On **pg-primary**, as **ec2-user**:

```bash
lsblk
```

`lsblk` lists all block devices (disks, partitions, LVM volumes) in a tree structure. This shows how physical disks are partitioned and where they are mounted.

Expected output (yours will differ):
```
NAME    MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
xvda    202:0    0  20G  0 disk
|-xvda1 202:1    0  20G  0 part /
...
```

### Step 3.3: LVM Walkthrough on pg-replica

On **pg-replica**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.144.241.128
```

The pg-replica server has a Ceph-simulated LVM setup for pgBackRest storage. LVM (Logical Volume Manager) adds a layer of abstraction between physical disks and filesystems, allowing you to resize volumes, create snapshots, and span multiple disks.

Check physical volumes:

```bash
sudo pvs
```

`pvs` shows Physical Volumes - the raw block devices that LVM uses as building blocks.

Expected output (yours will differ):
```
  PV         VG       Fmt  Attr PSize   PFree
  /dev/xvdb  ceph_vg  lvm2 a--  <10.00g    0
```

Check volume groups:

```bash
sudo vgs
```

`vgs` shows Volume Groups - pools of storage made from one or more physical volumes.

Expected output (yours will differ):
```
  VG      #PV #LV #SN Attr   VSize   VFree
  ceph_vg   1   1   0 wz--n- <10.00g    0
```

Check logical volumes:

```bash
sudo lvs
```

`lvs` shows Logical Volumes - the usable "virtual partitions" carved out of a volume group. This is what you format with a filesystem and mount.

Expected output (yours will differ):
```
  LV      VG      Attr       LSize   Pool Origin Data%  Meta%
  ceph_lv ceph_vg -wi-ao---- <10.00g
```

See detailed logical volume information:

```bash
sudo lvdisplay --maps
```

The `--maps` flag shows the physical extent mapping - which physical disk sectors back this logical volume.

Expected output (yours will differ):
```
  --- Logical volume ---
  LV Path                /dev/ceph_vg/ceph_lv
  LV Name                ceph_lv
  VG Name                ceph_vg
  LV Size                <10.00g
  ...
  --- Segments ---
  Logical extents 0 to 2559:
    Type                linear
    Physical volume     /dev/xvdb
    Physical extents    0 to 2559
```

### Step 3.4: Check Mount Options

Still on **pg-replica**, as **ec2-user**:

```bash
mount | grep xfs
```

This filters mount output to show only XFS filesystems and their mount options.

Expected output (yours will differ):
```
/dev/xvda1 on / type xfs (rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota)
/dev/mapper/ceph_vg-ceph_lv on /opt/ceph-sim type xfs (rw,noatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota)
```

Key mount options to look for:

- **noatime** - Do not update the "last accessed" timestamp on files. Without this, every read causes a write (to update the timestamp), doubling I/O. This should be set for all database data directories.
- **rw** - Mounted read-write (as opposed to read-only)

### Step 3.5: Monitor Disk I/O with iostat

Still on **pg-replica**, as **ec2-user**:

```bash
iostat -x 1 5
```

`iostat` shows I/O statistics for each disk device. The `-x` flag shows extended statistics. `1 5` means "sample every 1 second, take 5 samples." The first sample shows stats since boot - ignore it and look at samples 2-5 for current activity.

Expected output (yours will differ):
```
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           1.23    0.00    0.45    0.12    0.05   98.15

Device            r/s     w/s   rkB/s    wkB/s  await  %util
xvda             0.50    2.30    4.00    18.40   1.20   0.35
xvdb             0.10    0.80    0.80     6.40   0.90   0.15
...
```

How to read the important columns:

- **r/s, w/s** - Reads and writes per second. High values mean the disk is busy.
- **rkB/s, wkB/s** - Kilobytes read/written per second. This shows throughput.
- **await** - Average time (in milliseconds) each I/O request waited. For SSDs, this should be under 1 ms. For HDDs, under 10 ms. If this number is high, your disk is a bottleneck.
- **%util** - How busy the device is. 100% means it is completely saturated. For SSDs this metric can be misleading since they handle parallel I/O, but for single-queue devices, over 80% is concerning.

### Step 3.6: See Per-Process I/O Usage

Still on **pg-replica**, as **ec2-user**:

```bash
sudo iotop -ao -d 3 -n 2
```

`iotop` is like `top` but for disk I/O. The `-a` flag shows accumulated I/O since the tool started (instead of per-second rates). The `-o` flag only shows processes that are actually doing I/O. The `-d 3` sets a 3-second delay between updates. The `-n 2` takes 2 samples and exits.

Expected output (yours will differ):
```
Total DISK READ:       0.00 B/s | Total DISK WRITE:       4.00 K/s
Actual DISK READ:      0.00 B/s | Actual DISK WRITE:       8.00 K/s
    PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN     IO>    COMMAND
   1243 be/4 postgres      0.00 B     12.00 K  0.00 %  0.00 % postgres: walwriter
   1240 be/4 postgres      0.00 B      4.00 K  0.00 %  0.00 % postgres: checkpointer
...
```

### Step 3.7: Check for I/O Wait with vmstat

Still on **pg-replica**, as **ec2-user**:

```bash
vmstat 1 5
```

`vmstat` shows virtual memory statistics. `1 5` means "sample every 1 second, take 5 samples."

Expected output (yours will differ):
```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0      0 524288  65432 1876543    0    0     4    18   50  100  1  0 98  0  0
 0  0      0 524200  65432 1876600    0    0     0    12   48   95  1  0 99  0  0
...
```

The critical column is **wa** (wait) under the cpu section. This shows the percentage of CPU time spent waiting for disk I/O. If `wa` is consistently above 5-10%, your disks are too slow for the workload.

Other useful columns:
- **r** - Number of processes waiting for CPU time
- **b** - Number of processes in uninterruptible sleep (usually waiting for disk)
- **si/so** - Swap in/out. Should be 0 on a database server.
- **bi/bo** - Blocks read/written per second from block devices

Now return to your primary terminal:

```bash
exit
```

---

## Section 4: Kernel Tuning for PostgreSQL

The Linux kernel has hundreds of tunable parameters. A handful of them have a significant impact on PostgreSQL performance. In this section, you will review the current values and understand what each one does.

### Step 4.1: Check Dirty Page Settings

On **pg-primary**, as **ec2-user**:

```bash
sysctl -a | grep vm.dirty
```

`sysctl -a` lists all kernel parameters. We filter for `vm.dirty` which controls how Linux handles modified (dirty) pages in memory.

Expected output (yours will differ):
```
vm.dirty_background_bytes = 0
vm.dirty_background_ratio = 10
vm.dirty_bytes = 0
vm.dirty_expire_centisecs = 3000
vm.dirty_ratio = 20
vm.dirty_writeback_centisecs = 500
```

Here is what these mean:

- **vm.dirty_background_ratio** (default: 10) - When dirty pages exceed this percentage of total memory, Linux starts writing them to disk in the background. For PostgreSQL, lower values (like 5) give more consistent write latency because flushes are smaller and more frequent.
- **vm.dirty_ratio** (default: 20) - When dirty pages exceed this percentage, all writing processes are blocked until dirty pages are flushed to disk. This causes visible stalls. For PostgreSQL, lower values (like 10) prevent sudden I/O storms.
- **vm.dirty_expire_centisecs** (default: 3000) - Dirty pages older than 30 seconds (3000 centiseconds) get scheduled for writeback.
- **vm.dirty_writeback_centisecs** (default: 500) - The kernel flush daemon wakes up every 5 seconds to check for dirty pages.

### Step 4.2: Review All Key PostgreSQL Kernel Parameters

On **pg-primary**, as **ec2-user**:

```bash
sysctl vm.swappiness
```

Expected output (yours will differ):
```
vm.swappiness = 30
```

For PostgreSQL, set this to 1. This tells Linux to avoid swapping unless absolutely necessary.

```bash
sysctl kernel.shmmax
```

Expected output (yours will differ):
```
kernel.shmmax = 18446744073692774399
```

`kernel.shmmax` is the maximum size (in bytes) of a single shared memory segment. PostgreSQL uses shared memory for `shared_buffers`. On modern kernels with `mmap`-based shared memory (PostgreSQL 9.3+), this is usually already set high enough and rarely needs tuning.

```bash
sysctl kernel.shmall
```

Expected output (yours will differ):
```
kernel.shmall = 18446744073692774399
```

`kernel.shmall` is the total amount of shared memory (in pages) available system-wide. Like `shmmax`, modern kernels set this high enough by default.

```bash
sysctl vm.overcommit_memory
```

Expected output (yours will differ):
```
vm.overcommit_memory = 0
```

For PostgreSQL, set this to 2. This prevents the Linux OOM (Out-Of-Memory) killer from terminating the postmaster when memory is low. Without this, a memory spike from a bad query could cause Linux to kill PostgreSQL entirely.

```bash
sysctl vm.zone_reclaim_mode
```

Expected output (yours will differ):
```
vm.zone_reclaim_mode = 0
```

On NUMA (Non-Uniform Memory Access) servers - common in multi-socket systems - this controls whether the kernel reclaims memory from the local NUMA zone before allocating from remote zones. Set to 0 (the default) so PostgreSQL can use memory from any NUMA node freely. Setting it to 1 can cause severe performance issues because it forces premature memory reclamation.

```bash
sysctl net.core.somaxconn
```

Expected output (yours will differ):
```
net.core.somaxconn = 4096
```

This controls the maximum length of the listen queue for sockets. When a burst of connections hit PgBouncer or PostgreSQL, connections queue up here. The default of 128 is too low for production. 4096 is a good value.

### Step 4.3: Apply a Setting Temporarily

On **pg-primary**, as **ec2-user**:

```bash
sudo sysctl -w vm.swappiness=1
```

The `-w` flag writes a new value to a kernel parameter at runtime. This takes effect immediately but does not survive a reboot.

Expected output (yours will differ):
```
vm.swappiness = 1
```

Verify it took effect:

```bash
sysctl vm.swappiness
```

Expected output (yours will differ):
```
vm.swappiness = 1
```

### Step 4.4: Make Settings Permanent

On **pg-primary**, as **ec2-user**:

```bash
sudo vi /etc/sysctl.d/99-postgresql.conf
```

Add the following content (press `i` to enter insert mode, type the lines, then press `Esc` followed by `:wq` to save and quit):

```
# PostgreSQL kernel tuning
vm.swappiness = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
vm.zone_reclaim_mode = 0
net.core.somaxconn = 4096
```

Files in `/etc/sysctl.d/` are read at boot time. The `99-` prefix ensures this file is loaded last, overriding any earlier defaults.

Apply the file now without rebooting:

```bash
sudo sysctl -p /etc/sysctl.d/99-postgresql.conf
```

The `-p` flag loads settings from a file and applies them.

Expected output (yours will differ):
```
vm.swappiness = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
vm.zone_reclaim_mode = 0
net.core.somaxconn = 4096
```

Verify one of the settings:

```bash
sysctl vm.dirty_ratio
```

Expected output (yours will differ):
```
vm.dirty_ratio = 10
```

---

## Section 5: Systemd Service Management

Systemd is the init system on CentOS Stream 9. It manages all services including PostgreSQL. Understanding systemd is essential for starting, stopping, troubleshooting, and automating database operations.

### Step 5.1: Check PostgreSQL Service Status

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl status postgresql-17
```

This command shows: whether the service is running, its PID, how long it has been running, memory usage, and the last few log lines.

Expected output (yours will differ):
```
● postgresql-17.service - PostgreSQL 17 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled; preset: disabled)
     Active: active (running) since Wed 2026-06-17 10:00:00 UTC; 1 day ago
   Main PID: 1234 (postmaster)
      Tasks: 8 (limit: 4654)
     Memory: 45.0M
        CPU: 2.345s
     CGroup: /system.slice/postgresql-17.service
             ├─1234 /usr/pgsql-17/bin/postmaster -D /var/lib/pgsql/17/data/
             ├─1240 postgres: checkpointer
             ├─1241 postgres: background writer
             ...

Jun 17 10:00:00 pg-primary systemd[1]: Starting PostgreSQL 17 database server...
Jun 17 10:00:01 pg-primary postmaster[1234]: LOG:  redirecting log output...
...
```

Key information to look for:

- **Loaded** - Shows the unit file path and whether the service starts at boot ("enabled" means yes)
- **Active** - Current state. "active (running)" is what you want.
- **Main PID** - The postmaster PID
- **CGroup** - Shows the control group and all child processes

### Step 5.2: Read PostgreSQL Logs via journalctl

On **pg-primary**, as **ec2-user**:

```bash
sudo journalctl -u postgresql-17 --since "10 minutes ago"
```

`journalctl` reads from the systemd journal - a centralized log for all services. The `-u` flag filters by service name. The `--since` flag limits to recent entries so you are not overwhelmed.

Expected output (yours will differ):
```
Jun 18 12:00:00 pg-primary postmaster[1234]: LOG:  checkpoint starting: time
Jun 18 12:00:02 pg-primary postmaster[1234]: LOG:  checkpoint complete: wrote 5 buffers (0.0%)...
...
```

To see only errors and warnings:

```bash
sudo journalctl -u postgresql-17 -p err --since "1 hour ago"
```

The `-p err` flag filters to only show messages with priority "error" or higher.

### Step 5.3: Inspect the PostgreSQL Unit File

On **pg-primary**, as **ec2-user**:

```bash
systemctl cat postgresql-17
```

This shows the actual systemd unit file that defines how PostgreSQL starts.

Expected output (yours will differ):
```
# /usr/lib/systemd/system/postgresql-17.service
[Unit]
Description=PostgreSQL 17 database server
Documentation=https://www.postgresql.org/docs/17/static/
After=syslog.target
After=network-online.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/pgsql/17/data/
ExecStartPre=/usr/pgsql-17/bin/postgresql-17-check-db-dir ${PGDATA}
ExecStart=/usr/pgsql-17/bin/postmaster -D ${PGDATA}
ExecReload=/bin/kill -HUP $MAINPID
...

[Install]
WantedBy=multi-user.target
```

Key directives explained:

- **After=network-online.target** - PostgreSQL waits for the network to be ready before starting
- **Type=notify** - The service tells systemd when it is ready (instead of systemd guessing)
- **User=postgres** - The service runs as the `postgres` OS user
- **ExecStartPre** - A command that runs before the main process. Here it checks that the data directory exists.
- **ExecStart** - The actual command to start PostgreSQL
- **ExecReload** - The command for `systemctl reload` - sends SIGHUP to reload config without restart

### Step 5.4: Check Service Dependencies

On **pg-primary**, as **ec2-user**:

```bash
systemctl list-dependencies postgresql-17
```

This shows the dependency tree - what services must start before PostgreSQL, and what services depend on it.

Expected output (yours will differ):
```
postgresql-17.service
● ├─system.slice
● ├─network-online.target
● │ └─NetworkManager-wait-online.service
● └─sysinit.target
...
```

### Step 5.5: Create a Custom Systemd Timer for Daily Backup Verification

On **pg-primary**, as **ec2-user**:

First, create a script that checks if backups ran successfully:

```bash
sudo vi /usr/local/bin/check-backup-status.sh
```

Add the following content:

```bash
#!/bin/bash
# Check if pgBackRest backup completed in the last 24 hours
LOG_FILE="/var/log/backup-check.log"
echo "$(date): Running daily backup verification" >> "$LOG_FILE"
if sudo -u postgres pgbackrest --stanza=quantdb info 2>/dev/null | grep -q "full backup"; then
    echo "$(date): PASS - Backup stanza found" >> "$LOG_FILE"
else
    echo "$(date): WARN - No backup stanza or backup issue detected" >> "$LOG_FILE"
fi
```

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/check-backup-status.sh
```

Now create the systemd service unit:

```bash
sudo vi /etc/systemd/system/backup-check.service
```

Add the following content:

```ini
[Unit]
Description=Daily PostgreSQL backup verification

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-backup-status.sh
```

`Type=oneshot` means this service runs once and exits (unlike PostgreSQL which runs continuously).

Now create the timer unit:

```bash
sudo vi /etc/systemd/system/backup-check.timer
```

Add the following content:

```ini
[Unit]
Description=Run backup check daily at 7am

[Timer]
OnCalendar=*-*-* 07:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

- **OnCalendar** - When to run. This format means "every day at 07:00:00."
- **Persistent=true** - If the server was off when the timer should have fired, run it at next boot.

### Step 5.6: Reload and Enable the Timer

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl daemon-reload
```

After creating or modifying unit files, you must run `daemon-reload` so systemd picks up the changes.

```bash
sudo systemctl enable --now backup-check.timer
```

The `--now` flag starts the timer immediately in addition to enabling it for boot.

Verify the timer is active:

```bash
systemctl list-timers | grep backup
```

Expected output (yours will differ):
```
Thu 2026-06-19 07:00:00 UTC  18h left    n/a                          n/a          backup-check.timer     backup-check.service
```

### Step 5.7: loginctl enable-linger

On **pg-primary**, as **ec2-user**:

```bash
sudo loginctl enable-linger postgres
```

By default, systemd kills all processes owned by a user when they log out. `enable-linger` allows the `postgres` user's processes (including PostgreSQL itself) to keep running even when no one is logged in as that user. This is important for user-level systemd services.

---

## Section 6: Networking Fundamentals

A DBA needs to verify that PostgreSQL is listening, diagnose connection failures, and understand the network path between application servers and databases.

### Step 6.1: See All Listening Ports

On **pg-primary**, as **ec2-user**:

```bash
ss -tlnp
```

`ss` is a modern replacement for `netstat`. The flags: `-t` shows TCP sockets, `-l` shows only listening sockets, `-n` shows port numbers instead of service names, `-p` shows the process using each socket.

Expected output (yours will differ):
```
State   Recv-Q  Send-Q  Local Address:Port   Peer Address:Port  Process
LISTEN  0       244     0.0.0.0:5432          0.0.0.0:*          users:(("postmaster",pid=1234,fd=7))
LISTEN  0       128     0.0.0.0:6432          0.0.0.0:*          users:(("pgbouncer",pid=2345,fd=5))
LISTEN  0       128     0.0.0.0:6379          0.0.0.0:*          users:(("redis-server",pid=3456,fd=6))
LISTEN  0       128     0.0.0.0:9100          0.0.0.0:*          users:(("node_exporter",pid=4567,fd=3))
LISTEN  0       128     0.0.0.0:9187          0.0.0.0:*          users:(("postgres_export",pid=5678,fd=3))
...
```

Common ports on this server:
- **5432** - PostgreSQL
- **6432** - PgBouncer (connection pooler)
- **6379** - Redis
- **9100** - node_exporter (Prometheus system metrics)
- **9187** - postgres_exporter (Prometheus PG metrics)

### Step 6.2: See Active PostgreSQL Connections

On **pg-primary**, as **ec2-user**:

```bash
ss -tn state established '( dport = :5432 )'
```

This filters for TCP connections that are currently established and connecting to port 5432 (PostgreSQL). The `state established` filter shows only active connections, not listening sockets.

Expected output (yours will differ):
```
Recv-Q  Send-Q  Local Address:Port   Peer Address:Port
0       0       100.26.54.122:5432   54.144.241.128:45678
0       0       100.26.54.122:5432   100.26.54.122:56789
...
```

You should see a connection from pg-replica's IP (54.144.241.128) - that is the streaming replication connection.

### Step 6.3: Check Network Interfaces and IPs

On **pg-primary**, as **ec2-user**:

```bash
ip addr show
```

This displays all network interfaces with their IP addresses, MAC addresses, and status.

Expected output (yours will differ):
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
    inet 127.0.0.1/8 scope host lo
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001
    inet 10.0.1.100/24 brd 10.0.1.255 scope global dynamic eth0
...
```

Note the `mtu 9001` - AWS EC2 instances use jumbo frames (9001 bytes instead of the standard 1500) for better throughput between instances in the same VPC.

### Step 6.4: Check the Routing Table

On **pg-primary**, as **ec2-user**:

```bash
ip route show
```

This shows how the server decides where to send network traffic.

Expected output (yours will differ):
```
default via 10.0.1.1 dev eth0 proto dhcp src 10.0.1.100 metric 100
10.0.1.0/24 dev eth0 proto kernel scope link src 10.0.1.100 metric 100
...
```

The `default via` line is the default gateway - all traffic not matching a specific route goes here. For EC2, this is the VPC router.

### Step 6.5: Check Firewall Rules

On **pg-primary**, as **ec2-user**:

```bash
sudo firewall-cmd --list-all
```

`firewall-cmd` manages the firewalld service on CentOS. This shows all rules for the current zone.

Expected output (yours will differ):
```
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0
  sources:
  services: cockpit dhcpv6-client ssh
  ports: 5432/tcp 6432/tcp 6379/tcp 9100/tcp 9187/tcp
  protocols:
  ...
```

The `ports:` line shows which ports are open through the firewall. If PostgreSQL is not in this list, remote connections will be blocked even if `pg_hba.conf` allows them.

### Step 6.6: Capture PostgreSQL Network Traffic

On **pg-primary**, as **ec2-user**:

```bash
sudo tcpdump -i eth0 -n port 5432 -c 10
```

`tcpdump` captures network packets in real time. The `-i eth0` flag specifies the network interface. The `-n` flag prevents DNS lookups (faster). `port 5432` filters for PostgreSQL traffic only. The `-c 10` flag stops after capturing 10 packets.

Expected output (yours will differ):
```
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
12:00:00.123456 IP 54.144.241.128.45678 > 100.26.54.122.5432: Flags [P.], seq 1:33, ack 1, win 502, length 32
12:00:00.123500 IP 100.26.54.122.5432 > 54.144.241.128.45678: Flags [P.], seq 1:65, ack 33, win 501, length 64
...
10 packets captured
```

You can see the replication traffic flowing between primary and replica. The `Flags [P.]` means it is a data push.

### Step 6.7: Check MTU

On **pg-primary**, as **ec2-user**:

```bash
ip link show eth0 | grep mtu
```

Expected output (yours will differ):
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP mode DEFAULT group default qlen 1000
```

MTU (Maximum Transmission Unit) is the largest packet size the interface can send. AWS uses 9001 (jumbo frames) between instances in the same VPC. If you see 1500, you are on a standard network. Mismatched MTU between nodes can cause mysterious connection drops and performance issues.

### Step 6.8: Verify /etc/hosts for Inter-Node Resolution

On **pg-primary**, as **ec2-user**:

```bash
cat /etc/hosts
```

Expected output (yours will differ):
```
127.0.0.1   localhost localhost.localdomain
100.26.54.122   pg-primary
54.144.241.128  pg-replica
34.228.73.232   pg-container
34.228.32.17    pg-ops
```

This file maps hostnames to IP addresses locally, without needing DNS. For a database cluster, you want all nodes listed here so you can use hostnames (like `pg-replica`) instead of IP addresses in configuration files.

### Step 6.9: Test PostgreSQL Connectivity

On **pg-primary**, as **ec2-user**:

```bash
pg_isready -h 100.26.54.122 -p 5432
```

`pg_isready` is a PostgreSQL utility that checks if a server is accepting connections. It does not require authentication - it just checks if the port is open and the server responds.

Expected output (yours will differ):
```
100.26.54.122:5432 - accepting connections
```

Test connectivity to the replica:

```bash
pg_isready -h 54.144.241.128 -p 5432
```

Expected output (yours will differ):
```
54.144.241.128:5432 - accepting connections
```

---

## Section 7: SELinux for DBAs

SELinux (Security-Enhanced Linux) is enabled by default on CentOS and adds mandatory access control on top of normal Linux permissions. It is the most common cause of "it works as root but not as a service" problems.

### Step 7.1: Check SELinux Status

On **pg-primary**, as **ec2-user**:

```bash
getenforce
```

This returns a single word: `Enforcing`, `Permissive`, or `Disabled`.

Expected output (yours will differ):
```
Enforcing
```

- **Enforcing** - SELinux actively blocks unauthorized actions
- **Permissive** - SELinux logs violations but does not block them (useful for debugging)
- **Disabled** - SELinux is completely off

```bash
sestatus
```

Expected output (yours will differ):
```
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Memory protection checking:     actual (secure)
Max kernel policy version:      33
```

### Step 7.2: Find SELinux Denials

On **pg-primary**, as **ec2-user**:

```bash
sudo ausearch -m avc -ts recent
```

`ausearch` searches the audit log. The `-m avc` flag looks for Access Vector Cache messages - these are SELinux denial records. The `-ts recent` flag limits to the last 10 minutes.

If SELinux has not denied anything recently, you will see:

Expected output (yours will differ):
```
<no matches>
```

If there are denials, you will see entries like:

```
type=AVC msg=audit(1718700000.123:456): avc:  denied  { read } for  pid=1234 comm="postmaster" name="custom_data" ...
```

### Step 7.3: Diagnose a Denial with audit2why

On **pg-primary**, as **ec2-user**:

If you had a denial, you could pipe it through `audit2why` to get an explanation:

```bash
sudo ausearch -m avc -ts today | audit2why
```

`audit2why` reads SELinux denial messages and explains in plain English what policy rule caused the denial and how to fix it.

Expected output (yours will differ):
```
type=AVC msg=audit(...): avc:  denied  { read } ...
    Was caused by:
        Missing type enforcement (TE) allow rule.
        You can use audit2allow to generate a loadable module to allow this access.
```

### Step 7.4: Allow PgBouncer on a Non-Standard Port

On **pg-primary**, as **ec2-user**:

PgBouncer listens on port 6432, which is not in SELinux's default list of allowed PostgreSQL ports. You must tell SELinux that this port is a valid PostgreSQL port:

```bash
sudo semanage port -l | grep postgresql
```

This lists all ports SELinux currently recognizes as PostgreSQL ports.

Expected output (yours will differ):
```
postgresql_port_t              tcp      5432, 9898
```

Add port 6432:

```bash
sudo semanage port -a -t postgresql_port_t -p tcp 6432
```

The `-a` flag adds a new port definition. The `-t postgresql_port_t` assigns it the PostgreSQL SELinux type. The `-p tcp` specifies the protocol.

Verify:

```bash
sudo semanage port -l | grep postgresql
```

Expected output (yours will differ):
```
postgresql_port_t              tcp      5432, 6432, 9898
```

### Step 7.5: Set File Contexts for Custom Data Directories

On **pg-primary**, as **ec2-user**:

If you moved PostgreSQL's data directory to a non-standard location (like `/opt/pgsql/data`), SELinux would block PostgreSQL from reading it. You need to label the new directory with the correct SELinux context:

```bash
sudo semanage fcontext -a -t postgresql_db_t "/opt/pgsql/data(/.*)?"
```

This adds a rule saying "everything under `/opt/pgsql/data/` should have the `postgresql_db_t` SELinux type."

Then apply the rule to existing files:

```bash
sudo restorecon -Rv /opt/pgsql/data
```

`restorecon` resets file SELinux contexts based on the rules you defined. The `-R` flag is recursive. The `-v` flag shows each file as it is relabeled.

### Step 7.6: SELinux Booleans for PostgreSQL

On **pg-primary**, as **ec2-user**:

```bash
sudo getsebool -a | grep postgres
```

`getsebool` lists SELinux booleans - on/off switches that control specific behaviors. The `-a` flag shows all booleans.

Expected output (yours will differ):
```
postgresql_can_rsync --> off
postgresql_selinux_users_ddl --> on
```

If you use rsync for backups (like pgBackRest does), you need:

```bash
sudo setsebool -P postgresql_can_rsync on
```

The `-P` flag makes the change permanent (survives reboots). Without `-P`, it resets on next boot.

---

## Section 8: Troubleshooting Scenarios (Tie It All Together)

These scenarios combine everything you learned. For each one, practice the diagnostic flow - this is exactly how interview troubleshooting questions work.

### Scenario A: "PostgreSQL Won't Start"

On **pg-primary**, as **ec2-user**:

Imagine PostgreSQL failed to start. Here is the diagnostic sequence:

**Step A1: Check the service status**

```bash
sudo systemctl status postgresql-17
```

Look for: "Active: failed" and any error messages in the log output at the bottom.

**Step A2: Read the full journal log**

```bash
sudo journalctl -u postgresql-17 --since "5 minutes ago" --no-pager
```

The `--no-pager` flag prints the full output to your terminal instead of opening a pager. Look for lines containing `FATAL` or `ERROR`.

Common errors:
- `FATAL: could not open directory "pg_wal": No such file or directory` - Data directory corruption or wrong PGDATA path
- `FATAL: could not create lock file "postmaster.pid": File exists` - Stale PID file from a crash
- `FATAL: could not bind IPv4 address "0.0.0.0": Address already in use` - Another process is on port 5432

**Step A3: Check disk space**

```bash
df -h /var/lib/pgsql/17/data/
```

If the filesystem is at 100%, PostgreSQL cannot write WAL or create lock files and will refuse to start.

**Step A4: Check permissions**

```bash
ls -la /var/lib/pgsql/17/data/
```

The data directory must be owned by `postgres:postgres` and have permissions `0700`. If anything else owns it, PostgreSQL refuses to start for security.

Expected output (yours will differ):
```
drwx------. 20 postgres postgres 4096 Jun 17 10:00 .
```

**Step A5: Check for port conflicts**

```bash
ss -tlnp | grep 5432
```

If another process is already using port 5432, PostgreSQL cannot bind to it. You will see the conflicting process name in the output.

**Step A6: Check SELinux**

```bash
sudo ausearch -m avc -ts recent | grep postgres
```

If SELinux is blocking PostgreSQL from accessing files or ports, you will see denial messages here.

### Scenario B: "Queries Are Slow"

On **pg-primary**, as **ec2-user**:

Slow queries can be caused by CPU saturation, disk I/O bottlenecks, or memory pressure. Here is the diagnostic flow:

**Step B1: Check for I/O wait**

```bash
vmstat 1 3
```

Look at the `wa` column. If it is above 5-10%, the disks are slow and queries are waiting for I/O.

**Step B2: Check disk utilization**

```bash
iostat -x 1 3
```

Look at `await` (should be under 1 ms for SSD) and `%util` (should be under 80%). High values mean the disk is the bottleneck.

**Step B3: Check CPU usage**

```bash
top -bn1 | head -20
```

The `-b` flag runs top in batch mode (single snapshot). The `-n1` flag takes one sample. Look at the `%Cpu` line - high `us` (user) means CPU-bound queries. High `wa` (wait) confirms I/O problems.

**Step B4: Check what PostgreSQL is doing**

```bash
sudo su - postgres
```

```bash
psql -c "SELECT pid, state, wait_event_type, wait_event, left(query, 60) AS query FROM pg_stat_activity WHERE state = 'active' ORDER BY backend_start;"
```

This shows all currently running queries in PostgreSQL, what they are waiting on, and the first 60 characters of each query.

Expected output (yours will differ):
```
  pid  | state  | wait_event_type | wait_event |                            query
-------+--------+-----------------+------------+------------------------------------------------------------
  5678 | active | IO              | DataFileRead | SELECT * FROM large_table WHERE unindexed_column = 'val...
...
```

If `wait_event_type` is `IO`, the query is waiting for disk. If it is `Lock`, it is waiting for another transaction.

```bash
exit
```

**Step B5: Check memory pressure**

```bash
free -h
```

If `available` is very low and `Swap used` is non-zero, the server is under memory pressure. PostgreSQL processes may be swapping, which destroys performance.

### Scenario C: "Server Ran Out of Memory"

On **pg-primary**, as **ec2-user**:

**Step C1: Check dmesg for OOM killer activity**

```bash
sudo dmesg -T | grep -i "oom\|out of memory" | tail -10
```

`dmesg` shows kernel messages. The `-T` flag adds human-readable timestamps. The `grep` searches for OOM (Out-Of-Memory) killer messages.

Expected output if OOM killed something (yours will differ):
```
[Wed Jun 17 15:00:00 2026] Out of memory: Killed process 1234 (postmaster) total-vm:456789kB, anon-rss:123456kB
```

If you see the postmaster was killed, that means a memory spike (possibly from a bad query with lots of JOINs or sorts) caused Linux to kill the main PostgreSQL process.

**Step C2: Analyze current memory usage**

```bash
free -h
```

Check if memory has recovered or is still depleted.

**Step C3: Check PostgreSQL memory parameters**

```bash
sudo su - postgres
```

```bash
psql -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size', 'max_connections');"
```

Expected output (yours will differ):
```
         name          | setting | unit
-----------------------+---------+------
 effective_cache_size  | 524288  | 8kB
 maintenance_work_mem  | 65536   | kB
 max_connections       | 100     |
 shared_buffers        | 16384   | 8kB
 work_mem              | 4096    | kB
(5 rows)
```

The danger formula: `work_mem * max_connections` = maximum memory that sorts/hashes can consume. If `work_mem = 256MB` and `max_connections = 200`, that is 50 GB of potential sort memory - far more than most servers have.

```bash
exit
```

**Step C4: Prevent future OOM kills**

The kernel tuning from Section 4 helps here:

```bash
sysctl vm.overcommit_memory
```

If this is 0 (the default), set it to 2. With `overcommit_memory = 2`, the kernel refuses memory allocations that exceed the commit limit instead of silently overcommitting and then killing processes later.

---

## Summary: Commands Reference

Here is every command covered in this guide, organized by category.

### Process Management
| Command | Purpose |
|---|---|
| `ps auxf \| grep postgres` | Show PostgreSQL process tree |
| `top -p <PID>` | Monitor a specific process in real time |
| `strace -p <PID> -e trace=write -c` | Count system calls for a process |
| `lsof -i :5432` | Show who is connected to PostgreSQL |
| `lsof -p <PID>` | Show all files a process has open |
| `cat /proc/<PID>/status` | Detailed memory info for a process |

### Memory Management
| Command | Purpose |
|---|---|
| `free -h` | System memory overview |
| `cat /proc/meminfo` | Detailed memory statistics |
| `cat /proc/meminfo \| grep -i huge` | Hugepages configuration |
| `grep -i huge /proc/<PID>/status` | Check if a process uses hugepages |
| `sysctl vm.overcommit_memory` | Check overcommit setting |
| `sysctl vm.swappiness` | Check swap aggressiveness |

### Storage & I/O
| Command | Purpose |
|---|---|
| `df -hT` | Filesystem usage and types |
| `lsblk` | Block device layout |
| `pvs` / `vgs` / `lvs` | LVM physical volumes, volume groups, logical volumes |
| `lvdisplay --maps` | LVM extent mapping |
| `mount \| grep xfs` | XFS mount options |
| `iostat -x 1 5` | Per-device I/O statistics |
| `sudo iotop -ao` | Per-process I/O usage |
| `vmstat 1 5` | System-wide I/O wait and memory stats |

### Kernel Tuning
| Command | Purpose |
|---|---|
| `sysctl -a \| grep vm.dirty` | Show dirty page settings |
| `sysctl -w vm.swappiness=1` | Set parameter temporarily |
| `sysctl -p /etc/sysctl.d/99-postgresql.conf` | Load settings from file |
| `vi /etc/sysctl.d/99-postgresql.conf` | Permanent kernel settings |

### Systemd
| Command | Purpose |
|---|---|
| `systemctl status postgresql-17` | Service status and recent logs |
| `journalctl -u postgresql-17 --since "5 min ago"` | Read service logs |
| `systemctl cat postgresql-17` | View the unit file |
| `systemctl list-dependencies postgresql-17` | Service dependency tree |
| `systemctl daemon-reload` | Reload after unit file changes |
| `systemctl list-timers` | Show active timers |
| `loginctl enable-linger postgres` | Allow user services to persist |

### Networking
| Command | Purpose |
|---|---|
| `ss -tlnp` | All listening ports with process names |
| `ss -tn state established '( dport = :5432 )'` | Active PostgreSQL connections |
| `ip addr show` | Network interfaces and IPs |
| `ip route show` | Routing table |
| `firewall-cmd --list-all` | Firewall rules |
| `tcpdump -i eth0 -n port 5432 -c 10` | Capture PostgreSQL traffic |
| `ip link show eth0 \| grep mtu` | Check MTU size |
| `pg_isready -h <IP> -p 5432` | Test PostgreSQL connectivity |

### SELinux
| Command | Purpose |
|---|---|
| `getenforce` | Current SELinux mode |
| `sestatus` | Full SELinux status |
| `ausearch -m avc -ts recent` | Find SELinux denials |
| `audit2why` | Explain denial causes |
| `semanage port -a -t postgresql_port_t -p tcp 6432` | Allow PgBouncer port |
| `semanage fcontext -a -t postgresql_db_t "/path(/.*)?"` | Label custom directories |
| `restorecon -Rv /path` | Apply SELinux labels |
| `setsebool -P postgresql_can_rsync on` | Enable rsync for PG |

### Troubleshooting Quick Reference
| Symptom | First Commands |
|---|---|
| PG won't start | `systemctl status`, `journalctl -u`, `df -h`, `ls -la`, `ss -tlnp` |
| Queries slow | `vmstat`, `iostat -x`, `top`, `pg_stat_activity`, `free -h` |
| Out of memory | `dmesg -T \| grep oom`, `free -h`, PG memory settings, `sysctl vm.overcommit_memory` |

---

You now have a complete Linux systems toolkit for your interview with Lukasz. Every command in this guide works on your actual lab servers - run through them until the diagnostic patterns feel natural.
