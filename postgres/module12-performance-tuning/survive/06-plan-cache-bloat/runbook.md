# Scenario 06 - Plan Cache Bloat

**Severity:** MEDIUM
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: The events query is slow for 'pending' status
(only 50 rows) but fast for 'processed' (4950 rows).
The planner is using a generic plan that does not
consider the actual parameter value.
A developer set plan_cache_mode to fix a 'plan
instability' issue but made things worse.
```

---

## Key Concepts for Revision

- **Generic vs custom plans** - When PostgreSQL executes a prepared statement, it first creates custom plans (one per execution, using actual parameter values). After 5 executions, it starts comparing: if the generic plan (parameter-agnostic) is not much worse than the average custom plan, PostgreSQL switches to the generic plan to save planning time. `force_generic_plan` bypasses this comparison and always uses the generic plan.

- **Why generic plans hurt skewed data** - With skewed data (99% 'processed', 1% 'pending'), the optimal plan differs by parameter value. For `status = 'pending'` (50 rows), an index scan is best. For `status = 'processed'` (4950 rows), a seq scan is best. A generic plan cannot optimize for either case - it picks one plan for all parameter values.

- **plan_cache_mode controls the behavior** - Three values: `auto` (default - PostgreSQL decides), `force_custom_plan` (always re-plan with actual values), `force_generic_plan` (always use the generic plan). `auto` is correct for almost all workloads.

- **PL/pgSQL functions cache plans internally** - PL/pgSQL caches query plans within the function body. These cached plans behave similarly to prepared statements. `DISCARD ALL` clears prepared statements in the current session but does not clear PL/pgSQL plan caches across all sessions. Recreating the function or using `DISCARD ALL` per-session are the remedies.

- **DISCARD ALL clears session state** - `DISCARD ALL` resets all session-level state: prepared statements, temporary tables, advisory locks, plan caches, and session variables. It is the nuclear option for clearing stale plans in a session.

---

## Diagnostic Steps

### Step 1 - Check current plan_cache_mode

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SHOW plan_cache_mode;
```

Expected output:

```
 plan_cache_mode
-----------------
 force_generic_plan
(1 row)
```

This is the problem. The planner is forced to use generic plans for all prepared statements.

### Step 2 - Demonstrate the impact with EXPLAIN

Compare plans for the two status values:

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos6_events WHERE status = 'pending';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos6_events  (cost=0.00..100.00 rows=2500 ...)
   Filter: ((status)::text = 'pending'::text)
   Rows Removed by Filter: 4950
   Actual Rows: 50
...
```

The planner estimated 2500 rows (the generic estimate, half the table) but only found 50. A seq scan was used when an index scan would be much faster.

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos6_events WHERE status = 'processed';
```

For 'processed' (4950 rows), the seq scan is actually reasonable. The generic plan works here by coincidence.

### Step 3 - Check where the setting was persisted

```sql
\q
```

```bash
grep plan_cache_mode /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
plan_cache_mode = 'force_generic_plan'
```

The setting was persisted via `ALTER SYSTEM`.

---

## Resolution

### Step 1 - Reset plan_cache_mode to auto

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET plan_cache_mode;
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Reload configuration

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify the setting is back to auto

```sql
SHOW plan_cache_mode;
```

Expected output:

```
 plan_cache_mode
-----------------
 auto
(1 row)
```

### Step 4 - Clear stale plans in this session

```sql
DISCARD ALL;
```

Expected output:

```
DISCARD ALL
```

This clears all prepared statements and cached plans in the current session. Other active sessions will need to run `DISCARD ALL` individually, or disconnect and reconnect.

### Step 5 - Verify the planner now uses custom plans

Reconnect (DISCARD ALL closes the transaction state):

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos6_events WHERE status = 'pending';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Index Scan using idx_chaos6_status on chaos6_events  (cost=...)
   Index Cond: ((status)::text = 'pending'::text)
   Actual Rows: 50
   Planning Time: 0.150 ms
   Execution Time: 0.050 ms
...
```

The planner now uses an index scan for the selective 'pending' value.

### Step 6 - Confirm postgresql.auto.conf is clean

```sql
\q
```

```bash
grep plan_cache_mode /opt/pgsql/data/postgresql.auto.conf
```

There should be no output (the line was removed).

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- plan_cache_mode is auto
- EXPLAIN for selective query shows index scan
- postgresql.auto.conf has no plan_cache_mode override

---

## Interview Discussion Points

1. **When would you use force_custom_plan instead of auto?** - Rarely. `force_custom_plan` re-plans every execution, which adds CPU overhead. It might be useful if you have extremely skewed data distributions and the auto heuristic is making poor decisions about when to switch to generic plans. However, this is a per-session setting, so it is better applied with `SET` in specific sessions rather than globally.

2. **How does PostgreSQL decide when to switch from custom to generic plans?** - After the first 5 executions of a prepared statement, PostgreSQL compares the cost of the generic plan against the average cost of the 5 custom plans. If the generic plan cost is not more than 10% higher, it switches to the generic plan. This comparison happens once; after switching, it stays on generic. Recreating the prepared statement resets the counter.

3. **How do you clear PL/pgSQL plan caches without restarting?** - In PG 16, each backend caches PL/pgSQL plans independently. `DISCARD ALL` clears the cache for the current session. For all sessions, the options are: (1) `SELECT pg_terminate_backend(pid)` to force session reconnections, (2) Recreate the function with `CREATE OR REPLACE FUNCTION`, which invalidates cached plans, (3) Restart PostgreSQL (last resort).

4. **What is the performance impact of always using custom plans?** - Each execution requires a full planning cycle: parsing, rewriting, and optimization. For simple queries, planning overhead is negligible (sub-millisecond). For complex queries with many joins, planning can take 5-50ms per execution. On a system running thousands of queries per second, this adds up. Generic plans eliminate this overhead by planning once.

5. **How does connection pooling interact with plan caches?** - Connection poolers (PgBouncer, pgpool) in transaction mode reset sessions between clients. Prepared statements are lost when a connection is returned to the pool. This means plan caches are effectively cleared frequently, reducing the impact of stale plans but also eliminating the benefit of cached plans. In session mode pooling, plans persist for the lifetime of the client connection.
