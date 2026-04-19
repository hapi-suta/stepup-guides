# Scenario 08 - Autovacuum Too Aggressive

**Severity:** MEDIUM
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Autovacuum is consuming excessive I/O and CPU.
autovacuum_naptime=1s, cost_delay=0, cost_limit=10000.
Queries are running slower than expected.
Autovacuum workers are constantly active.
```

---

## Key Concepts for Revision

- **autovacuum_naptime** - How long autovacuum sleeps between rounds of checking tables. The default is 1 minute (`1min`). Setting this to `1s` means the autovacuum launcher wakes up every second to scan for tables needing work. On a system with many tables, this constant scanning itself creates overhead.

- **autovacuum_vacuum_cost_delay** - After autovacuum has done `cost_limit` worth of I/O work, it sleeps for this many milliseconds. The default is `2ms` (PostgreSQL 16). Setting it to `0` means autovacuum never sleeps - it runs at full speed, competing with user queries for disk I/O bandwidth. This is the single most impactful parameter for autovacuum resource usage.

- **autovacuum_vacuum_cost_limit** - The I/O cost budget before autovacuum pauses. Default is `200` (inherited from `vacuum_cost_limit`). Setting it to `10000` means autovacuum does 50x more work before each pause. Combined with `cost_delay=0`, this removes all throttling.

- **autovacuum_vacuum_scale_factor and threshold** - These control when a table becomes eligible for autovacuum. The formula is: vacuum when `dead_tuples > threshold + scale_factor * n_live_tup`. With `scale_factor=0.001` and `threshold=1`, a table with 10,000 rows gets vacuumed after just 11 dead tuples. This means nearly every write triggers a vacuum.

- **The right approach is tuning, not disabling** - When autovacuum causes performance problems, the fix is to adjust these parameters to balance cleanup speed vs I/O impact. Never disable autovacuum entirely - that leads to table bloat and XID wraparound risk.

---

## Diagnostic Steps

### Step 1 - Check for active autovacuum workers

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT pid, query, state, wait_event_type, wait_event,
       now() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
```

Expected output (yours will differ):

```
  pid  |                  query                  | state  | wait_event_type | wait_event | duration
-------+-----------------------------------------+--------+-----------------+------------+----------
 12345 | autovacuum: VACUUM public.aggressive_... | active |                 |            | 00:00:01
(1 row)
```

You may see autovacuum workers constantly running. They finish quickly, then immediately start again.

### Step 2 - Check the aggressive settings

```sql
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
  'autovacuum_naptime',
  'autovacuum_vacuum_cost_delay',
  'autovacuum_vacuum_cost_limit',
  'autovacuum_vacuum_scale_factor',
  'autovacuum_vacuum_threshold'
)
ORDER BY name;
```

Expected output (yours will differ):

```
              name               | setting | unit |       source
---------------------------------+---------+------+---------------------
 autovacuum_naptime              | 1       | s    | configuration file
 autovacuum_vacuum_cost_delay    | 0       | ms   | configuration file
 autovacuum_vacuum_cost_limit    | 10000   |      | configuration file
 autovacuum_vacuum_scale_factor  | 0.001   |      | configuration file
 autovacuum_vacuum_threshold     | 1       |      | configuration file
(5 rows)
```

All of these are set to extreme values. The `source` column shows `configuration file`, meaning they were set via `ALTER SYSTEM`.

### Step 3 - Confirm the overrides are in postgresql.auto.conf

```sql
SELECT name, setting, applied
FROM pg_file_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;
```

Expected output (yours will differ):

```
              name               | setting | applied
---------------------------------+---------+---------
 autovacuum_naptime              | 1s      | t
 autovacuum_vacuum_cost_delay    | 0       | t
 autovacuum_vacuum_cost_limit    | 10000   | t
 autovacuum_vacuum_scale_factor  | 0.001   | t
 autovacuum_vacuum_threshold     | 1       | t
(5 rows)
```

```bash
exit
```

---

## Resolution

### Step 1 - Reset autovacuum parameters to defaults

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Reset each parameter. This removes the override from `postgresql.auto.conf` and restores the built-in default.

```sql
ALTER SYSTEM RESET autovacuum_naptime;
```

```sql
ALTER SYSTEM RESET autovacuum_vacuum_cost_delay;
```

```sql
ALTER SYSTEM RESET autovacuum_vacuum_cost_limit;
```

```sql
ALTER SYSTEM RESET autovacuum_vacuum_scale_factor;
```

```sql
ALTER SYSTEM RESET autovacuum_vacuum_threshold;
```

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

### Step 3 - Verify the parameters are back to defaults

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
  'autovacuum_naptime',
  'autovacuum_vacuum_cost_delay',
  'autovacuum_vacuum_cost_limit',
  'autovacuum_vacuum_scale_factor',
  'autovacuum_vacuum_threshold'
)
ORDER BY name;
```

Expected output (yours will differ):

```
              name               | setting | unit
---------------------------------+---------+------
 autovacuum_naptime              | 60      | s
 autovacuum_vacuum_cost_delay    | 2       | ms
 autovacuum_vacuum_cost_limit    | -1      |
 autovacuum_vacuum_scale_factor  | 0.2     |
 autovacuum_vacuum_threshold     | 50      |
(5 rows)
```

The `cost_limit` showing `-1` means it inherits from the global `vacuum_cost_limit` (default 200).

### Step 4 - Confirm autovacuum is no longer constantly running

```sql
SELECT pid, query, state
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
```

You should see either no rows (autovacuum is sleeping) or occasional short-lived workers - not constant activity.

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
- autovacuum_naptime is 60s or more
- autovacuum_vacuum_cost_delay is greater than 0
- autovacuum_vacuum_cost_limit is default (-1 or 200)
- autovacuum_vacuum_scale_factor is 0.1 or higher
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What is a reasonable starting point for autovacuum tuning on a busy OLTP system?** - Start with the defaults and adjust based on monitoring. If autovacuum cannot keep up (dead tuples grow over time), reduce `autovacuum_vacuum_cost_delay` from 2ms to 0ms, or increase `autovacuum_vacuum_cost_limit` from 200 to 400-800. Reduce `naptime` from 60s to 15-30s only if you have many tables. Never go to the extreme of `naptime=1s` and `cost_delay=0` simultaneously.

2. **How do you know if autovacuum is causing I/O problems vs just being visible?** - Check `pg_stat_bgwriter.buffers_clean` and `pg_stat_wal.wal_bytes` during autovacuum runs. Compare query latency percentiles (p95, p99) when autovacuum is active vs inactive. If p99 latency spikes correlate with autovacuum worker activity, autovacuum is competing for I/O. If latency is stable, the autovacuum workers are not the bottleneck.

3. **Can you set different autovacuum aggressiveness per table?** - Yes. Use `ALTER TABLE t SET (autovacuum_vacuum_cost_delay = 10, autovacuum_vacuum_scale_factor = 0.01)`. This is useful when you have a mix of large fact tables (need aggressive vacuum) and small config tables (default is fine). Per-table settings override the global GUC for that table only.

4. **What is the difference between autovacuum_vacuum_cost_limit and vacuum_cost_limit?** - `vacuum_cost_limit` is the global setting that applies to manual VACUUM and is the default for autovacuum when `autovacuum_vacuum_cost_limit = -1`. Setting `autovacuum_vacuum_cost_limit` to a positive number overrides the global default for autovacuum workers only, leaving manual VACUUM unaffected.

5. **In PostgreSQL 16, what changed with the default autovacuum_vacuum_cost_delay?** - PostgreSQL 12 changed the default from `20ms` to `2ms`, making autovacuum significantly more responsive out of the box. This means modern PostgreSQL is already much better at keeping up with dead tuple accumulation. Reducing it to `0` is rarely needed except on very high-write systems with fast SSDs.
