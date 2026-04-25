# Use Exercise 07 - OS Triage

Given a running PostgreSQL server, use OS-level tools to diagnose what is happening before touching any database settings.

**Server:** NODE1 only

---

## Setup

SSH into NODE1 as ec2-user.

```bash
ssh -i ~/your-key.pem ec2-user@<NODE1_IP>
```

Stay as ec2-user for all tasks in this exercise. OS diagnostic tools do not require root or the postgres user.

---

## Task 1 - Load Average Interpretation

The server has been running for a while. Before you open psql or check pg_stat_activity, the first thing you check is whether the OS itself is under pressure.

Run the uptime command.

```bash
uptime
```

`uptime` shows how long the server has been running and three load average numbers. The numbers represent average CPU demand over the last 1, 5, and 15 minutes. A load of 1.0 means one full CPU core was busy the entire time.

**Expected output (yours will differ):**

```
 14:22:31 up 3 days,  2:14,  1 user,  load average: 0.45, 0.38, 0.31
```

**Answer these questions before moving on:**

1. Look at your 1-minute load average. Is this server CPU-bound right now? How can you tell?
2. This server has 2 vCPUs. If the 1-minute load average showed 2.0, what would that mean?
3. If the 1-minute load average showed 4.5, what would that mean for query response times?

---

## Task 2 - Memory Pressure Check

PostgreSQL performance depends heavily on how much free memory is available for OS page cache and shared_buffers. Before adjusting any memory settings, check what the OS reports.

Run the free command with human-readable output.

```bash
free -h
```

`free` shows total, used, free, and available memory. The `-h` flag prints sizes in MB/GB instead of bytes so the numbers are easier to read. Pay close attention to the `available` column and the `Swap` row.

**Expected output (yours will differ):**

```
               total        used        free      shared  buff/cache   available
Mem:           736Mi       412Mi        48Mi        12Mi       275Mi       312Mi
Swap:          1.0Gi         0Mi       1.0Gi
```

**Answer these questions before moving on:**

1. How much memory is available on your server right now?
2. Is swap being used? Check the `used` column under Swap.
3. The default `shared_buffers` for PG 16 on this server is likely 128MB. Should you increase it right now? Why or why not? (Hint: this server has ~736MB total RAM.)
4. What does it mean if swap `used` is greater than 0 on a database server?

---

## Task 3 - CPU vs IO Wait

A slow query might not be CPU-bound at all - it could be waiting on disk. The `wa` column in vmstat tells you how much time the CPU spent idle because it was waiting for IO to complete.

Run vmstat with a 1-second interval, 5 times.

```bash
vmstat 1 5
```

`vmstat` prints system statistics. The `1` means sample every 1 second. The `5` means collect 5 samples then stop. The first line is an average since boot - focus on lines 2 through 5, which are real-time.

**Expected output (yours will differ):**

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  0      0  49312  12544 270848    0    0     4    18   42   78  1  0 98  1  0
 1  0      0  49100  12544 270848    0    0     0    64  210  340  5  1 93  1  0
 0  0      0  49100  12544 271104    0    0     0     0  188  290  2  1 97  0  0
 0  0      0  49100  12544 271104    0    0     0    48  175  280  1  0 98  1  0
 0  0      0  49100  12544 271104    0    0     0     0  165  260  1  0 99  0  0
```

Key columns to focus on:
- `r` - processes waiting to run (CPU queue)
- `b` - processes blocked waiting for IO
- `wa` - percentage of CPU time spent waiting for IO
- `us` / `sy` - user and system CPU usage

**Answer these questions before moving on:**

1. What are your `wa` values across the 4 real-time samples?
2. If `wa` was consistently at 40%, what does that tell you about the bottleneck?
3. If `wa` is high, which PostgreSQL setting might help reduce disk IO? (Think about what keeps data in memory.)
4. What does a high `r` value tell you, and how is it different from a high `wa` value?

---

## Task 4 - Disk Throughput

vmstat tells you IO is happening. iostat tells you exactly which disk and how hard it is being hit. The `%util` column is the most important - it shows what percentage of time the disk was busy.

Run iostat with extended stats, skipping idle devices, at 1-second intervals for 3 samples.

```bash
iostat -xz 1 3
```

`iostat` reports CPU and disk IO statistics. The `-x` flag shows extended per-device stats. The `-z` flag hides devices with zero activity (keeps output clean). The `1 3` means sample every 1 second, 3 times.

**Expected output (yours will differ):**

```
Device            r/s     w/s     rkB/s     wkB/s   r_await   w_await  %util
nvme0n1          0.00    4.00      0.00     48.00      0.00      1.50   0.80
```

Key columns:
- `r/s` and `w/s` - reads and writes per second
- `rkB/s` and `wkB/s` - read and write throughput in KB/s
- `r_await` and `w_await` - average wait time in milliseconds for reads and writes
- `%util` - percentage of time the device was busy

**Answer these questions before moving on:**

1. What is the `%util` for your disk right now?
2. If a disk was sitting at 95% `%util`, what are three possible causes?
3. If `w_await` is 80ms but `r_await` is 1ms, what does that suggest?
4. PostgreSQL data files are on which disk on this server? (Hint: check `df /var/lib/pgsql/` or wherever your data directory is.)

---

## Task 5 - Kernel Parameters

PostgreSQL is sensitive to certain Linux kernel settings. Before tuning PostgreSQL itself, check whether the OS settings are working with you or against you.

Run each command below one at a time. Do not chain them together.

Check vm.swappiness:

```bash
cat /proc/sys/vm/swappiness
```

Check vm.dirty_ratio:

```bash
cat /proc/sys/vm/dirty_ratio
```

Check vm.dirty_background_ratio:

```bash
cat /proc/sys/vm/dirty_background_ratio
```

Check transparent hugepages status:

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

`cat` reads the contents of a file and prints it to the screen. These `/proc` and `/sys` paths are not regular files - they are kernel tunables exposed as virtual files. Reading them shows the current active value.

**Expected output (yours will differ):**

```
60
20
10
[always] madvise never
```

**Answer these questions before moving on:**

1. What is your current swappiness value? The default on CentOS is 60. Is that good or bad for a database server?
2. What does `vm.dirty_ratio` control, and why does a high value (like 40) cause problems for PostgreSQL write performance?
3. The transparent_hugepage output shows the current setting in brackets `[ ]`. What is your server currently set to, and what should it be for PostgreSQL?
4. Which of these four values would you change first on a dedicated PostgreSQL server, and why?

---

## Task 6 - Process Investigation

OS tools show you system-wide pressure. The next step is to see which process is actually consuming those resources. If PostgreSQL is not the top consumer, something else is competing with it.

Run top in batch mode, one snapshot, showing all processes sorted by CPU.

```bash
top -bn1
```

`top` shows a live view of running processes. The `-b` flag runs it in batch (non-interactive) mode so it prints output instead of opening the full-screen display. The `-n1` flag means take one snapshot and exit. Output is sorted by CPU by default.

**Expected output (yours will differ):**

```
top - 14:35:02 up 3 days,  2:27,  1 user,  load average: 0.12, 0.18, 0.22
Tasks: 112 total,   1 running, 111 sleeping,   0 stopped,   0 zombie
%Cpu(s):  2.3 us,  0.8 sy,  0.0 ni, 96.4 id,  0.4 wa,  0.0 hi,  0.1 si,  0.0 st
MiB Mem :    736.0 total,     49.0 free,    412.0 used,    275.0 buff/cache
MiB Swap:   1024.0 total,      0.0 free,      0.0 used.    312.0 avail Mem

  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
  812 postgres  20   0  218m   42m    8m S   1.7   5.7   0:12.34 postgres
  ...
```

Now run the same command, this time sorted by memory. The `-o %MEM` flag changes the sort order.

```bash
top -bn1 -o %MEM
```

**Answer these questions before moving on:**

1. What are the top 3 processes by CPU on your server right now? List the PID, user, %CPU, and command name.
2. What are the top 3 processes by memory (%MEM)?
3. Is a PostgreSQL process (`postgres`) the heaviest consumer? If not, what process is using more CPU or memory?
4. If you saw a process called `yum` or `dnf` at the top consuming significant CPU, what would you do before adjusting any PostgreSQL settings?

---

## Answers

Review these after you have completed all six tasks and written down your own answers.

**Task 1 - Load Average**

1. On a 2-vCPU server, a load below 2.0 means the server is not CPU-bound. If your 1-minute load is 0.4, the CPUs are mostly idle. A load above 2.0 means work is queuing.
2. A load of 2.0 on a 2-core server means both cores were fully saturated for that entire minute - 100% utilization. Queries may still complete, but there is no headroom.
3. A load of 4.5 on a 2-core server means work is queuing - roughly 2.5 units of work are waiting for CPU time at any moment. Query response times will be significantly degraded.

**Task 2 - Memory Pressure**

1. The `available` column is the right number to look at - not `free`. Available includes memory that can be reclaimed from cache.
2. If swap used is 0, the OS is not paging - good. If swap used is greater than 0 on a database server, something is wrong. The OS is moving memory to disk, which causes severe latency.
3. On a 736MB server, shared_buffers at 128MB is reasonable as a starting point. The general guideline is 25% of RAM - which would be ~184MB here. Do not blindly increase it without checking available memory first. If only 48MB is free and 312MB is available, you have room to increase slightly, but be careful.
4. Swap usage on a database server almost always means a memory configuration problem - either shared_buffers or work_mem is set too high, or another process is competing for memory.

**Task 3 - CPU vs IO Wait**

1. Healthy servers running light workloads typically show `wa` at 0-2%.
2. `wa` at 40% means the CPU is not the bottleneck - the disk is. The CPU spent 40% of its time idle but unable to proceed because it was waiting for IO to return. This is a storage bottleneck, not a CPU problem.
3. Increasing `shared_buffers` keeps more data blocks in memory, reducing the number of disk reads. Also consider `effective_cache_size`, which tells the query planner how much total memory (including OS cache) is available for caching data.
4. High `r` means processes are waiting for CPU time - the CPU queue is backed up. High `wa` means processes are waiting for disk IO - the disk is the bottleneck. These require different fixes: `r` points to CPU or query optimization issues, `wa` points to storage or memory tuning.

**Task 4 - Disk Throughput**

1. A `%util` under 20% on a lightly loaded dev server is normal.
2. Three possible causes for 95% `%util`:
   - A large sequential scan (table scan with no index) is reading many data blocks from disk.
   - A checkpoint is flushing a large number of dirty buffers to disk at once - consider tuning `checkpoint_completion_target` and `max_wal_size`.
   - Another process (backup, log rotation, OS update) is competing for disk IO alongside PostgreSQL.
3. If `w_await` is 80ms but `r_await` is 1ms, writes are being significantly delayed while reads are fast. This suggests write bottleneck - possibly a slow sync operation, a heavily loaded WAL disk, or `fsync` contention.
4. PostgreSQL data files default to `/var/lib/pgsql/16/data/`. Run `df /var/lib/pgsql/` to confirm which device they are on, then match that device name in the iostat output.

**Task 5 - Kernel Parameters**

1. A swappiness of 60 (the default) tells the kernel to move memory to swap fairly aggressively. For a database server, this is too high. A value of 1 (not 0) is recommended - it tells the kernel to avoid swapping unless absolutely necessary. Setting it to 0 can cause the OOM killer to trigger instead of swapping, which is worse.
2. `vm.dirty_ratio` is the percentage of total memory that can hold dirty (unwritten) data before the kernel forces a flush. If set to 40% on a 736MB server, that is ~295MB of buffered writes. When the kernel finally flushes all of that at once, PostgreSQL IO stalls during the flush. Lower values (10-15%) mean smaller, more frequent flushes - smoother IO for databases.
3. The value in brackets is the active setting. `[always]` means transparent hugepages are enabled. For PostgreSQL, this should be set to `never`. Transparent hugepages can cause latency spikes and increased memory usage. Set it with: `echo never > /sys/kernel/mm/transparent_hugepage/enabled`
4. Transparent hugepages (`[always]`) should be changed first. It has the most direct and unpredictable negative impact on PostgreSQL performance and costs nothing to fix. Swappiness is the second priority.

**Task 6 - Process Investigation**

1. On a lightly loaded server, the top CPU consumer might be `postgres`, `systemd`, or `sshd` with very low %CPU (under 2%).
2. PostgreSQL workers appear with the command `postgres` in the COMMAND column. Multiple postgres processes are normal - one is the postmaster, others are backend workers for active connections.
3. If PostgreSQL is not the top consumer, identify what is. Common culprits on a fresh lab server: `sssd` (authentication daemon), `tuned` (system tuning daemon), or `dnf` (package manager running updates in the background).
4. If `dnf` or `yum` is actively updating packages, wait for it to finish before benchmarking or tuning. Package updates cause burst IO and CPU that will skew all your diagnostic readings.
