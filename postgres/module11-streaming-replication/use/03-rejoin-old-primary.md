# Exercise 03 - Rejoin Old Primary as Standby (CentOS Stream 9)

**Time estimate:** 20-30 minutes
**Prerequisites:** Exercise 02 complete - NODE1 stopped (timeline 1), NODE2 promoted to primary (timeline 2)

---

## Objective

Use `pg_rewind` to rejoin NODE1 as a standby streaming from NODE2. This restores your two-node cluster with roles reversed.

---

## Why You Cannot Just Create standby.signal and Start

> **Concept:** After promotion, NODE2 started a new timeline (timeline 2). NODE1 is still on timeline 1. Even though they share the same history up to the promotion point, PostgreSQL treats them as diverged. If NODE1 had any WAL written after the standby disconnected (even a checkpoint), its data directory has diverged from NODE2's history. You cannot simply point NODE1 at NODE2 and start streaming - PostgreSQL would detect the timeline mismatch and refuse to connect. You need `pg_rewind` to rewind NODE1's data directory to the exact point where the timelines diverged, then let it stream forward on the new timeline.

---

## Step 1 - Verify pg_rewind Prerequisites

`pg_rewind` requires one of the following to be true on the **target** (NODE1 - the node being rewound):

### Option A - wal_log_hints = on

On **NODE1** (it is stopped, so check the config file):

```bash
grep wal_log_hints /opt/pgsql/data/postgresql.conf
```

**Expected:** `wal_log_hints = on`

### Option B - Data checksums enabled

```bash
/usr/pgsql-16/bin/pg_controldata -D /opt/pgsql/data | grep "Data page checksum"
```

**Expected:** `Data page checksum version: 1` (if checksums were enabled at initdb)

Either one is sufficient. If neither is true, `pg_rewind` will refuse to run and you would need to rebuild the standby from scratch using `pg_basebackup`.

> **Concept:** `pg_rewind` works by reading WAL to identify which data pages changed after the divergence point, then copying only those pages from the source (new primary). It needs `wal_log_hints` or checksums so that it can detect all modified pages - without these, some modifications are invisible in the WAL and `pg_rewind` could leave the data directory in an inconsistent state.

---

## Step 2 - Ensure NODE1 Is Stopped Cleanly

On **NODE1**:

```bash
/usr/pgsql-16/bin/pg_controldata -D /opt/pgsql/data | grep "Database cluster state"
```

**Expected:**
```
Database cluster state:               shut down
```

If it says `in production` or `shut down in recovery`, the server is still running or crashed. Stop it cleanly:

```bash
sudo systemctl stop postgresql-16
```

> **Concept:** `pg_rewind` requires the target to be shut down cleanly. If the old primary crashed (simulating a real failure), you may need to start it in single-user mode first to complete crash recovery, then shut it down cleanly. In this lab, we stopped it with systemctl, which is a clean shutdown.

---

## Step 3 - Ensure NODE2 Allows Connections From NODE1

On **NODE2** (new primary), switch to the postgres user:

```bash
sudo -iu postgres
```

Verify `pg_hba.conf` allows replication connections from NODE1:

```bash
grep replication /opt/pgsql/data/pg_hba.conf
```

**Expected:** A line like:
```
host    replication     replicator      [NODE1_IP]/32       scram-sha-256
```

If this line does not exist, add it:

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add at the end:

```
host    replication     replicator      [NODE1_IP]/32       scram-sha-256
```

Save and reload:

```bash
psql -c "SELECT pg_reload_conf();"
```

```bash
exit
```

---

## Step 4 - Create a Replication Slot on NODE2

On **NODE2** (new primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```sql
SELECT pg_create_physical_replication_slot('standby_slot');
```

**Expected:**
```
 pg_create_physical_replication_slot
--------------------------------------
 (standby_slot,)
```

This slot will hold WAL for NODE1 once it connects as a standby.

```bash
exit
```

---

## Step 5 - Run pg_rewind

On **NODE1** (stopped), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_rewind \
  --target-pgdata=/opt/pgsql/data \
  --source-server="host=[NODE2_IP] port=5432 user=replicator dbname=postgres" \
  --progress
```

Enter the replicator password when prompted: `replicator_pass_2026`

**Expected output (yours will differ):**
```
pg_rewind: connected to server
pg_rewind: servers diverged at WAL location 0/5000148 on timeline 1
pg_rewind: rewinding from last common checkpoint at 0/5000100 on timeline 1
pg_rewind: reading source file list
pg_rewind: reading target file list
pg_rewind: reading WAL in target
pg_rewind: need to copy XX MB (total source directory size is YY MB)
pg_rewind: XX/YY MB (100%) copied
pg_rewind: creating backup label and updating control file
pg_rewind: syncing target data directory
pg_rewind: Done!
```

> **Concept:** Look at what `pg_rewind` did. It connected to NODE2, found the divergence point (the LSN where timeline 2 branched), read WAL from NODE1 to figure out what pages changed after that point, then fetched fresh copies of only those pages from NODE2. This is far faster than a full `pg_basebackup` because it only copies the pages that diverged - often a tiny fraction of the total data.

```bash
exit
```

---

## Step 6 - Configure NODE1 as a Standby

After `pg_rewind`, NODE1's data directory matches NODE2's state at the divergence point. Now configure it as a standby.

### Create standby.signal

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
touch /opt/pgsql/data/standby.signal
```

### Update postgresql.conf for standby mode

```bash
cat >> /opt/pgsql/data/postgresql.conf << 'EOF'

# Standby configuration (after pg_rewind)
primary_conninfo = 'host=[NODE2_IP] port=5432 user=replicator password=replicator_pass_2026 application_name=walreceiver'
primary_slot_name = 'standby_slot'
hot_standby = on
EOF
```

Replace `[NODE2_IP]` with the actual IP of NODE2.

> **Concept:** `standby.signal` is an empty file that tells PostgreSQL to start in standby mode. It replaces the old `recovery.conf` approach from PG 11 and earlier. When PostgreSQL sees this file, it enters continuous recovery - connecting to the primary and streaming WAL indefinitely until you promote it or remove the file.

```bash
exit
```

---

## Step 7 - Start NODE1 as a Standby

```bash
sudo systemctl start postgresql-16
```

Check the log for successful startup. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
tail -20 /opt/pgsql/data/log/postgresql-*.log
```

**Expected log lines (yours will differ):**
```
LOG:  entering standby mode
LOG:  redo starts at 0/5000148
LOG:  started streaming WAL from primary at 0/6000000 on timeline 2
LOG:  consistent recovery state reached at 0/6000XXX
```

Key things to verify in the logs:
- "entering standby mode" confirms standby.signal was found
- "on timeline 2" confirms it is following the new timeline
- "consistent recovery state reached" means it is caught up

---

## Step 8 - Verify Replication From Both Sides

### On NODE1 (new standby), as the postgres user:

```sql
SELECT pg_is_in_recovery();
```

**Expected:** `t`

```sql
SELECT status, sender_host FROM pg_stat_wal_receiver;
```

**Expected:**
```
  status   | sender_host
-----------+-------------
 streaming | [NODE2_IP]
```

### On NODE2 (new primary), as the postgres user:

```sql
SELECT client_addr, state, sync_state FROM pg_stat_replication;
```

**Expected:**
```
 client_addr  |   state   | sync_state
--------------+-----------+------------
 [NODE1_IP]   | streaming | async
```

---

## Step 9 - Verify Data Consistency

On **NODE1** (new standby), as the postgres user:

```sql
\c labdb

SELECT count(*) FROM employees;
```

**Expected:**
```
 count
-------
 10001
```

The 10,001 count includes the "failover_test" row you inserted on NODE2 after promotion. If NODE1 shows 10,001, the rewind and replay worked perfectly.

---

## Step 10 - Verify the Replication Slot Is Active

On **NODE2** (new primary), as the postgres user:

```sql
SELECT slot_name, active, wal_status FROM pg_replication_slots;
```

**Expected:**
```
   slot_name   | active | wal_status
---------------+--------+------------
 standby_slot  | t      | reserved
```

Exit the postgres user on both nodes:

```bash
exit
```

---

## Current State

After this exercise:
- NODE2 is the **primary** (timeline 2)
- NODE1 is the **standby** (streaming from NODE2, timeline 2)
- Roles are reversed from the BUILD phase
- Full redundancy is restored

---

## Checkpoint

Before continuing, confirm:
- [ ] `pg_rewind` completed without errors
- [ ] You created `standby.signal` on NODE1
- [ ] NODE1 is streaming from NODE2 (check both `pg_stat_replication` and `pg_stat_wal_receiver`)
- [ ] NODE1 shows the correct row count (10,001)
- [ ] The replication slot on NODE2 is active
- [ ] You understand why `pg_rewind` is needed (timeline divergence)
- [ ] You can explain the difference between `pg_rewind` and `pg_basebackup` (partial vs full copy)

---

**Next:** [04 - Measure Lag](04-measure-lag.md)
