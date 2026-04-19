# Use Exercise 03 - Connection Audit

Use pg_stat_activity to build a full connection report: connections by user, by database, by state, and by idle time.

**Run on:** NODE1

---

## Your Mission

Connection audits are something you do when:
- The application is reporting timeouts and you suspect connection exhaustion
- You want to see which applications are connecting to which databases
- You need to find idle connections that can be cleaned up

In this exercise you will build a complete connection picture of the server.

---

## Instructions

SSH into NODE1 and switch to the postgres user.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

Open psql.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Part A - Connections by User

Write a query that shows:
- Each username
- How many connections they have
- How many are active (executing a query)
- How many are idle

Expected output format:

```
  usename  | total | active | idle
-----------+-------+--------+------
 postgres  |     3 |      1 |    2
 app_user  |     2 |      0 |    2
```

**Hint:** Use `COUNT(CASE WHEN state = 'active' THEN 1 END)` for conditional counts within a GROUP BY.

---

## Part B - Connections by Database

Write a query that shows each database and its total connection count, along with what percentage of `max_connections` that database is consuming.

Expected output format:

```
   datname    | connections | pct_of_max
--------------+-------------+------------
 stepup_store |           5 |        5.0
 postgres     |           1 |        1.0
```

**Hint:** Use a subquery or CTE to get `max_connections` from `pg_settings`.

---

## Part C - Connections by State

Write a query that shows the count of connections in each state, including the maximum idle time for that state.

Expected output format:

```
      state      | count | max_idle_seconds
-----------------+-------+------------------
 active          |     1 |                0
 idle            |     4 |              840
 idle in trans   |     0 |
```

**Hint:** `EXTRACT(epoch FROM (now() - state_change))` gives you seconds since last state change.

---

## Part D - Long Idle Connections

Write a query that lists all connections that have been idle for more than 10 minutes, showing:
- PID
- Username
- Database
- Application name
- Client address
- Idle time in minutes

Order by idle time descending.

Expected output format (yours will differ):

```
  pid  | usename  |   datname    |    application_name    | client_addr | idle_minutes
-------+----------+--------------+------------------------+-------------+--------------
  2834 | app_user | stepup_store | my_app                 | 10.0.1.52   |           42
```

---

## Part E - The Full Report

Combine everything into a single script at `/opt/pgsql/connection_audit.sh` that:

1. Prints the timestamp and server
2. Shows connections by user
3. Shows connections by database with % of max
4. Shows counts by state
5. Lists idle connections over 10 minutes
6. Prints a total connection count and % of max_connections

Exit psql first.

```sql
\q
```

Create the script.

```
vi /opt/pgsql/connection_audit.sh
```

Make it executable.

```
chmod +x /opt/pgsql/connection_audit.sh
```

Run it.

```
/opt/pgsql/connection_audit.sh
```

---

## Checkpoint

- [ ] Query A: connections grouped by user with active/idle breakdown
- [ ] Query B: connections by database with % of max
- [ ] Query C: connections by state with max idle time
- [ ] Query D: list of idle connections over 10 minutes
- [ ] Combined script runs and outputs all 5 sections

---

Proceed to: [Use Exercise 04 - Lock Detective](./04-lock-detective.md)
