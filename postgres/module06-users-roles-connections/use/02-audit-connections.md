# Exercise 02 - Audit Active Connections

**Module:** 06 - Users, Roles & Connections
**Time:** 15 minutes

---

## Scenario

Your monitoring alert fired: "High connection count on stepup_store." You need to identify what is connected, find any problematic sessions, and produce a report for the team.

---

## Setup

```bash
ssh -i your-key.pem ec2-user@NODE1
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Count connections by state

```sql
SELECT state, count(*) AS connection_count
FROM pg_stat_activity
GROUP BY state
ORDER BY connection_count DESC;
```

This groups all backends by their current state. Key states to look for:
- `active` - currently executing a query
- `idle` - connected but not doing anything
- `idle in transaction` - inside a BEGIN/COMMIT block doing nothing

Expected output (yours will differ):

```
          state          | connection_count
-------------------------+-----------------
 idle                    |               4
 active                  |               1
 idle in transaction     |               0
```

---

## Task 2 - Count connections by user

```sql
SELECT usename, count(*) AS connections
FROM pg_stat_activity
WHERE usename IS NOT NULL
GROUP BY usename
ORDER BY connections DESC;
```

Expected output (yours will differ):

```
  usename  | connections
-----------+-------------
 postgres  |           2
 app_user  |           2
```

---

## Task 3 - Find long-running queries

```sql
SELECT pid,
       usename,
       now() - query_start AS query_age,
       state,
       left(query, 60) AS query_snippet
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start IS NOT NULL
  AND now() - query_start > interval '30 seconds'
ORDER BY query_age DESC;
```

Expected output (yours will differ - may be empty):

```
 pid | usename | query_age | state | query_snippet
-----+---------+-----------+-------+---------------
(0 rows)
```

---

## Task 4 - Find blocked sessions

A session is blocked when it is waiting for a lock held by another session.

```sql
SELECT blocked.pid AS blocked_pid,
       blocked.usename AS blocked_user,
       blocking.pid AS blocking_pid,
       blocking.usename AS blocking_user,
       blocked.query AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Expected output (yours will differ - may be empty in a quiet lab):

```
 blocked_pid | blocked_user | blocking_pid | blocking_user | blocked_query
-------------+--------------+--------------+---------------+---------------
(0 rows)
```

---

## Task 5 - Find connections idle for more than 5 minutes

```sql
SELECT pid,
       usename,
       application_name,
       client_addr,
       state,
       now() - state_change AS idle_for
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < now() - interval '5 minutes'
ORDER BY idle_for DESC;
```

---

## Task 6 - Find connections from specific client IPs

```sql
SELECT pid, usename, client_addr, client_port, state, application_name
FROM pg_stat_activity
WHERE client_addr IS NOT NULL
ORDER BY client_addr;
```

NULL client_addr means the connection came through the Unix socket (local connection).

---

## Task 7 - Generate a summary report

```sql
SELECT
  'Total connections' AS metric,
  count(*)::text AS value
FROM pg_stat_activity
UNION ALL
SELECT
  'Active queries',
  count(*)::text
FROM pg_stat_activity WHERE state = 'active'
UNION ALL
SELECT
  'Idle connections',
  count(*)::text
FROM pg_stat_activity WHERE state = 'idle'
UNION ALL
SELECT
  'Idle in transaction',
  count(*)::text
FROM pg_stat_activity WHERE state LIKE 'idle in transaction%'
UNION ALL
SELECT
  'Max connections',
  setting
FROM pg_settings WHERE name = 'max_connections'
UNION ALL
SELECT
  'Available slots',
  (setting::int - (SELECT count(*) FROM pg_stat_activity))::text
FROM pg_settings WHERE name = 'max_connections';
```

Expected output (yours will differ):

```
        metric         | value
-----------------------+-------
 Total connections     | 5
 Active queries        | 1
 Idle connections      | 4
 Idle in transaction   | 0
 Max connections       | 100
 Available slots       | 95
```

---

## Task 8 - Exit

```bash
\q
```

```bash
exit
```

---

## Review Questions

1. What is the danger of `idle in transaction` sessions that regular `idle` sessions do not have?
2. How would you terminate all idle connections from a specific application without disconnecting active queries?
3. What does it mean when `client_addr` is NULL in pg_stat_activity?
