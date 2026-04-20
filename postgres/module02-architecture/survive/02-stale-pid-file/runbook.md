# Scenario 02 - Stale PID File

**Severity:** CRITICAL
**Expected Recovery Time:** 2-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
Error in logs mentions lock file / postmaster.pid.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **postmaster.pid** - A lock file PostgreSQL creates in PGDATA on startup. Contains the PID of the main postmaster process, the data directory path, the start timestamp, the port number, and socket directory info.
- **Why PostgreSQL checks it** - On startup, PostgreSQL reads postmaster.pid to see if another instance is already running with this data directory. If the PID in the file corresponds to a running process, startup is refused to prevent data corruption from two instances writing to the same data directory.
- **Stale PID file** - When PostgreSQL crashes (kill -9, power loss, OOM kill), it may not clean up postmaster.pid. The file remains with the old PID. If that PID happens to be reused by another OS process, PostgreSQL refuses to start even though no other PostgreSQL is running.
- **Crash recovery** - After removing a stale PID file and starting PostgreSQL, it automatically replays WAL from the last checkpoint to recover any in-flight transactions. This is normal and expected after an unclean shutdown.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled)
     Active: failed (Result: exit-code) since Sat 2026-04-19 14:22:08 UTC; 3min ago
    Process: 4821 ExecStart=/usr/pgsql-16/bin/postmaster -D /opt/pgsql/data (code=exited, status=1/FAILURE)
...
```

Look for "failed" or "inactive" status.

### Step 2 - Check PostgreSQL logs

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Expected output:

```
FATAL:  lock file "postmaster.pid" already exists
HINT:  Is another postmaster (PID 3217) running in data directory "/opt/pgsql/data"?
```

Look for messages like:
- "lock file postmaster.pid already exists"
- "Is another postmaster running?"

### Step 3 - Inspect the PID file

```bash
sudo cat /opt/pgsql/data/postmaster.pid
```

The first line is the PID. Note this number.

### Step 4 - Check if that PID is actually running

Replace `<PID>` with the PID from the file:

```bash
ps -fp <PID>
```

(`-f` shows full details including the command.) If the process is NOT a PostgreSQL postmaster (e.g., it is a `sleep` command or some other process), the PID file is stale.

### Step 5 - Double-check no PostgreSQL postmaster is running

```bash
pgrep -fa 'postgres.*-D'
```

(`pgrep` searches for processes by name. `-f` matches against the full command line, `-a` displays it.)

If this returns nothing (no output at all), no PostgreSQL postmaster is running. The PID file is definitely stale.

If a postmaster were actually running, you would see:

```
postgres  4521  0.0  1.2 294312 12544 ?  Ss  14:10  0:00 /usr/pgsql-16/bin/postmaster -D /opt/pgsql/data
```

---

## Resolution

### Step 1 - Kill the process holding the stale PID (if it exists)

If `ps -fp <PID>` showed a non-PostgreSQL process (like `sleep`), kill it first:

```bash
sudo kill <PID>
```

### Step 2 - Remove the stale PID file

```bash
sudo -iu postgres
```

```bash
rm /opt/pgsql/data/postmaster.pid
```

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
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled)
     Active: active (running) since Sat 2026-04-19 14:28:15 UTC; 5s ago
...
```

### Step 5 - Test a connection

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 'PostgreSQL is back';"
```

Expected output:

```
      ?column?
--------------------
 PostgreSQL is back
(1 row)
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
- postmaster.pid exists with a valid PID
- The PID in the file matches the running postmaster process
- psql connection succeeds

---

## Interview Discussion Points

1. **What does postmaster.pid contain?** - Line 1: PID. Line 2: data directory path. Line 3: start timestamp. Line 4: port number. Line 5: Unix socket directory. Line 6: listen address. Line 7: shared memory key/ID. PostgreSQL uses all of these to detect conflicts with other instances.

2. **Why does PostgreSQL refuse to start with a stale PID file?** - Safety. If PostgreSQL did not check, two instances could write to the same data directory simultaneously, causing immediate and unrecoverable corruption. The PID check is a critical safety mechanism, not just a convenience feature.

3. **What happens during crash recovery?** - PostgreSQL replays WAL records from the last completed checkpoint forward. Any transactions that were committed but not yet flushed to data files are replayed (redo). Any transactions that were in progress at crash time are rolled back. The database is guaranteed consistent after recovery completes.

4. **When is it safe to remove postmaster.pid?** - Only when you have confirmed that no PostgreSQL process is using this data directory. Check with `ps aux | grep postgres` and verify the PID in the file does not belong to a running postmaster. Never blindly remove it on a system you are not sure about.

5. **What other lock files does PostgreSQL use?** - PostgreSQL also creates a socket lock file (e.g., .s.PGSQL.5432.lock in /tmp). If this file is stale, you may also need to remove it. Additionally, each backend process registers in shared memory, which is cleaned up on a proper shutdown but may need manual intervention after certain crash scenarios.
