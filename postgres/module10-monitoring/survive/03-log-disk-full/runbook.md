# Scenario 03 - Log Disk Full

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Disk space on the log volume is critically low.
PostgreSQL may stop writing logs or even fail to write
WAL if the log and data are on the same volume.
Log files are also growing rapidly - every query is logged.
```

---

## Key Concepts for Revision

- **log_min_duration_statement = 0** - Setting this to `0` logs every single statement, regardless of duration. On a busy database, this can generate gigabytes of logs per hour. This is a useful short-term debugging tool but catastrophic if left on. The safe setting for production is typically 1000-5000ms.

- **Log rotation** - `log_rotation_age` (in minutes) and `log_rotation_size` (in kB) control when PostgreSQL starts a new log file. When both are non-zero, whichever threshold is hit first triggers rotation. Old files are not automatically deleted - you must arrange deletion separately (logrotate, cron, or pg_logdir_ls).

- **Disk full impact** - If the disk holding `pg_log` fills up, PostgreSQL cannot write new log entries. The server continues to function but all log output is silently lost. If `pg_log` is on the same volume as `pg_data` or `pg_wal`, a full disk is far more dangerous - PostgreSQL can crash or corrupt data if it cannot write WAL.

- **Immediate relief vs long-term fix** - In a disk-full emergency, the first action is always to free space immediately. Only then tune configuration. Acting in reverse order (tuning first) leaves the system in a broken state while you work.

---

## Diagnostic Steps

### Step 1 - Check disk usage

```bash
df -h /opt/pgsql/log
```

Expected output when broken (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvdf       1.0G  980M   20M  99% /opt/pgsql/log
```

### Step 2 - Find what is consuming space

```bash
du -sh /opt/pgsql/log/*
```

Expected output (yours will differ):

```
800M    /opt/pgsql/log/chaos_fill.bin
156M    /opt/pgsql/log/postgresql-2026-04-19.log
```

The `chaos_fill.bin` file is the large filler file. The log file is also growing rapidly due to `log_min_duration_statement = 0`.

### Step 3 - Confirm log flooding

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output when broken:

```
 log_min_duration_statement
----------------------------
 0
(1 row)
```

```bash
exit
```

---

## Resolution

Work in this order: free space first, then tune configuration.

### Step 1 - Remove the large filler file

```bash
sudo -iu postgres
```

```bash
rm /opt/pgsql/log/chaos_fill.bin
```

Confirm it is gone.

```bash
ls -lh /opt/pgsql/log/
```

### Step 2 - Compress old log files

```bash
gzip /opt/pgsql/log/postgresql-$(date +%Y-%m-%d --date='yesterday').log 2>/dev/null || true
```

(`2>/dev/null || true` = suppress errors if yesterday's log does not exist. The `||  true` prevents the script from stopping on a non-critical error.)

### Step 3 - Check free space

```bash
exit
```

```bash
df -h /opt/pgsql/log
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvdf       1.0G  160M  840M  17% /opt/pgsql
```

Space is now available.

### Step 4 - Fix log_min_duration_statement

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET log_min_duration_statement = 1000;"
```

Expected output:

```
ALTER SYSTEM
```

### Step 5 - Configure log rotation

Set rotation to daily with a 100MB size limit.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET log_rotation_age = 1440;"
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET log_rotation_size = '100MB';"
```

### Step 6 - Reload configuration

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 7 - Confirm log flooding has stopped

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output:

```
 log_min_duration_statement
----------------------------
 1s
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
- Chaos fill file removed
- log_min_duration_statement is not 0
- log_rotation_age is configured
- log_rotation_size is configured
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **If pg_data and pg_log are on the same volume and the disk fills up, what happens?** - PostgreSQL cannot write WAL. When WAL writes fail, PostgreSQL immediately panics and shuts down to prevent data corruption. This is a hard crash. On restart, PostgreSQL runs recovery against the last good WAL checkpoint. The key lesson: always put pg_log on a separate volume from pg_data and pg_wal.

2. **How would you automate log cleanup to prevent this recurring?** - Several approaches: (1) Configure `logrotate` with `compress`, `rotate 7`, and `dateext` to keep 7 days of gzipped logs. (2) Write a cron job that runs `find /opt/pgsql/log -name '*.log' -mtime +7 -delete`. (3) Set `log_rotation_size` to a value that forces frequent rotation, then combine with automated cleanup. The right solution depends on how much log history the team needs.

3. **What is the difference between log_rotation_size and log_truncate_on_rotation?** - `log_rotation_size` controls when a new file is started (by size). `log_truncate_on_rotation` controls whether PostgreSQL truncates (overwrites) an existing file when it would reuse the same filename. With a `%a` (weekday) filename pattern and `log_truncate_on_rotation = on`, PostgreSQL creates a fresh file each weekday and discards last week's content, giving you a rolling 7-day window automatically.

4. **How does setting log_min_duration_statement = 0 affect performance?** - Every query generates a log write. Log writes go through the logging collector subprocess which buffers them, but under high query rates this adds CPU overhead for string formatting and I/O. On a system doing 50,000 queries per second, logging everything can consume 20-30% additional CPU and generate hundreds of MB of I/O per minute. Use it only for short debugging windows.

5. **You freed space and tuned configuration. What else should you do before closing the incident?** - Check whether any WAL files were affected (run `pg_waldump` if concerned about WAL integrity). Review what triggered the disk fill in the first place - was `log_min_duration_statement = 0` set intentionally for debugging and left behind? Set up a disk space alert at 80% so you are warned before next time. Consider adding `log_directory` to a monitoring check in your health check script.
