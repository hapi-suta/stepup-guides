# Build Guide 05: PgBouncer and Redis Setup

| | |
|---|---|
| **Time** | 45 minutes |
| **Server** | pg-primary (3.90.199.62, private 172.31.19.86) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- What connection pooling is and why quant trading applications need it
- How to install and configure PgBouncer as a connection pool in front of PostgreSQL
- How to connect through PgBouncer and read pool statistics
- What Redis is and why quant funds use it alongside PostgreSQL
- How to install, configure, and test Redis on the same server

## Prerequisites

- BUILD-01 through BUILD-04 completed on pg-primary
- PostgreSQL 17 running with the `quantdb` database
- Users `quant_app`, `quant_readonly`, `quant_research`, `quant_pipeline` already created
- SSH access to pg-primary

---

## Part A: PgBouncer

---

## Step 1: Understand Connection Pooling

**Why does a quant trading application need this?**

A typical PostgreSQL server handles roughly 100-200 active connections before performance degrades. At a quant fund like Voleon, machine learning models constantly open connections to fetch predictions, query signals, and write results. Each model run might open a connection, run one query, and close it immediately. If 500 model workers do this simultaneously, PostgreSQL struggles.

PgBouncer sits between the application and PostgreSQL and acts as a middleman. Applications connect to PgBouncer (port 6432). PgBouncer maintains a small pool of real PostgreSQL connections (port 5432) and reuses them. A model worker gets a connection from the pool, runs its transaction, and the connection goes back to the pool - it does not close. The next worker reuses it.

**Transaction mode** is the most aggressive setting: the PostgreSQL connection returns to the pool after each transaction, not after the client disconnects. This means 20 real PostgreSQL connections can serve 200 application clients.

---

## Step 2: Install PgBouncer

SSH into pg-primary as ec2-user.

```
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user**, install PgBouncer from the default CentOS repositories.

```
sudo dnf install -y pgbouncer
```

The `-y` flag automatically answers yes to all prompts. This installs the `pgbouncer` package including its systemd service and default configuration files.

Expected output (yours will differ):
```
Installed:
  pgbouncer-1.21.0-1.el9.x86_64

Complete!
```

Verify the installation succeeded.

```
pgbouncer --version
```

Expected output (yours will differ):
```
PgBouncer 1.21.0
...
```

---

## Step 3: Configure PgBouncer

On **pg-primary**, as **ec2-user**, open the main configuration file.

```
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Replace the entire contents with the following configuration. Press `i` to enter insert mode, delete the existing content, paste the block below, then press `Esc` and type `:wq` to save.

```ini
[databases]
quantdb = host=127.0.0.1 port=5432 dbname=quantdb

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 50
max_client_conn = 1000
max_db_connections = 100
server_tls_sslmode = disable
log_connections = 1
log_disconnections = 1
admin_users = pgbouncer
stats_users = pgbouncer
```

**What each setting means:**

- `[databases]` - Maps a PgBouncer database name to the real PostgreSQL connection. Clients connect to `quantdb` on port 6432 and PgBouncer forwards to `quantdb` on 5432.
- `listen_addr = *` - PgBouncer listens on all network interfaces, not just localhost.
- `listen_port = 6432` - The port applications connect to. Convention is one above PostgreSQL's 5432.
- `auth_type = scram-sha-256` - Password authentication method, matching PostgreSQL's SCRAM hashing.
- `auth_file` - Points to the file containing usernames and password hashes.
- `pool_mode = transaction` - The connection returns to the pool after each transaction. Most efficient mode.
- `default_pool_size = 50` - Maximum real PostgreSQL connections per database-user pair.
- `max_client_conn = 1000` - Maximum total application clients that can connect to PgBouncer.
- `max_db_connections = 100` - Maximum real connections to PostgreSQL across all pools for this database.
- `server_tls_sslmode = disable` - Disables TLS between PgBouncer and PostgreSQL since both are on the same host.
- `log_connections = 1` - Logs every new client connection for troubleshooting.
- `log_disconnections = 1` - Logs every client disconnect.
- `admin_users = pgbouncer` - The `pgbouncer` role can connect to the internal `pgbouncer` admin database to run commands.
- `stats_users = pgbouncer` - The `pgbouncer` role can run `SHOW` commands to read pool statistics.

---

## Step 4: Create the pgbouncer Role in PostgreSQL

PgBouncer needs to authenticate users against a list of hashed passwords. You need to get those hashes from PostgreSQL. First, create the `pgbouncer` management role inside PostgreSQL.

On **pg-primary**, as **ec2-user**, switch to the postgres OS user.

```
sudo su - postgres
```

Now as **postgres** on **pg-primary**, open psql.

```
psql -d quantdb
```

Create the `pgbouncer` management role.

```sql
CREATE ROLE pgbouncer WITH LOGIN PASSWORD 'pgbouncer_2026';
```

Expected output (yours will differ):
```
CREATE ROLE
```

Now retrieve the SCRAM password hashes for all application users and the new pgbouncer role. This query reads from `pg_authid`, which is the system catalog that stores authentication information.

```sql
SELECT rolname, rolpassword
FROM pg_authid
WHERE rolname IN ('quant_app','quant_readonly','quant_research','quant_pipeline','pgbouncer');
```

Expected output (yours will differ):
```
     rolname      |                           rolpassword
------------------+------------------------------------------------------------------
 quant_app        | SCRAM-SHA-256$4096:somesalt...==
 quant_readonly   | SCRAM-SHA-256$4096:anothersalt...==
 quant_research   | SCRAM-SHA-256$4096:researchsalt...==
 quant_pipeline   | SCRAM-SHA-256$4096:pipelinesalt...==
 pgbouncer        | SCRAM-SHA-256$4096:bouncersalt...==
...
```

Copy the full hash strings for each user. You will need them in the next step.

Exit psql.

```
\q
```

Exit back to ec2-user.

```
exit
```

---

## Step 5: Create the PgBouncer Auth File

On **pg-primary**, as **ec2-user**, create the userlist file. This file tells PgBouncer which users are allowed to connect and what their hashed passwords are.

```
sudo vi /etc/pgbouncer/userlist.txt
```

Press `i` to enter insert mode. Add one line per user in the format `"username" "SCRAM-SHA-256$..."`. Paste the exact hash strings you copied from the previous step.

```
"quant_app" "SCRAM-SHA-256$4096:paste-full-hash-here"
"quant_readonly" "SCRAM-SHA-256$4096:paste-full-hash-here"
"quant_research" "SCRAM-SHA-256$4096:paste-full-hash-here"
"quant_pipeline" "SCRAM-SHA-256$4096:paste-full-hash-here"
"pgbouncer" "SCRAM-SHA-256$4096:paste-full-hash-here"
```

Press `Esc`, then type `:wq` to save.

Set the correct ownership so the `pgbouncer` OS user (which the service runs as) can read the file.

```
sudo chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt
```

Set permissions so only the pgbouncer user can read it (hashes are sensitive).

```
sudo chmod 600 /etc/pgbouncer/userlist.txt
```

---

## Step 6: Start PgBouncer

On **pg-primary**, as **ec2-user**, start the PgBouncer service.

```
sudo systemctl start pgbouncer
```

Enable it so it starts automatically after a server reboot.

```
sudo systemctl enable pgbouncer
```

Check that the service is running.

```
sudo systemctl status pgbouncer
```

Expected output (yours will differ):
```
● pgbouncer.service - A lightweight connection pooler for PostgreSQL
     Loaded: loaded (/usr/lib/systemd/system/pgbouncer.service; enabled; ...)
     Active: active (running) since Sun 2026-06-15 10:00:00 UTC; 5s ago
...
```

If the status shows `failed` instead of `active (running)`, check the logs.

```
sudo journalctl -u pgbouncer -n 50
```

Common issues: wrong file path in `auth_file`, incorrect ownership on `userlist.txt`, or a typo in `pgbouncer.ini`.

---

## Step 7: Test a Connection Through PgBouncer

On **pg-primary**, as **ec2-user**, connect to `quantdb` through PgBouncer on port 6432. This simulates what a model worker application would do.

```
psql -h 127.0.0.1 -p 6432 -U quant_app -d quantdb
```

When prompted, enter the password: `quant_app_2026`

Run a quick check inside psql.

```sql
SELECT current_database(), current_user;
```

Expected output (yours will differ):
```
 current_database | current_user
------------------+--------------
 quantdb          | quant_app
...
```

Exit psql.

```
\q
```

---

## Step 8: Read PgBouncer Pool Statistics

PgBouncer exposes a virtual database called `pgbouncer` that lets you inspect pool health, connection counts, and query rates. Connect to it.

On **pg-primary**, as **ec2-user**:

```
psql -h 127.0.0.1 -p 6432 -U pgbouncer -d pgbouncer
```

When prompted, enter the password: `pgbouncer_2026`

Show current pool status.

```sql
SHOW pools;
```

Expected output (yours will differ):
```
 database  |   user    | cl_active | cl_waiting | sv_active | sv_idle | ...
-----------+-----------+-----------+------------+-----------+---------+...
 quantdb   | quant_app |         0 |          0 |         0 |       1 | ...
...
```

Column meanings:
- `cl_active` - Clients currently executing a query
- `cl_waiting` - Clients waiting for a free server connection
- `sv_active` - Server connections currently used by a client
- `sv_idle` - Server connections idle and ready to be reused

Show connected clients.

```sql
SHOW clients;
```

Show server-side PostgreSQL connections PgBouncer is holding.

```sql
SHOW servers;
```

Exit psql.

```
\q
```

---

## Part B: Redis

---

## Step 9: Understand Redis at a Quant Fund

PostgreSQL is durable and relational - great for storing trade records, model configurations, and audit logs. But some lookups happen thousands of times per second and need sub-millisecond response times.

Examples at Voleon:
- **Model metadata** - "What version of model v42 is currently active?" - queried by every prediction worker before running.
- **Feature lookups** - Precomputed factor scores for 5,000 securities, refreshed every minute, read by hundreds of workers simultaneously.
- **Signal scores** - Latest signal value for a ticker, updated by pipeline workers and read by execution workers in near real-time.

Redis stores key-value pairs in memory. Reads take under 1 millisecond. This reduces load on PostgreSQL and prevents read queries from blocking write transactions on the PostgreSQL side.

Redis and PostgreSQL complement each other. PostgreSQL is the system of record. Redis is the fast lookup layer.

---

## Step 10: Install Redis

On **pg-primary**, as **ec2-user**, install Redis 7 from the CentOS repositories.

```
sudo dnf install -y redis
```

Expected output (yours will differ):
```
Installed:
  redis-7.2.4-1.el9.x86_64

Complete!
```

---

## Step 11: Configure Redis

On **pg-primary**, as **ec2-user**, open the Redis configuration file. The file location depends on the package version - check both paths.

```
ls /etc/redis/redis.conf /etc/redis.conf 2>/dev/null
```

Use whichever path exists. Typically on CentOS 9 with Redis 7 it is `/etc/redis/redis.conf`.

```
sudo vi /etc/redis/redis.conf
```

You need to change several settings. Use vi's search to find and edit each line. Press `/` followed by the setting name to jump to it.

Find and update these lines:

**bind** - Change from `bind 127.0.0.1 -::1` to listen on all interfaces.
```
bind 0.0.0.0
```

**port** - Should already be 6379. Confirm it.
```
port 6379
```

**requirepass** - Find the commented-out `requirepass` line and uncomment it, setting the password.
```
requirepass redis_voleon_2026
```

**maxmemory** - Find `# maxmemory <bytes>` and replace it with a 256 MB limit.
```
maxmemory 256mb
```

**maxmemory-policy** - Find `# maxmemory-policy noeviction` and set it to LRU eviction.
```
maxmemory-policy allkeys-lru
```

**save** - These lines control when Redis writes a snapshot to disk. Confirm or add these two lines.
```
save 900 1
save 300 10
```

`save 900 1` means: write a snapshot if at least 1 key changed in the last 900 seconds (15 minutes).
`save 300 10` means: write a snapshot if at least 10 keys changed in the last 300 seconds (5 minutes).

Press `Esc` and type `:wq` to save the file.

---

## Step 12: Start Redis

On **pg-primary**, as **ec2-user**, start the Redis service.

```
sudo systemctl start redis
```

Enable it to start automatically on reboot.

```
sudo systemctl enable redis
```

Check the service status.

```
sudo systemctl status redis
```

Expected output (yours will differ):
```
● redis.service - Redis persistent key-value database
     Loaded: loaded (/usr/lib/systemd/system/redis.service; enabled; ...)
     Active: active (running) since Sun 2026-06-15 10:15:00 UTC; 3s ago
...
```

---

## Step 13: Test Redis Locally

On **pg-primary**, as **ec2-user**, connect to Redis using the command-line client. The `-a` flag passes the password directly.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 ping
```

The `-h` flag sets the hostname, `-p` sets the port, `-a` passes the authentication password.

Expected output:
```
PONG
```

If you see `PONG`, Redis is running and authentication works.

Now set and retrieve a key simulating a model status flag.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 SET model:v42:status "active"
```

Expected output:
```
OK
```

Read it back.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 GET model:v42:status
```

Expected output:
```
"active"
```

Set a signal score for a ticker.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 SET signal:AAPL:latest "0.847"
```

Read it back.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 GET signal:AAPL:latest
```

Expected output:
```
"0.847"
```

Check how many keys are currently stored.

```
redis-cli -h 127.0.0.1 -p 6379 -a redis_voleon_2026 DBSIZE
```

Expected output (yours will differ):
```
(integer) 2
```

---

## Step 14: Test Redis from a Remote Server

This confirms the `bind 0.0.0.0` and firewall settings are correct. From **pg-ops** or **pg-replica** (any other server in your lab), run:

On **pg-ops** (or any other lab server), as **ec2-user**:

```
redis-cli -h 3.90.199.62 -p 6379 -a redis_voleon_2026 ping
```

Expected output:
```
PONG
```

If you get a timeout or connection refused, check that port 6379 is open in the AWS security group for pg-primary.

---

## Step 15: Verify Both Services Are Running

On **pg-primary**, as **ec2-user**, do a final check that both PgBouncer and Redis survived the configuration.

```
sudo systemctl status pgbouncer redis
```

Expected output (yours will differ):
```
● pgbouncer.service - A lightweight connection pooler for PostgreSQL
     Active: active (running) ...

● redis.service - Redis persistent key-value database
     Active: active (running) ...
```

Both should show `active (running)`.

---

## Summary

You now have:

- **PgBouncer** running on port 6432, pooling connections to PostgreSQL on 5432. Applications connect to 6432. PgBouncer manages a pool of 20 real PostgreSQL connections that can serve up to 200 application clients simultaneously. The `pgbouncer` admin user lets you inspect pool health with `SHOW pools;`.
- **Redis** running on port 6379, password-protected, with a 256 MB memory cap and LRU eviction. Model workers can store and retrieve sub-millisecond key-value data without touching PostgreSQL.

These two services together reduce PostgreSQL connection pressure (PgBouncer) and read query load (Redis) - both critical at a fund where hundreds of model workers run concurrently.
