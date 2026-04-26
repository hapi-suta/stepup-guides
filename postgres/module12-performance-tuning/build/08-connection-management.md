# Build 08 - Connection Management

**Estimated time:** 25-30 minutes

In this lab, you will learn how PostgreSQL handles connections, why too many connections hurt performance, and how to monitor and manage them on a resource-constrained server.

---

## Prerequisites

- PostgreSQL 16 running on your lab server
- Database `labdb` exists
- You can SSH into your server as `ec2-user`

---

## Section 1: Understanding the Cost Per Connection

Every time a client connects to PostgreSQL, the server forks a brand-new OS process. Each process consumes roughly 5-10MB of RAM just by existing - even if it is doing nothing. On this server with only 736MB of RAM, that adds up fast.

### Step 1: Log in to your server

```bash
ssh -i your-key.pem ec2-user@YOUR_SERVER_IP
```

### Step 2: Switch to the postgres user

```bash
sudo su - postgres
```

### Step 3: Connect to labdb

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

### Step 4: Check the current max_connections setting

This shows the maximum number of simultaneous connections PostgreSQL will accept.

```sql
SHOW max_connections;
```

Expected output (yours will differ):

```
 max_connections
-----------------
 100
(1 row)
```

The default is 100. That means PostgreSQL will allow up to 100 client connections at the same time.

### Step 5: Check how many connections exist right now

```sql
SELECT count(*) FROM pg_stat_activity;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

This counts every connection - including background processes like autovacuum and your own psql session. Even with nobody using the database, you will see several connections from PostgreSQL's internal workers.

**Key takeaway:** On this server (736MB RAM, 2 vCPUs), if all 100 connections were active at once, the memory overhead alone (100 x 5-10MB = 500MB-1GB) would exceed available RAM. That is why connection management matters.

---

## Section 2: Monitoring Active Connections

Not all connections are equal. Some are actively running queries, some are sitting idle, and some are stuck holding transactions open. You need to know which is which.

### Step 1: Query connection states

Run this inside your existing psql session:

```sql
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;
```

Expected output (yours will differ):

```
        state        | count
---------------------+-------
 active              |     1
 idle                |     3
                     |     2
(3 rows)
```

### Understanding each state

- **active** - The connection is currently running a query. This is yours right now (the SELECT you just ran).
- **idle** - The connection is open but not doing anything. It is waiting for the application to send the next query. These still consume memory.
- **idle in transaction** - The connection ran BEGIN but has not yet run COMMIT or ROLLBACK. This is the most dangerous state.
- **(empty/null)** - Background worker processes like autovacuum launcher. These are normal.

### Why "idle in transaction" is dangerous

When a connection is idle in transaction, it:

1. **Holds locks** - Other queries that need those same rows or tables will wait (or fail)
2. **Blocks autovacuum** - PostgreSQL cannot clean up dead rows from tables that have open transactions referencing them
3. **Wastes a connection slot** - It counts against max_connections even though it is doing nothing

A single forgotten `BEGIN` without a matching `COMMIT` can silently degrade your entire database.

---

## Section 3: Setting idle_in_transaction_session_timeout

PostgreSQL can automatically kill connections that sit in the "idle in transaction" state for too long. This is your safety net.

### Step 1: Exit psql

```
\q
```

### Step 2: Set the timeout using ALTER SYSTEM

This writes the setting to `postgresql.auto.conf` so it persists across restarts.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';"
```

The `-c` flag runs a single SQL command and exits. The value `30s` means 30 seconds.

Expected output (yours will differ):

```
ALTER SYSTEM
```

### Step 3: Reload the configuration

PostgreSQL needs to re-read its configuration files. This does not interrupt existing connections.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_reload_conf();"
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 4: Verify the setting took effect

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW idle_in_transaction_session_timeout;"
```

Expected output (yours will differ):

```
 idle_in_transaction_session_timeout
-------------------------------------
 30s
(1 row)
```

### Step 5: Test the timeout

Connect to psql interactively:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

Start a transaction but do not commit it:

```sql
BEGIN;
```

Now wait 30 seconds. Do not type anything. After 30 seconds, PostgreSQL will kill your session. Try running any command:

```sql
SELECT 1;
```

Expected output (yours will differ):

```
FATAL:  terminating connection due to idle-in-transaction timeout
server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.
The connection to the server was lost. Attempting reset: Succeeded.
```

The connection was terminated because it sat idle in a transaction for more than 30 seconds.

### Step 6: Verify in the PostgreSQL log

```bash
tail -n 5 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-25 10:15:32.456 UTC [12345] FATAL:  terminating connection due to idle-in-transaction timeout
2026-04-25 10:15:32.456 UTC [12345] DETAIL:  The session has been idle in a transaction for longer than the configured idle_in_transaction_session_timeout.
```

This confirms PostgreSQL is enforcing the timeout and logging it.

---

## Section 4: Connection Sizing Rule of Thumb

More connections does not mean more performance. In fact, the opposite is true.

### The rule

For OLTP (Online Transaction Processing) workloads:

```
Optimal max_connections = 2-4x CPU cores
```

On this lab server with 2 vCPUs, the optimal number of active connections is **4-8**. Even being generous, **20-30 max_connections** would be appropriate if you have PgBouncer in front.

### Why 100 connections is too many

With 100 active connections on 2 CPUs:

- **CPU contention** - 100 processes fighting for 2 CPUs means constant context switching
- **Lock contention** - More concurrent transactions means more lock conflicts
- **Memory pressure** - 100 x 5-10MB = 500MB-1GB just for connection overhead
- **Cache thrashing** - Each process needs buffer cache, and they evict each other's data

### For this lab

We will leave max_connections at 100 so you can run the experiments in the next section. In production, you would set it to 20-30 and put a connection pooler (PgBouncer) in front.

---

## Section 5: Simulating Connection Pressure with pgbench

pgbench is PostgreSQL's built-in benchmarking tool. You will use it to see how performance changes as you add more connections.

### Step 1: Connect to psql

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

### Step 2: Make sure you are not in a broken session

```sql
SELECT 1;
```

If this returns `1`, you are good. Type `\q` to exit psql.

```
\q
```

### Step 3: Initialize pgbench tables

This creates test tables with sample data. The `-s 10` flag sets the scale factor to 10, which creates about 1 million rows.

```bash
/usr/pgsql-16/bin/pgbench -i -s 10 -p 5432 labdb
```

- `-i` - Initialize (create tables and populate data)
- `-s 10` - Scale factor of 10 (10 x 100,000 = 1,000,000 rows)
- `-p 5432` - Connect on port 5432

Expected output (yours will differ):

```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 1.23 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 2.45 s (drop tables 0.01 s, create tables 0.01 s, client-side generate 1.23 s, vacuum 0.15 s, primary keys 1.05 s).
```

### Step 4: Run with 5 connections (low pressure)

```bash
/usr/pgsql-16/bin/pgbench -c 5 -j 2 -T 10 -p 5432 labdb
```

- `-c 5` - Simulate 5 concurrent client connections
- `-j 2` - Use 2 threads in pgbench itself (matches our 2 vCPUs)
- `-T 10` - Run for 10 seconds

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 5
number of threads: 2
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 4523
number of failed transactions: 0 (0.000%)
latency average = 11.052 ms
initial connection time = 9.241 ms
tps = 452.30 (without initial connection time)
```

**Write down the TPS (transactions per second) number.** In this example, it is 452.

### Step 5: Run with 50 connections (high pressure)

```bash
/usr/pgsql-16/bin/pgbench -c 50 -j 2 -T 10 -p 5432 labdb
```

- `-c 50` - Simulate 50 concurrent client connections

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 50
number of threads: 2
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 2187
number of failed transactions: 0 (0.000%)
latency average = 228.654 ms
initial connection time = 91.336 ms
tps = 218.67 (without initial connection time)
```

### Step 6: Compare the results

| Metric | 5 connections | 50 connections |
|--------|--------------|----------------|
| TPS | ~450 | ~220 |
| Latency | ~11ms | ~229ms |

With 10x more connections, you got roughly **half the throughput** and **20x the latency**. This is the connection scaling wall. Adding more connections made everything slower because:

1. Two CPUs cannot run 50 processes at once - constant context switching
2. All 50 connections compete for the same locks on the same rows
3. Shared buffer cache is thrashed by 50 different workloads

---

## Section 6: PgBouncer Concept (Theory)

On this lab server, we will not install PgBouncer because the server is resource-constrained (736MB RAM). This section explains how it works so you understand the architecture for production use.

### The Problem

Applications (especially web apps) open many connections. A web server with 20 worker processes might open 20 connections. Scale to 5 app servers and you have 100 connections - but only 2-8 are running queries at any given moment.

### The Solution: Connection Pooling

PgBouncer sits between your application and PostgreSQL:

```
Application (100 connections) --> PgBouncer (100 client-side)
                                      |
                                      v
                              PostgreSQL (20 server-side)
```

PgBouncer accepts 100 connections from the app but only opens 20 to PostgreSQL. When a client sends a query, PgBouncer borrows a server connection, runs the query, and returns the connection to the pool.

### Pool Modes

| Mode | How it works | Use case |
|------|-------------|----------|
| **session** | Client keeps the server connection until disconnect | Legacy apps that use session-level features (LISTEN/NOTIFY, prepared statements) |
| **transaction** | Client gets a server connection for the duration of one transaction | Web apps, APIs - the standard choice |
| **statement** | Client gets a server connection for a single statement | Rarely used - breaks multi-statement transactions |

**Transaction mode** is the standard for most web applications. It gives you the biggest connection reduction because connections are returned to the pool between transactions.

### Sample PgBouncer Configuration

This is for reference only - we are not installing PgBouncer on this server.

```ini
; pgbouncer.ini - sample configuration

[databases]
labdb = host=127.0.0.1 port=5432 dbname=labdb

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

; Pool settings
pool_mode = transaction
default_pool_size = 20
max_client_conn = 200
min_pool_size = 5

; Timeouts
server_idle_timeout = 600
client_idle_timeout = 0
query_timeout = 300

; Logging
log_connections = 1
log_disconnections = 1
```

Key settings explained:

- `pool_mode = transaction` - Use transaction-level pooling
- `default_pool_size = 20` - Keep 20 connections open to PostgreSQL per database/user pair
- `max_client_conn = 200` - Accept up to 200 client connections
- `listen_port = 6432` - Applications connect to port 6432 instead of 5432

With this setup, 200 application connections share just 20 PostgreSQL connections. Your database sees 20 connections instead of 200.

---

## Cleanup

### Step 1: Exit psql if you are still connected

```
\q
```

### Step 2: Exit the postgres user

```bash
exit
```

You are now back as `ec2-user`.

---

## Summary

In this lab, you learned:

1. **Each PostgreSQL connection is an OS process** consuming 5-10MB of RAM
2. **"idle in transaction" connections are dangerous** - they hold locks and block autovacuum
3. **idle_in_transaction_session_timeout** is your safety net for abandoned transactions
4. **Optimal max_connections = 2-4x CPU cores** for OLTP workloads
5. **More connections = worse performance** once you exceed CPU capacity
6. **PgBouncer** solves the connection scaling problem by pooling connections between apps and PostgreSQL
