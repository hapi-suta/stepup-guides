# USE Exercise 02: Replication Health Check

| | |
|---|---|
| **Time** | 30 minutes |
| **Server** | pg-primary (3.90.199.62), pg-replica (3.91.32.84) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice
- Checking replication status on the primary via pg_stat_replication
- Checking the WAL receiver on the replica via pg_stat_wal_receiver
- Calculating replication lag in bytes and time
- Checking replication slot status
- Monitoring WAL positions on primary vs. replay on replica
- Writing data on primary and verifying it appears on replica
- Checking Ceph-sim storage health on the replica
- Comparing pg_stat_replication before and after a batch insert

---

## Exercise 1: Open two terminals

You need two terminal windows open at the same time for this exercise - one connected to the primary and one connected to the replica.

Terminal 1 - connect to **pg-primary**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

Terminal 2 - connect to **pg-replica**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

Keep both terminals visible side by side if possible.

---

## Exercise 2: Check replication status on the primary

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Check the pg_stat_replication view - this shows all currently connected standbys:

```sql
SELECT
  client_addr,
  application_name,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  sync_state
FROM pg_stat_replication;
```

Expected output (yours will differ):
```
  client_addr   | application_name |   state   | sent_lsn  | write_lsn | flush_lsn | replay_lsn | sync_state
----------------+------------------+-----------+-----------+-----------+-----------+------------+------------
 172.31.22.69   | pg-replica       | streaming | 0/8A00100 | 0/8A00100 | 0/8A00100 | 0/8A00100  | async
(1 row)
```

Each LSN (Log Sequence Number) column shows how far along the WAL the replica is:
- `sent_lsn` - how much WAL the primary has sent to the replica
- `write_lsn` - how much the replica has written to disk
- `flush_lsn` - how much the replica has flushed (durable)
- `replay_lsn` - how much the replica has applied to its data files

---

## Exercise 3: Calculate replication lag in bytes

Still as **postgres** in the psql session on **pg-primary**:

This query shows the lag in bytes between what the primary has sent and what the replica has replayed:

```sql
SELECT
  client_addr,
  application_name,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_pretty
FROM pg_stat_replication;
```

Expected output (yours will differ):
```
  client_addr   | application_name | lag_bytes | lag_pretty
----------------+------------------+-----------+------------
 172.31.22.69   | pg-replica       |         0 | 0 bytes
(1 row)
```

A lag of 0 bytes means the replica is fully caught up. Any positive number means the replica is behind.

---

## Exercise 4: Calculate replication lag in time

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT
  client_addr,
  application_name,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;
```

Expected output (yours will differ):
```
  client_addr   | application_name | write_lag | flush_lag | replay_lag
----------------+------------------+-----------+-----------+------------
 172.31.22.69   | pg-replica       | 00:00:00  | 00:00:00  | 00:00:00
(1 row)
```

These time-based lag fields show how long ago the replica applied that WAL segment. If they show non-zero values, the replica is falling behind.

---

## Exercise 5: Check replication slot status

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT
  slot_name,
  plugin,
  slot_type,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS retained_wal
FROM pg_replication_slots;
```

Expected output (yours will differ):
```
   slot_name   | plugin | slot_type | active | retained_wal
---------------+--------+-----------+--------+--------------
 replica_slot  |        | physical  | t      | 0 bytes
(1 row)
```

A replication slot forces the primary to keep WAL files until the replica has consumed them. If the replica goes down and `retained_wal` keeps growing, it can fill up your disk - this is a common production risk.

---

## Exercise 6: Check WAL receiver status on the replica

Switch to **Terminal 2** - you are on **pg-replica** as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Check pg_stat_wal_receiver - this view only exists on standbys:

```sql
SELECT
  status,
  receive_start_lsn,
  received_lsn,
  last_msg_send_time,
  last_msg_receipt_time,
  sender_host,
  sender_port
FROM pg_stat_wal_receiver;
```

Expected output (yours will differ):
```
  status   | receive_start_lsn | received_lsn | last_msg_send_time | last_msg_receipt_time |  sender_host  | sender_port
-----------+-------------------+--------------+--------------------+-----------------------+---------------+-------------
 streaming | 0/7000000         | 0/8A00100    | 2026-06-15...      | 2026-06-15...         | 172.31.19.86  | 5432
(1 row)
```

The `sender_host` should be the private IP of the primary (172.31.19.86). Status `streaming` means it is actively receiving WAL.

---

## Exercise 7: Verify current WAL position on both servers

On **pg-replica**, still as **postgres** in psql:

```sql
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_is_in_recovery();
```

Switch to **Terminal 1** - on **pg-primary**, as **postgres** in psql:

```sql
SELECT pg_current_wal_lsn();
```

Compare the two LSN values. They should be very close or identical.

---

## Exercise 8: Write data on primary and verify it appears on replica

On **pg-primary**, as **postgres** in the psql session:

Insert a test row:

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
VALUES ('REPTEST-01', 'Replication Test Row', 'equity')
RETURNING id, symbol, created_at;
```

Note the `id` value that comes back. You will look for it on the replica.

Switch to **Terminal 2** - on **pg-replica**, as **postgres** in psql:

```sql
SELECT id, symbol, name, created_at
FROM quant.instruments
WHERE symbol = 'REPTEST-01';
```

Expected output (yours will differ):
```
  id  |   symbol   |         name         |         created_at
------+------------+----------------------+----------------------------
 1042 | REPTEST-01 | Replication Test Row | 2026-06-15 14:32:01.123456
(1 row)
```

The row should appear on the replica within milliseconds on an async setup.

---

## Exercise 9: Clean up test data and check lag impact

Switch back to **Terminal 1** - on **pg-primary**, as **postgres** in psql:

Delete the test row:

```sql
DELETE FROM quant.instruments WHERE symbol = 'REPTEST-01';
```

Confirm it is gone on primary:

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol = 'REPTEST-01';
```

Switch to **Terminal 2** - on **pg-replica**, confirm it is gone there too:

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol = 'REPTEST-01';
```

---

## Exercise 10: Compare pg_stat_replication before and after a batch insert

On **pg-primary**, as **postgres** in psql - capture baseline lag:

```sql
SELECT
  client_addr,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
  replay_lag
FROM pg_stat_replication;
```

Now run a batch insert to generate WAL activity:

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
SELECT
  'BATCH-' || gs,
  'Batch Insert Test ' || gs,
  'equity'
FROM generate_series(1, 500) gs;
```

Immediately check lag again:

```sql
SELECT
  client_addr,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
  replay_lag
FROM pg_stat_replication;
```

Wait a few seconds and check again:

```sql
SELECT
  client_addr,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
  replay_lag
FROM pg_stat_replication;
```

You should see lag_bytes spike briefly after the insert and then drop back to 0 as the replica catches up.

Clean up:

```sql
DELETE FROM quant.instruments WHERE symbol LIKE 'BATCH-%';
```

---

## Exercise 11: Check Ceph-sim storage health on the replica

Exit psql and the postgres shell on the replica.

On **pg-replica**, as **postgres** in psql:

```sql
\q
```

```bash
exit
```

Now as **ec2-user** on **pg-replica**:

Check how much space is used on the Ceph-sim mount:

```bash
df -h /mnt/ceph-sim
```

Expected output (yours will differ):
```
Filesystem                   Size  Used Avail Use% Mounted on
/dev/mapper/ceph--sim-data   50G   12G   38G  24%  /mnt/ceph-sim
```

Check the logical volumes:

```bash
sudo lvs
```

Expected output (yours will differ):
```
  LV    VG        Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  data  ceph-sim  -wi-ao----  50.00g
```

Check that the replica's PostgreSQL data directory or WAL is on Ceph-sim:

```bash
ls -lh /mnt/ceph-sim/
```

---

## Exercise 12: Exit both sessions cleanly

On **pg-primary**, as **postgres** in psql:

```sql
\q
```

```bash
exit
```

On **pg-replica**, if still connected:

```bash
exit
```

---

## Summary

In this exercise you:
- Queried pg_stat_replication on the primary to see connected standbys and LSN positions
- Queried pg_stat_wal_receiver on the replica to confirm it is streaming
- Calculated replication lag in both bytes and time
- Checked the replication slot and understood the risk of WAL retention
- Wrote data on the primary and confirmed it replicated to the standby
- Compared pg_stat_replication before and after a batch insert to see lag behavior
- Checked Ceph-sim storage health on the replica using df and lvs
