# Scenario 04 - Stale Postmaster PID

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL crashed (server power failure simulated).
Attempts to start PostgreSQL fail with:
'Is another postmaster running on port 5432?'
The database is DOWN.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **postmaster.pid** - This file lives in `PGDATA` and contains the PID of the running postmaster process on line 1, followed by the data directory path, start timestamp, port number, socket directory, listen address, and shared memory information. PostgreSQL checks this file at startup - if it exists and the PID in it belongs to a running process, PostgreSQL assumes another instance owns the data directory and refuses to start.

- **SIGKILL vs SIGTERM** - `kill -9` (SIGKILL) terminates a process immediately without giving it a chance to clean up. The process cannot trap or handle SIGKILL. This means PostgreSQL does not remove `postmaster.pid`, does not flush dirty pages, and does not write a clean shutdown checkpoint. This simulates a power failure or kernel OOM kill. `kill -15` (SIGTERM) or `pg_ctl stop -m fast` sends a signal that PostgreSQL can handle gracefully.

- **Crash recovery (WAL replay)** - After an unclean shutdown, PostgreSQL replays Write-Ahead Log (WAL) records from the last checkpoint to bring the database to a consistent state. This happens automatically on the next startup. The log will show "database system was not properly shut down" followed by "redo starts at" and eventually "database system is ready to accept connections."

- **Why PID 1 blocks startup** - PID 1 is the init/systemd process - it is always running. When PostgreSQL reads `postmaster.pid` and sees PID 1, it checks if that PID is alive. Since PID 1 is always alive, PostgreSQL concludes another postmaster owns the data directory and refuses to start. A truly stale PID (process no longer exists) would be detected and cleaned up automatically by PG16.

- **Shared memory cleanup after crash** - On SIGKILL, PostgreSQL may leave orphaned shared memory segments. Modern PostgreSQL (12+) uses `mmap`-based shared memory, which the OS cleans up automatically when the process dies. On older systems with System V shared memory, you might need to manually clean up with `ipcrm`.

---

## Diagnostic Steps

### Step 1 - Try to start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 2 - Check the service status

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: failed (Result: exit-code) since ...
```

### Step 3 - Check journalctl for the startup error

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20
```

Expected output (yours will differ):

```
pg_ctl: another server might be running; trying to start server anyway
FATAL:  lock file "postmaster.pid" already exists
HINT:  Is another postmaster (PID 1) running in data directory "/opt/pgsql/data"?
```

The key clue is "PID 1" - that is the init process, not a real PostgreSQL instance.

### Step 4 - Inspect the postmaster.pid file

```bash
sudo cat /opt/pgsql/data/postmaster.pid
```

Expected output (yours will differ):

```
1
/opt/pgsql/data
1713500000
5432
/var/run/postgresql
*
  5432001     0
ready
```

Line 1 shows PID `1`. That is definitely not a PostgreSQL process.

### Step 5 - Verify no actual PostgreSQL processes are running

```bash
sudo ps aux | grep postgres | grep -v grep
```

Expected output:

```
(no postgres processes shown, or only the grep itself)
```

No PostgreSQL processes are running. The PID file is stale.

---

## Resolution

### Step 1 - Remove the stale postmaster.pid file

```bash
sudo -iu postgres
```

```bash
rm /opt/pgsql/data/postmaster.pid
```

### Step 2 - Verify the file is gone

```bash
ls -la /opt/pgsql/data/postmaster.pid
```

Expected output:

```
ls: cannot access '/opt/pgsql/data/postmaster.pid': No such file or directory
```

```bash
exit
```

### Step 3 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

PostgreSQL will perform crash recovery automatically since the previous shutdown was unclean.

### Step 4 - Watch the logs for crash recovery

```bash
sudo tail -20 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/1234567
LOG:  invalid record length at 0/1234ABC: expected at least 24, got 0
LOG:  redo done at 0/1234AAA system usage: ...
LOG:  database system is ready to accept connections
```

The key line is "database system is ready to accept connections" - crash recovery completed.

### Step 5 - Verify PostgreSQL is running and accepting connections

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_postmaster_start_time();"
```

Expected output (yours will differ):

```
   pg_postmaster_start_time
-------------------------------
 2026-04-19 10:30:00.123456+00
(1 row)
```

### Step 6 - Confirm postmaster.pid has the correct PID

```bash
head -1 /opt/pgsql/data/postmaster.pid
```

Expected output (yours will differ):

```
54321
```

Verify this matches the running postgres process.

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data status
```

Expected output (yours will differ):

```
pg_ctl: server is running (PID: 54321)
```

The PIDs should match.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- PostgreSQL accepts connections
- postmaster.pid has correct PID
- postmaster.pid does not contain PID 1
- Crash recovery completed successfully

---

## Interview Discussion Points

1. **What scenarios cause a stale postmaster.pid in production?** - The most common causes are: (a) server power loss or kernel panic, (b) the OOM killer terminating the postmaster process, (c) `kill -9` issued by an operator or automation, (d) a container being forcefully stopped without a graceful shutdown signal. In all these cases, PostgreSQL has no chance to clean up its PID file.

2. **How does PostgreSQL 16 handle stale PID detection compared to older versions?** - PG16 checks whether the PID in `postmaster.pid` actually belongs to a running process. If the PID does not exist, PG16 logs a warning and removes the stale file automatically, then starts normally. However, if the PID belongs to a running process (like PID 1 or a recycled PID), PG16 cannot tell it apart from a real postmaster and refuses to start. Older versions (before PG12) were less sophisticated and often required manual cleanup.

3. **What is crash recovery and how long does it take?** - After an unclean shutdown, PostgreSQL replays all WAL records written since the last completed checkpoint. The duration depends on the `checkpoint_timeout` setting (default 5 minutes) and write volume. In the worst case, PG replays up to one checkpoint interval worth of WAL. Heavy write workloads with long checkpoint intervals can mean several minutes of recovery. Setting `checkpoint_timeout` lower reduces recovery time but increases I/O during normal operations.

4. **Should you ever manually delete postmaster.pid on a running server?** - Never. If PostgreSQL is running and you delete `postmaster.pid`, a second instance could start on the same data directory, causing catastrophic data corruption. Always verify with `ps aux | grep postgres` and `pg_isready` that no PostgreSQL processes are running before removing the PID file.

5. **What are the shared memory implications of an unclean shutdown?** - When PostgreSQL is killed with SIGKILL, dirty shared memory pages (unflushed data changes in `shared_buffers`) are lost. This is why crash recovery exists - it replays WAL to reconstruct those changes. Modern PostgreSQL (12+) uses `mmap` for shared memory, which the kernel cleans up automatically. Older versions using System V shared memory (`shmget`) could leave orphaned segments that need `ipcrm -m <shmid>` to clean up.
