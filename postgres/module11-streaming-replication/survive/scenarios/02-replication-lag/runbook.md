# Runbook 02 - Replication Lag

**Severity:** Warning - Standby is falling behind, risk of data loss on failover
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Measure the current lag

On the **primary** ([NODE1] or whichever node is primary), check replication status:

```sql
SELECT
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

Note the `replay_lag_bytes` value. Anything over 1 MB during normal operations is worth investigating.

Expected output (yours will differ):
```
 client_addr  |   state   |  sent_lsn   | write_lsn   | flush_lsn   | replay_lsn  | replay_lag_bytes
--------------+-----------+-------------+-------------+-------------+-------------+------------------
 10.0.1.52    | streaming | 0/A000F200  | 0/A000E800  | 0/A000E800  | 0/A000D000  |             8704
```

### Step 2: Check time-based lag

```sql
SELECT
  client_addr,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;
```

These interval columns show how far behind the standby is in wall-clock time.

### Step 3: Identify the cause

**Heavy write load** - Check if something is generating unusual write volume:

```sql
-- On the primary
SELECT pid, query, state, wait_event_type
FROM pg_stat_activity
WHERE state = 'active' AND backend_type = 'client backend'
ORDER BY xact_start;
```

Look for long-running bulk inserts, COPY operations, or pgbench processes.

**Slow replay on standby** - Check if the standby's disk I/O is saturated.

On [NODE2]:

```bash
iostat -x 1 3
```

`-x` shows extended stats. `1 3` takes a sample every 1 second, 3 times.

**Network bottleneck** - Compare sent_lsn vs write_lsn. If sent_lsn is far ahead of write_lsn, the network is the bottleneck.

### Step 4: Stop the write load

If pgbench or a bulk load is the cause:

On the primary:

```bash
sudo pkill pgbench
```

Or identify and cancel the specific backend:

```sql
SELECT pg_cancel_backend(pid) FROM pg_stat_activity
WHERE query LIKE '%chaos_load%' AND state = 'active';
```

### Step 5: Wait for catchup

Monitor lag until it returns to near zero:

```sql
SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

Re-run every few seconds. Lag should drop steadily.

### Step 6: Verify replication is healthy

```sql
SELECT state, slot_name FROM pg_stat_replication;
```

Confirm `state = 'streaming'` and the slot `standby_slot` is active.

Expected output (yours will differ):
```
   state   |  slot_name
-----------+--------------
 streaming | standby_slot
```

### Step 7: Verify data consistency

Compare row counts between primary and standby:

```sql
-- On primary
SELECT count(*) FROM employees;

-- On standby
SELECT count(*) FROM employees;
```

Counts should match once lag is zero.

---

## Key Concepts for Revision

- **pg_stat_replication** is the primary view for monitoring replication health. It lives on the primary and shows one row per connected standby.
- **LSN (Log Sequence Number)** is PostgreSQL's WAL position pointer. `pg_wal_lsn_diff()` converts two LSN values into a byte difference.
- **sent_lsn vs replay_lsn**: sent_lsn is what the primary shipped. replay_lsn is what the standby applied. The gap between them is your replication lag.
- **write_lag, flush_lag, replay_lag**: PG 10+ provides time-based lag columns. These are more intuitive than byte-based lag for capacity planning.
- **Replication slots** prevent the primary from recycling WAL segments the standby has not yet consumed. Without a slot, the primary could delete WAL the standby still needs, breaking replication.
- **Async vs sync replication**: In async mode (the default), the primary does not wait for the standby to confirm writes. This means lag is normal under heavy load but creates a data-loss window.

---

## Interview Discussion Points

1. **Acceptable lag thresholds**: What lag threshold triggers a page-level alert vs a warning? How do you define this in bytes vs time? Why is time-based lag often more useful for SLAs?

2. **Sync vs async tradeoffs**: When would you switch to synchronous replication? What is the write-latency cost? How does `synchronous_commit = remote_apply` differ from `remote_write`?

3. **Monitoring strategy**: How do you monitor replication lag in production? Discuss Prometheus + pg_stat_replication, check_postgres, or custom exporters. What alert thresholds do you set?

4. **Cascading standby impact**: If you have primary -> standby1 -> standby2, how does lag on standby1 affect standby2? Can standby2 ever be ahead of standby1?

5. **WAL generation rate**: How do you right-size `max_wal_size` and `wal_keep_size` when you know your peak write volume? What happens if WAL generation outpaces network throughput?

6. **Slot management risks**: What happens if the standby goes down for hours but the slot keeps accumulating WAL on the primary? How do you set `max_slot_wal_keep_size` to prevent disk exhaustion?

7. **Lag during maintenance**: Large operations like CREATE INDEX, VACUUM FULL, or bulk loads will always spike lag. How do you communicate this to the team and avoid false alerts?
