# Build 04 - Transaction Wraparound

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 25-30 minutes

---

## What You Will Learn

- What XID wraparound is and why it is catastrophic if it happens
- How to use the `age()` function to check how close a database is to wraparound
- What `datfrozenxid` and `relfrozenxid` are and how they protect you
- How anti-wraparound vacuum works and when it triggers
- How VACUUM FREEZE forces tuple freezing immediately
- How to read the Pulse dashboard's wraparound risk percentage

---

> **Concept: XID wraparound - the 32-bit clock problem**
> PostgreSQL uses 32-bit transaction IDs (XIDs). That gives you about 4 billion unique XIDs. PostgreSQL treats this as a circular counter - when it wraps around, old XIDs suddenly look "in the future" instead of "in the past." PostgreSQL would treat all previously visible rows as invisible (they would all look like they come from a future transaction). This is a complete data outage. To prevent this, VACUUM "freezes" old tuples - replacing their xmin with a special value that is always visible to every transaction, no matter where the XID counter is.

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

## Step 4 - Check the current XID age of each database

`age(datfrozenxid)` tells you how many transactions have occurred since the oldest unfrozen XID in that database. A higher number means more risk.

```sql
SELECT datname,
       age(datfrozenxid) AS xid_age,
       datfrozenxid
FROM pg_database
ORDER BY xid_age DESC;
```

Expected output (yours will differ):

```
   datname    | xid_age | datfrozenxid
--------------+---------+--------------
 stepup_store |    1523 |          748
 labdb         |    1456 |          815
 postgres      |    1201 |         1070
 template1    |    1201 |         1070
 template0    |    1201 |         1070
(5 rows)
```

> **Concept: datfrozenxid**
> `datfrozenxid` is the oldest XID that has NOT yet been frozen in a database. Every tuple with an xmin older than `datfrozenxid` has already been frozen and is safe from wraparound. The `age()` of `datfrozenxid` tells you how far you are from the 2-billion-transaction wraparound safety limit. PostgreSQL starts warning at 40 million XIDs of age, and forces anti-wraparound vacuum at `autovacuum_freeze_max_age` (default 200 million).

---

## Step 5 - Check the per-table freeze age

`relfrozenxid` works the same way but per table. It tells you the oldest unfrozen XID in that table's heap.

```sql
SELECT relname,
       age(relfrozenxid) AS xid_age,
       relfrozenxid
FROM pg_class
WHERE relkind = 'r'
  AND relname NOT LIKE 'pg_%'
ORDER BY xid_age DESC
LIMIT 10;
```

Expected output (yours will differ):

```
    relname    | xid_age | relfrozenxid
---------------+---------+--------------
 vacuum_demo   |     312 |         1459
 hot_orders    |     298 |         1473
 mvcc_demo     |     278 |         1493
(3 rows)
```

---

## Step 6 - Check the autovacuum_freeze_max_age setting

```sql
SHOW autovacuum_freeze_max_age;
```

Expected output (yours will differ):

```
 autovacuum_freeze_max_age
---------------------------
 200000000
(1 row)
```

When any table's `relfrozenxid` age exceeds 200 million, autovacuum will ignore its normal threshold rules and run a freeze vacuum on that table immediately, even if you have disabled autovacuum globally. This is called anti-wraparound autovacuum.

---

## Step 7 - Understand the safe wraparound margin

The hard wraparound limit is 2 billion XIDs. PostgreSQL applies a safety margin of 1 billion, which gives the `autovacuum_freeze_max_age` and `vacuum_freeze_min_age` parameters room to work. The full timeline:

```sql
SELECT 2000000000 - age(datfrozenxid) AS xids_until_autovacuum_forced,
       2100000000 - age(datfrozenxid) AS xids_until_warning_in_log,
       2147483648 - age(datfrozenxid) AS xids_until_hard_wraparound
FROM pg_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
 xids_until_autovacuum_forced | xids_until_warning_in_log | xids_until_hard_wraparound
------------------------------+---------------------------+----------------------------
               1999998477     |         2099998477        |         2147482125
(1 row)
```

This lab server is brand new - you are billions of transactions away from wraparound. On a busy production server these numbers matter a lot.

---

## Step 8 - Check autovacuum_vacuum_freeze_min_age

This parameter controls the minimum age a tuple's xmin must be before VACUUM will freeze it. The default is 50 million.

```sql
SHOW vacuum_freeze_min_age;
```

Expected output (yours will differ):

```
 vacuum_freeze_min_age
-----------------------
 50000000
(1 row)
```

> **Concept: The freezing process**
> When VACUUM runs normally, it freezes tuples whose xmin is older than `vacuum_freeze_min_age` (50 million XIDs by default). It stores a special "frozen" marker instead of the original xmin. A frozen tuple is always visible to all transactions. When VACUUM FREEZE runs, it forces freezing on ALL tuples regardless of age - useful when you need to quickly advance `relfrozenxid`.

---

## Step 9 - Run VACUUM FREEZE manually

`VACUUM FREEZE` is the emergency tool for advancing `relfrozenxid` immediately. It freezes every tuple in the table, regardless of age.

```sql
VACUUM FREEZE VERBOSE mvcc_demo;
```

Expected output (yours will differ):

```
INFO:  aggressively vacuuming "public.mvcc_demo"
INFO:  "mvcc_demo": found 0 removable, 5 nonremovable row versions in 1 out of 1 pages
DETAIL:  0 dead row versions cannot be removed yet, oldest xmin: 771
         Frozen in pages: 1 out of 1 frozen.
VACUUM
```

"Aggressively vacuuming" means PostgreSQL applied the freeze. "Frozen in pages: 1 out of 1" means all pages in this table are now frozen.

---

## Step 10 - Verify relfrozenxid advanced

```sql
SELECT relname,
       age(relfrozenxid) AS xid_age,
       relfrozenxid
FROM pg_class
WHERE relname = 'mvcc_demo';
```

Expected output (yours will differ):

```
  relname  | xid_age | relfrozenxid
-----------+---------+--------------
 mvcc_demo |       0 |         1771
(1 row)
```

The age dropped to near 0 because `relfrozenxid` advanced to the current XID.

---

## Step 11 - Check the Pulse dashboard wraparound panel

Open your browser to `http://<NODE1_IP>:8080` and look at the MVCC/Vacuum panel. The wraparound risk percentage is calculated as:

```
risk % = (age(datfrozenxid) / autovacuum_freeze_max_age) * 100
```

On this lab server the risk will be very low (well under 1%). On production servers you want to alert if this exceeds 50%.

---

## Step 12 - Simulate a high-age scenario (read-only demonstration)

You cannot actually advance XIDs without running transactions. But you can see what the alert thresholds look like:

```sql
SELECT
  CASE
    WHEN age(datfrozenxid) > 1500000000 THEN 'CRITICAL - wraparound imminent'
    WHEN age(datfrozenxid) > 500000000  THEN 'WARNING - run VACUUM FREEZE now'
    WHEN age(datfrozenxid) > 200000000  THEN 'CAUTION - autovacuum anti-wraparound running'
    ELSE 'OK'
  END AS wraparound_status,
  age(datfrozenxid) AS current_age
FROM pg_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
 wraparound_status | current_age
-------------------+-------------
 OK                |        1523
(1 row)
```

---

## Step 13 - Exit psql and postgres user

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

- XID wraparound occurs because transaction IDs are 32-bit integers - after ~4 billion transactions they roll over
- PostgreSQL prevents this by "freezing" old tuples - replacing their xmin with a permanently visible marker
- `datfrozenxid` tracks the oldest unfrozen XID per database; `relfrozenxid` tracks it per table
- `age(datfrozenxid)` tells you how far you are from the 2-billion wraparound limit
- Autovacuum triggers anti-wraparound vacuum when age exceeds `autovacuum_freeze_max_age` (default 200 million)
- `VACUUM FREEZE` forces immediate freezing of all tuples in a table
- Monitor wraparound risk on the Pulse dashboard's MVCC/Vacuum panel

---

## Next Step

Continue to **Build 05 - Bloat Detection and Remediation** to learn how to measure and fix table and index bloat.
