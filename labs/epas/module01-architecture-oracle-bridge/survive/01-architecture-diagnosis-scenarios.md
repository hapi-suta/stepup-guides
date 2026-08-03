---
layout: default
title: "Survive 01 - Architecture Diagnosis Scenarios"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 7
locked: "no"
---

# Survive 01 - Architecture Diagnosis Scenarios

## Severity

All three scenarios are **SEV-1 (Production Down or At Risk)**. These represent real incidents you will encounter as a production EPAS DBA.

## Format

**Paper-based diagnostic walkthrough.** No servers required. You are given monitoring alerts, log excerpts, and command outputs - exactly what you would see during a real incident. Your job is to diagnose root cause, plan resolution, and identify prevention measures.

Read each scenario carefully. Work through the diagnostic steps before looking at the resolution. In a real incident you will not have answer keys.

---

## Scenario 1: WAL Archiver Stuck - Disk Filling

### Alert

```
[CRITICAL] 2026-06-07 03:14:22 UTC
Host: epas-prod-primary (10.0.1.50)
Check: disk_usage_var_lib_edb
Status: CRITICAL - /var/lib/edb filesystem 96% full. Growth rate: 2GB/hour.
Threshold: >90% critical
Escalation: PagerDuty - DBA On-Call
```

### Key Concepts for Revision

- **WAL (Write-Ahead Log)** is EPAS's crash recovery and replication mechanism. Every data change is written to WAL segments (16 MB files by default) in `$PGDATA/pg_wal/` before the actual data files are updated. WAL segments accumulate until they are archived and recycled.
- **archive_command** is the shell command EPAS runs to copy completed WAL segments to a safe location (NFS, S3, local backup dir). When this command fails, WAL segments pile up in `pg_wal/` because EPAS cannot recycle them until they are successfully archived.
- **Archive status files** in `pg_wal/archive_status/` track each segment's state: `.ready` means "needs archiving," `.done` means "archived successfully." Hundreds of `.ready` files means the archiver is falling behind or failing.

### Available Evidence

**Disk usage breakdown:**

```
$ du -sh /var/lib/edb/as16/data/*/
4.0K    /var/lib/edb/as16/data/pg_commit_ts/
180G    /var/lib/edb/as16/data/pg_wal/
12G     /var/lib/edb/as16/data/base/
1.2G    /var/lib/edb/as16/data/pg_stat/
8.0K    /var/lib/edb/as16/data/pg_snapshots/
52K     /var/lib/edb/as16/data/pg_subtrans/
2.1G    /var/lib/edb/as16/data/pg_tblspc/
256K    /var/lib/edb/as16/data/pg_xact/
4.0K    /var/lib/edb/as16/data/pg_multixact/
```

**Archive status directory:**

```
$ ls /var/lib/edb/as16/data/pg_wal/archive_status/*.ready | wc -l
11264

$ ls -lt /var/lib/edb/as16/data/pg_wal/archive_status/*.ready | tail -3
-rw------- 1 enterprisedb enterprisedb 0 Jun  6 14:22 00000001000003A200000044.ready
-rw------- 1 enterprisedb enterprisedb 0 Jun  6 14:22 00000001000003A200000043.ready
-rw------- 1 enterprisedb enterprisedb 0 Jun  6 14:22 00000001000003A200000042.ready

$ ls /var/lib/edb/as16/data/pg_wal/archive_status/*.done | wc -l
0
```

**Archiver process:**

```
$ ps aux | grep archiver
enterprisedb  8821  0.0  0.1  389204  6240 ?  Ss  Jun06  0:12 postgres: archiver last was 00000001000003A200000041 at 2026-06-06 14:21:58 UTC
```

**PostgreSQL log (last archiver entries):**

```
2026-06-06 14:22:01.334 UTC [8821] LOG:  archive command failed with exit code 1
2026-06-06 14:22:01.334 UTC [8821] DETAIL:  The failed archive command was:
  cp pg_wal/00000001000003A200000042 /mnt/nfs-backup/wal_archive/00000001000003A200000042
2026-06-06 14:22:01.335 UTC [8821] LOG:  archiving write-ahead log file
  "00000001000003A200000042" failed too many times, will try again later
```

**NFS mount check:**

```
$ mount | grep nfs
$ df -h /mnt/nfs-backup/
df: /mnt/nfs-backup/: Stale file handle

$ showmount -e 10.0.5.10
clnt_create: RPC: Unable to receive
```

**Current archive settings:**

```
$ psql -U enterprisedb -c "SELECT name, setting FROM pg_settings
  WHERE name IN ('archive_mode','archive_command','archive_timeout');"
      name       |                              setting
-----------------+--------------------------------------------------------------------
 archive_mode    | on
 archive_command | cp %p /mnt/nfs-backup/wal_archive/%f
 archive_timeout | 300
```

### Diagnostic Steps

1. **Confirm what is filling the disk.** The `du -sh` output immediately shows `pg_wal/` at 180 GB - that is the problem. The `base/` directory (actual table data) is only 12 GB.

2. **Check archive status.** 11,264 `.ready` files with zero `.done` files means archiving has been failing for every segment since it broke. The archiver process is still running but the last successful archive was segment `...0041` at 14:21:58 UTC - roughly 13 hours ago.

3. **Read the archiver error.** The log shows `archive command failed with exit code 1` for a simple `cp` to `/mnt/nfs-backup/`. This tells you the destination is the problem, not the source.

4. **Check the NFS mount.** The `mount` output shows nothing mounted. `df` reports a stale file handle. `showmount` cannot reach the NFS server at all. The NFS server (10.0.5.10) is down or the network path to it is broken.

5. **Assess urgency.** At 96% full and growing 2 GB/hour, you have roughly 2-4 hours before the filesystem hits 100%. When that happens, EPAS will PANIC and shut down because it cannot write new WAL segments. This is a race against time.

### Resolution Steps

1. **Immediate - free disk space.** If the WAL segments have been replicated to standbys (check `pg_stat_replication`), you can force a checkpoint and manually remove old WAL segments using `pg_archivecleanup`:

   ```sql
   -- Find the oldest WAL segment still needed by any standby
   SELECT slot_name, restart_lsn FROM pg_replication_slots;
   ```

   ```bash
   pg_archivecleanup /var/lib/edb/as16/data/pg_wal/ 00000001000003A200000042
   ```

   This removes segments older than the specified file. Only do this if you accept that those segments are NOT archived (you may lose PITR capability for that window).

2. **Fix the NFS mount.** Contact the storage/infrastructure team to bring the NFS server back online. Once it is reachable:

   ```bash
   umount -f /mnt/nfs-backup
   mount -t nfs 10.0.5.10:/exports/wal_archive /mnt/nfs-backup
   ```

3. **Alternative - redirect archiving temporarily.** If NFS will take time to fix, change the archive_command to a local fallback path:

   ```sql
   ALTER SYSTEM SET archive_command = 'cp %p /var/lib/edb/wal_archive_local/%f';
   SELECT pg_reload_conf();
   ```

   The archiver will start working through the backlog of `.ready` files. As segments are archived, EPAS recycles them and disk usage drops.

4. **Monitor recovery.** Watch the `.ready` file count drop and disk usage stabilize:

   ```bash
   watch -n 5 'ls /var/lib/edb/as16/data/pg_wal/archive_status/*.ready | wc -l'
   ```

### Prevention

- **Use a resilient archive destination.** Replace the simple `cp` with a script that tries multiple destinations (local + remote) or uses `aws s3 cp` with retry logic. Never depend on a single NFS mount.
- **Monitor archive lag.** Set an alert when the count of `.ready` files exceeds 100 or when the oldest `.ready` file is more than 10 minutes old.
- **Set `max_wal_size` appropriately.** This controls how much WAL EPAS keeps before forcing a checkpoint. A smaller value means checkpoints happen more often and old WAL is recycled faster - but it does NOT help if archiving is broken because EPAS will not recycle unarchived segments regardless.
- **Separate `pg_wal` onto its own filesystem.** If `pg_wal` fills its own mount point, the main data directory is not affected. EPAS will still stop accepting writes, but the operating system and other services stay healthy.

### Interview Discussion Points

1. **"Why can't PostgreSQL/EPAS just delete old WAL segments when the disk is full, even if archiving failed?"** - This tests whether you understand that WAL is the only guarantee of durability. Deleting unarchived WAL means you lose the ability to do point-in-time recovery (PITR) to any point covered by those segments. EPAS deliberately chooses to stop rather than silently lose recoverability.

2. **"In Oracle, the ARCn process fills the Fast Recovery Area (FRA). How does Oracle handle a full FRA compared to how EPAS handles a full pg_wal directory?"** - Oracle suspends all DML and waits until space is freed in the FRA (or the DBA intervenes). EPAS behaves similarly - it PANICs if it cannot write WAL. The key difference is that Oracle's FRA is a managed space with automatic cleanup policies, while EPAS relies entirely on the archive_command succeeding.

3. **"If you had to choose between losing PITR coverage for the last 13 hours or letting the database crash from disk full, which would you choose and why?"** - This is a judgment call. In most production environments, a running database serving customers is worth more than 13 hours of PITR coverage - especially if you have streaming replication standbys that received those WAL segments. The right answer shows you can weigh tradeoffs under pressure.

---

## Scenario 2: Postmaster Crash Loop

### Alert

```
[CRITICAL] 2026-06-07 01:45:33 UTC
Host: epas-prod-primary (10.0.1.50)
Check: service_edb-as-16
Status: CRITICAL - EPAS service edb-as-16 restarting every 30 seconds.
        Application connections refused.
Threshold: 3+ restarts in 5 minutes
Escalation: PagerDuty - DBA On-Call + App Team Lead
```

### Key Concepts for Revision

- **The postmaster** is the parent process of all EPAS backends. It listens on port 5444 (EPAS default), forks child processes for each client connection, and manages shared memory. If the postmaster dies, every connection dies with it.
- **Crash recovery** happens automatically when the postmaster starts after an unclean shutdown. EPAS replays WAL from the last checkpoint forward to bring the database to a consistent state. This is analogous to Oracle's SMON instance recovery.
- **pg_control** is a small file in `$PGDATA/global/` that stores critical metadata: the last checkpoint location, the database system identifier, WAL segment size, and the database state (in production, shut down, in recovery, etc.). If pg_control is corrupted, EPAS cannot start because it does not know where to begin crash recovery.

### Available Evidence

**systemd journal:**

```
$ journalctl -u edb-as-16 --since "1 hour ago" --no-pager | tail -30

Jun 07 01:45:01 epas-prod-primary systemd[1]: Starting EDB Postgres Advanced Server 16...
Jun 07 01:45:02 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:02 UTC [19201]
  LOG:  starting EDB Postgres Advanced Server 16.4.0
Jun 07 01:45:02 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:02 UTC [19201]
  LOG:  database system was interrupted; last known up at 2026-06-07 01:38:14 UTC
Jun 07 01:45:02 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:02 UTC [19201]
  LOG:  database system was not properly shut down; automatic recovery in progress
Jun 07 01:45:02 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:02 UTC [19201]
  LOG:  redo starts at 3A2/42000028
Jun 07 01:45:03 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:03 UTC [19201]
  PANIC:  could not locate a valid checkpoint record
Jun 07 01:45:03 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:03 UTC [19201]
  LOG:  startup process (PID 19202) was terminated by signal 6: Aborted
Jun 07 01:45:03 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:03 UTC [19201]
  LOG:  aborting startup due to startup process failure
Jun 07 01:45:03 epas-prod-primary edb-as-16[19201]: 2026-06-07 01:45:03 UTC [19201]
  LOG:  database system is shut down
Jun 07 01:45:04 epas-prod-primary systemd[1]: edb-as-16.service: Main process exited, code=exited, status=1/FAILURE
Jun 07 01:45:04 epas-prod-primary systemd[1]: edb-as-16.service: Failed with result 'exit-code'.
Jun 07 01:45:34 epas-prod-primary systemd[1]: edb-as-16.service: Scheduled restart job, restart counter is at 47.
Jun 07 01:45:34 epas-prod-primary systemd[1]: Starting EDB Postgres Advanced Server 16...
```

**pg_controldata output:**

```
$ /usr/edb/as16/bin/pg_controldata /var/lib/edb/as16/data/
WARNING: Calculated CRC checksum does not match value stored in file.
WARNING: Either the file is corrupt, or it has a different layout than this program is expecting.
The results below are untrustworthy.

pg_control version number:            1300
Catalog version number:               202307071
Database system identifier:           7412839501927364821
Database cluster state:               in production
pg_control last modified:             Sat Jun  7 01:38:14 2026
Latest checkpoint location:           3A2/42000028
Latest checkpoint's REDO location:    3A2/42000028
Latest checkpoint's TimeLineID:       1
Latest checkpoint's PrevTimeLineID:   1
...
```

**Process investigation (what happened at 01:38):**

```
$ grep "01:38" /var/log/messages
Jun  7 01:38:12 epas-prod-primary operator[18500]: kill -9 sent to PID 8801 (postmaster)
  by user admin_jdoe via sudo

$ last -i | head -5
admin_jdoe  pts/2   10.0.100.55  Sat Jun  7 01:35 - 01:42  (00:07)
```

**Shared memory state:**

```
$ ipcs -m | grep enterprisedb
0x00000000 1572864  enterprisedb 600    2147483648  0

$ ls -la /var/lib/edb/as16/data/postmaster.pid
-rw------- 1 enterprisedb enterprisedb 88 Jun  7 01:45:34 postmaster.pid
```

### Diagnostic Steps

1. **Read the PANIC message.** The key line is `PANIC: could not locate a valid checkpoint record`. This means EPAS started crash recovery, found the checkpoint location recorded in pg_control, but the actual WAL at that location was unreadable or inconsistent.

2. **Check pg_controldata.** The CRC checksum warning confirms pg_control is corrupted. The `Database cluster state: in production` is also wrong for a database that is currently down - it should say `shut down` or `in recovery`. This means pg_control was not updated cleanly during the crash.

3. **Find root cause.** The `/var/log/messages` entry is the smoking gun: someone ran `kill -9` on the postmaster process (PID 8801) at 01:38. A `kill -9` (SIGKILL) does not give the postmaster any chance to perform an orderly shutdown. If a checkpoint was in progress at that moment, pg_control may have been partially written - hence the corruption.

4. **Assess the damage.** pg_control corruption is serious but recoverable in most cases. The data files and WAL files themselves may be fine - the problem is that EPAS cannot find its starting point for recovery.

5. **Check for stale shared memory and lock files.** The `ipcs` output shows a shared memory segment still allocated to enterprisedb. The `postmaster.pid` file exists and is being recreated each restart attempt. These are symptoms, not causes - they get cleaned up when the postmaster starts successfully.

### Resolution Steps

1. **Stop the restart loop.** Disable the systemd service so it stops restarting while you work:

   ```bash
   systemctl stop edb-as-16
   systemctl disable edb-as-16
   ```

2. **Clean up stale resources.** Remove the stale PID file and shared memory segment:

   ```bash
   rm /var/lib/edb/as16/data/postmaster.pid
   ipcrm -m 1572864
   ```

3. **Attempt recovery with pg_resetwal (last resort).** `pg_resetwal` rewrites pg_control with sane values and resets the WAL position. This is destructive - it may cause data loss for any transactions that were in-flight during the crash:

   ```bash
   # As enterprisedb user
   /usr/edb/as16/bin/pg_resetwal -f /var/lib/edb/as16/data/
   ```

   The `-f` flag forces the reset even though pg_control is unreadable. pg_resetwal will scan the `pg_wal/` directory to determine the correct WAL position.

4. **Start EPAS and verify.**

   ```bash
   systemctl enable edb-as-16
   systemctl start edb-as-16
   ```

   Once running, immediately check for data integrity:

   ```sql
   -- Check for corrupted pages
   SELECT datname FROM pg_database;
   -- If amcheck extension is available:
   CREATE EXTENSION IF NOT EXISTS amcheck;
   SELECT bt_index_check(c.oid)
     FROM pg_index i
     JOIN pg_class c ON i.indexrelid = c.oid
     WHERE c.relpages > 0;
   ```

5. **Take a fresh base backup immediately.** After pg_resetwal, the existing backup chain is broken. You cannot use previous WAL archives for PITR through the reset point:

   ```bash
   pg_basebackup -h localhost -p 5444 -U enterprisedb -D /backup/fresh-basebackup -Ft -z -P
   ```

6. **Investigate the human cause.** User `admin_jdoe` ran `kill -9` on the postmaster. Determine why and implement access controls to prevent it. This should trigger an incident review.

### Prevention

- **Never use `kill -9` on the postmaster.** Use `pg_ctl stop -m fast` for an orderly fast shutdown or `pg_ctl stop -m immediate` as a last resort (this is still safer than SIGKILL because the postmaster handles SIGQUIT by aborting all backends cleanly before exiting).
- **Restrict sudo access.** Only DBAs should have sudo access to the `enterprisedb` account or the ability to kill EPAS processes. Use sudoers rules to limit what commands operators can run.
- **Enable `full_page_writes = on`** (it is on by default). This ensures that after a crash, EPAS can recover any partially-written data pages. It does not prevent pg_control corruption from SIGKILL, but it limits collateral damage.
- **Maintain a streaming standby.** If the primary's pg_control is corrupted, you can promote the standby instead of running pg_resetwal. This is faster and does not risk data loss.

### Interview Discussion Points

1. **"Compare what happens during EPAS crash recovery to Oracle SMON instance recovery. What are the key differences?"** - Both replay transaction logs (WAL vs redo) from the last checkpoint to bring the database to a consistent state, then roll back uncommitted transactions. The key difference is that Oracle SMON also handles tablespace recovery and undo segment cleanup, while EPAS has a simpler architecture - there is no separate undo tablespace. EPAS uses MVCC with in-place tuple versioning, so "rollback" means marking transaction IDs as aborted in pg_xact (formerly pg_clog), not physically undoing changes.

2. **"Under what circumstances would you use pg_resetwal, and what are the risks?"** - This tests whether you understand that pg_resetwal is truly a last resort. It resets the transaction counter, OID counter, and WAL position. The risks: transactions that committed right before the crash may appear to have never happened. Replication slots become invalid. The backup chain is broken. If you have a standby, promoting it is almost always better.

3. **"The postmaster was killed during a checkpoint. Why does that specifically corrupt pg_control rather than data files?"** - pg_control is updated as a single 8 KB write during the checkpoint. If the kernel had not flushed this write to disk before the SIGKILL, the file on disk contains the previous (or partial) checkpoint data. Data files are protected by full_page_writes - the first modification to any page after a checkpoint writes the entire page to WAL, so crash recovery can restore it. But pg_control itself is not WAL-logged - it is updated directly.

---

## Scenario 3: Connection Storms After Failover

### Alert

```
[WARNING] 2026-06-07 08:22:15 UTC
Host: epas-prod-standby-promoted (10.0.2.50)
Check: connection_count
Status: WARNING - 487/500 connections used on new primary.
        Application latency 15x baseline (avg 3200ms vs 210ms normal).
Threshold: >80% max_connections = warning, >95% = critical
Escalation: Slack #dba-oncall + App Team
```

### Key Concepts for Revision

- **max_connections** sets the hard limit on simultaneous client connections. In EPAS/PostgreSQL, each connection gets its own backend process (forked from the postmaster). Unlike Oracle's shared server architecture, there is no built-in connection multiplexing - 500 connections means 500 OS processes, each consuming memory (work_mem, temp_buffers, etc.).
- **Connection pooling** with PgBouncer or Pgpool-II sits between the application and EPAS, maintaining a smaller pool of actual database connections and multiplexing application requests across them. This is not optional in production EPAS - it is essential.
- **EFM (EDB Failover Manager)** monitors primary/standby health and performs automated failover. After promoting a standby, EFM updates a virtual IP or notifies applications to reconnect. The "storm" happens because all application instances reconnect simultaneously.

### Available Evidence

**pg_stat_activity summary:**

```
=# SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count DESC;
        state        | count
---------------------+-------
 idle in transaction  |   401
 active               |    52
 idle                 |    31
 disabled             |     3
                      |     3
(5 rows)

=# SELECT usename, count(*) FROM pg_stat_activity
   WHERE state = 'idle in transaction'
   GROUP BY usename ORDER BY count DESC;
   usename    | count
--------------+-------
 app_service  |   312
 reporting_svc|    67
 etl_loader   |    22
(3 rows)

=# SELECT wait_event_type, wait_event, count(*)
   FROM pg_stat_activity
   WHERE state = 'active'
   GROUP BY wait_event_type, wait_event
   ORDER BY count DESC;
 wait_event_type |   wait_event    | count
-----------------+-----------------+-------
 Lock            | transactionid   |    38
 LWLock          | ProcArrayLock   |     9
 Client          | ClientRead      |     5
(3 rows)
```

**Application logs (from app team):**

```
2026-06-07 08:12:01 [pool-manager] WARN  Connection to 10.0.1.50:5444 lost. Reconnecting...
2026-06-07 08:12:01 [pool-manager] INFO  Attempting connection to 10.0.2.50:5444 (failover target)
2026-06-07 08:12:02 [pool-manager] INFO  Connection established to 10.0.2.50:5444
2026-06-07 08:12:02 [pool-manager] INFO  Initializing 50 connections (pool min-size)
2026-06-07 08:12:02 [pool-manager] INFO  BEGIN issued on all idle connections (validation query)
...
(repeated across 8 application server instances)
```

**EFM log:**

```
2026-06-07 08:10:45 [INFO]  Primary agent on 10.0.1.50 not responding. Starting failover.
2026-06-07 08:10:46 [INFO]  Promoting standby 10.0.2.50 to primary.
2026-06-07 08:10:48 [INFO]  Standby promoted successfully. New primary: 10.0.2.50.
2026-06-07 08:10:49 [INFO]  Virtual IP 10.0.1.100 moved to 10.0.2.50.
2026-06-07 08:10:50 [INFO]  Fencing old primary 10.0.1.50 (stopping EPAS service).
2026-06-07 08:10:51 [INFO]  Failover completed in 6 seconds.
```

**Connection timeline (from monitoring):**

```
08:10:45  Connections: 0 (standby, read-only)
08:10:48  Connections: 0 (promoted, accepting writes)
08:12:01  Connections: 47 (first app server reconnects)
08:12:02  Connections: 198 (4 app servers reconnected, each opening 50)
08:12:03  Connections: 396 (all 8 app servers reconnected)
08:12:05  Connections: 487 (reporting + ETL services reconnected)
08:15:00  Connections: 487 (no change - connections stuck idle in transaction)
08:22:15  Connections: 487 (alert fires - still stuck)
```

**Server resources on new primary:**

```
$ free -h
              total   used   free   shared  buff/cache  available
Mem:           64G     58G    1.2G    4.8G      4.0G       1.0G
Swap:          8G      3.2G   4.8G

$ top -bn1 | head -5
top - 08:22:30 up 142 days,  3:14,  2 users,  load average: 47.82, 38.15, 12.04
Tasks: 529 total,  53 running, 476 sleeping,   0 stopped,   0 zombie
%Cpu(s): 78.3 us, 12.1 sy,  0.0 ni,  4.2 id,  3.8 wa,  0.0 hi,  1.6 si
MiB Mem:  65536.0 total,   1228.8 free,  59392.0 used,   4915.2 buff/cache
MiB Swap:  8192.0 total,   4915.2 free,   3276.8 used.   1024.0 avail Mem
```

### Diagnostic Steps

1. **Understand the connection state.** 401 out of 487 connections are `idle in transaction`. This means each connection executed a `BEGIN` but never committed or rolled back. They are holding locks and consuming memory but doing no useful work.

2. **Identify the cause from app logs.** The application pool manager issues `BEGIN` on all idle connections as a "validation query" to test if the connection is alive. After failover, 8 app servers each opened 50 connections (their pool minimum) and ran `BEGIN` on all of them. That is 400 connections sitting in an open transaction doing nothing - matching the 401 `idle in transaction` count almost exactly.

3. **Check the lock contention.** 38 active queries are waiting on `transactionid` locks. These are real queries that need to modify rows, but the idle-in-transaction sessions are holding row-level locks from their `BEGIN` statements (some pool managers also run a simple SELECT as part of validation, which can take MVCC snapshots that block VACUUM and autovacuum).

4. **Assess memory pressure.** The server is using 58 GB of 64 GB RAM and has swapped 3.2 GB. Each backend process consumes memory for work_mem, temp_buffers, and catalog caches. With 487 backends, the new primary (which was sized as a standby, possibly with less RAM) is under severe memory pressure.

5. **Note the timing.** Failover completed at 08:10:51. The connection storm happened at 08:12:01-08:12:05 - about 70 seconds later. The alert fired at 08:22:15 - ten minutes of the system sitting in this degraded state. No self-healing occurred because the idle transactions never time out on their own.

### Resolution Steps

1. **Terminate the idle-in-transaction connections immediately.** This is the fastest way to restore service:

   ```sql
   -- Terminate all idle-in-transaction sessions older than 1 minute
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE state = 'idle in transaction'
     AND state_change < now() - interval '1 minute';
   ```

   This will disconnect those clients. Their connection pools will reconnect, but this time the system will not be under storm conditions.

2. **Set idle_in_transaction_session_timeout** to prevent this from happening again:

   ```sql
   ALTER SYSTEM SET idle_in_transaction_session_timeout = '60s';
   SELECT pg_reload_conf();
   ```

   This automatically aborts and disconnects any session that sits in `idle in transaction` for more than 60 seconds.

3. **Deploy PgBouncer in front of EPAS.** This is the real fix. PgBouncer in `transaction` pooling mode multiplexes hundreds of application connections onto a much smaller pool of actual database connections (e.g., 50-100):

   ```ini
   [databases]
   production = host=127.0.0.1 port=5444 dbname=production

   [pgbouncer]
   listen_port = 6432
   pool_mode = transaction
   max_client_conn = 2000
   default_pool_size = 50
   reserve_pool_size = 10
   ```

   Applications connect to PgBouncer on port 6432 instead of directly to EPAS on port 5444.

4. **Fix the application connection pool configuration.** The root cause is the pool manager's `BEGIN`-based validation query. Change it to a non-transactional health check:

   ```
   # HikariCP example
   connectionTestQuery=SELECT 1
   # Do NOT use BEGIN as a validation query
   ```

   Also configure connection pool ramp-up (gradual reconnection) instead of immediate reconnection of all minimum connections:

   ```
   minimumIdle=5       # Start with 5, grow as needed
   maximumPoolSize=50  # Cap at 50
   ```

5. **Size the standby appropriately.** If the standby is expected to become a primary during failover, it must have the same RAM and CPU as the primary. In this case, 64 GB may not be enough if you are running 500 connections. Either reduce max_connections and use PgBouncer, or increase RAM.

### Prevention

- **Always deploy PgBouncer or Pgpool-II in production.** Direct application-to-database connections in EPAS/PostgreSQL are an anti-pattern at scale. Oracle RAC has built-in connection multiplexing through shared server mode and DRCP - EPAS does not.
- **Configure `idle_in_transaction_session_timeout`** on every production instance. 60-120 seconds is a reasonable default. No legitimate application workload should leave a transaction open and idle for that long.
- **Set `statement_timeout`** as a safety net (e.g., `statement_timeout = '30s'` for OLTP). This prevents any single query from running indefinitely.
- **Test failover with realistic application load.** Most teams test failover with a single psql session. Test with all 8 application servers connected and running production-like traffic. The connection storm behavior only appears under realistic conditions.
- **Configure connection pool reconnection backoff.** Application pools should use exponential backoff with jitter when reconnecting after a failover - not immediate full-pool reconnection.

### Interview Discussion Points

1. **"In Oracle, Transparent Application Failover (TAF) and service relocation handle reconnection after failover. What is the EPAS equivalent, and where are the gaps?"** - EPAS does not have a built-in equivalent to TAF. EFM handles promotion and VIP failover, but the application is responsible for detecting the broken connection, reconnecting, and retrying the failed transaction. Libraries like libpq support `target_session_attrs=read-write` and multi-host connection strings, but there is no automatic in-flight transaction replay like TAF provides. This gap is why connection poolers and proper application retry logic are critical in EPAS environments.

2. **"Why does PostgreSQL/EPAS use a process-per-connection model instead of threads, and what are the operational implications?"** - Historical reasons (portability, simplicity, crash isolation) and safety (a crashed backend does not take down other connections). The operational implication is that memory consumption scales linearly with connection count - each backend allocates its own work_mem, temp_buffers, and catalog cache. At 500 connections with work_mem = 64 MB, you could theoretically use 32 GB just for sort operations. This is why connection pooling is not optional. Oracle's multi-threaded architecture (shared server mode) handles thousands of connections with lower per-session overhead.

3. **"You see 400 connections in 'idle in transaction' state. Walk me through exactly what resources those sessions are consuming and what damage they are causing, even though they are doing nothing."** - Each idle-in-transaction session holds: (a) an OS process consuming base memory (~10 MB per backend for stack, catalog cache, etc.), (b) any row-level locks from previous statements in the transaction, which block other sessions trying to modify those rows, (c) a transaction snapshot that prevents VACUUM from cleaning up dead tuples created after the snapshot was taken - this causes table bloat, and (d) a slot in the process array (ProcArray) that every new snapshot must scan, slowing down `GetSnapshotData()` for all other backends. The damage compounds over time: bloat grows, lock waits cascade, and memory pressure increases.
