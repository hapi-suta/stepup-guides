# Build 03 - Autovacuum Tuning

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 25-30 minutes

---

## What You Will Learn

- What autovacuum workers are and how to configure how many run at once
- How to tune the naptime (how frequently autovacuum wakes up to check tables)
- How to set aggressive per-table autovacuum settings for high-churn tables
- How to monitor autovacuum activity in real time via `pg_stat_user_tables`

---

> **Concept: Autovacuum is a daemon, not a query**
> Autovacuum is a background process that wakes up every `autovacuum_naptime` seconds (default 60), scans all tables across all databases, and triggers VACUUM on any table that meets the dead-tuple threshold. It spawns up to `autovacuum_max_workers` worker processes to run actual VACUUM jobs in parallel. These workers compete for I/O with regular queries - they are deliberately throttled to avoid overwhelming the system.

---

## Step 1 - Log in to NODE1

```bash
ssh -i ~/student.pem ec2-user@<NODE1_IP>
```

---

## Step 2 - Switch to the postgres user

```bash
sudo -iu postgres
```

---

## Step 3 - Connect to stepup_store

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 4 - Check current autovacuum worker configuration

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;
```

Expected output (yours will differ):

```
                    name                     | setting | unit |                         short_desc
---------------------------------------------+---------+------+-------------------------------------------------------------
 autovacuum                                  | on      |      | Starts the autovacuum subprocess.
 autovacuum_analyze_scale_factor             | 0.1     |      | Fraction of table size before auto-analyze.
 autovacuum_analyze_threshold                | 50      |      | Min row changes before auto-analyze.
 autovacuum_freeze_max_age                   | 200000000 |    | Max XID age before forced freeze vacuum.
 autovacuum_max_workers                      | 3       |      | Sets the maximum number of simultaneously running workers.
 autovacuum_multixact_freeze_max_age         | 400000000 |   | Max multixact age before forced vacuum.
 autovacuum_naptime                          | 60      | s    | Time to sleep between autovacuum runs.
 autovacuum_vacuum_cost_delay                | 2       | ms   | Vacuum cost delay for autovacuum, in ms.
 autovacuum_vacuum_cost_limit                | -1      |      | Vacuum cost limit for autovacuum.
 autovacuum_vacuum_insert_scale_factor       | 0.2     |      | Fraction of inserts to trigger vacuum.
 autovacuum_vacuum_insert_threshold          | 1000    |      | Min inserts before auto-vacuum.
 autovacuum_vacuum_scale_factor              | 0.2     |      | Fraction of reltuples before VACUUM.
 autovacuum_vacuum_threshold                 | 50      |      | Min dead tuples before VACUUM.
(13 rows)
```

---

## Step 5 - Understand autovacuum_max_workers

`autovacuum_max_workers` sets the maximum number of autovacuum worker processes that can run simultaneously across all databases. The default is 3.

```sql
SHOW autovacuum_max_workers;
```

Expected output (yours will differ):

```
 autovacuum_max_workers
------------------------
 3
(1 row)
```

> **Concept: Worker slots are shared across databases**
> If you have 10 databases and `autovacuum_max_workers = 3`, at most 3 tables (across all 10 databases combined) can be auto-vacuumed at the same time. On servers with many busy databases, increasing this to 5 or 6 helps ensure all databases get timely cleanup. The trade-off is more I/O from concurrent workers.

---

## Step 6 - Understand autovacuum_naptime

`autovacuum_naptime` is how often (in seconds) the autovacuum launcher wakes up to check if any table needs vacuuming. Default is 60 seconds.

```sql
SHOW autovacuum_naptime;
```

Expected output (yours will differ):

```
 autovacuum_naptime
--------------------
 60s
(1 row)
```

This does not mean VACUUM runs every 60 seconds. It means the launcher wakes up every 60 seconds to look at all tables. If a table needs vacuuming, it spawns a worker. If nothing needs vacuuming, it goes back to sleep.

---

## Step 7 - Create a high-churn table for per-table tuning

```sql
CREATE TABLE hot_orders (
  id        serial PRIMARY KEY,
  status    text,
  updated   timestamptz DEFAULT now()
);
```

Insert some rows:

```sql
INSERT INTO hot_orders (status)
SELECT 'pending' FROM generate_series(1, 1000);
```

Expected output (yours will differ):

```
INSERT 0 1000
```

---

## Step 8 - Check the autovacuum trigger threshold for hot_orders

With 1,000 rows and default settings, autovacuum triggers when dead tuples exceed:
50 + (0.2 * 1000) = 250 dead tuples.

That means 250 dead tuples accumulate before autovacuum runs. For an order status table that gets updated constantly, that is too much. Let's tune it per table.

---

## Step 9 - Set aggressive per-table autovacuum settings

`ALTER TABLE ... SET (storage_parameter)` lets you override the global autovacuum settings for a specific table. This does not require a server restart.

```sql
ALTER TABLE hot_orders SET (
  autovacuum_vacuum_threshold = 10,
  autovacuum_vacuum_scale_factor = 0.01
);
```

> **Concept: Per-table autovacuum overrides**
> The per-table settings use the same parameter names as the global ones, just without the `autovacuum_` prefix in some forms, but with it in the storage parameter list. With `threshold = 10` and `scale_factor = 0.01`, autovacuum triggers when dead tuples exceed 10 + (0.01 * 1000) = 20 dead tuples. That is much more aggressive than the global default of 250.

---

## Step 10 - Verify the per-table settings were applied

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'hot_orders';
```

Expected output (yours will differ):

```
  relname   |                               reloptions
------------+--------------------------------------------------------------------------
 hot_orders | {autovacuum_vacuum_threshold=10,autovacuum_vacuum_scale_factor=0.01}
(1 row)
```

---

## Step 11 - Generate updates to trigger autovacuum

Update all rows in hot_orders to create dead tuples:

```sql
UPDATE hot_orders SET status = 'processing', updated = now();
```

Expected output (yours will differ):

```
UPDATE 1000
```

Check dead tuple count:

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'hot_orders';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup | last_autovacuum | autovacuum_count
------------+------------+------------+-----------------+------------------
 hot_orders |       1000 |       1000 |                 |                0
(1 row)
```

---

## Step 12 - Wait for autovacuum to trigger

Autovacuum must wait for the naptime (default 60 seconds) before it checks again. With 1,000 dead tuples and a threshold of only 20, autovacuum will run the next time the launcher wakes up.

Wait about 60-90 seconds, then re-check:

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'hot_orders';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup |        last_autovacuum        | autovacuum_count
------------+------------+------------+-------------------------------+------------------
 hot_orders |       1000 |          0 | 2026-04-19 14:35:22.456789+00 |                1
(1 row)
```

`last_autovacuum` now has a timestamp and `autovacuum_count` incremented to 1. Autovacuum cleaned the table automatically.

---

## Step 13 - Monitor currently running autovacuum workers

While autovacuum is running you can see the active worker in `pg_stat_activity`:

```sql
SELECT pid, query, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
```

Expected output (yours will differ):

```
  pid  |                     query                     | state  | wait_event_type | wait_event
-------+------------------------------------------------+--------+-----------------+------------
 12345 | autovacuum: VACUUM public.hot_orders (to prevent wraparound) | active |                 |
(1 row)
```

If autovacuum is not running at the moment you check, the result will be 0 rows - autovacuum workers only appear here while they are actively doing work.

---

## Step 14 - Check pg_stat_user_tables for autovacuum stats on all tables

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       last_autovacuum,
       autovacuum_count,
       last_autoanalyze,
       autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;
```

This gives you an overview of which tables have the most dead tuples and when autovacuum last ran on each.

---

## Step 15 - Tune naptime for the lab (demonstration only)

For this lab you can temporarily lower naptime to 15 seconds so you see autovacuum trigger faster. This is a server-wide setting - do not use a 15-second naptime on production without careful I/O analysis.

```sql
ALTER SYSTEM SET autovacuum_naptime = '15s';
```

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

Verify the change took effect:

```sql
SHOW autovacuum_naptime;
```

Expected output (yours will differ):

```
 autovacuum_naptime
--------------------
 15s
(1 row)
```

> **Concept: ALTER SYSTEM vs ALTER TABLE**
> `ALTER SYSTEM` writes to `postgresql.auto.conf` and affects the entire server (takes effect after reload). `ALTER TABLE SET (...)` writes per-table options into the system catalog and takes effect immediately - no reload needed. Per-table settings always override the global defaults for that specific table.

---

## Step 16 - Reset naptime to default

```sql
ALTER SYSTEM RESET autovacuum_naptime;
```

```sql
SELECT pg_reload_conf();
```

---

## Step 17 - Exit psql and postgres user

```sql
\q
```

```bash
exit
```

```bash
exit
```

---

## Summary

- `autovacuum_max_workers` controls how many tables can be vacuumed simultaneously across all databases
- `autovacuum_naptime` sets how often the launcher wakes up to check for work (default 60 seconds)
- `ALTER TABLE SET (autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor)` lets you tune per table
- Per-table settings are essential for high-churn tables that cannot wait for the global threshold
- Monitor autovacuum activity with `pg_stat_user_tables` columns: `last_autovacuum`, `autovacuum_count`

---

## Next Step

Continue to **Build 04 - Transaction Wraparound** to learn about XID age, datfrozenxid, and anti-wraparound vacuum.
