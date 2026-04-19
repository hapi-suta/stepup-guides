# Scenario 08 - WAL Directory Missing

**Severity:** CRITICAL
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
A storage migration was in progress and the WAL directory
is no longer accessible. The database cannot start without
its write-ahead log.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **Write-Ahead Log (WAL)** - PostgreSQL writes every data change to the WAL before modifying the actual data files. This guarantees crash recovery: if the server crashes, PostgreSQL replays the WAL on startup to bring the database to a consistent state. Without access to the WAL directory, PostgreSQL cannot start at all because it cannot guarantee data integrity.

- **pg_wal directory** - By default, `pg_wal` lives inside PGDATA (e.g., `/opt/pgsql/data/pg_wal`). For performance, DBAs often move it to a separate disk by creating a symlink: `pg_wal -> /opt/pgsql/wal`. This puts WAL writes on a different I/O path than data file writes. PostgreSQL does not care whether `pg_wal` is a real directory or a symlink - it just follows the path. But if the symlink target disappears, startup fails.

- **Symlinks in PGDATA** - PostgreSQL uses symlinks for two common purposes: `pg_wal` (WAL directory) and tablespace directories under `pg_tblspc/`. Both are created during `initdb --waldir` or `CREATE TABLESPACE`. When troubleshooting startup failures, always check whether critical directories are symlinks and whether their targets still exist. `ls -la` shows symlink targets.

- **Startup sequence and WAL** - During startup, PostgreSQL opens the `pg_wal` directory to read the latest WAL files and determine the recovery point. If the directory is missing, the postmaster logs a FATAL error and exits immediately. This happens before any client connections are accepted - the server never reaches "accepting connections" state.

- **File ownership and permissions** - All files and directories inside PGDATA (and symlink targets) must be owned by the `postgres` OS user. The `pg_wal` directory and its contents need `700` permissions. If you restore or move a WAL directory, always verify ownership with `ls -la` and fix with `chown -R postgres:postgres`.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
 postgresql-16.service - PostgreSQL 16 database server
   Active: failed (Result: exit-code) since ...
```

### Step 2 - Check PostgreSQL logs for the startup error

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
FATAL:  could not open directory "pg_wal": No such file or directory
LOG:  database system is shut down
```

The FATAL message tells you exactly what is wrong: the `pg_wal` directory does not exist (or the symlink target is gone).

### Step 3 - Check if pg_wal is a symlink

```bash
ls -la /opt/pgsql/data/pg_wal
```

Expected output (yours will differ) - if pg_wal is a symlink:

```
lrwxrwxrwx  1 postgres postgres  15 Apr 18 10:00 /opt/pgsql/data/pg_wal -> /opt/pgsql/wal
```

The symlink points to `/opt/pgsql/wal`, but that target directory is missing.

Or if pg_wal is a regular directory, you will see an error:

```
ls: cannot access '/opt/pgsql/data/pg_wal': No such file or directory
```

### Step 4 - Look for the renamed directory

Someone may have renamed the WAL directory during a migration. Check for backup copies:

```bash
ls -la /opt/pgsql/ | grep wal
```

Expected output (yours will differ):

```
drwx------  3 postgres postgres  4096 Apr 18 10:00 wal.chaos-bak
```

Or check inside PGDATA:

```bash
ls -la /opt/pgsql/data/ | grep wal
```

Expected output (yours will differ):

```
lrwxrwxrwx  1 postgres postgres    15 Apr 18 10:00 pg_wal -> /opt/pgsql/wal
drwx------  3 postgres postgres  4096 Apr 18 10:00 pg_wal.chaos-bak
```

The `.chaos-bak` suffix tells you the directory was renamed.

---

## Resolution

### Step 1 - Rename the WAL directory back

If pg_wal is a symlink pointing to `/opt/pgsql/wal`:

```bash
sudo mv /opt/pgsql/wal.chaos-bak /opt/pgsql/wal
```

If pg_wal was a regular directory inside PGDATA:

```bash
sudo mv /opt/pgsql/data/pg_wal.chaos-bak /opt/pgsql/data/pg_wal
```

### Step 2 - Verify the directory exists and is accessible

```bash
ls -la /opt/pgsql/data/pg_wal
```

Expected output (yours will differ):

```
lrwxrwxrwx  1 postgres postgres  15 Apr 18 10:00 /opt/pgsql/data/pg_wal -> /opt/pgsql/wal
```

Or for a regular directory:

```
drwx------  3 postgres postgres  4096 Apr 18 10:00 /opt/pgsql/data/pg_wal
```

### Step 3 - Verify ownership

```bash
sudo ls -la /opt/pgsql/data/pg_wal/
```

Expected output (yours will differ):

```
total 65540
drwx------  3 postgres postgres     4096 Apr 18 10:00 .
-rw-------  1 postgres postgres 16777216 Apr 18 10:05 000000010000000000000001
...
drwx------  2 postgres postgres     4096 Apr 18 10:00 archive_status
```

All files should be owned by `postgres:postgres`. If not:

```bash
sudo chown -R postgres:postgres /opt/pgsql/wal
```

### Step 4 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 5 - Verify it started

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
 postgresql-16.service - PostgreSQL 16 database server
   Active: active (running) since ...
```

### Step 6 - Verify WAL is functioning

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "CHECKPOINT;"
```

Expected output (yours will differ):

```
CHECKPOINT
```

A successful checkpoint proves WAL writing is working.

### Step 7 - Verify WAL files exist

```bash
ls /opt/pgsql/data/pg_wal/ | head -5
```

Expected output (yours will differ):

```
000000010000000000000001
000000010000000000000002
archive_status
```

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
- pg_wal directory is accessible
- WAL files exist in pg_wal
- CHECKPOINT succeeds
- psql connection succeeds

---

## Interview Discussion Points

1. **Why is the WAL directory critical for PostgreSQL startup?** - PostgreSQL must read the WAL during startup to perform crash recovery. Even after a clean shutdown, the postmaster verifies the WAL directory is accessible before accepting connections. The WAL contains the authoritative record of all recent transactions. Without it, PostgreSQL cannot guarantee data consistency, so it refuses to start rather than risk serving corrupt data. This is a fundamental safety design.

2. **What are the advantages of placing pg_wal on a separate disk?** - WAL writes are sequential and fsync-heavy. Data file writes are random. Putting them on separate disks (or separate EBS volumes in AWS) prevents WAL writes from competing with data file I/O. This is especially important for write-heavy workloads. The symlink approach (`initdb --waldir=/opt/pgsql/wal`) is the standard way to do this. The trade-off: you now have two disks that must both be healthy for PostgreSQL to run.

3. **How would you recover if the WAL directory was permanently lost (not just renamed)?** - If the WAL files are truly gone and you have no backup, you have a potential data loss scenario. The last resort is `pg_resetwal`, which creates a new WAL history and clears the requirement for the old WAL files. But this can cause silent data corruption if there were uncommitted transactions. The proper approach: restore from a base backup plus WAL archive (PITR). This is why WAL archiving and regular backups are non-negotiable in production.

4. **How do you move the WAL directory to a new location on a running system?** - You cannot move it while PostgreSQL is running. The procedure: (1) stop PostgreSQL, (2) move the `pg_wal` contents to the new location, (3) remove the old `pg_wal` directory, (4) create a symlink from `$PGDATA/pg_wal` to the new location, (5) verify ownership, (6) start PostgreSQL. Alternatively, use `initdb --waldir` when creating the cluster to set it up from the beginning.

5. **What other symlinks does PostgreSQL use inside PGDATA, and what breaks if they go missing?** - Tablespace symlinks under `pg_tblspc/` point to the actual storage directories for each tablespace. If a tablespace symlink target disappears, any query that touches a table in that tablespace fails with "could not open file." Unlike the `pg_wal` symlink, a missing tablespace does not prevent startup - PostgreSQL starts fine but fails when you access data in the broken tablespace. The `pg_stat_tmp` directory can also be symlinked (for tmpfs performance), but missing it is less critical.
