# Runbook: Transaction ID Wraparound Emergency

**Severity:** Critical (P0 if age(datfrozenxid) > 1.8 billion)
**Risk:** If allowed to reach the wraparound limit, PostgreSQL will shut down the database to prevent data corruption. Recovery requires a standalone PostgreSQL VACUUM run, which requires downtime.

---

## Symptoms

- Custom monitoring: `age(datfrozenxid)` approaching 2 billion
- PostgreSQL log: `WARNING: database "dbname" must be vacuumed within N transactions`
- PostgreSQL log: `HINT: To avoid a database shutdown, execute a database-wide VACUUM in "dbname"`
- Autovacuum is running but not keeping up, or is disabled on key tables
- Tables with `autovacuum_enabled = false` storage parameter

---

## Immediate Actions (first 5 minutes)

1. Assess the current risk level:

```sql
SELECT datname,
       age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS transactions_remaining,
       round(age(datfrozenxid) * 100.0 / 2000000000, 2) AS pct_of_limit
FROM pg_database
ORDER BY xid_age DESC;
```

Risk thresholds:
- age < 500M: Monitor. Not urgent.
- age 500M-1B: Warning. Plan VACUUM FREEZE this week.
- age 1B-1.5B: High. VACUUM FREEZE this weekend.
- age 1.5B-1.8B: Critical. VACUUM FREEZE now during off-peak.
- age > 1.8B: Emergency. Drop everything. VACUUM FREEZE immediately.

2. Check which tables are not frozen:

```sql
SELECT schemaname, relname,
       greatest(age(relfrozenxid), age(relminmxid)) AS table_xid_age,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND greatest(age(relfrozenxid), age(relminmxid)) > 100000000
ORDER BY table_xid_age DESC
LIMIT 20;
```

3. Check for autovacuum being disabled on tables:

```sql
SELECT relname, reloptions
FROM pg_class
WHERE reloptions::text LIKE '%autovacuum_enabled=false%'
  AND relkind = 'r';
```

Any table with `autovacuum_enabled=false` is a wraparound risk if it has write activity.

---

## Diagnosis

### Why did autovacuum fall behind?

Check current autovacuum activity:

```sql
SELECT pid, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%'
ORDER BY duration DESC;
```

Check autovacuum stats for the problematic table:

```sql
SELECT relname, n_dead_tup, n_live_tup,
       last_autovacuum, last_autoanalyze,
       autovacuum_count
FROM pg_stat_user_tables
WHERE relname = '[TABLE-NAME]';
```

Common reasons autovacuum falls behind:
1. `autovacuum_enabled = false` on the table
2. `autovacuum_vacuum_cost_delay` too high (heavily throttled)
3. Long-running transactions on the primary preventing VACUUM from removing old rows
4. Very high write rate exceeding autovacuum throughput

### Check for long-running transactions blocking VACUUM

```sql
SELECT pid, now() - xact_start AS xact_duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
AND now() - xact_start > interval '1 hour'
ORDER BY xact_duration DESC;
```

A long-running transaction prevents VACUUM from removing rows that were live at the transaction's start time.

---

## Remediation

### Step 1: Re-enable autovacuum on affected tables

```sql
ALTER TABLE [SCHEMA].[TABLE-NAME] RESET (autovacuum_enabled);
-- This removes the autovacuum_enabled=false setting (restores to default=true)
```

### Step 2: Run manual VACUUM FREEZE on the most affected tables

```sql
-- Run VACUUM FREEZE on a specific table (no table lock, but I/O intensive)
VACUUM FREEZE VERBOSE [SCHEMA].[TABLE-NAME];
```

Monitor progress in a separate session:

```sql
SELECT pid, phase, heap_blks_total, heap_blks_vacuumed,
       round(heap_blks_vacuumed * 100.0 / NULLIF(heap_blks_total, 0), 2) AS pct_complete
FROM pg_stat_progress_vacuum;
```

### Step 3: Boost autovacuum aggressiveness

Temporarily increase autovacuum throughput via the parameter group:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters \
    ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=2,ApplyMethod=immediate \
    ParameterName=autovacuum_max_workers,ParameterValue=6,ApplyMethod=immediate \
    ParameterName=autovacuum_vacuum_cost_limit,ParameterValue=800,ApplyMethod=immediate \
    ParameterName=autovacuum_naptime,ParameterValue=15,ApplyMethod=immediate \
  --region [REGION]
```

After the emergency is resolved, restore `autovacuum_vacuum_cost_delay` to a value appropriate for your I/O capacity (typically 10-20ms for OLTP).

### Step 4: Terminate long-running transactions (if they are blocking VACUUM)

```sql
-- Confirm with the application team before terminating
SELECT pg_terminate_backend([PID]);
```

---

## Verification

After VACUUM FREEZE and autovacuum restoration:

```sql
-- Re-check wraparound proximity
SELECT datname, age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS transactions_remaining
FROM pg_database
ORDER BY xid_age DESC;
```

The `xid_age` should be significantly lower. A successful VACUUM FREEZE on all tables in a database can reduce `age(datfrozenxid)` substantially.

```sql
-- Verify autovacuum is now active on the table
SELECT relname, reloptions
FROM pg_class
WHERE relname = 't8_high_churn_events'
AND relkind = 'r';
-- reloptions should no longer show autovacuum_enabled=false
```

---

## Prevention

1. **Monitor age(datfrozenxid) as a standard metric:**
   - Warning alert at age > 500 million
   - Critical/page at age > 1 billion

2. **Never disable autovacuum on tables with write activity.** If autovacuum is causing performance problems, tune it - do not disable it.

3. **Set `autovacuum_freeze_max_age = 200000000`** - forces freezing on tables before they reach dangerous ages.

4. **Set per-table autovacuum tuning on high-churn tables** instead of disabling it:

```sql
ALTER TABLE high_churn_table SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.005,
  autovacuum_vacuum_cost_delay = 10
);
```

5. **Monitor table-level freeze age:** The database-level `age(datfrozenxid)` is driven by the most unfrozen table. Monitor per-table ages with the `pg_class.relfrozenxid` query.

---

## Escalation

If `age(datfrozenxid)` exceeds 1.9 billion:
- Immediately contact all application teams to prepare for potential emergency maintenance
- Schedule an emergency VACUUM FREEZE outside of peak hours
- If VACUUM FREEZE cannot complete before wraparound, plan for a controlled shutdown and standalone `vacuumdb --freeze` operation (requires direct filesystem access - not available on RDS)
- Open an AWS Support case to get guidance on emergency vacuum procedures for RDS at this scale
