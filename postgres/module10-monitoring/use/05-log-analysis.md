# Use Exercise 05 - Log Analysis

Parse PostgreSQL logs to find the top 10 slowest queries, identify error patterns, and detect unusual connection activity.

**Run on:** NODE1

---

## Your Mission

pg_stat_statements shows aggregate statistics. Logs show individual events with timestamps, user context, and error messages. Some problems only show up in logs - transient errors, connection failures, lock timeouts, and authentication issues.

In this exercise you will:
1. Generate a realistic log dataset
2. Extract slow queries and rank them
3. Find error patterns
4. Detect connection anomalies

---

## Instructions

SSH into NODE1 and switch to the postgres user.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

---

## Part A - Generate Log Data

First confirm slow query logging is enabled (from Guide 03).

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output (yours will differ):

```
 log_min_duration_statement
----------------------------
 1s
(1 row)
```

If it shows `-1` (disabled), temporarily set it to 500ms.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET log_min_duration_statement = 500;"
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Now generate some slow queries.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_sleep(1.5);"
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_sleep(0.8);"
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_sleep(2.1);"
```

Generate a connection attempt to a non-existent database (this will create an error log entry).

```
/usr/pgsql-16/bin/psql -p 5432 -d nonexistent_db -c "SELECT 1;" 2>&1 || true
```

Expected output:

```
psql: error: connection to server on socket "/run/postgresql/.s.PGSQL.5432" failed: FATAL:  database "nonexistent_db" does not exist
```

Confirm the log file location.

```
ls -lh /opt/pgsql/log/
```

Expected output (yours will differ):

```
total 56K
-rw------- 1 postgres postgres 56K Apr 19 10:45 postgresql-2026-04-19.log
```

Set the log file path in a variable for the rest of this exercise.

```
LOGFILE=/opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

---

## Part B - Extract the Top 10 Slowest Queries

Extract all slow query durations from the log.

```
grep 'duration:' "$LOGFILE" | grep -oP 'duration: \K[\d.]+ ms' | sort -rn | head -20
```

Expected output (yours will differ):

```
2104.234 ms
1512.120 ms
810.441 ms
...
```

Extract slow queries with their full statement.

```
grep 'duration:' "$LOGFILE" | tail -20
```

Expected output (yours will differ):

```
2026-04-19 10:44:01.234 UTC [2901]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 2104.234 ms  statement: SELECT pg_sleep(2.1);
2026-04-19 10:43:45.012 UTC [2899]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 1512.120 ms  statement: SELECT pg_sleep(1.5);
...
```

Write a one-liner that extracts the top 10 slowest queries with their durations and first 60 characters of the statement.

```
grep 'duration:' "$LOGFILE" | grep -oP 'duration: [\d.]+ ms  statement: .{1,60}' | sort -rn | head -10
```

---

## Part C - Find Error Patterns

Count errors by type.

```
grep 'FATAL\|ERROR\|PANIC' "$LOGFILE" | grep -oP '(FATAL|ERROR|PANIC):  [^:]+' | sort | uniq -c | sort -rn
```

Expected output (yours will differ):

```
      3 FATAL:  database "nonexistent_db" does not exist
      1 ERROR:  canceling statement due to user request
```

Extract all FATAL lines with context.

```
grep 'FATAL:' "$LOGFILE" | tail -10
```

Expected output (yours will differ):

```
2026-04-19 10:45:12.009 UTC [2910]: [2-1] user=postgres,db=nonexistent_db,app=psql,client= FATAL:  database "nonexistent_db" does not exist
```

---

## Part D - Detect Connection Anomalies

Count connection events (requires `log_connections = on` from Guide 03).

```
grep 'connection received\|connection authorized\|disconnection' "$LOGFILE" | wc -l
```

Expected output (yours will differ):

```
18
```

Find which users are connecting most frequently.

```
grep 'connection authorized' "$LOGFILE" | grep -oP 'user=\K\w+' | sort | uniq -c | sort -rn
```

Expected output (yours will differ):

```
      9 postgres
      2 app_user
```

Find rejected connections.

```
grep 'FATAL.*authentication\|FATAL.*password\|FATAL.*database.*does not exist' "$LOGFILE"
```

---

## Part E - Build a Log Report Script

Write a script at `/opt/pgsql/log_report.sh` that:

1. Takes the log file path as an argument (default to today's log)
2. Prints: total slow queries (over threshold), top 5 slowest with duration
3. Prints: error count by type
4. Prints: total connection events, unique users who connected
5. Exits 1 if any FATAL or PANIC entries exist

```
vi /opt/pgsql/log_report.sh
```

```
chmod +x /opt/pgsql/log_report.sh
```

Run it against today's log.

```
/opt/pgsql/log_report.sh /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

---

## Checkpoint

- [ ] Generated slow query log entries with `pg_sleep`
- [ ] Extracted and ranked slow queries by duration from the log file
- [ ] Found and counted error entries by type
- [ ] Found connection events and identified the most-active users
- [ ] Found rejected connection attempts
- [ ] Built and ran a log report script

---

Proceed to: [Use Exercise 06 - Baseline Comparison](./06-baseline-comparison.md)
