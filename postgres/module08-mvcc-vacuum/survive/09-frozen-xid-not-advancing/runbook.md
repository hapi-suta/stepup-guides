# Scenario 09 - Frozen XID Not Advancing

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Table xid_freeze_demo has autovacuum disabled.
relfrozenxid age is growing and frozen XIDs are not advancing.
Risk of XID wraparound if left unchecked.
```

---

## Key Concepts for Revision

- **Transaction ID (XID) wraparound** - PostgreSQL uses 32-bit transaction IDs. There are about 4.2 billion possible XIDs. Once the counter wraps around, old rows could appear to be "in the future" and become invisible. To prevent this, PostgreSQL must periodically "freeze" old XIDs - marking them as permanently visible so they no longer consume XID space.

- **relfrozenxid** - Each table tracks the oldest unfrozen XID in `pg_class.relfrozenxid`. `age(relfrozenxid)` tells you how many transactions have occurred since the table was last frozen. If this age reaches `autovacuum_freeze_max_age` (default 200 million), PostgreSQL triggers an aggressive anti-wraparound autovacuum. If it reaches 2 billion, PostgreSQL shuts down to prevent data loss.

- **VACUUM FREEZE** - A normal `VACUUM` only freezes tuples older than `vacuum_freeze_min_age` (default 50 million transactions). `VACUUM FREEZE` forces PostgreSQL to freeze ALL tuples regardless of age, resetting `relfrozenxid` to the current XID. This is the manual fix when a table's XID age is dangerously high.

- **Per-table autovacuum_enabled = false** - Disabling autovacuum on a specific table (via `ALTER TABLE ... SET (autovacuum_enabled = false)`) prevents both regular autovacuum AND the anti-wraparound autovacuum for that table. This is dangerous because the safety net against XID wraparound is removed. The global `autovacuum` GUC must also be on for per-table settings to matter.

- **Monitoring XID age** - The query `SELECT relname, age(relfrozenxid) FROM pg_class WHERE relkind = 'r' ORDER BY age(relfrozenxid) DESC` shows which tables are closest to needing a freeze. Production systems should alert when any table's age exceeds 100 million.

---

## Diagnostic Steps

### Step 1 - Connect to PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Find tables with high XID age

```sql
SELECT relname,
       age(relfrozenxid) AS xid_age,
       relfrozenxid
FROM pg_class
WHERE relkind = 'r'
  AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY age(relfrozenxid) DESC
LIMIT 10;
```

Expected output (yours will differ):

```
     relname      | xid_age | relfrozenxid
------------------+---------+--------------
 xid_freeze_demo  |   15432 |    750123456
 ...
```

The `xid_freeze_demo` table will have a notably higher age than other tables.

### Step 3 - Check if autovacuum is disabled on the table

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'xid_freeze_demo';
```

Expected output (yours will differ):

```
     relname      |        reloptions
------------------+---------------------------
 xid_freeze_demo  | {autovacuum_enabled=false}
(1 row)
```

The `autovacuum_enabled=false` in `reloptions` confirms autovacuum is disabled for this table.

### Step 4 - Check dead tuple count

```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'xid_freeze_demo';
```

Expected output (yours will differ):

```
     relname      | n_live_tup | n_dead_tup | last_vacuum | last_autovacuum
------------------+------------+------------+-------------+-----------------
 xid_freeze_demo  |       5000 |       5000 |             |
(1 row)
```

Dead tuples are accumulating because autovacuum is not running on this table.

```bash
exit
```

---

## Resolution

### Step 1 - Run VACUUM FREEZE on the table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

`VACUUM FREEZE` forces PostgreSQL to freeze all tuples and advance `relfrozenxid` to the current transaction ID.

```sql
VACUUM FREEZE VERBOSE xid_freeze_demo;
```

Expected output (yours will differ):

```
INFO:  aggressively vacuuming "public.xid_freeze_demo"
INFO:  finished vacuuming "public.xid_freeze_demo": index scans: 1
...
VACUUM
```

The `aggressively vacuuming` message confirms PostgreSQL is freezing all tuples.

### Step 2 - Re-enable autovacuum on the table

```sql
ALTER TABLE xid_freeze_demo SET (autovacuum_enabled = true);
```

Expected output:

```
ALTER TABLE
```

### Step 3 - Verify relfrozenxid age dropped

```sql
SELECT relname,
       age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relname = 'xid_freeze_demo';
```

Expected output (yours will differ):

```
     relname      | xid_age
------------------+---------
 xid_freeze_demo  |       1
(1 row)
```

The age should be very low (close to 0) because VACUUM FREEZE just advanced `relfrozenxid` to the current XID.

### Step 4 - Verify autovacuum is re-enabled

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'xid_freeze_demo';
```

Expected output (yours will differ):

```
     relname      |        reloptions
------------------+--------------------------
 xid_freeze_demo  | {autovacuum_enabled=true}
(1 row)
```

### Step 5 - Confirm dead tuples were cleaned

```sql
SELECT relname, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'xid_freeze_demo';
```

Expected output (yours will differ):

```
     relname      | n_dead_tup
------------------+------------
 xid_freeze_demo  |          0
(1 row)
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- xid_freeze_demo relfrozenxid age is below 1000
- autovacuum is re-enabled on the table
- Dead tuples cleaned
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What happens if age(relfrozenxid) reaches 2 billion?** - PostgreSQL shuts down and refuses to start. It prints a message telling you to run `VACUUM FREEZE` in single-user mode. This is a catastrophic failure mode because it causes a full outage. The shutoff at 2 billion exists to prevent silent data corruption from XID wraparound.

2. **What is the difference between VACUUM and VACUUM FREEZE?** - Regular `VACUUM` only freezes tuples older than `vacuum_freeze_min_age` (default 50 million XIDs). `VACUUM FREEZE` sets `vacuum_freeze_min_age` to 0 for that run, forcing every tuple to be frozen. Use `VACUUM FREEZE` when you need to immediately reduce a table's XID age, not as a routine operation.

3. **Why would someone disable autovacuum on a specific table?** - Common reasons include: large append-only tables where rows are never updated (no dead tuples to clean), bulk-load staging tables where vacuum during the load wastes I/O, or tables that are about to be dropped. The risk is that XID freeze stops happening too. If you disable autovacuum on a table, you take responsibility for running manual `VACUUM FREEZE` periodically.

4. **How do you monitor for XID wraparound risk in production?** - Query `SELECT datname, age(datfrozenxid) FROM pg_database` for database-level age, and `SELECT relname, age(relfrozenxid) FROM pg_class WHERE relkind = 'r' ORDER BY age DESC LIMIT 10` for table-level. Alert at 100 million, page at 150 million, emergency at 180 million. Many monitoring tools (pgwatch2, Datadog, pg_prometheus) include this check.

5. **Does VACUUM FREEZE lock the table?** - No. `VACUUM FREEZE` takes a `ShareUpdateExclusive` lock, which is the same as regular `VACUUM`. It does not block reads or writes. Only `VACUUM FULL` takes an `AccessExclusive` lock. However, `VACUUM FREEZE` on a large table can generate significant I/O because it must scan every page to freeze all tuples.
