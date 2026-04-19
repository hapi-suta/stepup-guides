# Use Exercise 02 - Autovacuum Monitoring

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Set aggressive autovacuum thresholds on a table, generate updates, and watch autovacuum trigger and complete via `pg_stat_user_tables`.

---

## Setup

```bash
ssh -i ~/student.pem ec2-user@<NODE1_IP>
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Lower the global autovacuum naptime

Lower naptime so autovacuum checks tables more frequently during this exercise.

```sql
ALTER SYSTEM SET autovacuum_naptime = '10s';
```

```sql
SELECT pg_reload_conf();
```

---

## Task 2 - Create a table with aggressive per-table autovacuum

```sql
CREATE TABLE avac_watch (
  id      serial PRIMARY KEY,
  counter integer DEFAULT 0
);
```

Insert 500 rows:

```sql
INSERT INTO avac_watch (counter)
SELECT i FROM generate_series(1, 500) AS i;
```

Set very aggressive autovacuum thresholds - trigger after just 5 dead tuples:

```sql
ALTER TABLE avac_watch SET (
  autovacuum_vacuum_threshold = 5,
  autovacuum_vacuum_scale_factor = 0.0
);
```

---

## Task 3 - Check baseline autovacuum stats

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       last_autovacuum,
       autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'avac_watch';
```

Note: `last_autovacuum` should be NULL and `autovacuum_count` should be 0.

---

## Task 4 - Generate dead tuples to trigger autovacuum

Update 10 rows - this creates 10 dead tuples, which exceeds the threshold of 5.

```sql
UPDATE avac_watch SET counter = counter + 100 WHERE id <= 10;
```

---

## Task 5 - Watch for autovacuum to trigger

Autovacuum checks every 10 seconds (the naptime you set). Run this query repeatedly, every 15 seconds, until you see autovacuum run.

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       last_autovacuum,
       autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'avac_watch';
```

You can also check if a worker is actively running:

```sql
SELECT pid, query, state
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
```

Keep re-running both queries until `last_autovacuum` has a timestamp and `autovacuum_count` is 1.

---

## Task 6 - Generate updates again and watch the cycle repeat

```sql
UPDATE avac_watch SET counter = counter + 200 WHERE id <= 20;
```

Wait about 15-20 seconds, then check:

```sql
SELECT relname,
       n_dead_tup,
       last_autovacuum,
       autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'avac_watch';
```

`autovacuum_count` should now be 2.

---

## Task 7 - Check autovacuum history in the PostgreSQL log

Autovacuum logs its work when `log_autovacuum_min_duration` is set. Check if any log lines appear:

```sql
SHOW log_autovacuum_min_duration;
```

If it shows -1 (disabled), autovacuum runs silently. Set it to 0 to log all autovacuum runs:

```sql
ALTER SYSTEM SET log_autovacuum_min_duration = 0;
```

```sql
SELECT pg_reload_conf();
```

Now generate more dead tuples:

```sql
UPDATE avac_watch SET counter = counter + 300 WHERE id <= 30;
```

After autovacuum runs (wait 15-20 seconds), check the log:

```bash
\q
```

```bash
sudo tail -20 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
2026-04-19 14:45:33 UTC [1234]: LOG:  automatic vacuum of table "stepup_store.public.avac_watch": index scans: 0
        pages: 0 removed, 3 remain, 3 scanned (100.00% of total)
        tuples: 30 removed, 500 remain, 0 are dead but not yet removable
        ...
```

---

## Task 8 - Reset configuration

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET autovacuum_naptime;
```

```sql
ALTER SYSTEM RESET log_autovacuum_min_duration;
```

```sql
SELECT pg_reload_conf();
```

---

## Cleanup

```sql
DROP TABLE avac_watch;
```

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

## Key Takeaways

- Autovacuum triggers when: `n_dead_tup > threshold + (scale_factor * n_live_tup)`
- Per-table settings override global settings - useful for high-churn tables
- `pg_stat_user_tables.autovacuum_count` increments each time autovacuum runs on the table
- `log_autovacuum_min_duration = 0` logs every autovacuum run - essential for tuning and debugging
- Watch `pg_stat_activity` to catch autovacuum workers in the act
