# Runbook: TXID Wraparound Approaching

**Scenario:** Transaction ID age is approaching the danger zone. Autovacuum has not been able to freeze old rows. If not addressed, PostgreSQL will enter read-only mode and eventually shutdown to prevent data corruption.

**Time limit:** 20 minutes (real wraparound emergencies have no time limit - resolve immediately)
**Severity:** P0 - Data integrity risk, imminent shutdown

---

## Background

PostgreSQL uses 32-bit transaction IDs. There are ~2.1 billion possible IDs. As the database ages, the oldest unfrozen tuple's XID age approaches 2.1 billion. PostgreSQL protects against wraparound by:
1. Warning at 1.6B: restricts new connections
2. Shutting down at 1.8B: prevents all writes

The fix is VACUUM FREEZE, which marks old tuples as frozen (immune to wraparound). Autovacuum does this automatically, but can be blocked by long-running transactions.

---

## Step 1 - Check TXID Age Status

**Immediate triage:**

```sql
-- Check database-level XID age (the most important metric)
SELECT
    datname,
    age(datfrozenxid) AS db_xid_age,
    CASE
        WHEN age(datfrozenxid) > 1600000000 THEN 'EMERGENCY - RESTRICT MODE IMMINENT'
        WHEN age(datfrozenxid) > 1500000000 THEN 'CRITICAL - ACT NOW'
        WHEN age(datfrozenxid) > 1000000000 THEN 'WARNING - Schedule maintenance'
        ELSE 'OK'
    END AS urgency
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

**Check table-level XID age:**

```sql
SELECT
    schemaname,
    relname,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(oid)) AS size,
    CASE
        WHEN age(relfrozenxid) > 1500000000 THEN 'FREEZE IMMEDIATELY'
        WHEN age(relfrozenxid) > 1000000000 THEN 'Schedule freeze today'
        WHEN age(relfrozenxid) > 500000000 THEN 'Monitor'
        ELSE 'OK'
    END AS action
FROM pg_class
WHERE relkind = 'r'
ORDER BY age(relfrozenxid) DESC
LIMIT 20;
```

---

## Step 2 - Find What is Blocking Autovacuum Freeze

Autovacuum cannot freeze rows visible to any active transaction:

```sql
-- Find the oldest active transaction
SELECT
    pid,
    usename,
    application_name,
    now() - xact_start AS txn_age,
    state,
    left(query, 100) AS query,
    backend_xid,
    backend_xmin
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start
LIMIT 10;
```

The oldest transaction here is preventing autovacuum from advancing the freeze horizon.

---

## Step 3 - Assess Whether to Kill the Blocking Transaction

If the blocking transaction is:
- `idle in transaction` for a long time: safe to terminate
- An ongoing legitimate job (ETL, pg_dump): contact the team running it
- A test/injected session (pg_sleep): terminate immediately

```sql
-- Confirm the blocker is idle in transaction
SELECT state, now() - state_change AS idle_for
FROM pg_stat_activity
WHERE pid = [BLOCKING_PID];
```

---

## Step 4 - Terminate the Blocker

```sql
SELECT pg_terminate_backend([BLOCKING_PID]);
```

Verify the oldest transaction is now gone:

```sql
SELECT min(xact_start), now() - min(xact_start) AS oldest_txn_age
FROM pg_stat_activity
WHERE xact_start IS NOT NULL;
```

---

## Step 5 - Run Emergency VACUUM FREEZE

Now that the blocker is gone, freeze the at-risk tables immediately:

```sql
-- Freeze all tables in the current database
-- This is an aggressive command - do it during low-traffic periods if possible
-- In a wraparound emergency, do it immediately regardless

VACUUM FREEZE VERBOSE wraparound_risk;
```

For the entire database (more thorough):

```sql
-- This freezes all tables with high XID age
VACUUM FREEZE;
```

Note: `VACUUM FREEZE` takes exclusive locks briefly at the table level. On a production system with active writes, it may block writes for a few seconds per table.

Expected output (yours will differ):
```
INFO:  aggressively vacuuming "public.wraparound_risk"
INFO:  scanned index "wraparound_risk_pkey" to remove 142857 row versions
INFO:  "wraparound_risk": removed 142857 row versions in 1984 pages
INFO:  "wraparound_risk": found 0 removable, 857143 nonremovable row versions in 11905 pages (0 for wraparound)
INFO:  "wraparound_risk": relfrozenxid now 758243921
INFO:  VACUUM
```

`relfrozenxid now 758243921` - the table's frozen XID has been updated to the current transaction ID. XID age is now near 0.

---

## Step 6 - Verify XID Age Reset

```sql
SELECT
    relname,
    age(relfrozenxid) AS xid_age_after_freeze
FROM pg_class
WHERE relname = 'wraparound_risk';
```

Expected:
```
       relname       | xid_age_after_freeze
---------------------+----------------------
 wraparound_risk     |                    3
```

XID age near 0 means the table is fully protected against wraparound.

Also check the database level:

```sql
SELECT datname, age(datfrozenxid) AS db_xid_age
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

---

## Step 7 - Set Up Monitoring

Add a CloudWatch alarm on `MaximumUsedTransactionIDs`:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-TXID-Wraparound-Critical-${DB_INSTANCE_ID}" \
  --metric-name MaximumUsedTransactionIDs \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1000000000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

At 1B: investigate and plan a freeze
At 1.5B: emergency - freeze immediately (Build 01 alarm)
At 1.6B: PostgreSQL itself starts restricting connections

---

## Step 8 - Enable Autovacuum Freeze Settings

For tables that are at risk regularly, set aggressive freeze settings:

```sql
ALTER TABLE wraparound_risk SET (
    autovacuum_freeze_max_age = 100000000,     -- start freeze at 100M XID age (not 200M)
    autovacuum_vacuum_cost_delay = 2            -- less throttling
);
```

In the parameter group, ensure autovacuum is not too slow:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=autovacuum_max_workers,ParameterValue=5,ApplyMethod=pending-reboot" \
    "ParameterName=autovacuum_naptime,ParameterValue=30,ApplyMethod=immediate" \
  --region "$REGION"
```

---

## Emergency: If PostgreSQL Has Already Entered Restricted Mode

```sql
-- Check if you are in restricted mode
SELECT pg_is_in_recovery(), current_setting('transaction_read_only');
```

If `transaction_read_only = on` from wraparound protection:
1. PostgreSQL will refuse write operations
2. You MUST run `VACUUM FREEZE` to unblock
3. Use superuser credentials (reserved connections)
4. Run: `VACUUM FREEZE;` (no table name = all tables)
5. PostgreSQL will automatically exit restricted mode after the freeze

This is the most critical recovery procedure. Practice it before you need it in production.
