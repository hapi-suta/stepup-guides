# Runbook 04 - Replication Slot Full

**Severity:** High - Disk exhaustion risk on primary
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Confirm the standby is down

SSH to [NODE2] and verify PostgreSQL is not running:

```bash
sudo systemctl status postgresql-16
```

Check if PostgreSQL is accepting connections. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

```bash
exit
```

You should see the service as inactive/dead and pg_isready failing.

### Step 2: Check replication slot status on the primary

SSH to [NODE1] and inspect the replication slot:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
  SELECT slot_name, active, restart_lsn,
         pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes
  FROM pg_replication_slots;
"
```

```bash
exit
```

Expected: `active` is `f` (false), and `retained_bytes` is large and growing.

> **Concept - Replication Slots**: A replication slot guarantees the primary retains WAL segments needed by the standby. When the standby is down, the slot keeps accumulating WAL, which can fill the disk.

### Step 3: Check WAL directory disk usage

On [NODE1], check how much disk space WAL is consuming:

```bash
sudo du -sh /var/lib/pgsql/16/data/pg_wal/
```

`-s` shows a single summary total. `-h` shows sizes in human-readable format (MB, GB).

```bash
df -h /var/lib/pgsql/16/data/
```

`df -h` shows disk free space in human-readable format for the filesystem containing the data directory.

If usage is critical (above 80%), you may need to drop the slot temporarily. Otherwise, proceed to restart the standby first.

### Step 4: Decide - restart standby or drop the slot

**Option A (preferred)** - Restart the standby so the slot catches up:

```bash
# On [NODE2]
sudo systemctl start postgresql-16
```

Wait 10-20 seconds, then check from [NODE1]. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT active, restart_lsn FROM pg_replication_slots;"
```

Expected: `active` is `t` (true).

Expected output (yours will differ):
```
 active |  restart_lsn
--------+--------------
 t      | 0/A0010000
```

```bash
exit
```

**Option B (emergency)** - If disk is nearly full, drop the slot.

On [NODE1], switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_drop_replication_slot('standby_slot');"
```

Then restart the standby and recreate the slot:

```bash
psql -c "SELECT pg_create_physical_replication_slot('standby_slot');"
```

```bash
exit
```

> **Concept - Slot vs No-Slot Tradeoff**: Without a slot, WAL segments can be recycled before the standby reads them, breaking replication. With a slot, you get guaranteed delivery but risk disk exhaustion. Monitoring slot lag is essential.

### Step 5: Verify replication is streaming

On [NODE1], confirm the standby reconnected:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
  SELECT client_addr, state,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected output (yours will differ):
```
 client_addr  |   state   | lag_bytes
--------------+-----------+-----------
 10.0.1.52    | streaming |         0
```

```bash
exit
```

Expected: `state` is `streaming` and `lag_bytes` is decreasing toward 0.

### Step 6: Verify WAL retention stopped growing

On [NODE1], check disk usage again:

```bash
sudo du -sh /var/lib/pgsql/16/data/pg_wal/
```

It should stabilize or decrease as the standby consumes retained WAL.

### Step 7: Verify data consistency

On both nodes:

```sql
SELECT count(*) FROM employees;
```

Counts should match between primary and standby.

---

## Key Concepts for Revision

- **pg_replication_slots** tracks all replication slots. Key columns: `slot_name`, `active`, `restart_lsn`, and `confirmed_flush_lsn` (for logical slots).
- **WAL retention** is the core mechanism. A physical replication slot tells the primary "do not recycle WAL segments at or after restart_lsn." When the consumer is down, WAL accumulates without limit.
- **max_slot_wal_keep_size** (PG 13+) provides a safety valve. Setting this limits how much WAL a slot can retain. When exceeded, the slot is invalidated rather than filling the disk.
- **pg_wal_lsn_diff()** calculates the byte difference between two WAL positions. Use it to measure how far behind a slot or standby is.
- **Monitoring** is critical. Alert on: inactive replication slots, slot retained bytes exceeding a threshold, and WAL directory disk usage.
- **Slot invalidation** happens when max_slot_wal_keep_size is exceeded. The standby must then be rebuilt from scratch using pg_basebackup.
- **wal_keep_size** (formerly wal_keep_segments) is a separate, older mechanism that retains WAL regardless of slots. Slots are preferred because they track exact consumer positions.

---

## Interview Discussion Points

1. **Slot monitoring strategy**: How would you monitor replication slots in production? What metrics do you alert on, and what thresholds do you set?

2. **max_slot_wal_keep_size**: Explain how this parameter protects against disk exhaustion. What happens to the standby when its slot is invalidated? How do you recover?

3. **Disk pressure decision**: If the primary is at 90% disk and the slot is retaining 50 GB of WAL, do you drop the slot or expand the disk? Walk through the tradeoffs of each approach.

4. **Slot types**: What is the difference between a physical replication slot and a logical replication slot? When would you use each? Can both cause WAL retention issues?

5. **Standby rebuild**: After dropping a slot and the standby falls too far behind, how do you rebuild it? Compare pg_basebackup, rsync from a backup, and restoring from a WAL archive.

6. **Multiple standbys**: If you have three standbys each with a replication slot, and one standby goes down for maintenance, how does that affect the primary? How do you handle planned maintenance windows?

7. **WAL archiving as a safety net**: How does continuous WAL archiving (archive_command) complement replication slots? Can a standby recover from an archive if the slot WAL is recycled?
