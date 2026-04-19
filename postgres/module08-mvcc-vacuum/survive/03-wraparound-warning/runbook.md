# Scenario 03 - Wraparound Warning

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: XID age is approaching the freeze threshold.
The Pulse dashboard shows high wraparound risk percentage.
autovacuum_freeze_max_age has been changed.
You must run VACUUM FREEZE to advance relfrozenxid.
```

---

## Key Concepts for Revision

- **XID wraparound is catastrophic** - If `relfrozenxid` age exceeds ~2 billion, PostgreSQL will treat all previously inserted tuples as "in the future" and make them invisible. This is a complete data outage. PostgreSQL starts protecting against this at `autovacuum_freeze_max_age` (default 200 million) by forcing anti-wraparound autovacuum.

- **VACUUM FREEZE vs regular VACUUM** - Regular VACUUM only freezes tuples older than `vacuum_freeze_min_age` (50 million by default). VACUUM FREEZE ignores that limit and freezes all tuples, regardless of age. When you need to quickly advance `relfrozenxid`, VACUUM FREEZE is the tool.

- **datfrozenxid vs relfrozenxid** - `relfrozenxid` is per table. `datfrozenxid` is per database - it is the minimum `relfrozenxid` across all tables in the database. PostgreSQL takes the worst-case table to set the database-level freeze horizon.

- **Restoring misconfigured freeze parameters** - If `autovacuum_freeze_max_age` or `vacuum_freeze_min_age` were changed via `ALTER SYSTEM`, they are in `postgresql.auto.conf`. Use `ALTER SYSTEM RESET` to restore defaults. The change takes effect on reload.

---

## Diagnostic Steps

### Step 1 - Check the Pulse dashboard

Open `http://<NODE1_IP>:8080`. The MVCC/Vacuum panel shows wraparound risk percentage. It will be high because `autovacuum_freeze_max_age` was lowered.

### Step 2 - Check current XID age vs freeze max age

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT datname,
       age(datfrozenxid) AS xid_age,
       current_setting('autovacuum_freeze_max_age')::bigint AS freeze_max_age,
       round(100.0 * age(datfrozenxid) /
             current_setting('autovacuum_freeze_max_age')::bigint, 2) AS risk_pct
FROM pg_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
   datname    | xid_age | freeze_max_age | risk_pct
--------------+---------+----------------+----------
 stepup_store |    3421 |           5000 |    68.42
(1 row)
```

The risk is high because `freeze_max_age` was lowered from 200 million to 5,000.

### Step 3 - Find the table with the highest XID age

```sql
SELECT relname, age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relkind = 'r'
ORDER BY xid_age DESC
LIMIT 5;
```

### Step 4 - Check the current freeze parameter settings

```sql
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('autovacuum_freeze_max_age', 'vacuum_freeze_min_age');
```

Expected output (yours will differ):

```
            name             | setting |        source
-----------------------------+---------+----------------------
 autovacuum_freeze_max_age   | 5000    | configuration file
 vacuum_freeze_min_age       | 100     | configuration file
(2 rows)
```

```bash
exit
```

---

## Resolution

### Step 1 - Restore freeze parameters to safe defaults

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
ALTER SYSTEM RESET vacuum_freeze_min_age;
```

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 2 - Verify the parameters are restored

```sql
SHOW autovacuum_freeze_max_age;
```

Expected output (yours will differ):

```
 autovacuum_freeze_max_age
---------------------------
 200000000
(1 row)
```

### Step 3 - Run VACUUM FREEZE on at-risk tables

Run VACUUM FREEZE on the table with the highest XID age (from your diagnostic). Replace `freeze_needed` if a different table showed higher age.

```sql
VACUUM FREEZE VERBOSE freeze_needed;
```

Expected output (yours will differ):

```
INFO:  aggressively vacuuming "public.freeze_needed"
INFO:  "freeze_needed": found 0 removable, 1000 nonremovable row versions in 6 out of 6 pages
DETAIL:  Frozen in pages: 6 out of 6 frozen.
VACUUM
```

### Step 4 - Run VACUUM FREEZE on the whole database

To freeze all tables quickly:

```sql
VACUUM FREEZE VERBOSE;
```

This scans and freezes every table in the current database. On a large database this takes time.

### Step 5 - Verify relfrozenxid advanced

```sql
SELECT relname, age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relname = 'freeze_needed';
```

Expected output (yours will differ):

```
   relname    | xid_age
--------------+---------
 freeze_needed|       1
(1 row)
```

Age near 0 confirms the freeze succeeded.

### Step 6 - Check the Pulse dashboard

Refresh `http://<NODE1_IP>:8080`. The wraparound risk percentage should now show close to 0%.

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
- autovacuum_freeze_max_age restored to 200000000
- vacuum_freeze_min_age restored to 50000000
- freeze_needed relfrozenxid age below 10000
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What happens if relfrozenxid age exceeds 2 billion?** - PostgreSQL will refuse to start new transactions in the affected database to prevent data corruption. You will see "database is not accepting commands to avoid wraparound data loss" in the logs. Recovery requires running a standalone vacuum with `pg_resetwal` as an absolute last resort - data may be permanently lost. This is why wraparound prevention is critical.

2. **What is the difference between VACUUM FREEZE and anti-wraparound autovacuum?** - Both freeze tuples, but they are triggered differently. VACUUM FREEZE is a manual command you run explicitly. Anti-wraparound autovacuum is triggered automatically by PostgreSQL when any table's `relfrozenxid` age exceeds `autovacuum_freeze_max_age`. Anti-wraparound autovacuum cannot be permanently stopped (it ignores `autovacuum = off` once the threshold is breached).

3. **Why would someone lower autovacuum_freeze_max_age?** - Usually by accident or misunderstanding. Some DBAs lower it thinking "more frequent freezing is safer" without realizing it causes more I/O from more frequent anti-wraparound vacuums. The default of 200 million is carefully chosen to give 2 billion minus 200 million = 1.8 billion XIDs of headroom.

4. **How do you check when VACUUM FREEZE last ran on a table?** - `pg_stat_user_tables.last_vacuum` shows when any manual VACUUM ran. You can infer it from `age(relfrozenxid)` - if it is very low (near 0), a freeze ran recently. The PostgreSQL log (with `log_autovacuum_min_duration`) will show "aggressively vacuuming" messages for anti-wraparound runs.

5. **Can you run VACUUM FREEZE without downtime?** - Yes. Regular VACUUM FREEZE takes a ShareUpdateExclusiveLock, the same as regular VACUUM. Reads and writes continue normally. Only VACUUM FULL requires an exclusive lock.
