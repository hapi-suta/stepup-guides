# MVCC and VACUUM

## Why This Module Matters

PostgreSQL never updates a row in place. It writes a new version and marks the old one
as dead. This design - Multi-Version Concurrency Control - is what lets readers never
block writers and writers never block readers. But it comes with a cost: someone has
to clean up the dead rows. That someone is VACUUM.

---

## MVCC Explained

### The Core Idea

In most storage systems, an UPDATE overwrites the existing data. PostgreSQL does
something different:

```
Before UPDATE:
+--------+----------+--------+
| ctid   | name     | salary |
+--------+----------+--------+
| (0,1)  | Alice    | 90000  |   <-- live tuple
+--------+----------+--------+

After UPDATE salary = 95000:
+--------+----------+--------+
| ctid   | name     | salary |
+--------+----------+--------+
| (0,1)  | Alice    | 90000  |   <-- dead tuple (old version, still on disk)
| (0,2)  | Alice    | 95000  |   <-- live tuple (new version)
+--------+----------+--------+
```

Both versions exist on disk simultaneously. The old version stays until VACUUM
removes it.

### Why Keep Old Versions?

Other transactions might still need them. If Transaction A started before Transaction B
updated Alice's salary, Transaction A should still see the old salary (90000). This is
the Repeatable Read / Snapshot Isolation guarantee.

Without MVCC, you'd need read locks - and readers would block writers, killing
concurrency. PostgreSQL's approach means:
- **Readers never block writers**
- **Writers never block readers**
- Writers only block other writers on the same row

---

## Transaction IDs (XIDs)

Every write transaction gets a unique 32-bit transaction ID (XID). PostgreSQL uses
XIDs to decide which row versions are visible to which transactions.

```
Transaction 100:  INSERT INTO orders VALUES (1, 'Widget');
Transaction 101:  UPDATE orders SET name = 'Gadget' WHERE id = 1;
Transaction 102:  SELECT * FROM orders;  -- which version does it see?
```

### The 32-bit Wraparound Problem

A 32-bit XID holds about 4.2 billion values. That sounds like a lot, but busy databases
can burn through millions of XIDs per day.

PostgreSQL treats XIDs as a circular space. At any point, about 2 billion XIDs are "in
the past" and about 2 billion are "in the future." When the counter wraps around, past
transactions could suddenly appear to be in the future - making their data invisible.

```
        XID circular number line (simplified)

    2 billion in the past   |   2 billion in the future
  <-------------------------+------------------------->
                         current XID

  If current XID wraps around far enough, old committed
  data looks like it's from the "future" and disappears.
```

This is called **XID wraparound** and it is a data-loss scenario if not prevented.
VACUUM's freezing process prevents it (covered below).

---

## Tuple Visibility

Every tuple (row version) carries hidden system columns:

| Column  | Meaning                                             |
|---------|-----------------------------------------------------|
| xmin    | XID of the transaction that inserted this tuple     |
| xmax    | XID of the transaction that deleted/updated this tuple (0 if still live) |
| ctid    | Physical location on disk (page, offset)            |

### How PostgreSQL Decides Visibility

When a transaction reads a row, it checks:

1. Was the inserting transaction (xmin) committed before my snapshot? If no, the row is invisible.
2. Is xmax zero? If yes, the row is live and visible.
3. Was the deleting transaction (xmax) committed before my snapshot? If yes, the row was deleted and is invisible. If no, the delete hasn't happened yet from my perspective - the row is still visible.

```
Transaction 100: INSERT (xmin=100, xmax=0)    -- visible to txns after 100 commits
Transaction 105: DELETE (xmin=100, xmax=105)   -- invisible to txns after 105 commits
Transaction 103: SELECT                        -- sees the row (103 < 105, so xmax=105 is "future")
Transaction 110: SELECT                        -- does not see the row (105 committed before 110)
```

### Seeing System Columns

```sql
SELECT ctid, xmin, xmax, * FROM orders;
```

This shows the physical location and transaction metadata for every tuple.

---

## Dead Tuples

A dead tuple is a row version that no running transaction needs anymore. It happens when:
- A row is UPDATEd (the old version becomes dead)
- A row is DELETEd (the tuple is marked dead)
- A transaction that INSERTed a row rolls back (the tuple becomes dead)

Dead tuples occupy disk space but serve no purpose. They:
- Waste storage
- Slow down sequential scans (the scanner reads dead tuples too)
- Bloat indexes (index entries still point to dead tuples)

---

## VACUUM

VACUUM is PostgreSQL's garbage collector. It has two jobs:

1. **Reclaim dead tuples** - mark the space as reusable for future inserts
2. **Freeze old XIDs** - prevent XID wraparound

### What Regular VACUUM Does

```
Before VACUUM:
Page 0: [live] [dead] [dead] [live] [dead]

After VACUUM:
Page 0: [live] [free] [free] [live] [free]
         ^               ^           ^
         still there     space reclaimed, available for new rows
```

Regular VACUUM does NOT return space to the operating system. The table file stays
the same size. The free space is reused internally by future INSERTs.

Regular VACUUM also:
- Updates the visibility map (tracks which pages have only visible tuples)
- Updates the free space map (tracks available space per page)
- Does NOT lock the table (reads and writes continue normally)

### VACUUM FULL

VACUUM FULL rewrites the entire table to a new file, compacting it and returning
space to the OS.

```
Before VACUUM FULL:
Table size: 10 GB (6 GB live data, 4 GB dead/free space)

After VACUUM FULL:
Table size: 6 GB (fully compacted)
```

The catch: VACUUM FULL takes an **ACCESS EXCLUSIVE lock** on the table. No reads,
no writes, nothing - for the entire duration. On a 10 GB table, that could be minutes
to hours.

Use VACUUM FULL only when:
- A table has massive bloat (50%+ dead space) after a bulk delete
- You can tolerate downtime on that table
- Regular VACUUM isn't enough because no new inserts will reuse the space

Alternative: `pg_repack` does the same compaction without the exclusive lock.

---

## Autovacuum

Running VACUUM manually on every table is not practical. Autovacuum is a background
process that does it automatically.

### When Autovacuum Triggers

Autovacuum launches a worker for a table when:

```
dead tuples > autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor * table_rows)
```

Defaults:
- `autovacuum_vacuum_threshold` = 50 (base number of dead tuples)
- `autovacuum_vacuum_scale_factor` = 0.2 (20% of table size)

For a table with 100,000 rows:
- Trigger = 50 + (0.2 * 100,000) = 20,050 dead tuples

For a table with 100 million rows:
- Trigger = 50 + (0.2 * 100,000,000) = 20,000,050 dead tuples

That 20 million dead tuple threshold for large tables is too high. This is the
number one autovacuum tuning issue.

### Tuning Autovacuum

**For large tables** - lower the scale factor:

```sql
ALTER TABLE big_table SET (autovacuum_vacuum_scale_factor = 0.01);
-- Now triggers at 1% dead tuples instead of 20%
```

**Key parameters:**

| Parameter                          | Default | What it controls                        |
|------------------------------------|---------|-----------------------------------------|
| autovacuum_vacuum_threshold        | 50      | Base dead tuple count before trigger     |
| autovacuum_vacuum_scale_factor     | 0.2     | Fraction of table rows added to threshold|
| autovacuum_naptime                 | 1min    | How often autovacuum checks for work     |
| autovacuum_max_workers             | 3       | Max parallel autovacuum workers          |
| autovacuum_vacuum_cost_delay       | 2ms     | Pause between I/O operations (throttle)  |
| autovacuum_vacuum_cost_limit       | -1      | I/O cost limit per round (-1 = use vacuum_cost_limit, default 200) |

**Common tuning for busy OLTP:**

```
autovacuum_max_workers = 5
autovacuum_naptime = 15s
autovacuum_vacuum_cost_delay = 2ms
autovacuum_vacuum_cost_limit = 400
```

### Autoanalyze

Autovacuum also runs ANALYZE to update table statistics (used by the query planner).
Trigger formula:

```
changed tuples > autovacuum_analyze_threshold + (autovacuum_analyze_scale_factor * table_rows)
```

Defaults: threshold = 50, scale_factor = 0.1 (10%).

---

## Table Bloat

Bloat is the accumulation of dead space inside a table or index.

### Causes

1. **High UPDATE rate** - every update creates a dead tuple
2. **Bulk DELETEs** - mass deletes create mass dead tuples
3. **Long-running transactions** - VACUUM cannot remove tuples that any open transaction might need
4. **Autovacuum falling behind** - dead tuples accumulate faster than autovacuum cleans them

### Long-Running Transactions - The Silent Killer

```
Transaction A starts at 10:00 AM (SELECT ... long report query)
Transaction B at 10:05: UPDATE orders SET status = 'shipped' WHERE ...
Transaction C at 10:10: UPDATE orders SET status = 'delivered' WHERE ...
...
Autovacuum runs at 10:15: cannot clean any dead tuples because Transaction A
    started before all of them and might still need the old versions
Transaction A finishes at 11:00 AM
```

One long-running transaction prevents VACUUM from cleaning up an hour's worth of
dead tuples across every table. Monitor `pg_stat_activity` for long transactions.

### Detecting Bloat

**Quick estimate using pg_stat_user_tables:**

```sql
SELECT relname,
       n_dead_tup,
       n_live_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 1) AS dead_pct,
       last_vacuum,
       last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```

**Precise measurement with pgstattuple:**

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT * FROM pgstattuple('orders');
-- dead_tuple_percent shows actual bloat
```

### Prevention

- Keep transactions short
- Tune autovacuum for large tables (lower scale_factor)
- Monitor dead tuple counts daily
- Kill idle-in-transaction sessions with `idle_in_transaction_session_timeout`

---

## XID Wraparound Protection

### Freezing

VACUUM's second job is freezing old XIDs. When a tuple's xmin is old enough,
VACUUM replaces it with a special "frozen" XID that means "this tuple is definitely
visible to everyone."

```
Before freeze: xmin = 1500 (a specific transaction)
After freeze:  xmin = FrozenTransactionId (universally visible)
```

Key parameters:
- `vacuum_freeze_min_age` (default 50 million) - don't freeze tuples younger than this
- `vacuum_freeze_table_age` (default 150 million) - do a full-table scan to freeze when the table's oldest XID is this old
- `autovacuum_freeze_max_age` (default 200 million) - force autovacuum regardless of other settings

### Anti-Wraparound Autovacuum

When a table's oldest unfrozen XID approaches `autovacuum_freeze_max_age`,
PostgreSQL forces an aggressive autovacuum. This vacuum:
- Cannot be cancelled
- Scans the entire table
- Ignores cost delay settings
- Takes priority over everything

If you see autovacuum running on a table that doesn't have many dead tuples, it's
probably an anti-wraparound vacuum doing freezing work.

### The Emergency Shutdown

If the database gets within 40 million XIDs of wraparound (about 2.1 billion consumed),
PostgreSQL refuses to start new write transactions and logs:

```
WARNING: database "mydb" must be vacuumed within X transactions
ERROR: database is not accepting commands to avoid wraparound data loss
```

At this point, you must start in single-user mode and run VACUUM FREEZE manually.
This is a true emergency - plan your monitoring to catch it long before this point.

---

## TOAST Tables

TOAST (The Oversized-Attribute Storage Technique) stores large column values
(over ~2 KB) in a separate side table.

### Relationship to VACUUM

Each main table with TOASTable columns has an associated TOAST table (e.g.,
`pg_toast.pg_toast_12345`). When you VACUUM the main table, PostgreSQL also
vacuums its TOAST table.

TOAST dead tuples are created when:
- A large column value is updated
- A row with large columns is deleted

TOAST tables can bloat independently. Check their size:

```sql
SELECT c.relname AS main_table,
       t.relname AS toast_table,
       pg_size_pretty(pg_relation_size(t.oid)) AS toast_size
FROM pg_class c
JOIN pg_class t ON t.oid = c.reltoastrelid
WHERE c.relkind = 'r'
ORDER BY pg_relation_size(t.oid) DESC;
```

---

## Putting It All Together

The lifecycle of a row in PostgreSQL:

```
1. INSERT  -->  New tuple created with xmin = current XID, xmax = 0
                |
2. UPDATE  -->  Old tuple gets xmax = current XID
                New tuple created with xmin = current XID, xmax = 0
                |
3. COMMIT  -->  Tuple is committed (visible to new snapshots)
                |
4. Other transactions finish reading old version
                |
5. VACUUM  -->  Dead tuple space marked as reusable
                Old XID frozen if old enough
                |
6. INSERT  -->  Reuses the free space from step 5
```

---

## Key Takeaways

1. PostgreSQL never overwrites rows - UPDATE creates a new version, DELETE marks the old one dead
2. XIDs are 32-bit and wrap around - VACUUM freezing prevents data loss
3. Tuple visibility uses xmin/xmax to determine which version each transaction sees
4. Regular VACUUM reclaims space within the table file; VACUUM FULL compacts but locks exclusively
5. Autovacuum default thresholds are too high for large tables - lower the scale_factor
6. Long-running transactions prevent VACUUM from cleaning dead tuples - monitor and kill them
7. Anti-wraparound autovacuum is PostgreSQL's emergency brake - don't let it get that far
8. TOAST tables bloat independently and are vacuumed alongside their main table
