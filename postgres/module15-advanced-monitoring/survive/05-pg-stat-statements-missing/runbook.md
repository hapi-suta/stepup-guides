# SURVIVE Runbook - 05: pg_stat_statements Missing

**Scenario:** pg_stat_statements was removed from shared_preload_libraries and PostgreSQL restarted
**Symptom:** No query statistics available, pg_stat_statements queries fail or return errors
**Severity:** Medium - monitoring continues but query performance data is gone

---

## Layer 1: Quick Triage

Try to query pg_stat_statements:

```bash
sudo -i -u postgres
psql -d stepup_store -c "SELECT count(*) FROM pg_stat_statements;"
```

If the extension is broken, you will see an error like:

```
ERROR:  pg_stat_statements must be loaded via shared_preload_libraries
```

or:

```
ERROR:  relation "pg_stat_statements" does not exist
```

The first error means the library is not preloaded. The second means the extension was also dropped.

Check the exporter logs for related errors:

```bash
sudo journalctl -u postgres_exporter -n 30 --no-pager | grep -i "error\|stat_statements"
```

---

## Layer 2: Root Cause Analysis

Check whether pg_stat_statements is listed in shared_preload_libraries:

```bash
sudo -i -u postgres
psql -c "SHOW shared_preload_libraries;"
```

Expected output when the problem exists (yours will differ):

```
 shared_preload_libraries
--------------------------

(1 row)
```

An empty value (or a value that does not include pg_stat_statements) confirms the library is not loaded.

Check the postgresql.conf directly:

```bash
grep shared_preload_libraries /opt/pgsql/data/postgresql.conf
```

If the line is missing or commented out, that is your root cause.

Check whether the extension object still exists in the database:

```bash
psql -d stepup_store -c "SELECT name, installed_version FROM pg_available_extensions WHERE name = 'pg_stat_statements';"
```

If `installed_version` is NULL, the extension was dropped from the database. If it shows a version, the extension object exists but the library is not loaded.

Exit psql:

```sql
\q
```

```bash
exit
```

---

## Layer 3: Fix and Verify

### Step 1 - Add pg_stat_statements back to shared_preload_libraries

```bash
sudo vi /opt/pgsql/data/postgresql.conf
```

Find the `shared_preload_libraries` line. Change it to:

```
shared_preload_libraries = 'pg_stat_statements'
```

If other libraries are listed (like `pg_prewarm`), keep them:

```
shared_preload_libraries = 'pg_stat_statements,pg_prewarm'
```

Save and close.

**Alternative method using ALTER SYSTEM (no vi required):**

```bash
sudo -i -u postgres
psql -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';"
exit
```

### Step 2 - Restart PostgreSQL

Changing `shared_preload_libraries` requires a full restart - a reload is not sufficient.

```bash
sudo systemctl restart postgresql-16
```

Wait 5-10 seconds for PostgreSQL to start fully.

```bash
sudo systemctl status postgresql-16
```

### Step 3 - Verify the library loaded

```bash
sudo -i -u postgres
psql -c "SHOW shared_preload_libraries;"
```

Expected output (yours will differ):

```
  shared_preload_libraries
----------------------------
 pg_stat_statements
(1 row)
```

### Step 4 - Recreate the extension if it was dropped

```bash
psql -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

### Step 5 - Verify the extension works

```bash
psql -d stepup_store -c "SELECT count(*) FROM pg_stat_statements;"
```

Expected output (yours will differ):

```
 count
-------
     0
(1 row)
```

Zero rows is correct after a restart (stats were reset). The fact that it returns 0 instead of an error means the extension is working.

### Step 6 - Generate some query traffic to populate the view

```bash
exit
```

```bash
sudo -u postgres /usr/pgsql-16/bin/pgbench -c 3 -T 30 -d stepup_store
```

### Step 7 - Verify the exporter picks up the stats

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_statements
```

Expected output (yours will differ):

```
# HELP pg_stat_statements_seconds_total ...
# TYPE pg_stat_statements_seconds_total counter
pg_stat_statements_seconds_total{...} 0.123
```

---

## Prevention

- Put postgresql.conf in version control
- Before restarting PostgreSQL after a config change, verify shared_preload_libraries still contains pg_stat_statements
- Add monitoring for `pg_extension_installed` to alert if critical extensions disappear
