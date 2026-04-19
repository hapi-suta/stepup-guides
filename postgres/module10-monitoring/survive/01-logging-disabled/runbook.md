# Scenario 01 - Logging Disabled

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL logs have stopped.
The on-call engineer cannot find any recent log entries.
No slow query data, no error messages, nothing.
Something changed in the configuration.
```

---

## Key Concepts for Revision

- **logging_collector** - This parameter controls whether PostgreSQL's background logger process runs. When it is `off`, PostgreSQL still sends log output to stderr, but nothing captures it to files. The server runs normally - only log collection stops. Because this is a `postmaster` context parameter, changing it requires a full server restart, not just a reload.

- **postgresql.auto.conf** - `ALTER SYSTEM` writes settings to `postgresql.auto.conf`, which overrides `postgresql.conf`. If someone ran `ALTER SYSTEM SET logging_collector = off`, the value in `postgresql.conf` does not matter - `auto.conf` wins. You must either use `ALTER SYSTEM SET logging_collector = on` (to write the correct value back to `auto.conf`) or `ALTER SYSTEM RESET logging_collector` (to remove the override and let `postgresql.conf` take effect).

- **Postmaster context parameters** - Parameters with `context = postmaster` in `pg_settings` require a full server restart. This is different from `sighup` parameters, which take effect with a reload. `logging_collector` is postmaster context, so re-enabling it requires a restart.

- **Impact of missing logs** - Without logs you lose: slow query detection, error history, authentication failure tracking, connection events, and checkpoint reporting. This turns monitoring blind. In production, missing logs is a SEV2 incident because you cannot diagnose other problems while it persists.

---

## Diagnostic Steps

### Step 1 - Check if log files are being written

```bash
sudo -iu postgres
```

```bash
ls -lt /opt/pgsql/log/
```

Look at the modification timestamp on the log files. If the newest file has not been updated in several minutes despite activity on the server, logging has stopped.

```bash
exit
```

### Step 2 - Check logging_collector setting

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW logging_collector;"
```

Expected output when broken:

```
 logging_collector
-------------------
 off
(1 row)
```

### Step 3 - Check what is in postgresql.auto.conf

```bash
grep -i logging_collector /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):

```
logging_collector = 'off'
```

This confirms `ALTER SYSTEM` was used to disable it.

```bash
exit
```

---

## Resolution

### Step 1 - Re-enable logging_collector via ALTER SYSTEM

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET logging_collector = on;"
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Exit postgres user

```bash
exit
```

### Step 3 - Restart PostgreSQL (required for postmaster context)

```bash
sudo systemctl restart postgresql-16
```

### Step 4 - Confirm PostgreSQL came back up

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since Sun 2026-04-19 10:05:01 UTC; 3s ago
```

### Step 5 - Confirm logs are being written

```bash
sudo -iu postgres
```

```bash
ls -lt /opt/pgsql/log/
```

Expected output (yours will differ):

```
total 12K
-rw------- 1 postgres postgres 1.2K Apr 19 10:05 postgresql-2026-04-19.log
```

The file modification time should be very recent.

### Step 6 - Generate a query and confirm it appears in the log

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_sleep(2);"
```

```bash
tail -5 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-19 10:05:15.234 UTC [3001]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 2004.123 ms  statement: SELECT pg_sleep(2);
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
- logging_collector is on
- Log directory exists
- Log file written in the last 5 minutes
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Why does changing logging_collector require a restart when most logging parameters only need a reload?** - `logging_collector` starts the background logger subprocess at PostgreSQL startup. This subprocess is part of the server process tree. You cannot add or remove a process from a running process tree without restarting. Parameters that control what gets logged (like `log_min_duration_statement`) are read by the existing logger process and take effect with a reload, but starting or stopping the logger itself requires a restart.

2. **If logging_collector is off, where does log output go?** - PostgreSQL still writes log output to stderr. On a systemd-managed server, systemd captures stderr from the postgresql-16 service and stores it in the journal. You can read it with `journalctl -u postgresql-16`. However, this is not rotated, searchable, or parseable the same way as log files.

3. **How would you detect that logging_collector was disabled if you had no shell access to the server?** - You can query `pg_settings`: `SELECT setting FROM pg_settings WHERE name = 'logging_collector'`. You can also query `pg_file_settings` to see what `postgresql.auto.conf` contains. Both work over a live database connection even without shell access.

4. **After re-enabling logging, is there a gap in your log history? Can you recover the missing events?** - No. Events that occurred while logging was off are gone - they were printed to stderr but not persisted. You can recover some information from `pg_stat_statements` (which still tracks queries in memory) and `pg_stat_activity` history (which is transient), but the detailed log record with timestamps and error messages is unrecoverable.

5. **What preventive controls would you put in place to detect logging going dark in the future?** - Monitor the modification timestamp of the log directory (alert if no new bytes in 10 minutes), monitor `pg_settings.setting` for `logging_collector` via a periodic check, and set up alerting on `pg_file_settings` changes. Some teams also configure `log_destination = 'syslog'` as a secondary destination so logs go to two places.
