# Runbook: TXID Wraparound Approaching

**Scenario:** The transaction ID age is climbing toward the wraparound danger zone. If it reaches ~2.1 billion, PostgreSQL will refuse new write transactions to prevent data corruption. This is a data-loss-prevention shutdown.

**Time limit:** 30 minutes (but the real danger is hours/days away - this is about stopping the climb)
**Severity:** P1 - Potential catastrophic data protection shutdown

---

## Symptoms

- CloudWatch alarm `MaximumUsedTransactionIDs` firing
- PostgreSQL log warnings: `WARNING: database "xxx" must be vacuumed within yyy transactions`
- XID age (from `pg_database.datfrozenxid`) approaching 1.5 billion
- Autovacuum running but cannot freeze rows

---

## Step 1 - Check Current XID Age

```sql
SELECT
    datname,
    age(datfrozenxid) AS xid_age,
    round(age(datfrozenxid)::numeric / 2147483647 * 100, 1) AS pct_to_wraparound
FROM pg_database
ORDER BY xid_age DESC;
```

Expected output:
```
  datname  |  xid_age   | pct_to_wraparound
-----------+------------+-------------------
 mydb      | 1200000000 |              55.9
 postgres  |  500000000 |              23.3
 template0 |  500000000 |              23.3
```

**Danger zones:**

| XID Age | Status | Action |
|---------|--------|--------|
| < 500M | Normal | Routine monitoring |
| 500M - 1B | Warning | Investigate why freeze is not happening |
| 1B - 1.5B | Critical | Urgent action required |
| > 1.5B | Emergency | All hands on deck |
| > ~2.1B | Shutdown | PostgreSQL refuses new writes |

---

## Step 2 - Find What is Blocking Freeze Operations

The most common cause is a long-running transaction holding back the freeze horizon:

```sql
SELECT
    pid,
    usename,
    application_name,
    now() - xact_start AS txn_age,
    state,
    left(query, 100) AS query,
    backend_xmin
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start ASC
LIMIT 10;
```

Look for:
- Sessions with `application_name` like `txid_blocker`
- Very old `txn_age` (hours or days)
- `backend_xmin` that is far behind the current XID

Also check for replication slots holding back the freeze:

```sql
SELECT
    slot_name,
    slot_type,
    active,
    age(xmin) AS xmin_age,
    age(catalog_xmin) AS catalog_xmin_age
FROM pg_replication_slots
WHERE xmin IS NOT NULL OR catalog_xmin IS NOT NULL
ORDER BY greatest(age(xmin), age(catalog_xmin)) DESC;
```

---

## Step 3 - Kill the Blocking Transaction

If the blocker is an idle-in-transaction session or the injected blocker:

```sql
SELECT pg_terminate_backend([BLOCKING_PID]);
```

Replace `[BLOCKING_PID]` with the pid from Step 2.

If it is a replication slot that is no longer needed:

```sql
SELECT pg_drop_replication_slot('slot_name');
```

---

## Step 4 - Check Which Tables Need Freezing

```sql
SELECT
    schemaname || '.' || relname AS table_name,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(relid)) AS size,
    last_autovacuum,
    last_vacuum
FROM pg_stat_user_tables
ORDER BY age(relfrozenxid) DESC
LIMIT 20;
```

Tables with the highest `xid_age` need to be vacuumed (frozen) first.

---

## Step 5 - Run Manual VACUUM FREEZE

Start with the tables that have the highest XID age:

```sql
VACUUM (FREEZE, VERBOSE) txid_test_1;
```

```sql
VACUUM (FREEZE, VERBOSE) txid_test_2;
```

```sql
VACUUM (FREEZE, VERBOSE) txid_test_3;
```

Expected output:
```
INFO:  aggressively vacuuming "public.txid_test_1"
INFO:  "txid_test_1": found 0 removable, 500000 nonremovable row versions in 5000 pages
INFO:  "txid_test_1": frozen 500000 row versions in 5000 pages
...
```

`FREEZE` tells VACUUM to mark all rows as frozen regardless of age. This is more aggressive than a normal VACUUM.

---

## Step 6 - Verify XID Age is Decreasing

```sql
SELECT
    datname,
    age(datfrozenxid) AS xid_age,
    round(age(datfrozenxid)::numeric / 2147483647 * 100, 1) AS pct_to_wraparound
FROM pg_database
ORDER BY xid_age DESC;
```

The `xid_age` should be lower after the VACUUM FREEZE operations.

---

## Step 7 - Speed Up Autovacuum for Large Tables

If autovacuum is too slow to keep up, reduce its throttling:

```sql
ALTER TABLE txid_test_1 SET (
    autovacuum_vacuum_cost_delay = 0,
    autovacuum_freeze_max_age = 100000000
);
```

- `autovacuum_vacuum_cost_delay = 0`: No throttling - autovacuum runs at full speed on this table.
- `autovacuum_freeze_max_age = 100000000`: Trigger aggressive freeze at 100M instead of 200M.

For the parameter group (affects all tables):

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=0,ApplyMethod=immediate" \
    "ParameterName=autovacuum_max_workers,ParameterValue=6,ApplyMethod=immediate" \
  --region "$REGION"
```

After the crisis is resolved, restore the defaults:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=2,ApplyMethod=immediate" \
    "ParameterName=autovacuum_max_workers,ParameterValue=3,ApplyMethod=immediate" \
  --region "$REGION"
```

---

## Step 8 - Stop the XID Burners

If the inject script is still running:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name LIKE 'txid_burner%';
```

---

## Prevention

1. **Set CloudWatch alarm on MaximumUsedTransactionIDs** at 1,000,000,000 (1 billion)
2. **Set idle_in_transaction_session_timeout = 60000** to prevent long-running transactions
3. **Monitor pg_database.datfrozenxid age** weekly
4. **Tune autovacuum for large tables** with lower scale_factor and cost_delay
5. **Clean up unused replication slots** that can hold back the freeze horizon

---

## Post-Incident Check

```sql
-- XID age should be well below 1 billion
SELECT datname, age(datfrozenxid) AS xid_age
FROM pg_database ORDER BY xid_age DESC;

-- No long-running transactions
SELECT pid, now() - xact_start AS age, left(query, 80)
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY age DESC LIMIT 5;

-- No stale replication slots
SELECT slot_name, active, age(xmin) FROM pg_replication_slots
WHERE xmin IS NOT NULL;
```
