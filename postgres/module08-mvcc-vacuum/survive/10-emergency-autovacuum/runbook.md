# Scenario 10 - Emergency Autovacuum

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Emergency (anti-wraparound) autovacuum is active.
autovacuum_freeze_max_age is set to 100000 (default: 200 million).
Anti-wraparound autovacuum cannot be cancelled and ignores I/O throttling.
Performance degradation reported on affected tables.
```

---

## Key Concepts for Revision

- **Emergency (anti-wraparound) autovacuum** - When a table's `age(relfrozenxid)` exceeds `autovacuum_freeze_max_age`, PostgreSQL triggers an "aggressive" anti-wraparound autovacuum. Unlike regular autovacuum, this one cannot be cancelled via `pg_cancel_backend()` - it restarts immediately. It also ignores `autovacuum_vacuum_cost_delay`, running at full I/O speed. This is PostgreSQL's last line of defense before XID wraparound shutdown.

- **autovacuum_freeze_max_age** - The XID age threshold that triggers anti-wraparound autovacuum. Default is 200 million. Setting this very low (like 100,000) means the threshold is hit constantly, causing emergency autovacuum to run all the time. This parameter requires a restart to change because it affects shared memory structures.

- **vacuum_freeze_table_age** - When a table's `age(relfrozenxid)` exceeds this value, a regular autovacuum will do an aggressive scan (similar to VACUUM FREEZE) to advance `relfrozenxid`. Default is 150 million. It must be less than `autovacuum_freeze_max_age`.

- **pg_stat_progress_vacuum** - This system view shows real-time progress of any running VACUUM operation, including emergency autovacuum. It shows the phase, total heap blocks, blocks scanned, and blocks vacuumed. This is how you monitor whether the emergency vacuum is making progress or stuck.

- **You cannot kill emergency autovacuum** - If you `pg_terminate_backend()` an anti-wraparound autovacuum worker, PostgreSQL immediately restarts it. The only way to stop it is to let it finish, or fix the underlying XID age problem by running manual `VACUUM FREEZE` yourself (which is faster because you control it).

---

## Diagnostic Steps

### Step 1 - Connect to PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Check for active autovacuum workers

```sql
SELECT pid, query, state,
       now() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
```

Expected output (yours will differ):

```
  pid  |                        query                        | state  |    duration
-------+-----------------------------------------------------+--------+----------------
 14321 | autovacuum: VACUUM public.emergency_vac_demo (to... | active | 00:00:03
(1 row)
```

The `(to prevent wraparound)` suffix in the query indicates this is an anti-wraparound emergency autovacuum, not a regular one.

### Step 3 - Check vacuum progress

```sql
SELECT pid, relid::regclass AS table_name,
       phase,
       heap_blks_total,
       heap_blks_scanned,
       heap_blks_vacuumed
FROM pg_stat_progress_vacuum;
```

Expected output (yours will differ):

```
  pid  |     table_name      |      phase       | heap_blks_total | heap_blks_scanned | heap_blks_vacuumed
-------+---------------------+------------------+-----------------+-------------------+--------------------
 14321 | emergency_vac_demo  | scanning heap    |             200 |                85 |                 50
(1 row)
```

This shows the emergency vacuum is actively working through the table.

### Step 4 - Check the low freeze thresholds

```sql
SELECT name, setting, unit, boot_val
FROM pg_settings
WHERE name IN (
  'autovacuum_freeze_max_age',
  'vacuum_freeze_table_age',
  'vacuum_freeze_min_age'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name             | setting |  unit  |  boot_val
-----------------------------+---------+--------+-----------
 autovacuum_freeze_max_age   | 100000  |        | 200000000
 vacuum_freeze_min_age       | 1000    |        | 50000000
 vacuum_freeze_table_age     | 50000   |        | 150000000
(3 rows)
```

The `setting` values are far below the `boot_val` (default) values. This is why emergency autovacuum keeps triggering.

```bash
exit
```

---

## Resolution

### Step 1 - Reset freeze thresholds to defaults

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET autovacuum_freeze_max_age;
```

```sql
ALTER SYSTEM RESET vacuum_freeze_table_age;
```

```sql
ALTER SYSTEM RESET vacuum_freeze_min_age;
```

### Step 2 - Exit postgres user before restarting

```bash
exit
```

### Step 3 - Restart PostgreSQL

These parameters require a restart because they affect shared memory structures.

```bash
sudo -iu postgres
```

```bash
exit
```

```bash
sudo systemctl restart postgresql-16
```

### Step 4 - Verify PostgreSQL is running

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since Sun 2026-04-19 11:30:01 UTC; 3s ago
...
```

### Step 5 - Verify freeze thresholds are back to defaults

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT name, setting
FROM pg_settings
WHERE name IN (
  'autovacuum_freeze_max_age',
  'vacuum_freeze_table_age',
  'vacuum_freeze_min_age'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name             |  setting
-----------------------------+-----------
 autovacuum_freeze_max_age   | 200000000
 vacuum_freeze_min_age       | 50000000
 vacuum_freeze_table_age     | 150000000
(3 rows)
```

### Step 6 - Confirm no emergency autovacuum is running

```sql
SELECT pid, query
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%to prevent wraparound%';
```

Expected output:

```
 pid | query
-----+-------
(0 rows)
```

No emergency autovacuum should be running because the thresholds are now much higher than any table's XID age.

### Step 7 - Run VACUUM FREEZE on the affected table to clean up

```sql
VACUUM FREEZE VERBOSE emergency_vac_demo;
```

Expected output (yours will differ):

```
INFO:  aggressively vacuuming "public.emergency_vac_demo"
...
VACUUM
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
- autovacuum_freeze_max_age is at default (200000000)
- vacuum_freeze_table_age is at default (150000000)
- No emergency autovacuum running
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **How do you distinguish emergency autovacuum from regular autovacuum in pg_stat_activity?** - Emergency (anti-wraparound) autovacuum shows `(to prevent wraparound)` appended to the query text in `pg_stat_activity`. Regular autovacuum just shows `autovacuum: VACUUM schema.table`. You can also check `pg_stat_progress_vacuum` - the phase will show it is doing an aggressive scan rather than a lazy one.

2. **What happens if you try to pg_cancel_backend() on an emergency autovacuum?** - The worker process gets the cancel signal and stops, but the autovacuum launcher immediately starts a new worker on the same table. You effectively cannot stop it. Even `pg_terminate_backend()` just causes a restart. The only way to stop it is to let it finish or reduce the XID age below the threshold by running manual VACUUM FREEZE first.

3. **Why does autovacuum_freeze_max_age require a restart while most autovacuum parameters only need a reload?** - `autovacuum_freeze_max_age` is a `postmaster` context parameter because it affects how shared memory structures related to XID tracking are initialized. The anti-wraparound mechanism is baked into the server at startup time. Changing it at runtime could create inconsistencies in the freeze tracking logic.

4. **In production, what autovacuum_freeze_max_age would you recommend?** - The default of 200 million is good for most workloads. Some high-transaction-rate systems lower it to 100-150 million to ensure freezing happens more frequently in smaller batches rather than one massive freeze pass. Never set it below 1 million in production - that causes constant emergency vacuuming. On the other end, never increase it above 500 million - that leaves too little margin before the 2 billion hard limit.

5. **How does emergency autovacuum affect replication lag?** - Emergency autovacuum runs without I/O throttling (`cost_delay=0`), generating WAL at maximum speed. On systems with streaming replicas, this burst of WAL can cause replication lag to spike. The replicas must also replay the vacuum WAL records, which adds I/O load on the replica side. In extreme cases, the WAL generation can exceed `max_wal_size`, triggering extra checkpoints on both primary and replicas.
