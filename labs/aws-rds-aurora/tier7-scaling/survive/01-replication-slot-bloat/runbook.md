# SURVIVE Scenario 01: Replication Slot Bloat - Runbook

**Incident type:** Logical replication slot not consumed. WAL accumulating on source.
**Severity:** P1 if storage is approaching limits. P2 if lag is growing but storage has headroom.
**Time to resolve:** 15-30 minutes depending on how much WAL has accumulated.

---

## Stop. Read This First.

Do not start remediation until you have assessed the situation. Dropping an active, healthy replication slot is a data-destroying action. Confirm which slots are the problem before touching anything.

---

## Step 1: Assess the Situation

### Check all replication slots

```sql
SELECT
  slot_name,
  plugin,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS consumer_lag,
  CASE WHEN NOT active THEN 'INACTIVE - CONSUMING WAL'
       WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) > 1073741824 THEN 'ACTIVE - HIGH LAG'
       ELSE 'OK'
  END AS health
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) DESC;
```

Write down:
- Which slots are inactive (`active = f`)
- How much WAL each inactive slot is retaining
- Which slots have legitimate consumers (check with the application team if unsure)

### Check current free storage

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[SOURCE-DB-IDENTIFIER] \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Minimum \
  --region [REGION]
```

Compare earliest and latest values to determine the rate of decrease. This tells you how urgently you need to act.

### Calculate time to disk full

```
Time remaining = FreeStorageSpace / (rate of WAL accumulation per hour)
```

If you have less than 2 hours of storage remaining, go to emergency remediation immediately. If you have more time, investigate the root cause first.

---

## Step 2: Identify the Root Cause

There are two problems in this scenario:

**Problem A: Subscription is disabled**

The active subscription (`tier7_sub`) was disabled, so the slot it owns is no longer being consumed.

Check subscription status on the **target** database:

```sql
SELECT subname, subenabled, substatus
FROM pg_stat_subscription;
```

If `subenabled = f`, the subscription is disabled.

**Problem B: Orphaned slot with no consumer**

A slot named `orphaned_slot_do_not_use` exists on the source with no application consuming it.

This is the more dangerous case - there is no subscription to re-enable. The only remediation is to drop the slot (accepting the data loss for whatever would have consumed it).

---

## Step 3: Fix Problem A - Re-enable the Subscription

On the **target** database:

```sql
ALTER SUBSCRIPTION tier7_sub ENABLE;
```

Verify the subscription is reconnecting:

```sql
SELECT subname, subenabled, substatus FROM pg_stat_subscription;
```

Expected:
```
  subname   | subenabled | substatus
------------+------------+-----------
 tier7_sub  | t          | streaming
(1 row)
```

Watch the lag drain on the **source**:

```sql
SELECT
  slot_name,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_name = 'tier7_sub';
```

The lag value should decrease as the subscriber catches up. This may take several minutes if significant WAL accumulated.

---

## Step 4: Fix Problem B - Drop the Orphaned Slot

Confirm there is truly no consumer for this slot. Query the application team, check DMS tasks, check any Debezium or CDC consumers.

If confirmed no consumer exists:

```sql
SELECT pg_drop_replication_slot('orphaned_slot_do_not_use');
```

Verify it is gone:

```sql
SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'orphaned_slot_do_not_use';
```

Expected: 0 rows.

As soon as you drop the slot, PostgreSQL is free to clean up the WAL it was retaining. The WAL directory will shrink, and `FreeStorageSpace` in CloudWatch will recover within minutes.

---

## Step 5: Verify Storage Recovery

Wait 5-10 minutes after dropping the slot, then check storage:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[SOURCE-DB-IDENTIFIER] \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum \
  --region [REGION]
```

You should see `FreeStorageSpace` increasing as WAL is cleaned up.

---

## Step 6: Post-Incident - Prevent Recurrence

### Add a CloudWatch alarm for slot lag

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "[SOURCE-DB-IDENTIFIER]-replication-slot-lag" \
  --metric-name OldestReplicationSlotLag \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=[SOURCE-DB-IDENTIFIER] \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 5120 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --region [REGION]
```

### Establish a slot audit procedure

Add this query to your weekly DBA checklist:

```sql
SELECT slot_name, active, plugin,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) DESC;
```

Any slot with `active = false` and lag > 0 is a risk. Investigate or drop.

### Document all legitimate slots

Maintain a list of replication slots and their owners:

| Slot Name | Owner | Purpose | Contact |
|-----------|-------|---------|---------|
| tier7_sub | Logical replication subscriber | DR sync | [DBA team] |
| [other slots] | ... | ... | ... |

Any slot not in this list should be investigated and dropped if unrecognized.

---

## Root Cause Summary

Two problems combined to create this incident:

1. A subscription was disabled (operator error, application bug, or network failure severed the subscriber connection without the slot being cleaned up).
2. An orphaned slot existed with no consumer, retaining WAL indefinitely.

The fix was:
1. Re-enable the subscription to allow the legitimate consumer to catch up.
2. Drop the orphaned slot to release WAL and recover disk space.

The prevention is:
- CloudWatch alarm on `OldestReplicationSlotLag`.
- Regular audit of `pg_replication_slots`.
- Document all legitimate slots so unknown slots are caught immediately.
