# Use Exercise 04 - Wraparound Simulation

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Check the current XID age, understand the wraparound timeline, and calculate how many transactions this server can process before reaching the dangerous wraparound threshold. Practice reading the wraparound metrics on the Pulse dashboard.

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

## Task 1 - Check current XID and datfrozenxid

```sql
SELECT datname,
       age(datfrozenxid)     AS current_age,
       datfrozenxid          AS frozen_xid,
       txid_current()        AS current_xid
FROM pg_database
WHERE datname NOT IN ('template0')
ORDER BY current_age DESC;
```

Note down the `current_age` and `current_xid` for stepup_store.

---

## Task 2 - Calculate the wraparound safety boundaries

```sql
SELECT
  datname,
  age(datfrozenxid)                          AS xid_age,
  200000000 - age(datfrozenxid)              AS txns_until_forced_autovacuum,
  1500000000 - age(datfrozenxid)             AS txns_until_log_warning,
  2000000000 - age(datfrozenxid)             AS txns_until_shutdown_risk
FROM pg_database
WHERE datname = 'stepup_store';
```

**Question:** How many transactions can this database handle before PostgreSQL is forced to run anti-wraparound autovacuum? How many before it risks shutdown?

---

## Task 3 - Find the most at-risk table

```sql
SELECT relname,
       age(relfrozenxid)   AS xid_age,
       relfrozenxid,
       200000000 - age(relfrozenxid) AS txns_until_forced_freeze
FROM pg_class
WHERE relkind = 'r'
ORDER BY xid_age DESC
LIMIT 5;
```

The table with the highest `xid_age` is the biggest wraparound risk. This is the table autovacuum will prioritize for freeze vacuum.

---

## Task 4 - Estimate daily transaction rate

Count the transactions PostgreSQL has processed since last statistics reset:

```sql
SELECT datname,
       xact_commit + xact_rollback AS total_transactions,
       stats_reset
FROM pg_stat_database
WHERE datname = 'stepup_store';
```

If `stats_reset` was recent (within the last day), you can estimate the daily rate. Calculate:

```
daily_rate = total_transactions / hours_since_reset * 24
days_until_forced_autovacuum = txns_until_forced_autovacuum / daily_rate
```

**Question:** At your current transaction rate, how many days until anti-wraparound autovacuum is forced?

---

## Task 5 - Simulate what a production server looks like

On a busy production database, the XID age might be in the tens or hundreds of millions. This query shows what monitoring thresholds look like at different ages:

```sql
SELECT
  xid_age,
  CASE
    WHEN xid_age > 1800000000 THEN 'CRITICAL - emergency VACUUM FREEZE NOW'
    WHEN xid_age > 1500000000 THEN 'HIGH - schedule maintenance window'
    WHEN xid_age > 500000000  THEN 'MEDIUM - investigate autovacuum'
    WHEN xid_age > 200000000  THEN 'LOW - autovacuum anti-wraparound running'
    ELSE 'OK'
  END AS risk_level,
  round(100.0 * xid_age / 2000000000, 2) AS risk_pct
FROM (
  SELECT age(datfrozenxid) AS xid_age
  FROM pg_database
  WHERE datname = 'stepup_store'
) AS sub;
```

---

## Task 6 - Run VACUUM FREEZE on the most at-risk table

From Task 3 you found the table with the highest XID age. Run VACUUM FREEZE on it to advance its `relfrozenxid`.

Replace `<most_at_risk_table>` with the table name from Task 3.

```sql
VACUUM FREEZE VERBOSE <most_at_risk_table>;
```

---

## Task 7 - Verify relfrozenxid advanced

```sql
SELECT relname,
       age(relfrozenxid) AS xid_age_before,
       relfrozenxid
FROM pg_class
WHERE relname = '<most_at_risk_table>';
```

The `xid_age` should now be near 0 and `relfrozenxid` should be close to the current XID.

---

## Task 8 - Check the Pulse dashboard wraparound panel

Open your browser to `http://<NODE1_IP>:8080`. On the MVCC/Vacuum panel, the wraparound risk percentage should be very low (less than 1%) on this lab server. On a production server, you would set alerts at 50% and pages at 75%.

---

## Task 9 - Check autovacuum_freeze_max_age in context

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
  'autovacuum_freeze_max_age',
  'vacuum_freeze_min_age',
  'vacuum_freeze_table_age'
);
```

Expected output (yours will differ):

```
            name             |  setting  | unit
-----------------------------+-----------+------
 autovacuum_freeze_max_age   | 200000000 |
 vacuum_freeze_min_age       | 50000000  |
 vacuum_freeze_table_age     | 150000000 |
(3 rows)
```

- `vacuum_freeze_min_age` (50M): minimum XID age before VACUUM will freeze a tuple
- `vacuum_freeze_table_age` (150M): when relfrozenxid age exceeds this, VACUUM scans the whole table to freeze
- `autovacuum_freeze_max_age` (200M): hard limit - anti-wraparound autovacuum fires at this age

---

## Cleanup

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

- XID wraparound happens because transaction IDs are 32-bit - they roll over after ~4 billion
- `age(datfrozenxid)` measures how many transactions ago the oldest unfrozen tuple was written
- Anti-wraparound autovacuum kicks in at `autovacuum_freeze_max_age` (200 million by default)
- Calculate days until forced autovacuum using: `txns_remaining / daily_transaction_rate`
- On production, alert at 50% of the 2-billion XID limit (~1 billion XIDs of age)
- `VACUUM FREEZE` advances `relfrozenxid` immediately by freezing all tuples in the table
