# USE-09: Linux Troubleshooting Drills

**Interview prep for:** Linux & Systems Fundamentals with Senior DevOps Engineer (Lukasz)
**Format:** 5 timed drills simulating real production incidents
**Total time:** ~60 minutes

## Lab Nodes

| Hostname       | Public IP        | Private IP      | Role                                      |
|----------------|------------------|-----------------|-------------------------------------------|
| pg-primary     | 100.26.54.122    | 172.31.19.86    | PG 17 primary, PgBouncer :6432, Redis :6379 |
| pg-replica     | 54.144.241.128   | 172.31.22.69    | PG 17 standby, pgBackRest, Ceph-sim LVM    |
| pg-container   | 34.228.73.232    | 172.31.21.45    | Docker: PG :5433, MySQL :3306, Redis :6380  |
| pg-ops         | 34.228.32.17     | 172.31.26.19    | Prometheus :9090, Grafana :3000             |

**SSH:** `ssh -i ~/.ssh/id_ed25519 ec2-user@<public-ip>`

---

## How to Use These Drills

Each drill simulates an alert or a teammate pinging you in Slack. Start a timer when you begin.
The goal is not just to find the answer - it is to build a repeatable diagnostic pattern you
can explain clearly in an interview.

For each drill:

1. Read the scenario
2. Start your timer
3. Run every command on the specified server
4. Note what each output tells you
5. Arrive at the root cause and fix
6. Stop your timer and compare against the target

---

## Drill 1: "PostgreSQL Is Slow - High I/O Wait"

**Scenario:** A Prometheus alert fires at 2 AM - pg-primary CPU is sitting at 40% iowait.
The on-call engineer pings you: "Database feels slow. Queries that normally take 50ms are
taking 2-3 seconds."

**Target time:** 15 minutes

---

### Step 1 - Confirm the I/O wait is real

On **pg-primary**, as **ec2-user**:

```bash
vmstat 1 5
```

This prints system stats once per second for 5 samples. Look at the `wa` column under `cpu`.

```
Expected output (yours will differ):
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0      0  52840  12456 678432    0    0     4   128  312  587  3  1 92  4  0
 0  1      0  52712  12456 678432    0    0     0   256  298  543  2  1 89  8  0
...
```

**What to look for:** The `wa` column shows the percentage of CPU time spent waiting on I/O.
Anything above 10-15% consistently is a problem. The `b` column shows processes blocked
waiting for I/O - if this is above 0 regularly, something is saturating the disk.

---

### Step 2 - Identify which disk device is overloaded

Still as **ec2-user** on **pg-primary**:

```bash
iostat -x 1 5
```

This shows extended disk statistics per device, one sample per second for 5 rounds.

```
Expected output (yours will differ):
Device    r/s     rkB/s   w/s     wkB/s   await  %util
xvda      0.50    8.00    45.20   2048.00  12.34  67.80
...
```

**What to look for:**

- `await` - Average time (ms) for I/O requests to complete. Above 20ms on SSD-backed EBS is concerning.
- `%util` - How busy the device is. Above 80% means the device is near saturation.
- `w/s` and `wkB/s` - Write operations per second and write throughput. High values point to heavy write activity.

If `iostat` is not installed, install it:

```bash
sudo dnf install -y sysstat
```

---

### Step 3 - Find which process is doing the most I/O

Still as **ec2-user** on **pg-primary**:

```bash
sudo iotop -ao
```

The `-a` flag shows accumulated I/O since iotop started. The `-o` flag shows only processes
that are actually doing I/O (hides idle processes).

```
Expected output (yours will differ):
Total DISK READ:       0.00 B/s | Total DISK WRITE:     12.45 M/s
Actual DISK READ:      0.00 B/s | Actual DISK WRITE:     8.23 M/s
   TID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN      IO    COMMAND
  1842 be/4 postgres    0.00 B    128.34 M     0.00 %  45.12 % postgres: checkpointer
  1845 be/4 postgres    0.00 B     24.56 M     0.00 %  12.34 % postgres: walwriter
...
```

**What to look for:** If `postgres: checkpointer` is at the top writing hundreds of MB,
checkpoints are the likely cause. If it is `postgres: walwriter`, WAL volume is the issue.

If `iotop` is not installed:

```bash
sudo dnf install -y iotop
```

Press `q` to exit iotop.

---

### Step 4 - Check if the checkpointer is the culprit

Still as **ec2-user** on **pg-primary**:

```bash
ps aux | grep checkpoint
```

```
Expected output (yours will differ):
postgres    1842  2.3  1.0 2345678  40960 ?  Ds   02:14   0:45 postgres: checkpointer
...
```

The `D` state (uninterruptible sleep) means the process is blocked on disk I/O. This
confirms the checkpointer is actively writing and waiting on disk.

---

### Step 5 - Check checkpoint configuration

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

Run these queries one at a time:

```sql
SHOW checkpoint_completion_target;
```

```
Expected output (yours will differ):
 checkpoint_completion_target
------------------------------
 0.9
(1 row)
```

This controls how much of the checkpoint interval PostgreSQL uses to spread out writes.
A value of `0.9` means PG tries to finish writing within 90% of the checkpoint_timeout
period. A value of `0.5` would cram all the writes into half the time - causing I/O spikes.

```sql
SHOW checkpoint_timeout;
```

```
Expected output (yours will differ):
 checkpoint_timeout
--------------------
 5min
(1 row)
```

The default is 5 minutes. For write-heavy workloads, increasing this to 15-30 minutes
reduces checkpoint frequency and spreads writes out more.

---

### Step 6 - Check checkpoint statistics

Still in **psql** on **pg-primary** as **postgres**:

```sql
SELECT checkpoints_timed,
       checkpoints_req,
       buffers_checkpoint,
       buffers_backend,
       maxwritten_clean
FROM pg_stat_bgwriter;
```

```
Expected output (yours will differ):
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_backend | maxwritten_clean
-------------------+-----------------+--------------------+-----------------+------------------
              1245 |              87 |            2345678 |           12345 |               34
(1 row)
```

**What to look for:**

- `checkpoints_req` - Checkpoints triggered because WAL hit `max_wal_size`. If this is high relative to `checkpoints_timed`, your max_wal_size is too small.
- `buffers_backend` - Buffers written directly by backend processes (not bgwriter/checkpointer). High values mean the background processes cannot keep up.
- `maxwritten_clean` - Times the bgwriter stopped because it hit `bgwriter_lru_maxpages`. High values mean bgwriter is throttled.

Exit psql:

```
\q
```

---

### Step 7 - Check WAL volume

Still as **postgres** on **pg-primary**:

```bash
ls -la /var/lib/pgsql/17/data/pg_wal/ | head -20
```

```
Expected output (yours will differ):
total 1048576
drwx------. 3 postgres postgres     4096 Jun 18 02:30 .
drwx------. 20 postgres postgres    4096 Jun 18 02:30 ..
-rw-------. 1 postgres postgres 16777216 Jun 18 02:30 000000010000000000000042
-rw-------. 1 postgres postgres 16777216 Jun 18 02:28 000000010000000000000043
...
```

Each WAL segment is 16 MB. Count the total files to estimate accumulation:

```bash
ls /var/lib/pgsql/17/data/pg_wal/ | wc -l
```

If you see 100+ WAL files, that is 1.6+ GB of WAL. Combined with frequent requested
checkpoints, this confirms `max_wal_size` needs to be increased.

```bash
exit
```

---

### Root Cause and Fix

**Root cause:** Frequent checkpoints due to undersized `max_wal_size` or low
`checkpoint_timeout`. The checkpointer has to flush large amounts of dirty buffers
to disk in short bursts, causing I/O spikes.

**Fix (on pg-primary, as ec2-user):**

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
SELECT pg_reload_conf();
```

```
\q
```

```bash
exit
```

These changes take effect immediately (no restart needed). The checkpoint interval
will stretch from 5 minutes to 15 minutes, and PG can accumulate up to 4 GB of WAL
before forcing a checkpoint.

---

## Drill 2: "Can't Connect to PostgreSQL"

**Scenario:** The application team pings you at 9:15 AM: "We're getting 'connection refused'
errors trying to reach PostgreSQL on pg-primary. All our services are down."

**Target time:** 10 minutes

---

### Step 1 - Verify the connection failure

On **pg-primary**, as **ec2-user**:

```bash
pg_isready -h 100.26.54.122 -p 5432
```

```
Expected output (yours will differ):
100.26.54.122:5432 - accepting connections
```

If it says `no response` or `rejecting connections`, PG is either down or not listening
on that address. The exit code tells you the status: 0 = accepting, 1 = rejecting,
2 = no response.

---

### Step 2 - Check if PostgreSQL is running

Still as **ec2-user** on **pg-primary**:

```bash
sudo systemctl status postgresql-17
```

```
Expected output (yours will differ):
 postgresql-17.service - PostgreSQL 17 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled)
     Active: active (running) since Thu 2026-06-18 08:00:00 UTC; 1h ago
   Main PID: 1234 (postgres)
...
```

**What to look for:**

- `Active: active (running)` means PG is up. If it says `inactive (dead)` or `failed`, PG is down.
- If it is down, check why: `sudo journalctl -u postgresql-17 --since "1 hour ago" --no-pager | tail -30`

---

### Step 3 - Check if PG is listening on the right port and address

Still as **ec2-user** on **pg-primary**:

```bash
ss -tlnp | grep 5432
```

```
Expected output (yours will differ):
LISTEN 0      244          0.0.0.0:5432      0.0.0.0:*    users:(("postgres",pid=1234,fd=7))
LISTEN 0      244             [::]:5432         [::]:*    users:(("postgres",pid=1234,fd=8))
```

**What to look for:**

- `0.0.0.0:5432` means PG is listening on all IPv4 interfaces. This is correct.
- `127.0.0.1:5432` means PG is only listening on localhost - remote connections will fail.
- If nothing appears, PG is not listening on port 5432 at all.

---

### Step 4 - Check the firewall

Still as **ec2-user** on **pg-primary**:

```bash
sudo firewall-cmd --list-all
```

```
Expected output (yours will differ):
public (active)
  target: default
  services: cockpit dhcpv6-client ssh
  ports: 5432/tcp 6432/tcp 6379/tcp
...
```

**What to look for:** Port `5432/tcp` must appear in the `ports` line. If it is missing,
that is your problem.

To add the port (if missing):

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
```

```bash
sudo firewall-cmd --reload
```

---

### Step 5 - Check pg_hba.conf for the client IP

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
cat /var/lib/pgsql/17/data/pg_hba.conf | grep -v "^#" | grep -v "^$"
```

```
Expected output (yours will differ):
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             172.31.0.0/16           scram-sha-256
host    replication     replicator      172.31.22.69/32         scram-sha-256
...
```

**What to look for:** There must be a `host` line that matches the client's IP range,
the database they are connecting to, and the user they are connecting as. If the
application connects from the VPC (`172.31.x.x`), the `172.31.0.0/16` line covers it.
If they connect from a public IP, that IP or its CIDR must be listed.

---

### Step 6 - Check listen_addresses

Still as **postgres** on **pg-primary**:

```bash
psql -d quantdb -c "SHOW listen_addresses;"
```

```
Expected output (yours will differ):
 listen_addresses
------------------
 *
(1 row)
```

A value of `*` means PG listens on all interfaces. If it says `localhost`, only local
connections work. Changing this requires a restart.

---

### Step 7 - Check the PostgreSQL logs for errors

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
sudo tail -50 /var/lib/pgsql/17/data/log/postgresql-$(date +%a).log
```

The log file naming pattern uses the day of the week (e.g., `postgresql-Thu.log`).
Look for lines containing `FATAL`, `could not bind`, or `connection`.

```
Expected output (yours will differ):
2026-06-18 09:14:32.123 UTC [5678] FATAL:  no pg_hba.conf entry for host "10.0.1.55", user "appuser", database "quantdb", no encryption
...
```

This tells you exactly which client was rejected and why.

---

### Step 8 - Check SELinux

Still as **ec2-user** on **pg-primary**:

```bash
sudo ausearch -m avc -ts recent
```

```
Expected output (yours will differ):
<no matches>
```

If `<no matches>` appears, SELinux is not blocking anything. If you see AVC denials
related to `postgresql`, SELinux is interfering. Check the current mode:

```bash
getenforce
```

If it returns `Enforcing` and you see AVC denials for postgres, you can temporarily
set it to permissive to test:

```bash
sudo setenforce 0
```

Then try the connection again. If it works, the permanent fix is to create a proper
SELinux policy, not to leave it permissive.

---

### Root Cause and Fix

**Most common causes (in order of frequency):**

1. **pg_hba.conf** - Missing entry for the client IP. Fix: add the appropriate `host` line and `SELECT pg_reload_conf();`
2. **Firewall** - Port 5432 not open. Fix: `sudo firewall-cmd --permanent --add-port=5432/tcp && sudo firewall-cmd --reload`
3. **listen_addresses** - Set to `localhost`. Fix: change to `*` in postgresql.conf and restart PG
4. **PG is down** - Crashed or was stopped. Fix: `sudo systemctl start postgresql-17` and investigate why it stopped
5. **SELinux** - Blocking the network socket. Fix: create proper SELinux policy module

---

## Drill 3: "Server Is Swapping"

**Scenario:** Monitoring shows pg-primary response times have tripled in the last hour.
A quick glance at Grafana on pg-ops shows memory utilization at 95%. You suspect
the server is swapping.

**Target time:** 10 minutes

---

### Step 1 - Check swap usage

On **pg-primary**, as **ec2-user**:

```bash
free -h
```

```
Expected output (yours will differ):
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       2.9Gi       120Mi       256Mi       780Mi       430Mi
Swap:          2.0Gi       512Mi       1.5Gi
```

**What to look for:**

- `Swap used` - Any value above 0 means the system has swapped at some point. 512Mi of active swap is significant.
- `Mem available` - This is the real indicator of how much memory is available (includes reclaimable cache). Below 200Mi on a 4 GB server is tight.
- `shared` - This is mostly PG's shared_buffers mapped via shared memory.

---

### Step 2 - Check if swapping is happening right now

Still as **ec2-user** on **pg-primary**:

```bash
vmstat 1 5
```

```
Expected output (yours will differ):
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0 524288  52840  12456 678432    0    0     4   128  312  587  3  1 92  4  0
 0  0 524288  52712  12456 678432   24   16     0   256  298  543  2  1 89  8  0
...
```

**What to look for:**

- `si` (swap in) - Pages swapped in from disk. If this is above 0 consistently, the system is actively reading from swap.
- `so` (swap out) - Pages swapped out to disk. Active swapping out means the system is under memory pressure right now.
- `swpd` - Total swap in use (KB). This number going up between samples means memory pressure is increasing.

If both `si` and `so` are 0, the system swapped at some point in the past but is not actively swapping now.

---

### Step 3 - Get detailed memory breakdown

Still as **ec2-user** on **pg-primary**:

```bash
cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|Dirty|Cached)"
```

```
Expected output (yours will differ):
MemTotal:        3960060 kB
MemFree:          122344 kB
MemAvailable:     440680 kB
Cached:           680432 kB
SwapCached:        12456 kB
SwapTotal:       2097148 kB
SwapFree:        1572864 kB
Dirty:              4528 kB
```

**What to look for:**

- `Dirty` - Pages modified in memory but not yet written to disk. High values (hundreds of MB) can cause I/O storms during writeback.
- `SwapCached` - Swap pages that are also in memory. This means the kernel is keeping a copy in both places - it read something back from swap but has not freed the swap slot yet.
- `MemAvailable` vs `MemTotal` - If available is less than 10% of total, memory is tight.

---

### Step 4 - Check the swappiness setting

Still as **ec2-user** on **pg-primary**:

```bash
sysctl vm.swappiness
```

```
Expected output (yours will differ):
vm.swappiness = 30
```

This value (0-100) controls how aggressively the kernel swaps out memory pages.
The default is usually 30 or 60. For database servers, a value of `1` is recommended -
it tells the kernel to avoid swapping unless absolutely necessary.

A value of `0` means "never swap unless the system would otherwise OOM." A value of `1`
means "swap only under extreme memory pressure." For PostgreSQL, `1` is the sweet spot.

---

### Step 5 - Check PostgreSQL memory settings

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
SHOW shared_buffers;
```

```
Expected output (yours will differ):
 shared_buffers
----------------
 128MB
(1 row)
```

```sql
SHOW work_mem;
```

```
Expected output (yours will differ):
 work_mem
----------
 64MB
(1 row)
```

```sql
SHOW maintenance_work_mem;
```

```
Expected output (yours will differ):
 maintenance_work_mem
----------------------
 256MB
(1 row)
```

**What to look for:** `shared_buffers` is allocated once at startup. `work_mem` is allocated
per-sort-operation per-query per-connection. A 64 MB work_mem with 100 connections
running complex queries could use 6.4 GB of RAM - far more than the 3.8 GB on this server.

---

### Step 6 - Find top memory consumers

Exit psql first:

```
\q
```

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
ps aux --sort=-%mem | head -10
```

```
Expected output (yours will differ):
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
postgres    1234  0.5 18.2 2345678 720000 ?      Ss   08:00   1:23 postgres: server process
postgres    5678  2.1  8.4 2345678 332000 ?      Rs   09:15   0:45 postgres: quantdb appuser SELECT
postgres    5679  1.8  7.2 2345678 285000 ?      Rs   09:15   0:42 postgres: quantdb appuser SELECT
...
```

**What to look for:**

- `RSS` - Resident Set Size in KB. This is the actual physical memory used by the process.
- `%MEM` - Percentage of total RAM. If a single backend is using 8%+ on a 4 GB server, that is 300+ MB - likely a large sort or hash operation consuming work_mem.

---

### Step 7 - Calculate total potential PG memory usage

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
SELECT count(*) AS active_connections FROM pg_stat_activity;
```

```
Expected output (yours will differ):
 active_connections
--------------------
                 47
(1 row)
```

Now calculate worst-case memory usage in your head:

- shared_buffers: 128 MB (fixed)
- work_mem potential: 47 connections x 64 MB = 3,008 MB (worst case)
- maintenance_work_mem: 256 MB (autovacuum workers use this)
- Total possible: 128 + 3,008 + 256 = 3,392 MB

On a server with 3,840 MB total RAM (and the OS needs ~500 MB), this is way too close.

```
\q
```

```bash
exit
```

---

### Root Cause and Fix

**Root cause:** `work_mem` is set too high for the number of concurrent connections.
Each connection can allocate multiple `work_mem` chunks for sorts, hashes, and merges.
Combined with shared_buffers and OS overhead, total memory demand exceeds physical RAM.

**Fix (on pg-primary, as ec2-user):**

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET vm.swappiness = '1';
SELECT pg_reload_conf();
```

Note: `vm.swappiness` is an OS-level setting, not a PG setting. Set it at the OS level:

```
\q
```

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
sudo sysctl -w vm.swappiness=1
```

To make it permanent across reboots:

```bash
echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.d/99-postgres.conf
```

---

## Drill 4: "Disk Filling Up"

**Scenario:** PagerDuty alert fires at 3 AM: "pg-primary root volume at 85% - threshold 80%."
The volume was at 45% yesterday. Something is growing fast.

**Target time:** 15 minutes

---

### Step 1 - See the full picture

On **pg-primary**, as **ec2-user**:

```bash
df -hT
```

```
Expected output (yours will differ):
Filesystem     Type      Size  Used Avail Use% Mounted on
/dev/xvda1     xfs        20G   17G  3.0G  85% /
devtmpfs       devtmpfs  1.9G     0  1.9G   0% /dev
tmpfs          tmpfs     1.9G   12M  1.9G   1% /dev/shm
...
```

**What to look for:**

- `Use%` - Which filesystem is filling up. If it is `/`, everything shares that space - PG data, logs, WAL, OS files.
- `Type` - XFS or ext4 tells you the filesystem type, which affects how you handle recovery.
- `Size` vs `Used` - 17 GB used on a 20 GB volume leaves only 3 GB. PG can crash if it runs out of space during a checkpoint.

---

### Step 2 - Check total PostgreSQL data size

Still as **ec2-user** on **pg-primary**:

```bash
sudo du -sh /var/lib/pgsql/17/data/
```

```
Expected output (yours will differ):
12G     /var/lib/pgsql/17/data/
```

This tells you how much of the disk PG is consuming total. If PG data is 12 GB out of
17 GB used, PG is the dominant consumer.

---

### Step 3 - Check WAL accumulation

Still as **ec2-user** on **pg-primary**:

```bash
sudo du -sh /var/lib/pgsql/17/data/pg_wal/
```

```
Expected output (yours will differ):
4.8G    /var/lib/pgsql/17/data/pg_wal/
```

WAL files are 16 MB each. 4.8 GB is about 300 WAL segments. This is a lot - it could
mean a replication slot is preventing WAL cleanup.

Count the files:

```bash
sudo ls /var/lib/pgsql/17/data/pg_wal/ | wc -l
```

```
Expected output (yours will differ):
302
```

---

### Step 4 - Check for temp file accumulation

Still as **ec2-user** on **pg-primary**:

```bash
sudo du -sh /var/lib/pgsql/17/data/base/pgsql_tmp/ 2>/dev/null || echo "No temp directory"
```

```
Expected output (yours will differ):
1.2G    /var/lib/pgsql/17/data/base/pgsql_tmp/
```

Temp files are created when queries need more memory than `work_mem` allows - sorts and
hashes spill to disk. 1.2 GB of temp files suggests large queries are running. These files
are cleaned up when the query finishes or the session disconnects.

---

### Step 5 - Check for table bloat

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
SELECT relname,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
WHERE relkind = 'r'
ORDER BY pg_total_relation_size(oid) DESC
LIMIT 10;
```

```
Expected output (yours will differ):
      relname       | total_size
--------------------+------------
 market_ticks       | 3200 MB
 order_history      | 1800 MB
 signal_log         | 890 MB
 position_snapshot  | 456 MB
...
```

**What to look for:** If a table is much larger than expected, it may be bloated (dead
tuples from UPDATE/DELETE that VACUUM has not cleaned up). Compare against what you know
the table should be.

---

### Step 6 - Check WAL retention settings

Still in **psql** on **pg-primary** as **postgres**:

```sql
SHOW max_wal_size;
```

```
Expected output (yours will differ):
 max_wal_size
--------------
 1GB
(1 row)
```

If `max_wal_size` is 1 GB but the actual WAL directory is 4.8 GB, something is preventing
WAL cleanup. The most common cause is a replication slot.

---

### Step 7 - Check replication slots holding WAL

Still in **psql** on **pg-primary** as **postgres**:

```sql
SELECT slot_name,
       slot_type,
       active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

```
Expected output (yours will differ):
   slot_name    | slot_type | active | retained_wal
----------------+-----------+--------+--------------
 replica_slot   | physical  | t      | 256 MB
 old_subscriber | logical   | f      | 4200 MB
(1 row)
```

**What to look for:**

- `active = f` (false) with a large `retained_wal` - This is your culprit. An inactive slot is holding 4.2 GB of WAL that cannot be recycled.
- This happens when a subscriber goes down or a slot is created and never used.

---

### Step 8 - Check log file sizes

```
\q
```

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
sudo du -sh /var/lib/pgsql/17/data/log/
```

```
Expected output (yours will differ):
890M    /var/lib/pgsql/17/data/log/
```

If PG logs are large, check if `log_statement = 'all'` is set - this logs every single
query and can fill disks fast. Also check `log_min_duration_statement` - if set to `0`,
it logs every query with its duration.

---

### Root Cause and Fix

**Root cause:** An inactive logical replication slot (`old_subscriber`) is preventing WAL
cleanup, causing 4.2 GB of WAL accumulation. Combined with normal data growth and log
files, the disk hit 85%.

**Fix (on pg-primary, as ec2-user):**

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

Drop the inactive slot (only after confirming it is truly abandoned):

```sql
SELECT pg_drop_replication_slot('old_subscriber');
```

Verify WAL count drops over the next few checkpoints:

```sql
SELECT count(*) FROM pg_ls_waldir();
```

```
\q
```

```bash
exit
```

**Prevention:** Set `max_slot_wal_keep_size` to limit how much WAL any single slot can retain:

```bash
sudo su - postgres
```

```bash
psql -d quantdb -c "ALTER SYSTEM SET max_slot_wal_keep_size = '2GB';"
```

```bash
psql -d quantdb -c "SELECT pg_reload_conf();"
```

```bash
exit
```

---

## Drill 5: "PostgreSQL OOM Killed"

**Scenario:** You wake up to a page: "PostgreSQL on pg-primary is down." You SSH in
and find PG was restarted by systemd. You suspect the Linux OOM killer struck overnight.

**Target time:** 10 minutes

---

### Step 1 - Confirm the OOM kill

On **pg-primary**, as **ec2-user**:

```bash
sudo dmesg | grep -i "oom\|kill" | tail -20
```

```
Expected output (yours will differ):
[234567.890123] Out of memory: Killed process 1234 (postgres) total-vm:4567890kB, anon-rss:2345678kB, file-rss:12345kB, shmem-rss:678901kB
[234567.890456] oom_reaper: reaped process 1234 (postgres), now anon-rss:0kB, file-rss:0kB, shmem-rss:0kB
...
```

**What to look for:**

- `Out of memory: Killed process` - Confirms the OOM killer acted.
- `total-vm` - Total virtual memory the process had mapped.
- `anon-rss` - Anonymous (non-file-backed) resident memory. This is the real memory usage that triggered the kill.
- The process name in parentheses tells you which PG process was killed.

---

### Step 2 - Check systemd journal for the restart

Still as **ec2-user** on **pg-primary**:

```bash
sudo journalctl -u postgresql-17 --since "yesterday" --no-pager | tail -30
```

```
Expected output (yours will differ):
Jun 18 03:14:22 pg-primary postgres[1234]: LOG:  server process (PID 5678) was terminated by signal 9: Killed
Jun 18 03:14:22 pg-primary postgres[1234]: LOG:  terminating any other active server processes
Jun 18 03:14:23 pg-primary postgres[1234]: LOG:  all server processes terminated; reinitializing
Jun 18 03:14:24 pg-primary postgres[1234]: LOG:  database system was interrupted; last known up at 2026-06-18 02:45:12 UTC
Jun 18 03:14:25 pg-primary postgres[1234]: LOG:  database system was not properly shut down; automatic recovery in progress
Jun 18 03:14:26 pg-primary postgres[1234]: LOG:  redo starts at 0/42000028
...
```

**What to look for:**

- `terminated by signal 9: Killed` - Signal 9 (SIGKILL) from the OOM killer. PG cannot catch this signal.
- `automatic recovery in progress` - PG is replaying WAL to recover to a consistent state. This means data is safe (assuming WAL is intact) but there is downtime during recovery.

---

### Step 3 - Check current memory state

Still as **ec2-user** on **pg-primary**:

```bash
free -h
```

```
Expected output (yours will differ):
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       1.2Gi       1.8Gi       256Mi       780Mi       2.3Gi
Swap:          2.0Gi         0B       2.0Gi
```

After the OOM kill and restart, memory looks fine because the offending processes are gone.
The problem was what happened before the kill, not the current state.

---

### Step 4 - Get details on what was killed

Still as **ec2-user** on **pg-primary**:

```bash
sudo dmesg | grep -A5 "Out of memory"
```

```
Expected output (yours will differ):
[234567.890123] Out of memory: Killed process 1234 (postgres) total-vm:4567890kB, anon-rss:2345678kB, file-rss:12345kB, shmem-rss:678901kB
[234567.890124] oom_kill_process: total pagecache:678901kB, total shmem:256789kB, total rss:3456789kB
[234567.890125] Memory cgroup out of memory: Killed process 1234 (postgres)
[234567.890126] [ pid ]   uid  tgid total_vm      rss pgtables_bytes swapents    oom_score_adj name
[234567.890127] [ 1234]    26  1234  4567890  2345678   4567890        0              0 postgres
[234567.890128] [ 5678]    26  5678  2345678   890123   1234567        0              0 postgres
...
```

**What to look for:**

- The table shows every process's memory usage at the time of the OOM event.
- `rss` column (in pages, multiply by 4 to get KB) shows actual memory per process.
- `oom_score_adj` of 0 means no OOM priority adjustment - the kernel picks the largest consumer.
- Add up the RSS of all postgres processes to see the total PG memory footprint at the time of the crash.

---

### Step 5 - Check overcommit settings

Still as **ec2-user** on **pg-primary**:

```bash
sysctl vm.overcommit_memory
```

```
Expected output (yours will differ):
vm.overcommit_memory = 0
```

```bash
sysctl vm.overcommit_ratio
```

```
Expected output (yours will differ):
vm.overcommit_ratio = 50
```

**What the values mean:**

- `vm.overcommit_memory = 0` - Heuristic overcommit. The kernel guesses whether a memory allocation will succeed. It often says yes even when physical memory is tight, leading to OOM kills later.
- `vm.overcommit_memory = 1` - Always overcommit. Never say no to malloc(). This makes OOM kills even more likely.
- `vm.overcommit_memory = 2` - Strict overcommit. The kernel limits total virtual memory to swap + (RAM x overcommit_ratio/100). Allocations that exceed this limit fail immediately with an error instead of succeeding and getting OOM-killed later. This is what PostgreSQL recommends.

With `vm.overcommit_memory = 2` and `vm.overcommit_ratio = 50`, the system allows:
2 GB swap + (3.8 GB x 0.50) = 3.9 GB total commit limit. This prevents overallocation.

---

### Step 6 - Calculate PG memory footprint

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW autovacuum_work_mem;
SHOW max_connections;
```

```
Expected output (yours will differ):
 shared_buffers
----------------
 128MB

 work_mem
----------
 64MB

 maintenance_work_mem
----------------------
 256MB

 autovacuum_work_mem
---------------------
 -1

 max_connections
-----------------
 100
```

**Memory math:**

- `shared_buffers`: 128 MB (fixed at startup)
- `work_mem` worst case: 100 connections x 64 MB = 6,400 MB (each connection can use multiple work_mem chunks)
- `maintenance_work_mem`: 256 MB (used by VACUUM, CREATE INDEX, etc.)
- `autovacuum_work_mem = -1` means it falls back to `maintenance_work_mem` (256 MB). With 3 autovacuum workers, that is 768 MB.
- Theoretical max: 128 + 6,400 + 768 = 7,296 MB on a 3,840 MB server

This is severely overprovisioned.

```
\q
```

```bash
exit
```

---

### Step 7 - Review what happened overnight

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

Check if there were large queries running overnight:

```sql
SELECT datname, usename, state, query,
       pg_size_pretty(pg_total_relation_size(
           (regexp_match(query, 'FROM\s+(\w+)', 'i'))[1]::regclass
       )) AS table_size
FROM pg_stat_activity
WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%'
LIMIT 5;
```

Also check if any large maintenance operations ran:

```sql
SELECT datname, usename, query, backend_start
FROM pg_stat_activity
WHERE query ILIKE '%vacuum%' OR query ILIKE '%reindex%' OR query ILIKE '%create index%'
LIMIT 5;
```

```
\q
```

```bash
exit
```

---

### Root Cause and Fix

**Root cause:** `work_mem` at 64 MB with 100 max_connections means PG can theoretically
allocate over 6 GB of sort/hash memory on a server with only 3.8 GB of RAM. An overnight
batch of complex queries (or a runaway query with many sort nodes) exhausted physical
memory, and the Linux OOM killer terminated the postgres process.

**Fix (on pg-primary, as ec2-user):**

Step A - Tune PG memory settings:

```bash
sudo su - postgres
```

```bash
psql -d quantdb
```

```sql
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET maintenance_work_mem = '128MB';
ALTER SYSTEM SET shared_buffers = '960MB';
SELECT pg_reload_conf();
```

Note: `shared_buffers` change requires a restart to take effect.

```
\q
```

```bash
exit
```

Step B - Set strict overcommit at the OS level:

On **pg-primary**, as **ec2-user**:

```bash
sudo sysctl -w vm.overcommit_memory=2
```

```bash
sudo sysctl -w vm.overcommit_ratio=80
```

Make permanent:

```bash
echo "vm.overcommit_memory = 2" | sudo tee -a /etc/sysctl.d/99-postgres.conf
```

```bash
echo "vm.overcommit_ratio = 80" | sudo tee -a /etc/sysctl.d/99-postgres.conf
```

Step C - Restart PG to apply shared_buffers change:

```bash
sudo systemctl restart postgresql-17
```

```bash
sudo systemctl status postgresql-17
```

---

## Interview Topic Mapping

This table maps each drill to the Linux and systems topics that Lukasz is likely to explore
during the interview.

| Drill | Scenario | Key Interview Topics |
|-------|----------|---------------------|
| 1 | High I/O Wait | `vmstat`, `iostat`, `iotop`, I/O scheduling, checkpoint tuning, WAL mechanics, EBS performance characteristics |
| 2 | Can't Connect | `systemctl`, `ss`/`netstat`, firewall-cmd, pg_hba.conf, listen_addresses, SELinux, `ausearch`, log analysis |
| 3 | Server Swapping | `free`, `/proc/meminfo`, `vm.swappiness`, shared memory, work_mem sizing, process memory (`ps aux --sort`), Linux page cache |
| 4 | Disk Filling Up | `df`, `du`, filesystem types, WAL lifecycle, replication slots, temp files, log rotation, `max_slot_wal_keep_size` |
| 5 | OOM Killed | `dmesg`, `journalctl`, OOM killer scoring, `vm.overcommit_memory` modes, memory overcommit math, PG memory architecture |

### Cross-Cutting Themes Lukasz Will Probe

These topics come up across multiple drills and are worth studying separately:

- **How Linux virtual memory works** - Page cache, anonymous pages, dirty pages, writeback, swappiness. Drill 1 and 3 both touch this.
- **systemd service management** - `systemctl status`, `journalctl -u`, service restart behavior, `Restart=on-failure` in unit files. Drill 2 and 5.
- **Monitoring and observability** - How you would set up alerts for each scenario. What Prometheus metrics (node_exporter) correspond to each drill.
- **Capacity planning** - How to size a PG server's memory, disk, and I/O based on workload. Drill 3 and 5 are about getting the math right.
- **Defense in depth** - Each fix should include both an immediate remediation and a preventive measure. Lukasz will want to hear both.

### Quick Reference - Key Commands to Memorize

```
vmstat 1 5          - CPU, memory, swap, I/O overview (1-second intervals, 5 samples)
iostat -x 1 5       - Per-device I/O stats with await and utilization
free -h             - Memory and swap summary in human-readable format
df -hT              - Filesystem usage with filesystem type
du -sh <dir>        - Directory size summary
ss -tlnp            - Listening TCP sockets with process names
dmesg | grep -i oom - Check for OOM killer events
journalctl -u <svc> - Service-specific logs from systemd journal
ps aux --sort=-%mem - Processes sorted by memory usage (descending)
sysctl -a | grep vm - All virtual memory kernel parameters
```
