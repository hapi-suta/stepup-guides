# Scenario 05 - Slow Query Flood

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Log files are growing at 500MB/hour.
log_min_duration_statement appears to be set to 0.
Disk alerts are firing. On-call cannot find real errors
because the log is buried in noise.
```

---

## Key Concepts for Revision

- **log_min_duration_statement = 0** - The value `0` means "log every statement regardless of duration." This is intentionally useful for brief debugging windows but catastrophic if left on permanently. The value `-1` means "log no statements based on duration." Any positive value (in milliseconds) logs only queries exceeding that threshold.

- **sighup context parameters** - Both `log_min_duration_statement` and `log_statement` have `sighup` context. This means changes take effect immediately on `SELECT pg_reload_conf()` or `sudo systemctl reload postgresql-16`. No restart required.

- **Log noise vs signal** - When every `SELECT 1` health check and every simple lookup is logged, the signal (the actual slow queries and errors) is buried. DBAs cannot find real problems. Slow query logs only have value when they capture the outliers, not the baseline.

- **The correct fix** - Setting `log_min_duration_statement = -1` (disabling slow query logging entirely) is not the right fix - you lose visibility. Set it to a reasonable threshold: 1000ms for most production systems, 500ms for systems where response time SLAs are tight.

---

## Diagnostic Steps

### Step 1 - Confirm the log is flooding

Check the log file size and growth rate.

```bash
ls -lh /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 234M Apr 19 10:30 postgresql-2026-04-19.log
```

Check log growth over 5 seconds. First, capture the current file size in bytes.

(`stat -c%s` = print just the file size in bytes. This is a Linux-specific flag.)

```bash
SIZE1=$(stat -c%s /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log)
```

Wait 5 seconds for the log to grow.

```bash
sleep 5
```

Capture the file size again.

```bash
SIZE2=$(stat -c%s /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log)
```

Print the difference.

```bash
echo "Growth in 5 seconds: $(( SIZE2 - SIZE1 )) bytes"
```

Expected output (yours will differ):

```
Growth in 5 seconds: 48200 bytes
```

### Step 2 - Sample the log to see what is flooding it

```bash
sudo -iu postgres
```

```bash
tail -20 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-19 10:30:01.001 UTC [3100]: [1-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 0.123 ms  statement: SELECT 1;
2026-04-19 10:30:01.002 UTC [3101]: [1-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 0.118 ms  statement: SELECT 1;
...
```

Sub-millisecond queries in the slow query log - `log_min_duration_statement = 0`.

### Step 3 - Confirm the setting

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output when broken:

```
 log_min_duration_statement
----------------------------
 0
(1 row)
```

```bash
exit
```

---

## Resolution

### Step 1 - Set log_min_duration_statement to a reasonable threshold

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET log_min_duration_statement = 1000;"
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Reload the configuration (no restart needed)

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify the setting took effect

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output:

```
 log_min_duration_statement
----------------------------
 1s
(1 row)
```

### Step 4 - Confirm log flooding has stopped

Wait 10 seconds and check growth rate again.

```bash
exit
```

Capture the current file size in bytes.

```bash
SIZE1=$(stat -c%s /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log)
```

Wait 10 seconds.

```bash
sleep 10
```

Capture the file size again.

```bash
SIZE2=$(stat -c%s /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log)
```

Print the difference.

```bash
echo "Growth in 10 seconds: $(( SIZE2 - SIZE1 )) bytes"
```

Expected output (yours will differ):

```
Growth in 10 seconds: 0 bytes
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- log_min_duration_statement is not 0
- log_min_duration_statement is not -1 (logging still enabled)
- postgresql.auto.conf updated
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Why is log_min_duration_statement = -1 also a wrong answer?** - Setting it to -1 disables slow query logging entirely. You lose the ability to detect slow queries, which are the most common indicator of a developing performance problem. The goal is to restore appropriate logging, not eliminate it. The right value depends on your SLA: if users expect 200ms responses, log anything over 500ms.

2. **Can you change log_min_duration_statement per session?** - Yes. `SET log_min_duration_statement = 100;` within a session overrides the server setting for that session only. This is useful for debugging a specific application session without flooding the server-wide log. The session-level setting is automatically reset when the session ends.

3. **What is the relationship between log_min_duration_statement and log_statement?** - They work independently. `log_statement = 'all'` logs every statement immediately when received (before execution), with no duration. `log_min_duration_statement` logs statements after execution, only if they exceed the threshold, with their actual duration. Using `log_statement = 'ddl'` plus `log_min_duration_statement = 1000` is a common production pattern: log all schema changes always, and log slow queries.

4. **If you need to debug a specific slow query during production hours, what is a safer alternative to setting log_min_duration_statement = 0 server-wide?** - Use `auto_explain`: `LOAD 'auto_explain'; SET auto_explain.log_min_duration = 100;` within a single session. This logs EXPLAIN plans for slow queries in that session only, without affecting any other session. Alternatively, use `pg_stat_statements` to monitor aggregate statistics without logging individual executions.

5. **How would you automate detection of log flooding in the future?** - Add a check to your monitoring script that measures the log file size growth rate (compare size now vs 5 minutes ago). If growth exceeds a threshold (e.g., 10MB in 5 minutes), alert. Also monitor `pg_settings` directly: a nightly job that checks `SELECT setting FROM pg_settings WHERE name = 'log_min_duration_statement' AND setting::int < 100` and alerts if true.
