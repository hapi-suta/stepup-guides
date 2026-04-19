# Runbook 09 - Stale Statistics

| Field         | Value                                        |
|---------------|----------------------------------------------|
| Scenario      | Planner using outdated row estimates          |
| Severity      | MEDIUM                                       |
| Recovery Time | 2-5 minutes                                  |
| Blast Radius  | Queries on affected table choose wrong plans  |

---

## Fix Path

### Step 1 - Reproduce the Slow Query

Run an EXPLAIN on a query that should use the index.

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  EXPLAIN SELECT * FROM chaos_stats_test WHERE category = 42;
"
```

You will see a **Seq Scan** with an estimated row count near 500 (based on the stale 500000-row estimate). With only 1000 actual rows and category having 1000 distinct values, the planner should estimate ~1 row and choose an **Index Scan**.

### Step 2 - Check Statistics vs Reality

Compare what the planner thinks vs actual row count.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname,
         n_live_tup,
         n_dead_tup,
         last_analyze,
         last_autoanalyze
  FROM pg_stat_user_tables
  WHERE relname = 'chaos_stats_test';
"
```

Note:
- `n_live_tup` shows the stale estimate (~500000)
- `last_analyze` shows when stats were last collected - before the DELETE

Now check the actual count.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT count(*) FROM chaos_stats_test;
"
```

The actual count is ~1000, but the planner thinks there are ~500000 rows.

### Step 3 - Check Autovacuum/Autoanalyze Setting

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname, reloptions
  FROM pg_class
  WHERE relname = 'chaos_stats_test';
"
```

Autovacuum is disabled, which also disables autoanalyze for this table.

### Step 4 - Re-enable Autovacuum

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  ALTER TABLE chaos_stats_test SET (autovacuum_enabled = true);
"
```

### Step 5 - Run ANALYZE

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  ANALYZE chaos_stats_test;
"
```

### Step 6 - Verify the Plan Changed

Run the same EXPLAIN again.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  EXPLAIN SELECT * FROM chaos_stats_test WHERE category = 42;
"
```

You should now see an **Index Scan** on `idx_chaos_stats_category` with an estimated row count of ~1. The planner now has accurate statistics.

### Step 7 - Confirm Statistics Are Current

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname,
         n_live_tup,
         last_analyze
  FROM pg_stat_user_tables
  WHERE relname = 'chaos_stats_test';
"
```
```bash
exit
```

The `n_live_tup` should now be close to 1000, and `last_analyze` should be recent.

---

## Revision Concepts

### How the Planner Uses Statistics

The PostgreSQL query planner decides between Seq Scan, Index Scan, Hash Join, Merge Join, etc. based on **cost estimates**. These estimates depend on:

1. **pg_class.reltuples** - estimated total rows in the table
2. **pg_class.relpages** - estimated pages on disk
3. **pg_statistic** - column-level statistics (most common values, histogram bounds, null fraction, distinct values)

When these statistics are stale, the planner makes bad decisions. In this scenario:
- Planner thinks 500000 rows exist
- For `WHERE category = 42`, it estimates 500000 / 1000 = 500 rows
- 500 rows is enough to favor a Seq Scan over an Index Scan
- But only ~1 row actually matches, making Index Scan far better

### ANALYZE

`ANALYZE` samples rows from the table and updates the statistics in `pg_statistic`. It does not lock the table (it takes only a brief ShareUpdateExclusiveLock).

Key details:
- Default sample size is controlled by `default_statistics_target` (default: 100)
- Higher values = more accurate stats but slower ANALYZE
- Column-level override: `ALTER TABLE t ALTER COLUMN c SET STATISTICS 500;`

### Autoanalyze Thresholds

Autoanalyze triggers when:
```
changes > autovacuum_analyze_threshold + autovacuum_analyze_scale_factor * n_live_tup
```

Default: 50 + 0.1 * n_live_tup (10% of rows changed).

In this scenario, autoanalyze would have triggered (499000 deletes > 10% of 500000), but autovacuum was disabled at the table level, which also disables autoanalyze.

### n_live_tup vs count(*)

`pg_stat_user_tables.n_live_tup` is an estimate maintained by the stats collector. It is updated by autovacuum/autoanalyze and manual VACUUM/ANALYZE. It is NOT updated by every INSERT/DELETE/UPDATE. For the exact count, you must run `SELECT count(*)` - which requires a full table scan.

---

## Interview Discussion

**Q: A query that used to be fast is now slow. No schema changes. What do you check first?**

Run EXPLAIN (ANALYZE) to see the actual plan and compare estimated vs actual row counts. If the estimates are wildly wrong, stale statistics are the likely cause. Check `last_analyze` and `last_autoanalyze` in `pg_stat_user_tables`. Run ANALYZE if stats are outdated.

**Q: How do stale statistics cause bad query plans?**

The planner chooses between Seq Scan and Index Scan based on how many rows it expects to return. If it overestimates rows (stale high count), it chooses Seq Scan because reading the whole table is cheaper than many random index lookups. If it underestimates, it might choose a Nested Loop where a Hash Join would be better. Accurate statistics are essential for good plans.

**Q: When should you run ANALYZE manually?**

After bulk loads (COPY or mass INSERT), after large DELETEs, after ALTER TABLE operations that change data distribution, and after restoring from a backup. Autoanalyze handles routine changes, but large batch operations can leave stats stale until the next autoanalyze cycle.

**Q: What is the difference between ANALYZE and VACUUM ANALYZE?**

`ANALYZE` only updates statistics. `VACUUM ANALYZE` removes dead tuples AND updates statistics. After a large DELETE, you want both - VACUUM to reclaim space and ANALYZE to update the row estimates. Running them together saves a pass over the table.

**Q: Can stale statistics cause problems beyond slow queries?**

Yes. The planner uses statistics for parallel query decisions, join order, and memory allocation (e.g., hash table sizing). Wildly wrong estimates can cause hash joins to spill to disk, or the planner to choose a join order that generates billions of intermediate rows. In extreme cases, a bad plan can consume all available memory or run for hours instead of seconds.
