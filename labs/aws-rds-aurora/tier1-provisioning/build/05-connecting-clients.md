# Build 05 - Connecting Clients to RDS
## Tier 1: Provisioning and Connectivity

**Estimated time:** 30 minutes
**Difficulty:** Beginner
**Prerequisite:** Build 01 complete (running RDS instance with endpoint and credentials)

---

## What You Will Do

You will connect to your RDS PostgreSQL instance using three different clients. You will also learn about the master user's permissions and how to set up SSL properly.

---

## Before You Start

Have these ready:

- Your RDS endpoint (from Build 01)
- Your master username (`postgres`)
- Your master password
- Your database name (`labdb`)
- psql installed: `psql --version`
- pgAdmin 4 installed: https://www.pgadmin.org/download/

Set a variable for your endpoint so you do not have to type it repeatedly:

```bash
export RDS_ENDPOINT="suta-rds-lab.abc123.us-east-1.rds.amazonaws.com"
```

Replace the value with your actual endpoint.

---

## Part A - Connecting with psql

psql is the command-line client that ships with PostgreSQL. It is the tool DBAs use most.

### Method 1 - Flags Format

Each piece of the connection is a separate flag:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb -p 5432
```

What each flag does:
- `-h` - the hostname to connect to (the RDS endpoint)
- `-U` - the username to authenticate as
- `-d` - the name of the database to use after connecting
- `-p` - the port number (5432 is the default for PostgreSQL)

You will be prompted:
```
Password for user postgres:
```

Type your password and press Enter. The password will not be visible as you type.

### Method 2 - Connection String Format

Everything in one string:

```bash
psql "postgresql://postgres:YOUR_PASSWORD@$RDS_ENDPOINT:5432/labdb"
```

> **Concept:** Connection strings follow the URL format. Do not use this format in scripts because the password is visible in your shell history. Use the flags format with a password file or environment variable instead.

### Method 3 - Using PGPASSWORD Environment Variable

Set the password as an environment variable so you do not have to type it each time. In a terminal session:

```bash
export PGPASSWORD="your_password_here"
psql -h $RDS_ENDPOINT -U postgres -d labdb -p 5432
```

The `PGPASSWORD` environment variable is read by psql automatically.

> **Warning:** This is fine for a lab session. In production, clear it after: `unset PGPASSWORD`

### Method 4 - Using a .pgpass File

A `.pgpass` file stores credentials so psql never prompts you. Each line follows this format:

```
hostname:port:database:username:password
```

Create the file:

```bash
echo "$RDS_ENDPOINT:5432:labdb:postgres:YOUR_PASSWORD" >> ~/.pgpass
```

Set the correct permissions (required - psql ignores the file if permissions are too open):

```bash
chmod 600 ~/.pgpass
```

Now connect without a password prompt:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb
```

### Useful psql Commands Inside the Prompt

Once connected, these commands help you explore the database:

```
\l              -- list all databases
\c dbname       -- switch to a different database
\dt             -- list tables in current database
\d tablename    -- describe a table's structure
\du             -- list users and their roles
\conninfo       -- show current connection details
\timing         -- toggle query timing on/off
\q              -- quit psql
```

Try them now:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb
```

Inside psql:
```sql
\conninfo
```

Expected output:
```
You are connected to database "labdb" as user "postgres" on host "suta-rds-lab.abc123.us-east-1.rds.amazonaws.com" (address "54.234.189.12") at port "5432".
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
```

Note the "SSL connection" line. By default, RDS enforces SSL.

---

## Part B - Connecting with pgAdmin 4

pgAdmin is a visual tool for working with PostgreSQL. It shows your databases, tables, and functions as a tree, and lets you run queries in a window.

### Step 1 - Open pgAdmin

1. Open pgAdmin 4 from your Applications folder (Mac) or Start Menu (Windows).
2. The first time you open it, it will ask you to set a master password for pgAdmin. This is pgAdmin's own password, not the database password. Set one and remember it.
3. pgAdmin opens in your browser (usually http://127.0.0.1:5050).

### Step 2 - Register a New Server

1. In the left panel, you will see **Servers** at the top.
2. Right-click on **Servers**.
3. Click **Register** > **Server**.

A dialog box opens.

### Step 3 - General Tab

In the "Register - Server" dialog:

1. Click on the **General** tab.
2. In the **Name** field, type: `SUTA RDS Lab`

This is just the display name in pgAdmin. It can be anything.

### Step 4 - Connection Tab

1. Click on the **Connection** tab.
2. Fill in these fields:

| Field | Value |
|-------|-------|
| Host name / address | Your RDS endpoint (e.g. `suta-rds-lab.abc123.us-east-1.rds.amazonaws.com`) |
| Port | `5432` |
| Maintenance database | `labdb` |
| Username | `postgres` |
| Password | Your master password |
| Save password? | Toggle on (for the lab) |

### Step 5 - SSL Tab

1. Click the **SSL** tab.
2. Change **SSL mode** from "Prefer" to **Require**.

This tells pgAdmin to always use SSL when connecting. AWS RDS supports SSL on all connections.

### Step 6 - Save and Connect

1. Click **Save**.
2. pgAdmin will try to connect. A spinner appears briefly.
3. If successful, you will see your server in the left panel with a green icon.
4. Click the arrow next to **SUTA RDS Lab** to expand it.
5. Click **Databases** to see `labdb`.
6. Click **labdb** > **Schemas** > **public** > **Tables** to browse your tables.

### Step 7 - Run a Query in pgAdmin

1. In the left panel, right-click on **labdb**.
2. Click **Query Tool**.
3. A query editor window opens.
4. Type in the editor:

```sql
SELECT current_database(), current_user, version();
```

5. Click the **Execute** button (the play button, or press F5).
6. Results appear in the panel below the editor.

Expected output:
```
current_database | current_user |          version
-----------------+-------------+-----------------------------------------
 labdb           | postgres     | PostgreSQL 16.6 on aarch64-unknown...
```

### Troubleshooting pgAdmin Connection Failures

If pgAdmin cannot connect:

1. **Check the error message** - pgAdmin usually shows a helpful error. Look for:
   - "timeout expired" = security group issue
   - "password authentication failed" = wrong password
   - "could not translate host name" = wrong endpoint

2. **Test with psql first** - if psql works but pgAdmin does not, the problem is in pgAdmin's settings.

3. **Check SSL settings** - some pgAdmin versions require you to download the AWS certificate bundle and specify it. If SSL mode "Require" fails, try "Allow" temporarily to confirm basic connectivity.

---

## Part C - Connecting from Python

Python is the most common language used with PostgreSQL in data engineering and backend development. The main library is `psycopg2`.

### Step 1 - Install psycopg2

In your terminal (outside psql):

```bash
pip3 install psycopg2-binary
```

`psycopg2-binary` includes pre-compiled binaries so you do not need to compile from source. In production, use `psycopg2` (without `-binary`) for better performance.

### Step 2 - A Basic Connection Script

Create a file. Save it as `/tmp/rds_connect.py`:

```python
import psycopg2
import os
import sys

# Get credentials from environment variables
# Never hardcode these in your scripts
RDS_HOST = os.environ.get("RDS_HOST")
RDS_PORT = int(os.environ.get("RDS_PORT", "5432"))
RDS_DB   = os.environ.get("RDS_DB", "labdb")
RDS_USER = os.environ.get("RDS_USER", "postgres")
RDS_PASS = os.environ.get("RDS_PASS")

# Validate required env vars
missing = [v for v in ["RDS_HOST", "RDS_PASS"] if not os.environ.get(v)]
if missing:
    print(f"ERROR: Missing environment variables: {', '.join(missing)}")
    sys.exit(1)

try:
    conn = psycopg2.connect(
        host=RDS_HOST,
        port=RDS_PORT,
        dbname=RDS_DB,
        user=RDS_USER,
        password=RDS_PASS,
        sslmode="require",
        connect_timeout=10
    )
    print("Connected successfully!")

    cursor = conn.cursor()

    # Check PostgreSQL version
    cursor.execute("SELECT version()")
    version = cursor.fetchone()[0]
    print(f"PostgreSQL version: {version[:60]}...")

    # Check current database and user
    cursor.execute("SELECT current_database(), current_user")
    db, user = cursor.fetchone()
    print(f"Database: {db}")
    print(f"User: {user}")

    # Check if this is a writer or reader
    cursor.execute("SELECT pg_is_in_recovery()")
    is_replica = cursor.fetchone()[0]
    role = "replica (reader)" if is_replica else "primary (writer)"
    print(f"Role: {role}")

    cursor.close()
    conn.close()
    print("Connection closed.")

except psycopg2.OperationalError as e:
    print(f"Connection failed: {e}")
    sys.exit(1)
```

### Step 3 - Run the Script

Set environment variables and run:

```bash
export RDS_HOST="suta-rds-lab.abc123.us-east-1.rds.amazonaws.com"
export RDS_PASS="your_password_here"
python3 /tmp/rds_connect.py
```

Expected output:
```
Connected successfully!
PostgreSQL version: PostgreSQL 16.6 on aarch64-unknown-linux-gnu, compiled by aarch64...
Database: labdb
User: postgres
Role: primary (writer)
Connection closed.
```

### Step 4 - Insert and Query Data from Python

Add this to your script after the connection check, or create a new file `/tmp/rds_data.py`:

```python
import psycopg2
import os

conn = psycopg2.connect(
    host=os.environ["RDS_HOST"],
    port=5432,
    dbname="labdb",
    user="postgres",
    password=os.environ["RDS_PASS"],
    sslmode="require"
)

cursor = conn.cursor()

# Create a table
cursor.execute("""
    CREATE TABLE IF NOT EXISTS python_test (
        id SERIAL PRIMARY KEY,
        message TEXT NOT NULL,
        inserted_at TIMESTAMPTZ DEFAULT NOW()
    )
""")

# Insert using parameterized query (safe - never use string formatting for SQL)
messages = [
    ("Hello from psycopg2",),
    ("Parameterized queries prevent SQL injection",),
    ("Always use %s placeholders",),
]
cursor.executemany(
    "INSERT INTO python_test (message) VALUES (%s)",
    messages
)

# Commit the transaction
conn.commit()
print(f"Inserted {len(messages)} rows.")

# Read back
cursor.execute("SELECT id, message, inserted_at FROM python_test ORDER BY id")
rows = cursor.fetchall()
for row in rows:
    print(f"  {row[0]}: {row[1]}")

cursor.close()
conn.close()
```

Run it:

```bash
python3 /tmp/rds_data.py
```

Expected output:
```
Inserted 3 rows.
  1: Hello from psycopg2
  2: Parameterized queries prevent SQL injection
  3: Always use %s placeholders
```

> **Concept:** Always use parameterized queries (`%s` placeholders in psycopg2). Never build SQL strings by concatenating user input. SQL injection can destroy your database or expose all your data.

---

## Part D - The Master User and rds_superuser

### What Can the Master User Do?

When you created the RDS instance, you set a master username (`postgres`). This user is powerful but NOT a true PostgreSQL superuser.

Connect with psql and check:

```bash
psql -h $RDS_ENDPOINT -U postgres -d labdb
```

Check superuser status:

```sql
SELECT rolname, rolsuper FROM pg_roles WHERE rolname = 'postgres';
```

Expected output:
```
 rolname  | rolsuper
----------+----------
 postgres | f
(1 row)
```

`rolsuper = f` - not a superuser.

Check what roles this user has:

```sql
SELECT r.rolname AS member_of
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.roleid
WHERE m.member = (SELECT oid FROM pg_roles WHERE rolname = 'postgres');
```

Expected output:
```
      member_of
---------------------
 rds_superuser
 rds_replication
 rds_password
(3 rows)
```

The master user is a member of:
- `rds_superuser` - almost-superuser privileges
- `rds_replication` - can set up logical replication
- `rds_password` - can change passwords

### What rds_superuser Can and Cannot Do

```sql
-- What rds_superuser CAN do:

-- Create databases
CREATE DATABASE myapp;

-- Create users
CREATE USER appuser WITH PASSWORD 'strongpassword';

-- Grant roles
GRANT rds_superuser TO appuser;

-- Use pg_stat_statements, pg_stat_activity
SELECT count(*) FROM pg_stat_activity;

-- Create most extensions
CREATE EXTENSION pg_stat_statements;
```

```sql
-- What rds_superuser CANNOT do:

-- Read password hashes (you'll get an error)
SELECT passwd FROM pg_shadow;

-- Read arbitrary files from the server filesystem
SELECT pg_read_file('/etc/passwd');

-- Load custom C extensions not approved by AWS
CREATE EXTENSION some_custom_extension;
```

These restrictions exist because RDS is a shared managed service. AWS needs to maintain control of the underlying host.

### Creating an App User (Best Practice)

Do not use the master user for your application. Create a dedicated user:

```sql
-- Create an application user
CREATE USER appuser WITH PASSWORD 'AppSecurePassword123!';

-- Create the application database
CREATE DATABASE myapp OWNER appuser;

-- Connect to the app database
\c myapp

-- Grant only the privileges the app needs
GRANT CONNECT ON DATABASE myapp TO appuser;
GRANT USAGE ON SCHEMA public TO appuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;

-- Future tables created by the master user will also be accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO appuser;
```

Exit psql:
```sql
\q
```

Test logging in as the new user:

```bash
psql -h $RDS_ENDPOINT -U appuser -d myapp -p 5432
```

---

## Part E - SSL Connection Verification

By default, RDS connections use SSL. You can verify this and enforce certificate verification.

### Step 1 - Download the AWS Certificate Bundle

```bash
curl -o /tmp/global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Expected output:
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  177k  100  177k    0     0   312k      0 --:--:-- --:--:-- --:--:--  312k
```

### Step 2 - Connect with Certificate Verification

```bash
psql "host=$RDS_ENDPOINT \
      port=5432 \
      dbname=labdb \
      user=postgres \
      sslmode=verify-full \
      sslrootcert=/tmp/global-bundle.pem"
```

Expected output:
```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

labdb=>
```

The SSL line confirms you are connected securely.

Inside psql, verify SSL details:

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:
```
 ssl | version |             cipher
-----+---------+--------------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

### Step 3 - Force SSL at the Database Level (Production Practice)

In production, you want to ensure ALL connections use SSL. You can enforce this at the parameter group level by setting `rds.force_ssl = 1`.

Check current setting:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" \
  --output text
```

Expected output:
```
default.postgres16
```

To force SSL, you would create a custom parameter group, set `rds.force_ssl = 1`, and apply it to the instance. This is covered in a later tier.

---

## Summary

| Client | Use Case | Key Flag/Setting |
|--------|---------|-----------------|
| psql | Quick queries, DBA tasks, scripting | `-h endpoint -U user -d db` |
| pgAdmin | Visual browsing, query development, ERDs | SSL mode: Require |
| psycopg2 | Python applications and scripts | `sslmode="require"`, use %s placeholders |
| master user | Initial setup only | Member of rds_superuser, not true superuser |
| app user | All application connections | Least privilege - only grant what the app needs |
| SSL | All connections | Use verify-full in production with the AWS cert bundle |

**Tier 1 build guides complete.** Move to the USE exercises to practice without step-by-step guidance.
