# Runbook: Wraparound Emergency (XID Exhaustion Risk)

**Severity:** Critical
**Last Updated:** 2026-06-09
**Owner:** DBA Team

---

## Symptoms

- CloudWatch alarm or monitoring alert: database transaction age approaching wraparound limit
- PostgreSQL logs: `WARNING: database "mydb" must be vacuumed within X transactions`
- PostgreSQL logs: `ERROR: database is not accepting commands to avoid wraparound data loss`
- Tables with autovacuum disabled accumulating dead tuples
- `age(datfrozenxid)` approaching 2 billion (2,000,000,000)

---

## Impact

- At 2 billion transactions without VACUUM FREEZE, PostgreSQL enters read-only mode
- ALL writes are refused across the entire database - not just affected tables
- This is a database-wide emergency that requires immediate manual intervention
- Recovery requires running VACUUM FREEZE, which can take hours on large tables

---

## Immediate Actions (first 5 minutes)

### Step 1: Check Database Transaction Age

```sql
SELECT
    datname,
    age(datfrozenxid) AS age,
    CASE
        WHEN age(datfrozenxid) > 1200000000 THEN 'CRITICAL - VACUUM FREEZE NOW'
        WHEN age(datfrozenxid) > 1000000000 THEN 'WARNING - plan VACUUM FREEZE'
        WHEN age(datfrozenxid) > 500000000 THEN 'ELEVATED - monitor closely'
        ELSE 'OK'
    END AS status
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

### Step 2: Identify Tables with Oldest Transaction IDs

```sql
SELECT
    n.nspname AS schema,
    c.relname AS table_name,
    age(c.relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
    c.reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY age(c.relfrozenxid) DESC
LIMIT 20;
```

### Step 3: Check Autovacuum Status

```sql
SELECT
    schemaname || '.' || relname AS table_name,
    n_dead_tup AS dead_tuples,
    n_live_tup AS live_tuples,
    CASE
        WHEN n_live_tup > 0
        THEN round(n_dead_tup::numeric / n_live_tup * 100, 1)
        ELSE 0
    END AS dead_pct,
    last_autovacuum,
    last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Step 4: Find Tables with Autovacuum Disabled

```sql
SELECT
    n.nspname || '.' || c.relname AS table_name,
    c.reloptions,
    age(c.relfrozenxid) AS xid_age
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND c.reloptions::text LIKE '%autovacuum_enabled=false%'
ORDER BY age(c.relfrozenxid) DESC;
```

---

## Remediation

### Fix 1: Run VACUUM FREEZE on Affected Tables

Start with the tables that have the oldest transaction IDs:

```sql
VACUUM (FREEZE, VERBOSE) m09_wraparound_test1;
VACUUM (FREEZE, VERBOSE) m09_wraparound_test2;
VACUUM (FREEZE, VERBOSE) m09_wraparound_test3;
```

The `FREEZE` option marks all tuples as frozen, resetting the transaction age. The `VERBOSE` option shows progress information.

For large tables, VACUUM FREEZE can take a long time. Monitor progress:

```sql
SELECT
    pid,
    datname,
    relid::regclass AS table_name,
    phase,
    heap_blks_total,
    heap_blks_scanned,
    CASE
        WHEN heap_blks_total > 0
        THEN round(heap_blks_scanned::numeric / heap_blks_total * 100, 1)
        ELSE 0
    END AS pct_complete
FROM pg_stat_progress_vacuum;
```

### Fix 2: Re-enable Autovacuum on All Tables

```sql
ALTER TABLE m09_wraparound_test1 SET (autovacuum_enabled = true);
ALTER TABLE m09_wraparound_test2 SET (autovacuum_enabled = true);
ALTER TABLE m09_wraparound_test3 SET (autovacuum_enabled = true);
```

### Fix 3: Verify Autovacuum is Re-enabled

```sql
SELECT
    n.nspname || '.' || c.relname AS table_name,
    c.reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND c.reloptions::text LIKE '%autovacuum_enabled=false%';
```

This should return zero rows.

### Fix 4: Clean Up Test Tables (Optional)

If these tables were created for the exercise only:

```sql
DROP TABLE IF EXISTS m09_wraparound_test1;
DROP TABLE IF EXISTS m09_wraparound_test2;
DROP TABLE IF EXISTS m09_wraparound_test3;
```

---

## Verification

After running VACUUM FREEZE and re-enabling autovacuum:

```sql
-- Check database age has decreased
SELECT datname, age(datfrozenxid) AS age
FROM pg_database
WHERE datname = 'postgres';

-- Check no tables have autovacuum disabled
SELECT count(*)
FROM pg_class c
WHERE c.relkind = 'r'
  AND c.reloptions::text LIKE '%autovacuum_enabled=false%';
-- Should return 0

-- Check dead tuples are cleaned up
SELECT relname, n_dead_tup
FROM pg_stat_user_tables
WHERE relname LIKE 'm09_wraparound%';
-- dead_tup should be 0 or very low after VACUUM
```

Run `validate.sh` to confirm all checks pass.

---

## Prevention

1. Never disable autovacuum in production unless you have a manual VACUUM schedule
2. Monitor `age(datfrozenxid)` with CloudWatch custom metrics or a monitoring Lambda
3. Set alerts at these thresholds:
   - 500,000,000: WARNING (investigate)
   - 1,000,000,000: HIGH (plan VACUUM FREEZE maintenance window)
   - 1,200,000,000: CRITICAL (VACUUM FREEZE immediately)
4. Tune autovacuum parameters for large tables:
   ```sql
   ALTER TABLE large_table SET (
       autovacuum_vacuum_scale_factor = 0.01,
       autovacuum_analyze_scale_factor = 0.005
   );
   ```
5. Include XID age in weekly operational review

---

## Escalation

- If database is in read-only mode due to wraparound: this is a SEV1. All hands on deck.
- If VACUUM FREEZE on a large table will take > 4 hours: coordinate with application team for maintenance window
- If multiple databases are at risk: escalate to DBA team lead for parallel VACUUM coordination
