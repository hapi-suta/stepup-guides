# Build 06 - OS-Level Diagnostics

**Module 12 - Performance Tuning**
**Estimated Time: 25-30 minutes**

Before you tune PostgreSQL itself, you need to understand what the operating system is telling you. This guide teaches you five essential Linux tools that every DBA should run BEFORE touching any PostgreSQL settings. Think of these as your "vital signs check" - just like a doctor checks heart rate and blood pressure before diagnosing anything.

---

## Prerequisites

- Your CentOS Stream 9 server is running
- You have your SSH key (.pem file) and server IP address from the welcome email

---

## Step 0: Connect to Your Server

Open your terminal (Mac) or PowerShell (Windows).

SSH into your server. Replace `YOUR_SERVER_IP` with the IP from your welcome email.

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@YOUR_SERVER_IP
```

This connects you to your server as the `ec2-user` account. The `-i` flag tells SSH which private key file to use for authentication.

You should now see a prompt like:

```
[ec2-user@pg-primary ~]$
```

You will stay as `ec2-user` for most of this lab. We only switch to the `postgres` user when we need to run database commands.

---

## Section 1: Understanding Load Average with uptime

The `uptime` command gives you a quick snapshot of how busy your server is. It is the first command many sysadmins run when investigating a slow system.

### Step 1.1: Run uptime

```bash
uptime
```

Expected output (yours will differ):

```
 22:05:25 up 2 days,  9 min,  1 user,  load average: 0.00, 0.00, 0.00
```

### Step 1.2: Understand the output

Here is what each piece means:

| Field | Meaning |
|-------|---------|
| `22:05:25` | Current server time |
| `up 2 days, 9 min` | How long the server has been running since last reboot |
| `1 user` | Number of users currently logged in |
| `load average: 0.00, 0.00, 0.00` | Average number of processes waiting to run over the last 1, 5, and 15 minutes |

### Step 1.3: Check your CPU count

To know if a load average is "high" or "low", you need to compare it to the number of CPUs your server has.

```bash
nproc
```

Expected output (yours will differ):

```
2
```

This tells you the server has 2 CPU cores.

### Step 1.4: How to interpret load average

The rule of thumb:

- **Load average below CPU count** (e.g., 0.5 on 2 CPUs) - Server is comfortable. Processes are not waiting.
- **Load average equal to CPU count** (e.g., 2.0 on 2 CPUs) - Server is fully utilized. Every CPU is busy, but nothing is waiting.
- **Load average above CPU count** (e.g., 5.0 on 2 CPUs) - Server is overloaded. Processes are queuing up and waiting for a CPU.

On a database server, a sustained load average above your CPU count usually means either too many queries are running at once, or queries are doing too much work (like full table scans).

---

## Section 2: Reading top Output

The `top` command shows you a live view of CPU usage, memory usage, and running processes. We will run it in "batch mode" so it prints one snapshot and exits - this is easier to read when learning.

### Step 2.1: Run top in batch mode

```bash
top -bn1 | head -15
```

The `-b` flag runs top in batch mode (prints output and exits instead of showing a live updating screen). The `-n1` flag tells it to take only 1 snapshot. The `| head -15` part shows only the first 15 lines so the output is not overwhelming.

Expected output (yours will differ):

```
top - 22:05:25 up 2 days, 9 min,  0 users,  load average: 0.00, 0.00, 0.00
Tasks: 109 total,   1 running, 108 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
MiB Mem :    736.8 total,    169.2 free,    420.5 used,    416.1 buff/cache
MiB Swap:   1024.0 total,   1017.7 free,      6.2 used.    316.3 avail Mem
```

### Step 2.2: Understand the CPU line

Look at the line that starts with `%Cpu(s)`. Each field tells you what percentage of CPU time is spent doing a specific type of work.

```
%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
```

| Field | Full Name | What It Means |
|-------|-----------|---------------|
| `us` | User | Time spent running application code (like PostgreSQL queries). High `us` means your queries are working hard. |
| `sy` | System | Time spent on operating system tasks (like writing files to disk). Usually low. |
| `ni` | Nice | Time spent on low-priority processes. Rarely important for DBAs. |
| `id` | Idle | Time the CPU is doing nothing. 100% idle means the server is not busy at all. |
| `wa` | I/O Wait | Time the CPU is waiting for disk reads or writes to finish. **This is critical for DBAs.** High `wa` often means PostgreSQL is doing too many disk reads - usually from missing indexes or sequential scans on large tables. |
| `hi` | Hardware Interrupts | Time handling hardware signals. Should be near zero. |
| `si` | Software Interrupts | Time handling software signals. Should be near zero. |
| `st` | Steal | Time "stolen" by other virtual machines on the same physical host. If this is high, your cloud provider is overloading the physical server. |

**Key takeaway for DBAs:** Focus on `us`, `wa`, and `id`. If `wa` is high, you likely have a disk I/O problem. If `us` is high, your queries are CPU-bound.

### Step 2.3: Understand the memory lines

```
MiB Mem :    736.8 total,    169.2 free,    420.5 used,    416.1 buff/cache
MiB Swap:   1024.0 total,   1017.7 free,      6.2 used.    316.3 avail Mem
```

| Field | What It Means |
|-------|---------------|
| `total` | Total physical RAM on the server (736.8 MB on this small instance) |
| `free` | RAM not being used by anything. A low number here is NOT necessarily bad - Linux intentionally uses free RAM for caching. |
| `used` | RAM actively used by running programs (including PostgreSQL) |
| `buff/cache` | RAM used by Linux to cache recently read files. This makes repeated disk reads faster. Linux will give this memory back to applications when they need it. |
| `avail Mem` | The REAL number to watch. This is how much memory is actually available for new processes. It includes `free` plus any `buff/cache` that can be reclaimed. |
| `Swap used` | How much swap space (disk used as fake RAM) is in use. |

**Why swap is a red flag on PostgreSQL servers:** Swap means the OS is moving data from RAM to disk because it ran out of physical memory. Disk is thousands of times slower than RAM. If PostgreSQL's `shared_buffers` or working memory gets swapped to disk, query performance will drop dramatically. On our server, 6.2 MB of swap is in use - that is very small and not a concern. But if you see hundreds of MB in swap, something is wrong.

---

## Section 3: vmstat - System Activity Snapshot

The `vmstat` command (virtual memory statistics) gives you a wider view than `top`. It shows processes, memory, swap, disk I/O, and CPU usage all in one compact output. It is great for watching trends over time.

### Step 3.1: Run vmstat

```bash
vmstat 2 5
```

The first number `2` means take a sample every 2 seconds. The second number `5` means take 5 samples total. So this command will run for about 10 seconds and then stop.

Expected output (yours will differ):

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0   6400 173308      0 426112    0    0   108    47   22   27  0  0 100  0  0
 0  0   6400 173308      0 426112    0    0     0     0   18   22  0  0 100  0  0
 0  0   6400 173308      0 426112    0    0     0     0   15   20  0  0 100  0  0
 0  0   6400 173308      0 426112    0    0     0     0   17   21  0  0 100  0  0
 0  0   6400 173308      0 426112    0    0     0     0   16   19  0  0 100  0  0
```

**Note:** The first line of numbers is an average since boot. Look at lines 2-5 for current activity.

### Step 3.2: Understand the key columns

| Column | Section | What It Means |
|--------|---------|---------------|
| `r` | procs | Number of processes currently running or waiting for CPU. If this is consistently higher than your CPU count (2), the server is overloaded. |
| `b` | procs | Number of processes blocked waiting for disk I/O. If this is above 0 for multiple samples, your disk is a bottleneck. |
| `swpd` | memory | Amount of swap in use (in KB). Same warning as before - high swap is bad for PostgreSQL. |
| `free` | memory | Free RAM in KB. |
| `si` | swap | Swap in - KB/sec being read FROM swap back into RAM. Should be 0. |
| `so` | swap | Swap out - KB/sec being written TO swap from RAM. **If this is above 0, the server is actively swapping and performance is degrading right now.** |
| `bi` | io | Block in - KB/sec read from disk. High during heavy sequential scans. |
| `bo` | io | Block out - KB/sec written to disk. High during checkpoints or heavy INSERT/UPDATE. |
| `cs` | system | Context switches per second. Very high numbers can indicate too many connections. |
| `us` | cpu | Same as `top` - user CPU percentage. |
| `sy` | cpu | Same as `top` - system CPU percentage. |
| `wa` | cpu | Same as `top` - I/O wait percentage. |
| `id` | cpu | Same as `top` - idle percentage. |

**Key takeaway for DBAs:** Watch the `si` and `so` columns. If `so` is above 0, the server is actively pushing memory to disk. Also watch `b` - blocked processes usually mean slow disks.

---

## Section 4: iostat - Disk I/O Analysis

The `iostat` command focuses specifically on disk performance. When `top` shows high `wa` (I/O wait), `iostat` tells you which disk is slow and why.

### Step 4.1: Install sysstat (if not already installed)

The `iostat` and `sar` commands come from the `sysstat` package. Let's make sure it is installed.

```bash
sudo dnf install -y sysstat
```

The `dnf install` command installs a package. The `-y` flag automatically answers "yes" to the confirmation prompt.

Expected output (yours will differ):

```
Last metadata expiration check: 1:23:45 ago on Sat 25 Apr 2026.
Package sysstat-12.7.2-1.el9.x86_64 is already installed.
Nothing to do.
Complete!
```

### Step 4.2: Run iostat

```bash
iostat -xz 2 3
```

The `-x` flag shows extended statistics (more columns). The `-z` flag hides devices with zero activity so the output is cleaner. `2 3` means sample every 2 seconds, take 3 samples.

Expected output (yours will differ):

```
Linux 5.14.0-391.el9.x86_64 (pg-primary)     04/25/2026     _x86_64_    (2 CPU)

avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           0.04    0.00    0.06    0.01    0.00   99.89

Device            r/s     rkB/s   rrqm/s  %rrqm r_await rareq-sz     w/s     wkB/s   wrqm/s  %wrqm w_await wareq-sz     d/s     dkB/s   drqm/s  %drqm d_await dareq-sz     f/s f_await  aqu-sz  %util
nvme0n1          2.00    216.75     0.00   0.00    0.35   108.38     0.57     94.81     0.22  27.78    1.02   166.32    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.15
```

### Step 4.3: Understand the key columns

| Column | What It Means |
|--------|---------------|
| `r/s` | Read operations per second. High during sequential scans. |
| `w/s` | Write operations per second. High during heavy INSERT/UPDATE/DELETE or checkpoints. |
| `rkB/s` | Kilobytes read per second from this device. |
| `wkB/s` | Kilobytes written per second to this device. |
| `r_await` | Average time (in milliseconds) a read request waited to be completed. Under 1ms is excellent. Over 10ms is slow. |
| `w_await` | Average time (in milliseconds) a write request waited to be completed. Same thresholds as r_await. |
| `%util` | How busy the disk is, as a percentage. 100% means the disk is fully saturated - it cannot take any more requests. |

**What "disk saturated" looks like:**

```
Device            r/s     rkB/s   ...     w/s     wkB/s   ...  r_await  w_await  %util
nvme0n1        850.00  108800.00  ...   420.00   53760.00  ...    45.20    38.50   99.80
```

In this example, `%util` is at 99.80% - the disk is maxed out. The `r_await` of 45ms means reads are waiting a long time. This server needs either faster disks, fewer queries, or better indexes to reduce disk reads.

**Our server shows 0.15% util** - the disk is barely working. That is expected on an idle lab server.

---

## Section 5: sar - Historical Data

The `sar` command (System Activity Reporter) is unique because it can show you what happened in the PAST. The other tools (`top`, `vmstat`, `iostat`) only show what is happening right now. If a problem occurred at 3 AM and you are investigating at 9 AM, `sar` is your friend.

### Step 5.1: Enable sysstat data collection

The `sysstat` service must be running to collect historical data. Let's make sure it is enabled.

```bash
sudo systemctl enable --now sysstat
```

This starts the `sysstat` service immediately (`--now`) and also configures it to start automatically on boot (`enable`).

Expected output (yours will differ):

```
Created symlink /etc/systemd/system/multi-user.target.wants/sysstat.service -> /usr/lib/systemd/system/sysstat.service.
```

### Step 5.2: Check CPU usage over time

```bash
sar -u 1 3
```

The `-u` flag tells `sar` to report CPU utilization. `1 3` means sample every 1 second, take 3 samples.

Expected output (yours will differ):

```
Linux 5.14.0-391.el9.x86_64 (pg-primary)     04/25/2026     _x86_64_    (2 CPU)

22:10:01        CPU     %user     %nice   %system   %iowait    %steal     %idle
22:10:02        all      0.00      0.00      0.50      0.00      0.00     99.50
22:10:03        all      0.00      0.00      0.00      0.00      0.00    100.00
22:10:04        all      0.50      0.00      0.00      0.00      0.00     99.50
Average:        all      0.17      0.00      0.17      0.00      0.00     99.67
```

The columns match what you learned in the `top` section (`%user`, `%iowait`, `%idle`, etc.).

### Step 5.3: Check memory usage over time

```bash
sar -r 1 3
```

The `-r` flag tells `sar` to report memory utilization.

Expected output (yours will differ):

```
Linux 5.14.0-391.el9.x86_64 (pg-primary)     04/25/2026     _x86_64_    (2 CPU)

22:11:01    kbmemfree   kbavail kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit
22:11:02       173308    316300    420548     55.74         0    426112    598400     34.32
22:11:03       173308    316300    420548     55.74         0    426112    598400     34.32
22:11:04       173308    316300    420548     55.74         0    426112    598400     34.32
Average:       173308    316300    420548     55.74         0    426112    598400     34.32
```

The `%memused` column shows the percentage of RAM in use (55.74%). The `kbavail` column is the most important - it shows how much memory is truly available.

### Step 5.4: When to use sar

Use `sar` when:

- A problem happened in the past and you need to investigate after the fact
- You want to see trends over hours or days
- You need to prove to a manager that the server WAS overloaded at a specific time

Historical data is stored in `/var/log/sa/`. You can look at yesterday's data with:

```bash
sar -u -f /var/log/sa/sa$(date -d yesterday +%d)
```

The `-f` flag tells `sar` to read from a specific file instead of collecting live data. **Note:** This command will only work if sysstat has been running for at least one day. On a fresh lab server, the file may not exist yet.

---

## Section 6: Connecting OS Metrics to PostgreSQL

Now that you know how to read these tools, here is how to connect what you see to PostgreSQL problems. This is the most important section - it turns raw numbers into action items.

### High %wa (I/O Wait) - Check for Missing Indexes

When `top` or `vmstat` shows high I/O wait, the CPU is spending a lot of time waiting for disk reads. In PostgreSQL, this usually means:

- Queries are doing sequential scans (reading entire tables from disk) instead of using indexes
- The `shared_buffers` cache is too small, forcing PostgreSQL to read from disk constantly

**What to do next:** Connect to PostgreSQL and check for sequential scans.

Switch to the postgres user:

```bash
sudo su - postgres
```

This switches you to the `postgres` operating system user, which has permission to run PostgreSQL commands.

Connect to labdb:

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Check for tables with high sequential scan counts:

```sql
SELECT relname, seq_scan, idx_scan
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 5;
```

This query shows the top 5 tables by number of sequential scans. If `seq_scan` is high and `idx_scan` is low (or zero), that table probably needs an index.

Exit psql:

```sql
\q
```

Exit the postgres user and return to ec2-user:

```bash
exit
```

### High %us (User CPU) - CPU-Bound Queries

When `us` is high, PostgreSQL is using a lot of CPU to process queries. This usually means:

- Complex queries with lots of sorting, joining, or aggregating
- Functions or calculations running inside queries
- `pg_stat_statements` extension can show you which queries use the most CPU

**What to do next:** Look at `pg_stat_statements` (covered in a later Build guide).

### Swap In Use - shared_buffers May Be Too Large

If `vmstat` shows `swpd` is growing or `so` (swap out) is above 0, the server does not have enough RAM for everything running on it. On a PostgreSQL server, the most common cause is `shared_buffers` being set too high.

On this lab server with 736 MB of RAM, `shared_buffers` should be no more than about 180 MB (roughly 25% of RAM). Setting it to 512 MB would leave almost no room for the operating system and other PostgreSQL memory needs.

### High Load Average - Too Many Active Queries

If `uptime` shows a load average above your CPU count (2 on this server) for an extended period:

- Too many queries are running simultaneously
- Check `max_connections` and consider using a connection pooler like PgBouncer
- Look for long-running queries with `pg_stat_activity`

---

## Quick Reference Card

Save this for daily use:

| Symptom You See | Tool to Confirm | Likely PostgreSQL Cause |
|----------------|-----------------|------------------------|
| Server feels slow | `uptime` | Load average above CPU count |
| High I/O wait | `iostat -xz 2 3` | Missing indexes, seq scans |
| Memory pressure | `vmstat 2 5` (check `so` column) | shared_buffers too large |
| CPU pegged | `top -bn1` (check `us`) | Complex queries, bad plans |
| Past incident | `sar -u -f /var/log/sa/saDD` | Historical CPU/memory data |

---

## What You Learned

In this guide, you used five OS-level diagnostic tools:

1. **uptime** - Quick load average check (compare to `nproc`)
2. **top** - CPU breakdown (us, wa, id) and memory overview
3. **vmstat** - Process, memory, swap, I/O, and CPU in one view
4. **iostat** - Detailed disk performance (%util, await)
5. **sar** - Historical data for past incidents

You also learned how to connect OS-level symptoms to PostgreSQL problems - high I/O wait means check for missing indexes, swap usage means check shared_buffers sizing, and high CPU means check your queries.

**Next up:** Build 07 - OS Kernel Tuning for PostgreSQL, where you will change kernel settings to make the OS work better with PostgreSQL.
