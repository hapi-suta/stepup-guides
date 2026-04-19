# Scenario 05 - VACUUM FULL Locks Table

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: VACUUM FULL is running on vfull_lockout.
All queries against this table are blocked (lock wait).
Application is reporting query timeouts.
You must decide: wait for it to finish, or cancel it.
```

---

## Key Concepts for Revision

- **VACUUM FULL holds AccessExclusiveLock** - VACUUM FULL is the most aggressive lock a DBA can place on a table short of `DROP TABLE`. It blocks all SELECT, INSERT, UPDATE, DELETE, and even simple `LOCK TABLE` commands. No query can proceed until VACUUM FULL finishes.

- **The decision: wait or cancel** - If VACUUM FULL is 90% done, cancelling means restarting from scratch later - with the same locking impact. If it just started, cancelling and scheduling it for a maintenance window is the right call. Check `pg_stat_progress_vacuum` to see how far along it is.

- **Cancelling VACUUM FULL is safe** - VACUUM FULL is a read-modify-write operation, but cancelling it mid-run is safe. PostgreSQL will roll back any partial changes. The table returns to its pre-VACUUM state. No data is lost.

- **pg_stat_progress_vacuum** - Added in PostgreSQL 9.6, this view shows the progress of an in-progress VACUUM, including the current phase, how many heap pages have been scanned, and how many have been vacuumed. It is the right tool for estimating remaining time.

- **Preventing future VACUUM FULL surprises** - VACUUM FULL on large tables should be scheduled only during maintenance windows. For production tables, `pg_repack` achieves the same result without an exclusive lock.

---

## Diagnostic Steps

### Step 1 - Find the VACUUM FULL process

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT pid, query, state, now() - query_start AS running_for
FROM pg_stat_activity
WHERE query LIKE '%VACUUM FULL%'
  AND state = 'active';
```

Expected output (yours will differ):

```
  pid  |          query           | state  |  running_for
-------+--------------------------+--------+--------------
 12345 | VACUUM FULL vfull_lockout| active | 00:00:23
(1 row)
```

Note the PID and how long it has been running.

### Step 2 - Check VACUUM FULL progress

```sql
SELECT phase,
       heap_blks_scanned,
       heap_blks_total,
       round(100.0 * heap_blks_scanned / NULLIF(heap_blks_total, 0), 1) AS pct_done
FROM pg_stat_progress_vacuum
WHERE relid = 'vfull_lockout'::regclass;
```

Expected output (yours will differ):

```
         phase          | heap_blks_scanned | heap_blks_total | pct_done
------------------------+-------------------+-----------------+----------
 vacuuming heap         |               142 |             277 |     51.3
(1 row)
```

51% complete. In this scenario, you will cancel it because the application is being impacted.

### Step 3 - Check what is blocked behind VACUUM FULL

```sql
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       now() - blocked.query_start AS waiting_for
FROM pg_stat_activity AS blocked
WHERE blocked.wait_event_type = 'Lock'
  AND blocked.wait_event = 'relation';
```

This shows all queries waiting for VACUUM FULL to release its lock.

```bash
exit
```

---

## Resolution - Option A: Cancel VACUUM FULL

Use this option when VACUUM FULL has not been running long and the application impact is unacceptable.

### Step 1 - Cancel the VACUUM FULL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Replace `12345` with the actual PID:

```sql
SELECT pg_cancel_backend(12345);
```

Expected output (yours will differ):

```
 pg_cancel_backend
-------------------
 t
(1 row)
```

### Step 2 - Verify VACUUM FULL stopped

```sql
SELECT pid, query, state
FROM pg_stat_activity
WHERE query LIKE '%VACUUM FULL%';
```

Expected output (yours will differ):

```
(0 rows)
```

### Step 3 - Confirm the table is accessible

```sql
SELECT count(*) FROM vfull_lockout;
```

Expected output (yours will differ):

```
 count
-------
 25000
(1 row)
```

The table is accessible immediately after VACUUM FULL is cancelled.

---

## Resolution - Option B: Wait for Completion

Use this option when VACUUM FULL is near completion (over 80%) and the business impact of waiting is acceptable.

Monitor progress every 30 seconds:

```sql
SELECT phase, heap_blks_scanned, heap_blks_total,
       round(100.0 * heap_blks_scanned / NULLIF(heap_blks_total, 0), 1) AS pct_done
FROM pg_stat_progress_vacuum
WHERE relid = 'vfull_lockout'::regclass;
```

Once the row disappears from `pg_stat_progress_vacuum`, VACUUM FULL is complete.

```bash
exit
```

---

## Preventing Recurrence

To avoid this in the future, use VACUUM FULL only in scheduled maintenance windows. For online bloat removal, use `pg_repack`:

```bash
/usr/pgsql-16/bin/pg_repack -d stepup_store -t vfull_lockout
```

(pg_repack must be installed separately - it is not bundled with PostgreSQL.)

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No VACUUM FULL running on vfull_lockout
- vfull_lockout is accessible without lock wait
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What lock does VACUUM FULL take and what does it block?** - AccessExclusiveLock. This is the maximum lock level - it conflicts with every other lock mode. SELECT, INSERT, UPDATE, DELETE, TRUNCATE, and ALTER TABLE all block behind it. Nothing can read or write the table until VACUUM FULL completes.

2. **How do you estimate how long a running VACUUM FULL will take to finish?** - Use `pg_stat_progress_vacuum`. Divide `heap_blks_scanned / elapsed_seconds` to get the scan rate. Then calculate `(heap_blks_total - heap_blks_scanned) / scan_rate` for the remaining time. This is an estimate - the write phase (copying live tuples to the new file) can vary.

3. **Is cancelling VACUUM FULL safe? Does it leave the table in a corrupt state?** - Yes, it is safe. VACUUM FULL uses a transaction internally. If it is cancelled, the transaction rolls back. The original table remains intact. However, you lose all progress made so far - it starts from scratch next time.

4. **What is pg_repack and how does it differ from VACUUM FULL?** - `pg_repack` is an extension that rebuilds a bloated table online, without an extended exclusive lock. It creates a new copy of the table in the background, streams changes using a trigger, then does a brief lock swap at the end (milliseconds). For production tables that cannot tolerate downtime, pg_repack is the standard tool.

5. **What should you check before running VACUUM FULL on a production table?** - (1) Current table size and expected new size (will it fit on the disk?). (2) Time estimate (how long will the lock last?). (3) Is there a maintenance window available? (4) Is there a replica? VACUUM FULL also generates WAL, which must be shipped to replicas. (5) Would pg_repack be a better option?
