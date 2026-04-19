# Runbook 07 - Table Bloat Emergency

| Field         | Value                                        |
|---------------|----------------------------------------------|
| Scenario      | Massive dead tuple bloat with autovacuum off  |
| Severity      | MEDIUM                                       |
| Recovery Time | 5-15 minutes                                 |
| Blast Radius  | Single table - queries slow, disk waste       |

---

## Fix Path

### Step 1 - Identify the Bloated Table

Check `pg_stat_user_tables` for tables with high dead tuple counts.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname,
         n_live_tup,
         n_dead_tup,
         CASE WHEN n_live_tup + n_dead_tup > 0
              THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1)
              ELSE 0
         END AS dead_pct,
         last_vacuum,
         last_autovacuum,
         last_analyze
  FROM pg_stat_user_tables
  WHERE n_dead_tup > 1000
  ORDER BY n_dead_tup DESC;
"
```

You will see `chaos_bloat_test` with ~150000 dead tuples and a dead_pct over 70%.

### Step 2 - Measure Exact Bloat with pgstattuple

The `pgstattuple` extension gives precise physical bloat measurements.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  CREATE EXTENSION IF NOT EXISTS pgstattuple;
  SELECT * FROM pgstattuple('chaos_bloat_test');
"
```

Key fields to look at:
- `dead_tuple_count` - number of dead tuples
- `dead_tuple_percent` - percentage of table occupied by dead tuples
- `free_space` - space that could be reclaimed

### Step 3 - Check Autovacuum Setting

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname, reloptions
  FROM pg_class
  WHERE relname = 'chaos_bloat_test';
"
```

The `reloptions` column will show `{autovacuum_enabled=false}`. This is why autovacuum has not cleaned up the dead tuples.

### Step 4 - Re-enable Autovacuum

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  ALTER TABLE chaos_bloat_test SET (autovacuum_enabled = true);
"
```

### Step 5 - Run Manual VACUUM

Do not wait for autovacuum to kick in - run a manual VACUUM with VERBOSE to see what it does.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  VACUUM VERBOSE chaos_bloat_test;
"
```

The output will show how many dead tuples were removed and how many pages were freed.

### Step 6 - Verify Bloat is Reduced

Run pgstattuple again to confirm the dead tuple percentage dropped.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT dead_tuple_count, dead_tuple_percent, free_percent
  FROM pgstattuple('chaos_bloat_test');
"
```

After VACUUM, `dead_tuple_count` should be 0 or very low. Note that `free_percent` may still be high - VACUUM marks space as reusable but does not return it to the OS.

### Step 7 - Verify Autovacuum is Re-enabled

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT relname, reloptions
  FROM pg_class
  WHERE relname = 'chaos_bloat_test';
"
```

```bash
exit
```

The `reloptions` should no longer contain `autovacuum_enabled=false`.

---

## Revision Concepts

### MVCC and Dead Tuples

PostgreSQL uses Multi-Version Concurrency Control (MVCC). When you UPDATE a row, PostgreSQL does not overwrite the old data. Instead, it:
1. Marks the old row version as "dead" (sets xmax)
2. Creates a new row version with the updated data

The old row version stays on disk until VACUUM removes it. These are "dead tuples."

After 3 full-table updates of 50000 rows, there are approximately 150000 dead tuple versions sitting on disk - 3x the actual data.

### VACUUM vs VACUUM FULL

**VACUUM** (regular):
- Marks dead tuple space as reusable by future INSERTs
- Does NOT return disk space to the OS
- Does NOT lock the table - reads and writes can continue
- Should be the default choice

**VACUUM FULL**:
- Rewrites the entire table, reclaiming all space
- Returns disk space to the OS
- Takes an ACCESS EXCLUSIVE lock - blocks ALL queries
- Use only when you need to physically shrink the table

### pg_repack Alternative

In production, `pg_repack` is preferred over VACUUM FULL because it:
- Rewrites the table without holding an exclusive lock for the entire duration
- Only takes a brief lock at the start and end
- Rebuilds indexes at the same time

### Autovacuum Tuning

Autovacuum triggers when dead tuples exceed a threshold:
```
threshold = autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * n_live_tup
```

Default values:
- `autovacuum_vacuum_threshold` = 50 rows
- `autovacuum_vacuum_scale_factor` = 0.2 (20%)

For a table with 50000 rows: threshold = 50 + 0.2 * 50000 = 10050 dead tuples.

For large tables (millions of rows), the 20% scale factor means autovacuum may not trigger until millions of dead tuples accumulate. Lower the scale factor for large tables:

```sql
ALTER TABLE big_table SET (autovacuum_vacuum_scale_factor = 0.01);
```

---

## Interview Discussion

**Q: What is MVCC and how does it relate to bloat?**

MVCC keeps old row versions around so concurrent transactions can see a consistent snapshot. The trade-off is that dead tuples accumulate and must be cleaned up by VACUUM. If VACUUM falls behind or is disabled, the table bloats - consuming more disk and making sequential scans slower.

**Q: When would you use VACUUM FULL vs pg_repack?**

VACUUM FULL in a maintenance window when downtime is acceptable. pg_repack when you need to reclaim space without blocking production queries. Regular VACUUM in all other cases - it is usually sufficient because the freed space will be reused by future writes.

**Q: How do you tune autovacuum for a high-write table?**

Lower `autovacuum_vacuum_scale_factor` (e.g., from 0.2 to 0.01) so VACUUM runs more frequently. Increase `autovacuum_vacuum_cost_limit` to let VACUUM do more work per cycle. Set these at the table level so you do not affect other tables. Monitor `n_dead_tup` and `last_autovacuum` in `pg_stat_user_tables` to confirm tuning is effective.

**Q: Why would someone disable autovacuum on a table?**

Rarely valid. Some teams disable it during bulk loads to avoid autovacuum overhead, then re-enable and run a manual VACUUM/ANALYZE afterward. This is risky if someone forgets to re-enable it. A safer approach is to raise the threshold temporarily rather than disabling entirely.

**Q: How does table bloat affect query performance?**

Sequential scans must read all pages, including those full of dead tuples. Index scans are less affected but still suffer because the heap pages they reference may contain mostly dead data. The table also consumes more buffer cache space, potentially evicting other useful pages.
