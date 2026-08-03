# USE 05 - Client Connection Patterns
## Tier 1: Provisioning and Connectivity

**Estimated time:** 30 minutes
**Type:** Hands-on exercise
**Prerequisite:** Build 05 complete, running RDS instance

---

## Overview

Real applications do not open and close one database connection per request. They use connection pools, which reuse connections across many requests. This exercise covers three connection patterns and a password rotation scenario.

---

## Part 1 - Connect from Three Different Clients

You will connect to the same RDS instance from three different tools. Use the instance from Build 01 or provision a fresh one.

Set your variables:

```bash
export RDS_ENDPOINT="your-rds-endpoint-here"
export RDS_USER="postgres"
export RDS_DB="labdb"
```

### Client A - psql with a Connection Service File

A connection service file (`~/.pg_service.conf`) stores named connection profiles. You can then connect with just the profile name.

**Step 1 - Create the service file:**

```bash
cat > ~/.pg_service.conf << 'EOF'
[suta-rds-lab]
host=REPLACE_WITH_YOUR_ENDPOINT
port=5432
dbname=labdb
user=postgres
sslmode=require
EOF
```

Replace `REPLACE_WITH_YOUR_ENDPOINT` with your actual endpoint.

**Step 2 - Set permissions:**

```bash
chmod 600 ~/.pg_service.conf
```

**Step 3 - Connect using the service name:**

```bash
PGPASSWORD="your_password" psql service=suta-rds-lab
```

You can also put the password in `~/.pgpass`:

```bash
echo "$RDS_ENDPOINT:5432:labdb:postgres:your_password" >> ~/.pgpass
chmod 600 ~/.pgpass
psql service=suta-rds-lab
```

No password prompt. You connect directly.

**Verify inside psql:**

```sql
\conninfo
\q
```

### Client B - Python with psycopg2 and a Connection Pool

Install the required library:

```bash
pip3 install psycopg2-binary
```

Create `/tmp/connection_pool_demo.py`:

```python
import psycopg2
from psycopg2 import pool
import os
import threading

RDS_HOST = os.environ["RDS_ENDPOINT"]
RDS_PASS = os.environ.get("PGPASSWORD", "")

# Create a connection pool: minimum 2, maximum 10 connections
connection_pool = psycopg2.pool.ThreadedConnectionPool(
    minconn=2,
    maxconn=10,
    host=RDS_HOST,
    port=5432,
    dbname="labdb",
    user="postgres",
    password=RDS_PASS,
    sslmode="require"
)

print(f"Pool created. Connections open: {connection_pool.minconn}")

def run_query(thread_id):
    """Simulates a web request that needs a database connection."""
    conn = connection_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT pg_backend_pid(), current_timestamp")
        pid, ts = cur.fetchone()
        print(f"Thread {thread_id}: connected on PID {pid} at {ts}")
        cur.close()
    finally:
        # CRITICAL: always return the connection to the pool
        connection_pool.putconn(conn)

# Simulate 5 concurrent web requests
threads = []
for i in range(5):
    t = threading.Thread(target=run_query, args=(i,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

connection_pool.closeall()
print("All connections closed.")
```

Run it:

```bash
python3 /tmp/connection_pool_demo.py
```

Expected output (PID values will vary):
```
Pool created. Connections open: 2
Thread 0: connected on PID 12345 at 2025-01-15 16:00:01.123+00
Thread 1: connected on PID 12346 at 2025-01-15 16:00:01.124+00
Thread 2: connected on PID 12345 at 2025-01-15 16:00:01.125+00
Thread 3: connected on PID 12346 at 2025-01-15 16:00:01.126+00
Thread 4: connected on PID 12345 at 2025-01-15 16:00:01.127+00
All connections closed.
```

Notice: 5 threads but only 2 PIDs. Threads are sharing and reusing the 2 pooled connections.

### Client C - Node.js with the `pg` Library

If you have Node.js installed:

```bash
mkdir -p /tmp/node-rds-demo
cd /tmp/node-rds-demo
npm init -y
npm install pg
```

Create `/tmp/node-rds-demo/connect.js`:

```javascript
import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  host: process.env.RDS_ENDPOINT,
  port: 5432,
  database: 'labdb',
  user: 'postgres',
  password: process.env.PGPASSWORD,
  ssl: {
    rejectUnauthorized: false, // for lab use only; use true with cert in production
  },
  max: 10,            // maximum pool size
  idleTimeoutMillis: 30000,   // close idle connections after 30s
  connectionTimeoutMillis: 5000,  // fail fast if cannot connect in 5s
});

async function main() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT version(), current_database(), pg_backend_pid()'
    );
    const row = result.rows[0];
    console.log('Connected!');
    console.log('Database:', row.current_database);
    console.log('PID:', row.pg_backend_pid);
    console.log('Version:', row.version.split(' ').slice(0, 2).join(' '));
  } finally {
    client.release();
  }
  await pool.end();
}

main().catch(console.error);
```

Run it:

```bash
node /tmp/node-rds-demo/connect.js
```

Expected output:
```
Connected!
Database: labdb
PID: 12350
Version: PostgreSQL 16.6
```

---

## Part 2 - Connection Pooling Concepts

Answer these questions based on what you observed in Part 1.

### Question 1

In the Python pool demo, you created a pool with `minconn=2, maxconn=10`. You ran 5 concurrent threads. Only 2 PIDs appeared in the output.

Why did 5 threads use only 2 database connections? What is the benefit of this?

### Question 2

What happens in a connection pool when all `maxconn` connections are in use and a new thread tries to get a connection?

With psycopg2 `ThreadedConnectionPool`, the caller will get a `PoolError: connection pool exhausted`. The caller must wait or fail.

In production, you would handle this:

```python
try:
    conn = connection_pool.getconn()
except psycopg2.pool.PoolError as e:
    # Log the error and return HTTP 503 to the caller
    raise ServiceUnavailableError("Database pool exhausted") from e
```

### Question 3

Should you use `psycopg2.pool.SimpleConnectionPool` or `psycopg2.pool.ThreadedConnectionPool` for a web server that handles concurrent requests?

Answer: `ThreadedConnectionPool`. It is thread-safe. `SimpleConnectionPool` is NOT thread-safe - using it from multiple threads simultaneously can cause connection mix-ups.

### Question 4 - PgBouncer (Discussion)

At high scale, even a pool of 10 connections inside your application may not be enough. Imagine 100 application servers each with a pool of 10 = 1000 total connections to PostgreSQL.

PostgreSQL's `max_connections` defaults to 100 (and uses ~10 MB of RAM per connection). With 1000 app connections you would exhaust it.

The solution is a dedicated connection pooler like PgBouncer. PgBouncer sits between your app and PostgreSQL, multiplexing thousands of client connections onto a small number of actual server connections.

```
[100 App Servers]  x10 connections each
        |
        v  (1000 connections to PgBouncer)
   [PgBouncer]
        |
        v  (20 connections to PostgreSQL)
  [RDS PostgreSQL]
```

PgBouncer is not covered in this tier but is covered in Tier 3.

---

## Part 3 - Password Rotation Scenario

**The scenario:** Your company's security policy requires database passwords to be rotated every 90 days. Today is rotation day.

Walk through the rotation process without breaking the application.

### Step 1 - Check Who Uses This Password

Before changing anything, figure out what is using the old password. Connect with the master user and check active connections:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb
```

```sql
SELECT pid, usename, application_name, client_addr, state
FROM pg_stat_activity
WHERE usename NOT IN ('postgres', 'rdsadmin')
ORDER BY usename;
```

This shows all non-admin connections. These are your application connections that use the password you are about to rotate.

### Step 2 - Plan the Rotation

For a smooth rotation with no downtime:
1. Add a new password (keep old one working)
2. Update all apps to use the new password
3. Verify all apps are connected with new password
4. Optionally: force disconnect old sessions

On RDS you can change the password directly - there is no "temporary second password" feature in PostgreSQL. So the rotation causes a brief period where existing connections work (they do not re-authenticate) but new connections must use the new password.

### Step 3 - Change the Password via AWS Console

1. Go to RDS > Databases.
2. Click on your instance.
3. Click **Modify**.
4. Under "Settings", find "Master password".
5. Enter the new password.
6. Click **Continue**.
7. Choose **Apply immediately**.
8. Click **Modify DB instance**.

### Step 4 - Change the Password via CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --master-user-password "NewSecurePassword456!" \
  --apply-immediately
```

AWS applies the password change within a minute. Existing connections are NOT dropped. New connections must use the new password.

### Step 5 - Change the Password for an App User (via psql)

The master password is changed through AWS. An app user's password is changed through PostgreSQL:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb
```

```sql
ALTER USER appuser WITH PASSWORD 'NewAppUserPassword789!';
```

### Step 6 - Verify New Password Works

```bash
PGPASSWORD="NewSecurePassword456!" psql \
  -h $RDS_ENDPOINT -U postgres -d labdb -c "SELECT 1 AS test"
```

Expected output:
```
 test
------
    1
(1 row)
```

### Step 7 - Update Application Configuration

In a real deployment you would update the app's configuration. For this lab, just update your environment variable:

```bash
export PGPASSWORD="NewSecurePassword456!"
```

Then test the Python connection script from Build 05 to confirm the new password works.

---

## Part 4 - Review Questions

Answer these without looking at the guides:

1. What psql command shows you the current connection details (host, port, database, user)?

2. You have 50 application threads all trying to query the database at the same time. Without a connection pool, how many PostgreSQL backend processes would be created? With a pool of 10, how many?

3. Name two benefits of using a `.pg_service.conf` file over typing connection flags every time.

4. Why do you NEVER change the IP address of an RDS endpoint by hand, even if you know the IP?

5. A developer asks: "Can I connect directly to the RDS instance via SSH to check what's running?" What is your answer and why?

6. What is the difference between the psql `-W` flag and the `PGPASSWORD` environment variable?

---

## Summary

| Pattern | When to Use |
|---------|-------------|
| psql with .pgpass | Manual DBA work, scripts |
| psql with .pg_service.conf | Team environments with shared connection profiles |
| psycopg2 pool | Python applications with concurrent requests |
| Node.js pg Pool | Node.js applications with concurrent requests |
| Password rotation | Every 90 days; update apps before forcing disconnect |
| PgBouncer | When application connections > 100 or max_connections is a bottleneck |
