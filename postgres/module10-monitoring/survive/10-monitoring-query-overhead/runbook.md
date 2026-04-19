# Scenario 10 - Monitoring Query Overhead

**Severity:** MEDIUM
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Monitoring configuration is causing overhead.
log_statement='all' logs every single query.
log_min_duration_statement=0 logs every query's duration.
Parser, planner, and executor stats logging is enabled.
Log files are growing rapidly and disk I/O is elevated.
```

---

## Key Concepts for Revision

- **log_statement = 'all'** - Logs every SQL statement sent to the server. This is extremely verbose on a busy system. A server handling 10,000 queries/second generates millions of log lines per hour. The overhead comes from: formatting each statement into a log line, writing to the log file, and the I/O for log writes competing with data I/O. Use `log_statement = 'ddl'` in production to capture schema changes only.

- **log_min_duration_statement = 0** - Logs the duration of every statement that takes 0 or more milliseconds (meaning all of them). This is redundant with `log_statement = 'all'` and doubles the log volume. A better production value is `1000` (1 second) to only log slow queries, or `500` for tighter monitoring.

- **log_parser_stats, log_planner_stats, log_executor_stats** - These log internal timing statistics for each query phase (parsing, planning, execution). They use `getrusage()` system calls to measure CPU and memory per phase. On a high-throughput system, the overhead of these system calls is measurable (1-3% CPU). These are debugging tools, not production settings. They should normally be `off`.

- **log_duration** - Logs the duration of every completed statement. When `log_min_duration_statement` is already set to 0, this is completely redundant - you get two log lines per query instead of one.

- **The monitoring paradox** - Too little monitoring leaves you blind. Too much monitoring degrades the very performance you are trying to observe. The goal is to find the balance: enough visibility to detect problems, without the monitoring itself becoming a problem.

---

## Diagnostic Steps

### Step 1 - Check log file growth

```bash
sudo -iu postgres
```

```bash
ls -lh /opt/pgsql/log/
```

Expected output (yours will differ):

```
total 24M
-rw------- 1 postgres postgres 24M Apr 19 11:20 postgresql-2026-04-19.log
```

The log file is abnormally large for the amount of activity on the server.

### Step 2 - Look at the log content to see the verbosity

```bash
tail -30 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-19 11:20:01 UTC LOG:  statement: SELECT 1;
2026-04-19 11:20:01 UTC LOG:  duration: 0.042 ms
2026-04-19 11:20:01 UTC LOG:  PARSER STATISTICS
2026-04-19 11:20:01 UTC DETAIL:  ! system usage stats:  0.000012 s user, ...
2026-04-19 11:20:01 UTC LOG:  PLANNER STATISTICS
2026-04-19 11:20:01 UTC DETAIL:  ! system usage stats:  0.000008 s user, ...
2026-04-19 11:20:01 UTC LOG:  EXECUTOR STATISTICS
2026-04-19 11:20:01 UTC DETAIL:  ! system usage stats:  0.000015 s user, ...
```

A single `SELECT 1` generates 7+ log lines. This is excessive.

### Step 3 - Connect and check the settings

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT name, setting
FROM pg_settings
WHERE name IN (
  'log_statement',
  'log_min_duration_statement',
  'log_duration',
  'log_lock_waits',
  'log_parser_stats',
  'log_planner_stats',
  'log_executor_stats'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name            | setting
----------------------------+---------
 log_duration               | on
 log_executor_stats         | on
 log_lock_waits             | on
 log_min_duration_statement | 0
 log_parser_stats           | on
 log_planner_stats          | on
 log_statement              | all
(7 rows)
```

Every logging option is turned up to maximum.

```bash
exit
```

---

## Resolution

### Step 1 - Set production-appropriate logging values

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Log only DDL statements (CREATE, ALTER, DROP) - not every query.

```sql
ALTER SYSTEM SET log_statement = 'ddl';
```

Log only queries that take longer than 1 second. This captures slow queries without logging fast ones.

```sql
ALTER SYSTEM SET log_min_duration_statement = 1000;
```

Turn off redundant duration logging.

```sql
ALTER SYSTEM SET log_duration = 'off';
```

Keep lock wait logging - it is low volume and useful for debugging contention.

```sql
ALTER SYSTEM SET log_lock_waits = 'on';
```

Turn off parser, planner, and executor stats - these are debugging tools, not for production.

```sql
ALTER SYSTEM SET log_parser_stats = 'off';
```

```sql
ALTER SYSTEM SET log_planner_stats = 'off';
```

```sql
ALTER SYSTEM SET log_executor_stats = 'off';
```

### Step 2 - Reload the configuration

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

### Step 3 - Verify the new settings

```sql
SELECT name, setting
FROM pg_settings
WHERE name IN (
  'log_statement',
  'log_min_duration_statement',
  'log_duration',
  'log_lock_waits',
  'log_parser_stats',
  'log_planner_stats',
  'log_executor_stats'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name            | setting
----------------------------+---------
 log_duration               | off
 log_executor_stats         | off
 log_lock_waits             | on
 log_min_duration_statement | 1000
 log_parser_stats           | off
 log_planner_stats          | off
 log_statement              | ddl
(7 rows)
```

### Step 4 - Confirm log volume has dropped

Run a few test queries and check the log.

```sql
SELECT count(*) FROM pg_stat_user_tables;
```

```sql
SELECT 1;
```

```bash
exit
```

```bash
sudo -iu postgres
```

```bash
tail -5 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

You should see far fewer log lines per query. The simple `SELECT 1` should NOT appear in the log (it takes less than 1 second).

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
- log_statement is not 'all'
- log_min_duration_statement is 1000ms or higher
- log_parser_stats is off
- log_planner_stats is off
- log_executor_stats is off
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What is the CPU overhead of log_parser_stats, log_planner_stats, and log_executor_stats?** - These call `getrusage()` before and after each phase of query processing. On Linux, `getrusage()` is fast but not free - it reads kernel accounting data. On a system processing 50,000 queries/second, that is 300,000 extra system calls per second (6 calls per query for start/end of each phase). This adds 1-3% CPU overhead depending on hardware. On a system already at 90% CPU, this pushes it over the edge.

2. **Why use log_min_duration_statement instead of log_statement='all' for slow query detection?** - `log_statement='all'` logs every query regardless of speed. It creates noise that makes finding slow queries hard. `log_min_duration_statement = 1000` only logs queries that took over 1 second, plus it includes the actual duration - giving you both the query text and how long it took. This is the standard production approach for slow query monitoring.

3. **What is the relationship between pg_stat_statements and query logging?** - `pg_stat_statements` aggregates query statistics in memory (total calls, mean time, min/max time per query fingerprint). It has near-zero overhead because it hooks into the executor, not the logging system. Query logging writes to disk for every logged query. For production monitoring, `pg_stat_statements` is preferred over verbose logging. Use logging only for specific debugging or compliance requirements.

4. **When would you temporarily enable log_statement='all'?** - During specific debugging sessions: tracking down a suspected SQL injection attack, diagnosing an application that sends unexpected queries, or auditing what a specific connection does. Always set it temporarily (`SET log_statement = 'all'` in a specific session) rather than globally, and turn it off when done.

5. **How do you monitor the monitoring overhead itself?** - Track log file growth rate (bytes/minute). Monitor disk I/O on the log partition. Compare query latency p99 with logging enabled vs disabled. Check `pg_stat_io` for `context = 'normal'` writes to see how much I/O the logger process generates. If the log partition runs out of space, PostgreSQL may hang waiting for log writes, which is the worst possible outcome of over-monitoring.
