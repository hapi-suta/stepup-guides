# Scenario 06 - Wrong Data Directory

**Severity:** CRITICAL
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start after a scheduled
maintenance window. The service exits immediately.
The DBA team was reconfiguring paths after an upgrade
from PG 15 to PG 16 and may have set a wrong path.
```

---

## Key Concepts for Revision

- **data_directory tells PostgreSQL where its data lives** - This is the most fundamental configuration parameter. It points to the directory containing `base/`, `global/`, `pg_wal/`, and all other PostgreSQL data subdirectories. If this path is wrong, PostgreSQL cannot start because it cannot find its data files.

- **data_directory is set in postgresql.conf** - It can also be set via the `-D` flag when starting the server, or via the `PGDATA` environment variable. The systemd service file typically sets `PGDATA` which tells PostgreSQL where to find `postgresql.conf`, and `data_directory` inside that file can override the physical location.

- **Common causes of wrong data_directory** - During major version upgrades, the old cluster and new cluster have different data directories (e.g., `/opt/pgsql/data15` vs `/opt/pgsql/data16`). A copy-paste error or incomplete config migration can leave `data_directory` pointing to the old cluster's path. Also happens when moving data to a new mount point.

- **The PostgreSQL log is your first diagnostic tool** - When PostgreSQL fails to start, it writes the reason to the log. The log location is typically in `postgresql.conf` via `log_directory`, but since PostgreSQL cannot read the config from the wrong data dir, you may need to check `journalctl` or the systemd journal for startup errors.

- **Systemd environment overrides** - The systemd unit file for PostgreSQL sets `PGDATA` via an environment file (often `/etc/sysconfig/postgresql-16` or similar). This `PGDATA` tells PostgreSQL where to find `postgresql.conf`. The `data_directory` setting inside `postgresql.conf` then tells PostgreSQL where the actual data files are. They are usually the same, but can differ.

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
  Process: ... ExecStart=... (code=exited, status=1/FAILURE)
```

The service failed to start.

### Step 2 - Check the journal for startup errors

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20
```

Expected output (yours will differ):

```
... FATAL:  data directory "/opt/pgsql/data_OLD_v15" does not exist
... LOG:  database system is shut down
```

The log clearly shows the wrong data directory path.

### Step 3 - Verify the wrong path does not exist

```bash
ls -la /opt/pgsql/data_OLD_v15
```

Expected output:

```
ls: cannot access '/opt/pgsql/data_OLD_v15': No such file or directory
```

### Step 4 - Find the correct data directory

Check what directories actually exist under /opt/pgsql/:

```bash
ls -la /opt/pgsql/
```

Expected output (yours will differ):

```
drwx------  20 postgres postgres 4096 ... data
drwxr-xr-x   2 postgres postgres 4096 ... backup
drwxr-xr-x   2 postgres postgres 4096 ... log
lrwxrwxrwx   1 postgres postgres   25 ... wal -> ...
```

The correct data directory is `/opt/pgsql/data`.

### Step 5 - Find the bad setting in postgresql.conf

```bash
sudo -iu postgres
```

```bash
grep data_directory /opt/pgsql/data/postgresql.conf
```

Expected output:

```
data_directory = '/opt/pgsql/data_OLD_v15'	# chaos injection
```

---

## Resolution

### Step 1 - Fix data_directory in postgresql.conf

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the line with `data_directory = '/opt/pgsql/data_OLD_v15'` and the chaos comment. Change it to:

```
data_directory = '/opt/pgsql/data'
```

Save and exit (`:wq`).

### Step 2 - Verify the edit

```bash
grep data_directory /opt/pgsql/data/postgresql.conf
```

Expected output:

```
data_directory = '/opt/pgsql/data'
```

No chaos comment should remain.

```bash
exit
```

### Step 3 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 4 - Verify it started

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
 postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

### Step 5 - Verify the data directory is correct

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW data_directory;"
```

Expected output:

```
 data_directory
----------------
 /opt/pgsql/data
(1 row)
```

### Step 6 - Verify data is accessible

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT count(*) FROM orders;"
```

Expected output (yours will differ):

```
 count
-------
 10000
(1 row)
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- data_directory is /opt/pgsql/data
- Chaos injection comment removed from postgresql.conf
- Database is accessible and queries work

---

## Interview Discussion Points

1. **How does systemd know where postgresql.conf is if data_directory is wrong?** - The systemd unit file sets `PGDATA` via an environment variable (e.g., in `/etc/sysconfig/postgresql-16`). PostgreSQL uses `PGDATA` to locate `postgresql.conf`. Once it reads `postgresql.conf`, it uses the `data_directory` parameter for the actual data. If `PGDATA` points to `/opt/pgsql/data` but `data_directory` in that file says `/opt/pgsql/data_OLD_v15`, PostgreSQL reads the config from the right place but looks for data in the wrong place.

2. **What is the difference between PGDATA and data_directory?** - `PGDATA` is an OS environment variable that tells PostgreSQL where to find its configuration files (`postgresql.conf`, `pg_hba.conf`). `data_directory` is a setting inside `postgresql.conf` that tells PostgreSQL where the actual data files are. Usually they point to the same directory. They can differ if you want config files in one location and data files in another.

3. **How would you handle this if the server had no console access (cloud)?** - SSH into the instance. Check `journalctl` for the error message. If you cannot access the filesystem to edit the config, you may need to: (1) Mount the EBS volume on another instance. (2) Edit postgresql.conf on the mounted volume. (3) Re-attach and start. On RDS/Aurora, you do not control the data directory - AWS manages it.

4. **What other config errors can prevent PostgreSQL from starting?** - Invalid `shared_buffers` (larger than available RAM), wrong `port` (already in use), bad `listen_addresses`, corrupted `pg_hba.conf`, wrong `unix_socket_directories`, `max_connections` too high for available shared memory, and missing WAL directory (if `pg_wal` is a symlink that points nowhere).

5. **Should you keep backup copies of postgresql.conf?** - Yes. Version-control your postgresql.conf. Keep a backup copy before any change. The pattern `cp postgresql.conf postgresql.conf.bak-$(date +%Y%m%d)` is standard practice. Some teams use git to track config changes. On this lab server, the inject script created `postgresql.conf.chaos-06-backup` which could also be used for recovery.
