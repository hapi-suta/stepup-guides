# Scenario 02 - Old Cluster Still Running During pg_upgrade

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: pg_upgrade is failing to start.
The error message indicates the old cluster is still
running. The upgrade cannot proceed.
```

---

## Key Concepts for Revision

- **Why pg_upgrade requires both clusters stopped** - `pg_upgrade` reads and modifies internal catalog files and data files directly, bypassing the PostgreSQL server process. It must have exclusive access to both data directories. If either server is running, it holds locks on shared memory segments and write-locks on data files, which pg_upgrade cannot work around.

- **pg_isready as a quick health check** - `pg_isready` connects to a PostgreSQL server and reports whether it is accepting connections. It returns exit code 0 if the server is ready, non-zero otherwise. It is the fastest way to check if a cluster is running without examining processes.

- **The postmaster.pid file** - When PostgreSQL starts, it writes its PID and the data directory path to `postmaster.pid` inside the data directory. pg_upgrade checks for this file to detect a running server. If you see `postmaster.pid exists` in a pg_upgrade error, the server (or a crashed server) has left this file behind.

- **pg_ctl stop modes** - `pg_ctl stop -m fast` is the correct mode for pre-upgrade shutdown. `fast` mode rolls back open transactions and shuts down cleanly. `immediate` mode skips the checkpoint and may require crash recovery on the next start. Never use `immediate` before an upgrade.

- **Verifying stop before proceeding** - Always verify the cluster is stopped using `pg_isready` before running pg_upgrade. Do not rely on `pg_ctl stop` returning without error - verify the cluster is actually no longer listening.

---

## Diagnostic Steps

### Step 1 - Attempt pg_upgrade and read the error

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output (yours will differ):

```
Checking cluster versions                                     ok
There seems to be a postmaster servicing the old cluster.
Please shutdown that postmaster and try again.
Failure, exiting
```

The message is unambiguous: the old cluster is still running.

### Step 2 - Confirm PG15 is running

```
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output (yours will differ):

```
/run/postgresql:5433 - accepting connections
```

Exit code 0 confirms PG15 is accepting connections.

```
exit
```

### Step 3 - Find what is running PG15

```
sudo systemctl status postgresql-15
```

Expected output (yours will differ):

```
○ postgresql-15.service - PostgreSQL 15 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-15.service; disabled)
     Active: inactive (dead)
```

The systemd service is not managing it. Check the process directly.

```
ps aux | grep postgres | grep 5433
```

Expected output (yours will differ):

```
postgres  1234  0.0  0.5  220000  22000 ?  Ss  10:00  0:00 /usr/pgsql-15/bin/postgres -D /opt/pgsql/data15
```

PG15 was started manually with `pg_ctl`, not through systemd.

---

## Resolution

### Step 1 - Stop PG15 cleanly

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

### Step 2 - Verify PG15 is stopped

```
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - no response
```

### Step 3 - Verify no postmaster.pid remains

```
ls /opt/pgsql/data15/postmaster.pid
```

If the file does not exist, you will see:

```
ls: cannot access '/opt/pgsql/data15/postmaster.pid': No such file or directory
```

That means the PID file was cleaned up and the cluster shut down properly.

If `postmaster.pid` still exists after stopping, the cluster did not shut down cleanly. This can happen after a crash. Remove the file only if you are certain the process is no longer running.

### Step 4 - Verify PG16 target is also stopped

```
/usr/pgsql-16/bin/pg_isready -p 5434
```

Expected output:

```
/run/postgresql:5434 - no response
```

### Step 5 - Re-run pg_upgrade --check

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output:

```
*Clusters are compatible*
```

```
exit
```

---

## Validation

```
./validate.sh
```

Expected checks:
- PG15 cluster is stopped
- PG16 target cluster is stopped
- pg_upgrade --check passes with both clusters stopped
- PG16 production cluster is still running

---

## Interview Discussion Points

1. **Why does pg_upgrade require both clusters to be shut down before it can proceed?** - pg_upgrade manipulates data files and catalog structures directly on disk, bypassing the PostgreSQL server. If a server is running, it holds write locks on data files, has data cached in shared buffers that has not been flushed, and may be actively writing WAL. pg_upgrade cannot safely read or modify files that a running server considers exclusively owned.

2. **What does the postmaster.pid file contain, and what does its presence tell you?** - `postmaster.pid` contains the PID of the running postgres process, the data directory path, the port, and the socket path. pg_upgrade checks for this file to detect a running server. A stale `postmaster.pid` (left behind by a crash) can also trigger this error - in that case, the server is not running but the file was not cleaned up. You must verify the process is truly gone before removing a stale pid file.

3. **What is the difference between `pg_ctl stop -m fast` and `pg_ctl stop -m immediate`?** - `fast` mode sends SIGINT to the postmaster, which rolls back all active transactions and performs a clean checkpoint before stopping. `immediate` mode sends SIGQUIT, which causes the server to abort immediately without checkpointing - equivalent to a crash. After `immediate`, the next start performs crash recovery. Always use `fast` before an upgrade to ensure a clean checkpoint and a clean starting state for the new cluster.

4. **If pg_ctl stop returns success but pg_isready still shows the server as running, what could be happening?** - The postmaster process received the shutdown signal and exited, but child processes (backends, autovacuum workers, WAL writer) may still be cleaning up. `pg_ctl stop` waits for the postmaster to exit, but `pg_isready` checks the socket - which may still exist briefly. Wait 2-3 seconds and retry `pg_isready`. If it persists, check `ps aux` for remaining postgres processes.

5. **After a `--link` upgrade, can you start the old cluster to verify it is still intact?** - No. After `--link` mode, starting the old cluster would be dangerous because it shares data blocks with the new cluster through hard links. If the old cluster writes anything, it corrupts data the new cluster depends on. The `pg_control.old` file pg_upgrade creates is not sufficient to safely run the old cluster. Your only safe rollback for `--link` mode is a pre-upgrade backup.
