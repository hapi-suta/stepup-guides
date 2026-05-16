# Build 05: Verify Replication End-to-End (CentOS Stream 9)

Confirm that streaming replication is working correctly between your primary
and standby. This is the final BUILD step.

---

## 1. Check pg_stat_replication on the primary

On NODE1, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
  client_addr   |  state    | sync_state | replay_lag_bytes
----------------+-----------+------------+------------------
 172.31.31.190  | streaming | async      |                0
(1 row)
```

- `client_addr` = NODE2's private IP
- `state` = `streaming`
- `sync_state` = `async`
- `replay_lag_bytes` = small number (ideally 0)

> **Concept - pg_stat_replication is the primary's view**: This view shows one
> row per connected standby. It exists ONLY on the primary. An empty result means
> no standbys are connected - more severe than lag.

Exit back to ec2-user:

```bash
exit
```

---

## 2. Check pg_stat_wal_receiver on the standby

On NODE2, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
SELECT status, sender_host, slot_name,
       received_lsn, latest_end_lsn
FROM pg_stat_wal_receiver;"
```

Expected output (yours will differ):

```
  status   | sender_host | slot_name   | received_lsn | latest_end_lsn
-----------+-------------+-------------+--------------+----------------
 streaming | pg-primary  | standby_slot | 0/4000148   | 0/4000148
(1 row)
```

- `status` = `streaming`
- `sender_host` = `pg-primary` (or NODE1's IP)
- `slot_name` = `standby_slot`

> **Concept - pg_stat_wal_receiver is the standby's view**: This is the mirror
> of pg_stat_replication. It exists ONLY on the standby. Together, these two views
> give you both sides of the replication connection.

Exit back to ec2-user:

```bash
exit
```

---

## 3. Test live replication

On NODE1 (primary), switch to the postgres user:

```bash
sudo -iu postgres
```

Insert a uniquely tagged row:

```bash
psql -d labdb -c "
INSERT INTO employees (name, department) VALUES ('replication_test', 'verify');"
```

Exit back to ec2-user:

```bash
exit
```

On NODE2 (standby), switch to the postgres user:

```bash
sudo -iu postgres
```

Immediately query for it:

```bash
psql -d labdb -c "
SELECT * FROM employees WHERE department = 'verify' ORDER BY id DESC LIMIT 1;"
```

Expected output (yours will differ):

```
  id   |       name        | department |          hired_at
-------+-------------------+------------+----------------------------
 10001 | replication_test  | verify     | 2026-05-16 00:30:00.123+00
(1 row)
```

The row appears within 1-2 seconds. This confirms live streaming replication is working.

Exit back to ec2-user:

```bash
exit
```

---

## 4. Check the replication slot

On NODE1, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
SELECT slot_name, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;"
```

Expected output (yours will differ):

```
  slot_name   | active | restart_lsn | confirmed_flush_lsn
--------------+--------+-------------+---------------------
 standby_slot | t      | 0/4000000   |
(1 row)
```

- `slot_name` = `standby_slot`
- `active` = `t` (the standby is connected and using it)

> **Concept - active = t means the slot is in use**: An active slot has a
> connected consumer. An inactive slot (`active = f`) with a non-null
> `restart_lsn` means WAL is being retained for a disconnected standby. This is
> where disk fills if you forget about an abandoned slot.

---

## 5. Check WAL archiving

Still as the postgres user on NODE1:

```bash
psql -c "
SELECT archived_count, last_archived_wal, last_archived_time, failed_count
FROM pg_stat_archiver;"
```

Expected output (yours will differ):

```
 archived_count |     last_archived_wal      |     last_archived_time      | failed_count
----------------+----------------------------+-----------------------------+--------------
              3 | 000000010000000000000003   | 2026-05-16 00:20:00.123+00  |            0
(1 row)
```

`archived_count` should be greater than 0 and `failed_count` should be 0.

List the first 5 archived WAL files. The pipe to `head -5` limits output to 5 lines:

```bash
ls /var/lib/pgsql/16/archive/ | head -5
```

Expected output (yours will differ):

```
000000010000000000000001
000000010000000000000002
000000010000000000000003
```

Exit back to ec2-user:

```bash
exit
```

---

## What you built

```
NODE1 (pg-primary)                 NODE2 (pg-standby)
┌─────────────────┐               ┌─────────────────┐
│  PostgreSQL 16  │               │  PostgreSQL 16  │
│  wal_level=     │   streaming   │  hot_standby=on │
│    replica      │──────WAL────->│  standby.signal │
│  replicator role│   (async)     │  recovery mode  │
│  standby_slot   │               │  read queries OK│
│  archive_mode=on│               │  writes rejected│
└─────────────────┘               └─────────────────┘
```

You now understand:
- How to install PG from PGDG on CentOS Stream 9
- How WAL flows from primary to standby
- What standby.signal and primary_conninfo do
- What replication slots are and why they matter
- What archive_mode gives you beyond streaming
- Where config files live on CentOS (inside PGDATA, not /etc/postgresql/)

Proceed to `use/01-check-replication-status.md` for Phase 2.
