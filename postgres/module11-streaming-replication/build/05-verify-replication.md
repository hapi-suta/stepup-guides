# Build 05: Verify Replication End-to-End

Confirm that streaming replication is working correctly between your primary
and standby. This is the final BUILD step.

---

## 1. Check pg_stat_replication on the primary

On NODE1:
```bash
sudo -iu postgres psql -c "
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;"
```

Expected:
- `client_addr` = NODE2's IP
- `state` = `streaming`
- `sync_state` = `async`
- `replay_lag_bytes` = small number (ideally 0)

> **Concept - pg_stat_replication is the primary's view**: This view shows one
> row per connected standby. It exists ONLY on the primary. An empty result means
> no standbys are connected - more severe than lag.

## 2. Check pg_stat_wal_receiver on the standby

On NODE2:
```bash
sudo -iu postgres psql -c "
SELECT status, sender_host, slot_name,
       received_lsn, latest_end_lsn
FROM pg_stat_wal_receiver;"
```

Expected:
- `status` = `streaming`
- `sender_host` = NODE1's IP
- `slot_name` = `standby_slot`

> **Concept - pg_stat_wal_receiver is the standby's view**: This is the mirror
> of pg_stat_replication. It exists ONLY on the standby. Together, these two views
> give you both sides of the replication connection.

## 3. Test live replication

On NODE1 (primary), insert a uniquely tagged row:

```bash
sudo -iu postgres psql -d labdb -c "
INSERT INTO employees (name, department) VALUES ('replication_test_$(date +%s)', 'verify');"
```

On NODE2 (standby), immediately query for it:

```bash
sudo -iu postgres psql -d labdb -c "
SELECT * FROM employees WHERE department = 'verify' ORDER BY id DESC LIMIT 1;"
```

Expected: the row appears within 1-2 seconds.

## 4. Check the replication slot

On NODE1:
```bash
sudo -iu postgres psql -c "
SELECT slot_name, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;"
```

Expected:
- `slot_name` = `standby_slot`
- `active` = `t`

> **Concept - active = t means the slot is in use**: An active slot has a
> connected consumer. An inactive slot (`active = f`) with a non-null
> `restart_lsn` means WAL is being retained for a disconnected standby. This is
> where disk fills if you forget about an abandoned slot.

## 5. Check WAL archiving

On NODE1:
```bash
sudo -iu postgres psql -c "
SELECT archived_count, last_archived_wal, last_archived_time, failed_count
FROM pg_stat_archiver;"
```

Expected: `archived_count` > 0, `failed_count` = 0.

```bash
sudo -iu postgres ls /var/lib/postgresql/16/archive/ | head -5
```

Expected: WAL segment files (names like `000000010000000000000001`).

## 6. Run verify.sh

```bash
./build/verify.sh
```

This script automates the checks above. All checks must PASS before proceeding
to Phase 2.

---

## What you built

```
NODE1 (primary)                    NODE2 (standby)
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
- How to install PG from PGDG on Debian
- How WAL flows from primary to standby
- What standby.signal and primary_conninfo do
- What replication slots are and why they matter
- What archive_mode gives you beyond streaming

Proceed to `use/01-check-replication-status.md` for Phase 2.
