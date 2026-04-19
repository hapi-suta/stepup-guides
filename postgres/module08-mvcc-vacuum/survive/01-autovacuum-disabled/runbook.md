# Scenario 01 - Autovacuum Disabled Globally

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Dead tuples accumulating across all tables.
Autovacuum has been disabled. No automatic cleanup is running.
Tables in stepup_store show growing dead tuple counts.
```

---

## Key Concepts for Revision

- **Autovacuum is your safety net** - Autovacuum runs in the background to remove dead tuples, update statistics for the planner, and advance the XID freeze horizon. When it is disabled, dead tuples accumulate silently until tables become bloated and query plans degrade. On a busy production system, disabling autovacuum is equivalent to removing the oil filter from a car engine - it works fine for a while, then fails badly.

- **ALTER SYSTEM writes to postgresql.auto.conf** - When a DBA runs `ALTER SYSTEM SET autovacuum = off`, the setting is written to `postgresql.auto.conf`, which overrides `postgresql.conf`. Even if `postgresql.conf` says `autovacuum = on`, the `auto.conf` setting wins. You must use `ALTER SYSTEM RESET` or remove the line from `postgresql.auto.conf` to undo it.

- **pg_reload_conf() vs restart** - Autovacuum on/off is a `sighup` parameter - it takes effect with a reload, not a restart. You do not need to stop the database to re-enable autovacuum.

- **Dead tuples without autovacuum** - Dead tuples are not cleaned up automatically, so tables grow bloated, sequential scans get slower (more pages to read), and the planner gets stale statistics. The XID freeze horizon also stops advancing, increasing wraparound risk over time.

- **VACUUM as an emergency measure** - While fixing the root cause (re-enabling autovacuum), you should also manually VACUUM the most bloated tables immediately to stop the immediate damage.

---

## Diagnostic Steps

### Step 1 - Check if autovacuum is running

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SHOW autovacuum;
```

Expected output (yours will differ):

```
 autovacuum
------------
 off
(1 row)
```

If it shows `off`, autovacuum has been disabled.

### Step 2 - Confirm the source of the override

```sql
SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE name = 'autovacuum';
```

Expected output (yours will differ):

```
    name    | setting |    source    |             sourcefile              | sourceline
------------+---------+--------------+-------------------------------------+------------
 autovacuum | off     | configuration file | /opt/pgsql/data/postgresql.auto.conf |          3
(1 row)
```

The `sourcefile` pointing to `postgresql.auto.conf` means an `ALTER SYSTEM` command put it there.

### Step 3 - Check dead tuple accumulation

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;
```

You will see `avac_neglected` and possibly other tables with dead tuples.

```bash
exit
```

---

## Resolution

### Step 1 - Re-enable autovacuum

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET autovacuum;
```

This removes the override from `postgresql.auto.conf`, restoring the default value of `on`.

### Step 2 - Reload the configuration

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify autovacuum is now on

```sql
SHOW autovacuum;
```

Expected output (yours will differ):

```
 autovacuum
------------
 on
(1 row)
```

### Step 4 - Manually VACUUM the bloated table

Do not wait for autovacuum to wake up. Run VACUUM on the known bloated table immediately.

```sql
VACUUM VERBOSE avac_neglected;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.avac_neglected"
INFO:  "avac_neglected": removed 10000 row versions in 56 pages
VACUUM
```

### Step 5 - Confirm dead tuples are cleared

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'avac_neglected';
```

Expected output (yours will differ):

```
    relname     | n_live_tup | n_dead_tup
----------------+------------+------------
 avac_neglected |       5000 |          0
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
- autovacuum is ON
- autovacuum not overridden in postgresql.auto.conf
- avac_neglected dead tuples below 100
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Why would someone disable autovacuum?** - Common (bad) reasons include: a DBA thinks autovacuum is causing I/O spikes and disables it instead of tuning it, a performance consultant gives wrong advice, or a script disables it "temporarily" during a bulk load and forgets to re-enable it. The right response to autovacuum I/O spikes is to tune `autovacuum_vacuum_cost_delay` and `autovacuum_vacuum_cost_limit`, not disable autovacuum entirely.

2. **What is the difference between autovacuum = off in postgresql.conf vs postgresql.auto.conf?** - They are the same parameter, but `postgresql.auto.conf` has higher precedence and always wins. If both files have conflicting values, `postgresql.auto.conf` wins. `ALTER SYSTEM RESET` removes the entry from `postgresql.auto.conf` so the `postgresql.conf` value applies again.

3. **Can you disable autovacuum for just one table without affecting the whole server?** - Yes. `ALTER TABLE t SET (autovacuum_enabled = false)` disables autovacuum for just that table. This is sometimes done for large archive tables that never change. The global `autovacuum` GUC must still be on for per-table autovacuum to work.

4. **How long can a database safely run without autovacuum before hitting serious problems?** - It depends on write rate. At 1 million transactions per day, you would hit the anti-wraparound autovacuum trigger (200 million XIDs) in about 200 days. But table bloat and stale statistics would cause query plan degradation within days or weeks on a busy OLTP system. There is no safe "off" period for production databases.

5. **After re-enabling autovacuum, how do you know it is actually running?** - Check `pg_stat_activity` for rows where `query LIKE 'autovacuum:%'`. Also watch `pg_stat_user_tables.last_autovacuum` - it will update as autovacuum processes each table. Set `log_autovacuum_min_duration = 0` temporarily to log every autovacuum run.
