# Exercise 01 - Check Replication Status (CentOS Stream 9)

**Time estimate:** 15-20 minutes
**Prerequisites:** BUILD phase complete - NODE1 (primary) and NODE2 (standby) streaming, labdb with 10,000 employees

---

## Objective

Learn every monitoring query you need to verify streaming replication health. By the end of this exercise, you should be able to assess replication status from either node without referencing this guide.

---

## Step 1 - Confirm Which Node Is Primary and Which Is Standby

On each node, switch to the postgres user and run this query:

```bash
sudo -iu postgres
```

```sql
SELECT pg_is_in_recovery();
```

**Expected:**
- NODE1 (primary): `f`
- NODE2 (standby): `t`

> **Concept:** `pg_is_in_recovery()` is the single most important function for determining a node's role. A primary returns `f` (false) - it is not in recovery. A standby returns `t` (true) - it is perpetually in recovery, replaying WAL from the primary.

---

## Step 2 - Inspect Replication From the Primary (pg_stat_replication)

On **NODE1** (primary), as the postgres user:

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;
```

**Expected:**
```
 pid  | usename  | application_name | client_addr  |   state   |  sent_lsn   | write_lsn   | flush_lsn   | replay_lsn  | sync_state
------+----------+------------------+--------------+-----------+-------------+-------------+-------------+-------------+------------
 1234 | replicator | walreceiver    | [NODE2_IP]   | streaming | 0/5000148   | 0/5000148   | 0/5000148   | 0/5000148   | async
```

**Verify these things:**
- `state` = `streaming` (not `catchup` or `startup`)
- `client_addr` = `[NODE2_IP]`
- `sync_state` = `async` (unless you configured synchronous replication)
- All four LSN columns should be close to each other (ideally identical when idle)

> **Concept:** The four LSN columns represent different stages of WAL delivery. `sent_lsn` is what the primary shipped. `write_lsn` is what the standby wrote to disk. `flush_lsn` is what the standby flushed (fsync). `replay_lsn` is what the standby actually applied. If `replay_lsn` falls behind `sent_lsn`, the standby is receiving WAL faster than it can apply it.

---

## Step 3 - Inspect Replication From the Standby (pg_stat_wal_receiver)

On **NODE2** (standby), as the postgres user:

```sql
SELECT
    pid,
    status,
    receive_start_lsn,
    latest_end_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    sender_host,
    sender_port,
    conninfo
FROM pg_stat_wal_receiver;
```

**Verify these things:**
- `status` = `streaming`
- `sender_host` = `[NODE1_IP]`
- `last_msg_send_time` and `last_msg_receipt_time` are recent (within seconds of now)

> **Concept:** `pg_stat_wal_receiver` is the standby-side counterpart to `pg_stat_replication`. Together they give you both perspectives. In production, always check both - a primary might think it is sending WAL, but the standby might not be receiving it (network partition).

---

## Step 4 - Check the Replication Slot

On **NODE1** (primary), as the postgres user:

```sql
SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status
FROM pg_replication_slots;
```

**Verify these things:**
- `active` = `t` (the standby is connected and using the slot)
- `wal_status` = `reserved` (WAL files are being held for this consumer)
- `confirmed_flush_lsn` is NULL for physical slots (only logical slots use it)

> **Concept:** A replication slot prevents the primary from removing WAL segments the standby still needs. Without a slot, if the standby falls far behind, the primary might recycle WAL files, breaking replication. The tradeoff - a slot can cause disk to fill if the standby goes down for a long time and WAL accumulates. Always monitor `wal_status`; if it changes to `lost`, the slot can no longer be satisfied.

---

## Step 5 - Check WAL Archiving (pg_stat_archiver)

On **NODE1** (primary), as the postgres user:

```sql
SELECT
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time
FROM pg_stat_archiver;
```

**Verify these things:**
- `failed_count` = 0 (no archiving failures)
- `last_archived_time` is reasonably recent

> **Concept:** Even with streaming replication, WAL archiving is your safety net. If streaming breaks, the standby can fall back to restoring archived WAL files. In production, `failed_count > 0` is an alert-worthy condition.

---

## Step 6 - Calculate Replication Lag in Bytes

On **NODE1** (primary), as the postgres user:

```sql
SELECT
    client_addr,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn) AS write_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

**Expected (idle system):** All values at or near 0.

> **Concept:** `pg_wal_lsn_diff()` gives the byte distance between two WAL positions. On an idle system, all values should be 0 or very close to 0. Under load, `replay_lag_bytes` will often be the largest - the standby receives WAL quickly but applying it takes more work. A steadily growing replay lag means the standby cannot keep up with write volume.

---

## Step 7 - Check Replication Lag in Time (Standby Side)

On **NODE2** (standby), as the postgres user:

```sql
SELECT
    now() - pg_last_xact_replay_timestamp() AS replay_lag;
```

**Important caveat:** This query only works when there is write activity on the primary. If the primary is idle, `pg_last_xact_replay_timestamp()` stays frozen at the last transaction's time, making the lag appear to grow even though the standby is fully caught up. Do not alarm on this value during quiet periods.

---

## Step 8 - Build a Combined Health Check Query

On **NODE1** (primary), as the postgres user:

```sql
SELECT
    r.client_addr,
    r.state,
    r.sync_state,
    s.slot_name,
    s.active AS slot_active,
    s.wal_status,
    pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn) AS replay_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn)) AS replay_lag_pretty
FROM pg_stat_replication r
LEFT JOIN pg_replication_slots s
    ON r.client_addr::text = s.active_pid::text
    OR s.slot_name = 'standby_slot'
WHERE s.slot_name = 'standby_slot';
```

Save this query - you will use it throughout the remaining exercises.

When done, exit the postgres user:

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You can identify primary vs standby using `pg_is_in_recovery()`
- [ ] You checked `pg_stat_replication` on the primary
- [ ] You checked `pg_stat_wal_receiver` on the standby
- [ ] You verified the replication slot is active
- [ ] You calculated lag in both bytes and time
- [ ] All lag values are at or near zero

---

**Next:** [02 - Manual Promote](02-manual-promote.md)
