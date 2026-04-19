# Scenario 01 - postgresql.conf Syntax Error

**Severity:** CRITICAL
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
A colleague edited postgresql.conf to tune memory settings
and now the database will not start.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **postgresql.conf parsing** - PostgreSQL reads `postgresql.conf` line by line at startup. Each line must follow the format `parameter = value`. If any line has invalid syntax, PostgreSQL prints a FATAL error with the exact file name and line number, then refuses to start. It does not skip bad lines - one bad line kills the whole startup.

- **Log-driven debugging** - PostgreSQL logs are your single best diagnostic tool. When a startup fails, the log tells you the exact file, line number, and nature of the syntax error. Always check logs before guessing. The default log location is configured by `log_directory` (here: `/opt/pgsql/log/`).

- **Configuration file hierarchy** - PostgreSQL loads settings from three places in order: `postgresql.conf`, files in `conf.d/` (via `include_dir`), and `postgresql.auto.conf` (written by ALTER SYSTEM). Later values override earlier ones. A syntax error in any of these files will prevent startup.

- **pg_ctl vs systemctl** - `systemctl start postgresql-16` uses the systemd unit file, which calls `pg_ctl start` under the hood. When troubleshooting, `journalctl -u postgresql-16` shows the systemd-level view, while the PostgreSQL log files show the database-level errors. Check both.

- **Safe editing practices** - Always back up `postgresql.conf` before editing. Use `pg_ctl reload` (or `SELECT pg_reload_conf()`) to test changes on a running server before restarting. Some parameters (like `shared_buffers`) require a restart, but most can be tested with a reload first.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Look for "failed" in the output. The status line will say the service did not start.

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: failed (Result: exit-code) since ...
     ...
```

### Step 2 - Check the PostgreSQL log for the exact error

```bash
sudo tail -20 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
FATAL:  could not read configuration file "/opt/pgsql/data/postgresql.conf": syntax error at line 742
LOG:  the database system is shut down
```

The line number in the error tells you exactly where the problem is.

### Step 3 - Inspect the bad line

Use the line number from the log to look at the offending line.

```bash
sudo -iu postgres
```

```bash
sed -n '740,745p' /opt/pgsql/data/postgresql.conf
```

Expected output (yours will differ):

```
# chaos injection - bad syntax
work_mem = 64MB extra_garbage
```

The problem is clear - `extra_garbage` after the value makes the line invalid. PostgreSQL expects one `parameter = value` per line, with only an optional comment after a `#`.

```bash
exit
```

---

## Resolution

### Step 1 - Back up the current conf file

```bash
sudo -iu postgres
```

```bash
cp /opt/pgsql/data/postgresql.conf /opt/pgsql/data/postgresql.conf.broken
```

### Step 2 - Remove the bad lines using vi

```bash
vi /opt/pgsql/data/postgresql.conf
```

Go to the bottom of the file (press `G`). Find the lines:

```
# chaos injection - bad syntax
work_mem = 64MB extra_garbage
```

Delete both lines (position cursor on each line and press `dd`). Save and exit (`:wq`).

### Step 3 - Verify the fix looks correct

```bash
tail -5 /opt/pgsql/data/postgresql.conf
```

Confirm the bad lines are gone.

```bash
exit
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
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

### Step 6 - Confirm you can connect

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

### Step 7 - Verify work_mem has a valid value

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW work_mem;"
```

Expected output (yours will differ):

```
 work_mem
----------
 4MB
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
- PostgreSQL accepts connections
- postgresql.conf has no syntax errors
- Chaos injection line removed from postgresql.conf
- work_mem shows a valid value

---

## Interview Discussion Points

1. **How does PostgreSQL report configuration file errors?** - PostgreSQL logs a FATAL message with the exact file path and line number where parsing failed. It then refuses to start. This is intentional - a partially-parsed configuration could lead to running with unexpected settings (wrong memory limits, wrong authentication rules), which is worse than not starting at all.

2. **What is the difference between a reload and a restart for configuration changes?** - A reload (`pg_ctl reload` or `SELECT pg_reload_conf()`) re-reads configuration files without stopping the server. Most parameters take effect immediately. However, some parameters (like `shared_buffers`, `max_connections`, `wal_level`) require a full restart because they affect shared memory allocation or process structure that cannot change while the server is running. The column `context` in `pg_settings` tells you which parameters need a restart (`postmaster`) vs. a reload (`sighup`).

3. **If postgresql.conf has a syntax error and PG is already running, what happens on reload?** - PostgreSQL logs a warning about the syntax error but keeps running with the previous settings. It does not crash or shut down. This is why `pg_ctl reload` is safer than a restart for testing config changes - if you made a mistake, the running server is unaffected.

4. **What tools exist to validate postgresql.conf without restarting?** - On a running server, `pg_ctl reload` will test the file and report errors without crashing. You can also use `postgres -C parameter_name -D /opt/pgsql/data` to check individual parameter values, though this does not catch all syntax errors. Starting with PG16, the `pg_file_settings` view shows parsed settings and flags any errors in the `error` column.

5. **Walk through the postgresql.conf precedence order when the same parameter appears multiple times.** - Within a single file, the last occurrence wins. Across files, `postgresql.auto.conf` (written by ALTER SYSTEM) overrides everything in `postgresql.conf` and `conf.d/` includes. Within `conf.d/`, files are loaded in filename-sorted order, so `99-tuning.conf` overrides `01-base.conf`. This layering lets you keep a base config and override specific values without editing the main file.
