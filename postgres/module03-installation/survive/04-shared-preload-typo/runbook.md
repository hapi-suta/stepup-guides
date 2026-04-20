# Scenario 04 - shared_preload_libraries Typo

**Severity:** CRITICAL
**Expected Recovery Time:** 2-4 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
A junior DBA modified postgresql.conf to enable query statistics tracking.
PG will not start now.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **shared_preload_libraries loading process** - When PostgreSQL starts, the postmaster reads `postgresql.conf` and attempts to load every library listed in `shared_preload_libraries`. It searches for each library name as a `.so` file in the `pkglibdir` directory (`/usr/pgsql-16/lib/`). If the name is misspelled, no `.so` file matches, and PostgreSQL aborts startup with a FATAL error.

- **PostgreSQL log files** - The server log is the single best diagnostic tool for startup failures. On this system, logs are in `/opt/pgsql/log/postgresql-*.log`. The FATAL error message tells you exactly which library name failed to load. Always check logs before guessing.

- **postgresql.conf syntax** - Parameters like `shared_preload_libraries` take a comma-separated list of library names in single quotes. PostgreSQL uses these names directly to look up `.so` files. There is no spell-check or "did you mean?" suggestion - a single character typo causes a hard failure.

- **pg_stat_statements** - One of the most important extensions for database monitoring. It tracks execution statistics for all SQL statements: call count, total time, rows returned, block I/O. Nearly every production PostgreSQL deployment should have it enabled. It requires being in `shared_preload_libraries` because it needs to allocate shared memory at startup.

- **Recovering from bad config** - If PostgreSQL will not start due to a config error, you cannot use `ALTER SYSTEM` or `pg_reload_conf()` because those require a running server. You must edit `postgresql.conf` directly on disk, then start the service. This is one of the few cases where direct file editing is the only option.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Look for "failed" status.

### Step 2 - Check PostgreSQL logs for the exact error

```bash
sudo tail -20 /opt/pgsql/log/postgresql-*.log
```

Expected output includes:

```
FATAL:  could not access file "pg_stat_statments": No such file or directory
LOG:  the database system is shut down
```

The key detail: `pg_stat_statments` - notice the missing 'e'. It should be `pg_stat_statements`.

### Step 3 - Inspect the config file

```bash
sudo grep shared_preload_libraries /opt/pgsql/data/postgresql.conf
```

Expected output:

```
shared_preload_libraries = 'pg_stat_statments'
```

Compare carefully: `statments` vs `statements`. The 'e' after 'stat' is missing.

### Step 4 - Verify the correct library exists

```bash
ls /usr/pgsql-16/lib/pg_stat_state*
```

Expected output:

```
/usr/pgsql-16/lib/pg_stat_statements.so
```

The correct file is `pg_stat_statements.so` (with the 'e'). The config has a typo.

---

## Resolution

### Step 1 - Fix the typo in postgresql.conf

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the line:

```
shared_preload_libraries = 'pg_stat_statments'
```

Change it to:

```
shared_preload_libraries = 'pg_stat_statements'
```

(Add the missing 'e' - `stat_e_ments`.)

```bash
exit
```

### Step 2 - Verify the fix before starting

```bash
sudo grep shared_preload_libraries /opt/pgsql/data/postgresql.conf
```

Expected output:

```
shared_preload_libraries = 'pg_stat_statements'
```

### Step 3 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 4 - Verify it started

```bash
sudo systemctl status postgresql-16
```

Look for "active (running)" status.

### Step 5 - Confirm the library loaded

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW shared_preload_libraries;"
```

`-p 5432` connects on port 5432. `-d labdb` connects to the labdb database. `-c` runs a single SQL command and exits.

Expected output:

```
 shared_preload_libraries
--------------------------
 pg_stat_statements
```

### Step 6 - Verify the extension works

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM pg_stat_statements;"
```

Expected output:

```
 count
-------
     0
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
- shared_preload_libraries has correct spelling
- postgresql.conf has no typo
- pg_stat_statements extension works
- psql connection succeeds

---

## Interview Discussion Points

1. **How do you diagnose a PostgreSQL startup failure?** - Three steps in order: (1) `systemctl status postgresql-16` to confirm it failed, (2) check the log file for FATAL messages - this gives you the exact error, (3) inspect the relevant config file. The logs almost always tell you exactly what is wrong. Never guess - always read the logs first.

2. **What is the difference between FATAL and ERROR in PG logs?** - FATAL terminates the connection or, during startup, aborts the entire server. ERROR fails the current transaction but the connection stays alive. PANIC causes all server processes to abort and triggers a crash recovery on next startup. During startup, a FATAL in shared_preload_libraries is server-fatal because the postmaster itself encounters it.

3. **How would you prevent this kind of error in production?** - Use `ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';` instead of editing `postgresql.conf` by hand. `ALTER SYSTEM` writes to `postgresql.auto.conf` and validates parameter names (though not library names). Better yet, use configuration management (Ansible, Puppet) with tested templates. Always test config changes on a non-production instance first. After editing, run `pg_ctl -D /opt/pgsql/data -c` (if available) or attempt a restart in a maintenance window.

4. **Can you reload shared_preload_libraries without a restart?** - No. `shared_preload_libraries` requires a full server restart because the libraries allocate shared memory, which is sized at startup. A `pg_reload_conf()` (SIGHUP) will not load new shared libraries. This is why changes to this parameter must be planned as a maintenance event with downtime.

5. **What other shared_preload_libraries are commonly used in production?** - `pg_stat_statements` (query stats), `auto_explain` (log slow query plans), `pg_cron` (in-database job scheduler), `pg_partman_bgw` (partition maintenance), `timescaledb` (time-series), `pgaudit` (audit logging). Each one adds a small amount of shared memory overhead. List only what you actually use - every entry is a potential startup blocker if the library goes missing.
