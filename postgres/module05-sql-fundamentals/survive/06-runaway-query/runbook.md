# Scenario 06 - Runaway Query

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Server CPU at 100%. Database response time spiking.
A nightly report job appears stuck and is consuming all available CPU.
Other queries are being starved.
Application name: runaway_report_job
```

---

## Key Concepts for Revision

- **pg_stat_activity** - This system view shows one row per server process. The columns `pid`, `query`, `state`, `query_start`, and `wait_event` tell you what every connection is doing right now. A query with `state = 'active'` and `query_start` far in the past is likely runaway.

- **pg_cancel_backend vs pg_terminate_backend** - `pg_cancel_backend(pid)` sends a cancel signal. The query is aborted but the session stays connected - the client can issue a new query. `pg_terminate_backend(pid)` kills the entire connection. Always try cancel first. Use terminate only if cancel does not work (e.g., the query is stuck in a system call).

- **Cartesian joins** - A CROSS JOIN (or a join with no ON clause) produces every combination of rows from both sides. Two tables with 50,000 rows each produce 2.5 billion rows. These are almost always bugs (a missing WHERE clause or join condition). They consume unbounded CPU and memory.

- **statement_timeout** - This GUC sets the maximum time any single statement can run before PostgreSQL automatically cancels it. Set at the database level (`ALTER DATABASE ... SET statement_timeout = '60s'`) or per role. A value of 0 means no limit - dangerous in production.

- **application_name** - Applications should set `application_name` when connecting so that DBAs can identify which application owns each connection in `pg_stat_activity`. This makes triage much faster during incidents.

---

## Diagnostic Steps

### Step 1 - Connect to the server

Log in to the server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Find the runaway query

List all active queries sorted by how long they have been running:

```sql
SELECT pid, now() - query_start AS duration, state, application_name, LEFT(query, 80) AS query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND pid != pg_backend_pid()
ORDER BY query_start;
```

Expected output (yours will differ):

```
  pid  |    duration     | state  |   application_name   |                  query_preview
-------+-----------------+--------+----------------------+--------------------------------------------------
 12345 | 00:03:42.123456 | active | runaway_report_job   | SELECT COUNT(*) FROM generate_series(1, 50000) a
(1 row)
```

The `runaway_report_job` has been running for several minutes and is consuming all CPU.

### Step 3 - Examine the full query

Get the full query text for the runaway PID. Replace `12345` with the actual PID from Step 2:

```sql
SELECT query FROM pg_stat_activity WHERE pid = 12345;
```

Expected output (yours will differ):

```
 SELECT COUNT(*) FROM generate_series(1, 50000) a CROSS JOIN generate_series(1, 50000) b WHERE a > b;
```

This is a cartesian join producing ~1.25 billion rows. It will never finish in a reasonable time.

### Step 4 - Check resource consumption

See if the query is waiting on anything or purely CPU-bound:

```sql
SELECT pid, wait_event_type, wait_event
FROM pg_stat_activity
WHERE pid = 12345;
```

Expected output (yours will differ):

```
  pid  | wait_event_type | wait_event
-------+-----------------+------------
 12345 |                 |
(1 row)
```

Empty `wait_event_type` means the process is actively running on CPU - not waiting for I/O or locks. This confirms it is CPU-bound.

---

## Resolution

### Step 1 - Cancel the runaway query

Try `pg_cancel_backend` first. Replace `12345` with the actual PID:

```sql
SELECT pg_cancel_backend(12345);
```

Expected output:

```
 pg_cancel_backend
-------------------
 t
(1 row)
```

`t` (true) means the cancel signal was sent.

### Step 2 - Verify the query was cancelled

Wait 2 seconds, then check:

```sql
SELECT pid, state, application_name
FROM pg_stat_activity
WHERE application_name = 'runaway_report_job';
```

If the query is gone or shows `state = 'idle'`, the cancel worked. If it still shows `state = 'active'`, use the stronger terminate:

```sql
SELECT pg_terminate_backend(12345);
```

This kills the entire connection. The client will need to reconnect.

### Step 3 - Set statement_timeout to prevent future runaways

Set a database-level timeout so no query can run longer than 5 minutes:

```sql
ALTER DATABASE stepup_store SET statement_timeout = '300s';
```

Expected output:

```
ALTER DATABASE
```

The `300s` means 300 seconds (5 minutes). Any query running longer will be automatically cancelled. This protects the server from future runaway queries.

Verify it was set:

```sql
SELECT datname, setconfig
FROM pg_db_role_setting s
JOIN pg_database d ON d.oid = s.setdatabase
WHERE d.datname = 'stepup_store';
```

Expected output (yours will differ):

```
   datname    |         setconfig
--------------+---------------------------
 stepup_store | {statement_timeout=300s}
(1 row)
```

### Step 4 - Verify server health is restored

Check that no runaway queries remain:

```sql
SELECT pid, now() - query_start AS duration, LEFT(query, 60) AS query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND pid != pg_backend_pid();
```

Expected output:

```
 pid | duration | query_preview
-----+----------+---------------
(0 rows)
```

No more active queries consuming resources.

Exit psql:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No runaway queries active (runaway_report_job is gone)
- No queries running longer than 5 minutes
- statement_timeout is set to a non-zero value

---

## Interview Discussion Points

1. **When would you use pg_cancel_backend vs pg_terminate_backend?** - Always try `pg_cancel_backend` first. It sends a query-cancel signal that lets the connection gracefully abort the statement. The client session stays alive and can issue new queries. Use `pg_terminate_backend` only if cancel does not work within a few seconds - it kills the entire backend process, closing the connection and forcing the client to reconnect. Some operations (like certain C-language functions or system calls) do not check for cancel signals, so terminate is the fallback.

2. **What is the difference between statement_timeout and lock_timeout?** - `statement_timeout` limits total execution time of any statement. `lock_timeout` limits how long a statement will wait to acquire a lock before giving up. A query can fail from lock_timeout even though it has not yet started executing. Both are important safety nets: statement_timeout prevents runaway queries, lock_timeout prevents queries from blocking behind long-held locks.

3. **How would you set different timeouts for different workloads?** - Use role-level settings: `ALTER ROLE reporting_user SET statement_timeout = '600s'` for long reports, `ALTER ROLE web_app SET statement_timeout = '5s'` for web requests. This way, each workload gets an appropriate limit without affecting others. Application-level settings via `SET statement_timeout = ...` at the start of each transaction are also common.

4. **How do you prevent cartesian joins from reaching production?** - Code review is the first defense. Linters like `sqlfluff` can flag CROSS JOINs. In PostgreSQL, you can set `statement_timeout` and `work_mem` limits per role so that even if a bad query slips through, it is killed before it causes damage. Some teams also use `pg_stat_statements` to alert on queries with unusually high `rows` counts.

5. **What system-level signs indicate a runaway query?** - CPU usage pegged at 100% for a single core (PostgreSQL is single-process-per-connection). `top` or `htop` will show a postgres process consuming 100% CPU. The `pg_stat_activity` duration column confirms which query is responsible. On the OS side, load average climbs, and other queries experience increased latency.
