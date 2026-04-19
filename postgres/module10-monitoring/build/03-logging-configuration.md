# Guide 03 - Logging Configuration

Configure PostgreSQL's logging system to capture slow queries, connection events, and errors in a structured format you can actually read and parse.

**Run all commands on:** NODE1

---

## Overview

PostgreSQL has a powerful built-in logging system, but most of it is off by default. Turning on the right settings lets you:
- Capture queries that exceed a duration threshold
- Rotate log files automatically so disk space does not fill up
- Parse logs with standard tools to find patterns
- Feed the Pulse Recent Orders and Query Stats panels

By the end of this guide you will know:
- What each key logging parameter does
- How to set a log format that includes useful context
- How to parse logs to find slow queries

---

## Section 1 - Connect and Check Current Logging State

SSH into NODE1.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

Check the current logging configuration by querying pg_settings.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT name, setting, unit FROM pg_settings WHERE name LIKE 'log%' ORDER BY name;"
```

Expected output (yours will differ):

```
             name              |    setting     | unit
-------------------------------+----------------+------
 log_checkpoints               | off            |
 log_connections               | off            |
 log_destination               | stderr         |
 log_directory                 | log            |
 log_disconnections            | off            |
 log_duration                  | off            |
 log_filename                  | postgresql-%a.log |
 log_line_prefix               | %m [%p]        |
 log_min_duration_statement    | -1             | ms
 log_rotation_age              | 1440           | min
 log_rotation_size             | 10240          | kB
 logging_collector             | on             |
...
```

Exit psql.

```sql
\q
```

---

## Section 2 - Understand the Key Parameters

Before editing the config, understand what each parameter controls:

| Parameter | What it does |
|---|---|
| `log_destination` | Where logs go: `stderr`, `csvlog`, `jsonlog`, or `syslog` |
| `logging_collector` | Must be `on` to write log files to disk |
| `log_directory` | Directory where log files are written |
| `log_filename` | Pattern for log file names |
| `log_rotation_age` | Rotate log file after this many minutes |
| `log_rotation_size` | Rotate log file when it reaches this size (kB) |
| `log_min_duration_statement` | Log queries slower than this (ms). `-1` = disabled. `0` = log everything |
| `log_statement` | Log all DDL (`ddl`), all modifications (`mod`), or all queries (`all`) |
| `log_line_prefix` | Format string prepended to every log line |
| `log_checkpoints` | Log checkpoint start/end with duration and bytes |
| `log_connections` | Log each new connection |
| `log_disconnections` | Log each disconnection with session duration |

---

## Section 3 - Edit postgresql.conf

Open the configuration file.

```
vi /opt/pgsql/data/postgresql.conf
```

### 3.1 - Set the log destination and collector

Find the `log_destination` line and set it to `stderr` (the default, which logging_collector captures to files).

```
log_destination = 'stderr'
```

Make sure `logging_collector` is on.

```
logging_collector = on
```

### 3.2 - Set the log directory and filename

```
log_directory = '/opt/pgsql/log'
```

```
log_filename = 'postgresql-%Y-%m-%d.log'
```

(`%Y-%m-%d` = year-month-day in the filename. This creates one file per day, which makes it easy to find logs from a specific date.)

### 3.3 - Configure rotation

```
log_rotation_age = 1440
```

```
log_rotation_size = 100MB
```

(`log_rotation_age = 1440` = rotate after 1440 minutes, which is 24 hours. `log_rotation_size = 100MB` = also rotate if the file hits 100MB before the 24-hour mark. Set to `0` to disable size-based rotation.)

### 3.4 - Set the slow query threshold

```
log_min_duration_statement = 1000
```

(`1000` = log any query that takes more than 1000ms (1 second). In development labs, 100ms is a good threshold to see more queries. In production, 1000-5000ms is typical.)

> **Concept - log_min_duration_statement**: This is the single most useful logging parameter for performance work. It captures only slow queries instead of flooding your logs with every statement. Setting it to `0` logs everything - useful for debugging a specific issue but never appropriate in production. Setting it to `-1` disables slow query logging entirely.

### 3.5 - Set the log line prefix

```
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

The format tokens in `log_line_prefix`:

| Token | Meaning |
|---|---|
| `%t` | Timestamp with milliseconds |
| `%p` | Process ID |
| `%l` | Log line number within the session |
| `%u` | Username |
| `%d` | Database name |
| `%a` | Application name |
| `%h` | Client hostname or IP |

### 3.6 - Enable checkpoint and connection logging

```
log_checkpoints = on
```

```
log_connections = on
```

```
log_disconnections = on
```

Save and exit vi with `:wq`.

---

## Section 4 - Reload the Configuration

Most logging parameters take effect with a reload (no restart needed).

Exit the postgres user first.

```
exit
```

Reload the PostgreSQL configuration.

```
sudo systemctl reload postgresql-16
```

Switch back to postgres and confirm the new settings loaded.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_min_duration_statement;"
```

Expected output:

```
 log_min_duration_statement
----------------------------
 1s
(1 row)
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW log_line_prefix;"
```

Expected output:

```
                  log_line_prefix
---------------------------------------------------
 %t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h
(1 row)
```

---

## Section 5 - Generate a Slow Query and Observe the Log

Run a query that will be slow enough to log. `pg_sleep()` forces a delay.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_sleep(2);"
```

Expected output:

```
 pg_sleep
----------

(1 row)
```

Now look at the log file.

```
tail -20 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-19 10:15:23.412 UTC [2841]: [1-1] user=postgres,db=stepup_store,app=psql,client= LOG:  connection received: host=[local]
2026-04-19 10:15:23.413 UTC [2841]: [2-1] user=postgres,db=stepup_store,app=psql,client= LOG:  connection authorized: user=postgres database=stepup_store
2026-04-19 10:15:25.820 UTC [2841]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 2004.321 ms  statement: SELECT pg_sleep(2);
2026-04-19 10:15:25.821 UTC [2841]: [4-1] user=postgres,db=stepup_store,app=psql,client= LOG:  disconnection: session time: 0:00:02.412 user=postgres database=stepup_store host=[local]
```

The `duration: 2004.321 ms` line is a slow query log entry. This is exactly what you would look for when hunting slow queries in production.

> **Concept - Log Line Prefix Context**: The prefix fields (`user=`, `db=`, `app=`, `client=`) are critical in production because they let you filter the log to a specific application, user, or database. Without them, a busy server's log is a mix of hundreds of different connections and you cannot tell which lines belong together.

---

## Section 6 - Parse Logs for Slow Queries

Find all slow query log entries.

```
grep 'duration:' /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | head -20
```

Expected output (yours will differ):

```
2026-04-19 10:15:25.820 UTC [2841]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  duration: 2004.321 ms  statement: SELECT pg_sleep(2);
```

Sort slow queries by duration to find the worst offenders.

```
grep 'duration:' /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | grep -oP 'duration: \K[\d.]+' | sort -rn | head -10
```

Expected output (yours will differ):

```
2004.321
245.102
128.443
...
```

(`grep -oP` = use Perl regex to extract just the number after "duration: ". `sort -rn` = sort numerically in reverse order.)

---

## Section 7 - Check Log File Rotation

Confirm the log directory contains the expected files.

```
ls -lh /opt/pgsql/log/
```

Expected output (yours will differ):

```
total 48K
-rw------- 1 postgres postgres 48K Apr 19 10:16 postgresql-2026-04-19.log
```

PostgreSQL will automatically create a new file each day. When `log_rotation_size` is hit, a new file with an incrementing suffix is created within the same day.

---

## Section 8 - Exit

```
exit
```

---

## Checkpoint

By the end of this guide you should have:

- [ ] Understood what `logging_collector`, `log_destination`, `log_directory` control
- [ ] Set `log_min_duration_statement = 1000` to capture slow queries
- [ ] Configured `log_line_prefix` with timestamp, pid, user, db, app, and client fields
- [ ] Enabled `log_checkpoints`, `log_connections`, and `log_disconnections`
- [ ] Set daily rotation with a 100MB size limit
- [ ] Generated a slow query and confirmed it appears in the log
- [ ] Used grep to extract slow query durations from the log file

---

Proceed to: [Guide 04 - Wait Events and Locks](./04-wait-events-locks.md)
