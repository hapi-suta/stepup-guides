# Build 01 - MVCC Fundamentals

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 25-30 minutes

---

## What You Will Learn

- How PostgreSQL implements Multi-Version Concurrency Control (MVCC)
- What xmin and xmax are and what they tell you about a row's visibility
- How UPDATE creates a new tuple version and leaves the old one as a dead tuple
- How to use the pageinspect extension to see raw tuple headers
- How to watch dead tuple counts rise on the Pulse dashboard

---

> **Concept: What is MVCC?**
> MVCC stands for Multi-Version Concurrency Control. Instead of locking a row when it is being read, PostgreSQL keeps multiple versions of each row simultaneously. Readers always see a consistent snapshot of the data as it existed when their transaction started - even if other transactions are modifying rows at the same moment. This means readers never block writers and writers never block readers.

---

## Step 1 - Log in to NODE1

Open a terminal and SSH to your server.

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

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - Install the pageinspect extension

The `pageinspect` extension lets you read raw page-level data from heap files. You need it to see xmin and xmax values.

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
```

Expected output (yours will differ):

```
CREATE EXTENSION
```

---

## Step 5 - Create a test table

```sql
CREATE TABLE mvcc_demo (
  id   serial PRIMARY KEY,
  name text
);
```

---

## Step 6 - Insert a row

```sql
INSERT INTO mvcc_demo (name) VALUES ('version_one');
```

Expected output (yours will differ):

```
INSERT 0 1
```

---

## Step 7 - View the tuple header with pageinspect

`heap_page_items` reads the raw page and shows you every tuple stored in it, including hidden fields that `SELECT *` never shows.

```sql
SELECT lp, lp_off, t_xmin, t_xmax, t_ctid,
       t_infomask::bit(16) AS infomask
FROM heap_page_items(get_raw_page('mvcc_demo', 0));
```

Expected output (yours will differ):

```
 lp | lp_off | t_xmin | t_xmax | t_ctid | infomask
----+--------+--------+--------+--------+------------------
  1 |   8160 |    742 |      0 | (0,1)  | 0000100000000010
(1 row)
```

> **Concept: xmin and xmax**
> Every row version (called a "tuple") carries two hidden transaction IDs. `xmin` is the transaction ID that inserted this tuple - it marks when the row was born. `xmax` is the transaction ID that deleted or updated this tuple - a value of 0 means nobody has deleted it yet. PostgreSQL uses these values to decide whether a tuple is visible to your transaction's snapshot.

---

## Step 8 - See xmin and xmax directly via system columns

PostgreSQL exposes xmin and xmax as system columns you can query directly.

```sql
SELECT xmin, xmax, id, name FROM mvcc_demo;
```

Expected output (yours will differ):

```
 xmin | xmax | id |    name
------+------+----+-------------
  742 |    0 |  1 | version_one
(1 row)
```

The `xmin` matches the transaction ID that ran your INSERT. The `xmax` is 0 - this row has not been deleted or updated.

---

## Step 9 - Update the row and observe a new tuple version

```sql
UPDATE mvcc_demo SET name = 'version_two' WHERE id = 1;
```

---

## Step 10 - Query the system columns again

```sql
SELECT xmin, xmax, id, name FROM mvcc_demo;
```

Expected output (yours will differ):

```
 xmin | xmax | id |    name
------+------+----+-------------
  743 |    0 |  1 | version_two
(1 row)
```

The `xmin` has changed to a new transaction ID. PostgreSQL created a brand-new tuple for the updated row.

> **Concept: UPDATE creates two tuples**
> When you run UPDATE, PostgreSQL does NOT modify the existing row in place. It writes a new tuple with the new values and marks the old tuple as dead by setting its `xmax` to the current transaction ID. The old tuple (version_one) still exists on disk until VACUUM removes it. This is why UPDATE can cause table bloat.

---

## Step 11 - See both tuple versions with pageinspect

```sql
SELECT lp, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('mvcc_demo', 0));
```

Expected output (yours will differ):

```
 lp | t_xmin | t_xmax | t_ctid
----+--------+--------+--------
  1 |    742 |    743 | (0,2)
  2 |    743 |      0 | (0,2)
(1 row)
```

Two tuples are now on the page. Line pointer 1 is the old dead tuple - its `t_xmax` is set to the update transaction. Line pointer 2 is the live tuple. The `t_ctid` on the old tuple points to (0,2), meaning "the current version of this row is at page 0, item 2".

---

## Step 12 - Check dead tuple count in pg_stat_user_tables

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'mvcc_demo';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup
------------+------------+------------
 mvcc_demo  |          1 |          1
(1 row)
```

One live tuple, one dead tuple. The dead tuple is the old version_one row.

---

## Step 13 - Create more dead tuples

Run several updates to build up dead tuples.

```sql
UPDATE mvcc_demo SET name = 'version_three' WHERE id = 1;
```

```sql
UPDATE mvcc_demo SET name = 'version_four' WHERE id = 1;
```

```sql
UPDATE mvcc_demo SET name = 'version_five' WHERE id = 1;
```

---

## Step 14 - Check dead tuple count again

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'mvcc_demo';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup
------------+------------+------------
 mvcc_demo  |          1 |          4
(1 row)
```

Four dead tuples have accumulated - one for each update.

---

## Step 15 - Open the Pulse dashboard

Open a browser and go to:

```
http://<NODE1_IP>:8080
```

Navigate to the MVCC/Vacuum panel. You should see the `mvcc_demo` table appearing in the dead tuple count. The dashboard polls `pg_stat_user_tables` every few seconds, so your numbers will appear shortly.

---

## Step 16 - Understand transaction snapshots

Transaction snapshots are what determine which tuple versions are visible to your query. Open a second terminal window and SSH to NODE1.

In terminal 1, start a transaction but do not commit:

```sql
BEGIN;
```

```sql
SELECT xmin, xmax, name FROM mvcc_demo;
```

Expected output (yours will differ):

```
 xmin | xmax |     name
------+------+--------------
  745 |    0 | version_five
(1 row)
```

---

## Step 17 - In terminal 2, update the row

In terminal 2, switch to postgres and connect to stepup_store, then run:

```sql
UPDATE mvcc_demo SET name = 'version_six' WHERE id = 1;
```

---

## Step 18 - Back in terminal 1, read the row again (still inside BEGIN)

```sql
SELECT xmin, xmax, name FROM mvcc_demo;
```

Expected output (yours will differ):

```
 xmin | xmax |     name
------+------+--------------
  745 |    0 | version_five
(1 row)
```

> **Concept: Snapshot Isolation**
> You still see version_five even though terminal 2 already committed version_six. PostgreSQL took a snapshot of active transactions when your BEGIN ran. Any rows created by transactions that started after your snapshot are invisible to you. This is repeatable read behavior at the default READ COMMITTED level - at READ COMMITTED, you would see the newly committed row on the next SELECT within the same transaction. The key point is that reads never block writes.

---

## Step 19 - End the transaction

```sql
ROLLBACK;
```

```bash
exit
```

---

## Step 20 - Exit postgres user

```bash
exit
```

---

## Summary

- Every row in PostgreSQL is stored as a tuple with hidden `xmin` and `xmax` fields
- INSERT sets xmin to the inserting transaction ID; xmax stays 0
- UPDATE writes a new tuple with a new xmin and sets xmax on the old tuple
- Dead tuples are the old row versions left behind by UPDATE and DELETE
- Transaction snapshots determine which tuple versions each query can see
- The Pulse dashboard reads `pg_stat_user_tables` to show dead tuple counts in real time

---

## Next Step

Continue to **Build 02 - Vacuum Operations** to learn how to remove dead tuples and reclaim space.
