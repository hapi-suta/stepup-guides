# Exercise 02 - Manual Promote

**Time estimate:** 15-20 minutes
**Prerequisites:** Exercise 01 complete - both nodes healthy, replication lag at zero

---

## Objective

Promote NODE2 from standby to primary. Understand what happens to timelines during promotion and verify the new primary accepts writes.

---

## Step 1 - Confirm Starting State

On **NODE2** (standby):

```sql
SELECT pg_is_in_recovery();
```

**Expected:** `t`

On **NODE1** (primary):

```sql
SELECT client_addr, state FROM pg_stat_replication;
```

**Expected:** One row showing NODE2 streaming.

---

## Step 2 - Stop the Old Primary (NODE1)

This simulates a planned failover where you stop the primary first to prevent split-brain.

On **NODE1**:

```bash
sudo systemctl stop postgresql
```

Or if not using systemd:

```bash
pg_ctl -D /var/lib/postgresql/16/main stop -m fast
```

**Expected:** PostgreSQL stops cleanly.

> **Concept:** In a planned failover, always stop the old primary before promoting the standby. If both nodes accept writes at the same time (split-brain), you will have divergent data that is extremely painful to reconcile. In an unplanned failover (primary crashed), the primary is already down - but you must ensure it stays down and does not come back as a primary.

---

## Step 3 - Promote NODE2

You have two options. Pick one.

### Option A - pg_ctl promote (from the OS)

On **NODE2**:

```bash
/usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main promote
```

> **Note:** On Debian, `pg_ctl` is not in the default PATH. Use the full path
> `/usr/lib/postgresql/16/bin/pg_ctl` or run as the postgres user:
> `sudo -iu postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main promote`

**Expected:**
```
waiting for server to promote.... done
server promoted
```

### Option B - pg_promote() (from SQL)

On **NODE2**, connect to psql:

```sql
SELECT pg_promote(wait := true, wait_seconds := 60);
```

**Expected:**
```
 pg_promote
------------
 t
```

> **Concept:** Both methods do the same thing - they write a promote trigger that tells the WAL receiver to stop and the recovery process to finish. `pg_promote()` was added in PG 12 and is convenient when you already have a SQL connection. `pg_ctl promote` is the traditional method and works even if you cannot connect via SQL.

---

## Step 4 - Verify Promotion Succeeded

On **NODE2** (now primary):

```sql
SELECT pg_is_in_recovery();
```

**Expected:** `f`

This is the definitive check. If it returns `f`, NODE2 is now a read-write primary.

---

## Step 5 - Verify Writes Work

On **NODE2**:

```sql
\c labdb

INSERT INTO employees (name, department)
VALUES ('failover_test', 'Engineering');

SELECT count(*) FROM employees;
```

**Expected:**
```
 count
-------
 10001
```

The count should be 10,001 (original 10,000 plus the test row). If the INSERT succeeds, the promotion is confirmed - standbys reject all writes.

---

## Step 6 - Understand the Timeline Change

On **NODE2** (new primary):

```sql
SELECT timeline_id FROM pg_control_checkpoint();
```

**Expected:**
```
 timeline_id
-------------
           2
```

Before promotion, both nodes were on timeline 1. After promotion, NODE2 advanced to timeline 2.

> **Concept:** A timeline is PostgreSQL's way of tracking history branches. Think of it like a git branch. When a standby promotes, it starts a new timeline to distinguish its WAL from the old primary's WAL. This is critical - if the old primary had written any WAL after the standby diverged, timeline IDs prevent the two histories from being confused. The old primary is still on timeline 1. The new primary is on timeline 2. Any new WAL generated on NODE2 is tagged as timeline 2.

---

## Step 7 - Check the Timeline History File

On **NODE2**, look at the timeline history file:

```bash
ls -la /var/lib/postgresql/16/main/pg_wal/00000002.history
```

**Expected:** The file exists.

```bash
cat /var/lib/postgresql/16/main/pg_wal/00000002.history
```

**Expected:**
```
1	0/5000148	no recovery target specified
```

This tells you: timeline 2 branched from timeline 1 at LSN `0/5000148`.

> **Concept:** The history file is how PostgreSQL tracks the lineage of timelines. When you later use `pg_rewind` or set up a new standby, PostgreSQL reads these history files to understand where timelines diverged. This is the mechanism that makes it safe to rejoin old nodes.

---

## Step 8 - Check pg_stat_wal_receiver Is Gone

On **NODE2** (new primary):

```sql
SELECT * FROM pg_stat_wal_receiver;
```

**Expected:** Zero rows. The WAL receiver process only runs on standbys. After promotion, it shuts down.

---

## Step 9 - Verify the Replication Slot State

On **NODE2** (new primary):

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

**Expected:** Either zero rows or an inactive slot. The old `standby_slot` was on NODE1. NODE2 does not have replication slots unless you create them.

---

## Current State

After this exercise:
- NODE1 is **stopped** (old primary, timeline 1)
- NODE2 is the **new primary** (timeline 2, accepting writes)
- There is no standby - you have lost redundancy

This is the most dangerous moment in a failover. You have exactly one copy of your data. The next exercise walks you through rejoining NODE1 as a standby to restore redundancy.

---

## Checkpoint

Before continuing, confirm:
- [ ] NODE1 is stopped
- [ ] NODE2 returns `pg_is_in_recovery() = f`
- [ ] You successfully wrote a row to labdb on NODE2
- [ ] NODE2 is on timeline 2
- [ ] You found and read the timeline history file
- [ ] You understand why stopping the old primary first prevents split-brain

---

**Next:** [03 - Rejoin Old Primary](03-rejoin-old-primary.md)
