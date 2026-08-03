# BUILD 01: Connecting to PostgreSQL with Python

**Module:** 00c - Python DBA Automation
**Prerequisites:** Module 00a (Python Basics), Module 00b (Data Structures), a running PostgreSQL instance
**Time:** 45-60 minutes

You have been connecting to PostgreSQL with `psql` for years. Now you will do it from Python. Same database, same queries - just a different client. By the end of this guide, you will connect to PostgreSQL, run queries, and fetch results - all from Python code.

---

## Step 1: Install psycopg2

psycopg2 is the standard PostgreSQL adapter for Python. It has been around since 2001 and is used by virtually every Python application that talks to Postgres. The `-binary` variant includes pre-compiled C libraries so you do not need `pg_config` or development headers on your machine.

Run:

```bash
pip3 install psycopg2-binary
```

Expected output (yours will differ):

```
Collecting psycopg2-binary
  Downloading psycopg2_binary-2.9.9-cp311-cp311-linux_x86_64.whl (3.0 MB)
Installing collected packages: psycopg2-binary
Successfully installed psycopg2-binary-2.9.9
```

Verify it installed:

```bash
python3 -c "import psycopg2; print(psycopg2.__version__)"
```

Expected output (yours will differ):

```
2.9.9 (dt dec pq3 ext lo64)
```

---

## Step 2: Your First Connection

**DBA Analogy:** `psycopg2.connect()` is like typing `psql -h localhost -p 5432 -U postgres -d postgres`. It opens a session to the server. The connection object IS your session.

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(
    host='localhost',
    port=5432,
    dbname='postgres',
    user='postgres',
    password='your_password_here'
)
print('Connected! Server version:', conn.server_version)
conn.close()
"
```

Expected output (yours will differ):

```
Connected! Server version: 160004
```

The `server_version` is an integer - `160004` means 16.4. Just like `SELECT version()` but as a number.

**Key point:** Always call `conn.close()` when you are done. An unclosed connection stays open on the server - just like a `psql` session you forgot to quit. We will learn a better pattern (the `with` statement) in Step 8.

---

## Step 3: Connection Parameters

Here are the parameters you already know from `psql` and `libpq`:

| Parameter  | Default     | psql Equivalent        |
|------------|-------------|------------------------|
| `host`     | localhost   | `-h` or `PGHOST`       |
| `port`     | 5432        | `-p` or `PGPORT`       |
| `dbname`   | same as user| `-d` or `PGDATABASE`   |
| `user`     | OS user     | `-U` or `PGUSER`       |
| `password` | none        | `PGPASSWORD`           |
| `sslmode`  | prefer      | `sslmode` in conninfo  |

You can also pass a full connection string:

```python
conn = psycopg2.connect("host=localhost port=5432 dbname=postgres user=postgres")
```

Or a URI:

```python
conn = psycopg2.connect("postgresql://postgres:password@localhost:5432/postgres")
```

Same formats you use in `pg_hba.conf` debugging and `primary_conninfo`. Nothing new here.

---

## Step 4: Using Environment Variables for Credentials

**NEVER hardcode passwords in scripts.** This is the same rule you follow with `.pgpass` - you do not put passwords in shell scripts, and you do not put them in Python scripts either.

Python reads environment variables with `os.environ`:

```bash
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD=your_password_here
```

Now connect without any hardcoded values:

```bash
python3 -c "
import os
import psycopg2

conn = psycopg2.connect(
    host=os.environ['PGHOST'],
    port=os.environ['PGPORT'],
    dbname=os.environ['PGDATABASE'],
    user=os.environ['PGUSER'],
    password=os.environ['PGPASSWORD']
)
print('Connected to', os.environ['PGDATABASE'], 'as', os.environ['PGUSER'])
conn.close()
"
```

Expected output (yours will differ):

```
Connected to postgres as postgres
```

**Bonus:** psycopg2 actually reads the standard `PG*` environment variables automatically if you do not pass parameters. So this also works:

```python
conn = psycopg2.connect()  # reads PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
```

Just like `psql` with no arguments picks up your environment.

---

## Step 5: The Cursor Object

**DBA Analogy:** You already know what a cursor is. In PL/pgSQL, you declare a cursor, open it, fetch rows from it, and close it. psycopg2 cursors work the same way.

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(dbname='postgres', user='postgres')
cur = conn.cursor()

cur.execute('SELECT datname, pg_database_size(datname) FROM pg_database WHERE datistemplate = false')

rows = cur.fetchall()
for row in rows:
    print(f'{row[0]}: {row[1]} bytes')

cur.close()
conn.close()
"
```

Expected output (yours will differ):

```
postgres: 7987123 bytes
mydb: 12345678 bytes
```

The flow is exactly what you do in psql:
1. Open a connection (like starting `psql`)
2. Create a cursor (psql does this implicitly)
3. Execute a query (`cur.execute()` = typing SQL and hitting Enter)
4. Fetch the results (`cur.fetchall()` = seeing the result set)
5. Close cursor and connection (like `\q`)

---

## Step 6: Fetching Results - fetchone, fetchall, fetchmany

**DBA Analogy:** These map directly to the FETCH command you use with PL/pgSQL cursors.

| Python Method      | PL/pgSQL Equivalent      | Use When                          |
|--------------------|--------------------------|-----------------------------------|
| `fetchone()`       | `FETCH NEXT FROM cur`    | You expect 1 row or process one at a time |
| `fetchall()`       | `FETCH ALL FROM cur`     | Result set is small (fits in memory) |
| `fetchmany(size)`  | `FETCH 100 FROM cur`     | Large result set, batch processing |

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(dbname='postgres', user='postgres')
cur = conn.cursor()

# fetchone - get one row
cur.execute('SELECT version()')
row = cur.fetchone()
print('Version:', row[0])

# fetchall - get all rows
cur.execute('SELECT datname FROM pg_database WHERE datistemplate = false')
rows = cur.fetchall()
print('Databases:', [r[0] for r in rows])

# fetchmany - get N rows at a time
cur.execute('SELECT schemaname, tablename FROM pg_tables')
batch = cur.fetchmany(5)
print('First 5 tables:', [r[1] for r in batch])

cur.close()
conn.close()
"
```

Expected output (yours will differ):

```
Version: PostgreSQL 16.4 on x86_64-pc-linux-gnu, compiled by gcc ...
Databases: ['postgres', 'mydb']
First 5 tables: ['pg_statistic', 'pg_type', 'pg_foreign_table', 'pg_authid', 'pg_shadow']
```

**When it matters:** If you query `pg_stat_activity` on a busy server, `fetchall()` is fine - maybe a few hundred rows. But if you SELECT from a 100-million-row table, `fetchall()` will try to load all 100 million rows into Python's memory. Use `fetchmany()` or iterate the cursor instead.

---

## Step 7: Parameterized Queries - CRITICAL Security

**DBA Analogy:** Parameterized queries in psycopg2 are exactly like prepared statements. When you write `PREPARE stmt AS SELECT * FROM users WHERE id = $1` and then `EXECUTE stmt(42)`, the database knows `42` is a value, not SQL code. psycopg2 does the same thing with `%s` placeholders.

The safe way:

```python
cur.execute("SELECT * FROM pg_database WHERE datname = %s", ('mydb',))
```

The `%s` is a placeholder. psycopg2 sends the query and the parameter separately to PostgreSQL. The value can NEVER be interpreted as SQL.

**NEVER do this:**

```python
# DANGEROUS - SQL INJECTION
dbname = input("Enter database name: ")
cur.execute(f"SELECT * FROM pg_database WHERE datname = '{dbname}'")
```

Here is why. Imagine someone enters: `'; DROP TABLE important_data; --`

The query becomes:

```sql
SELECT * FROM pg_database WHERE datname = ''; DROP TABLE important_data; --'
```

That is SQL injection. The attacker just dropped your table.

**Demo - see the difference:**

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(dbname='postgres', user='postgres')
cur = conn.cursor()

# SAFE - parameterized
evil_input = \"'; DROP TABLE students; --\"
cur.execute('SELECT datname FROM pg_database WHERE datname = %s', (evil_input,))
print('Safe query returned:', cur.fetchall())
# Returns empty list - the evil string was treated as a literal value

# What the UNSAFE version would have sent:
unsafe_query = f\"SELECT datname FROM pg_database WHERE datname = '{evil_input}'\"
print('Unsafe query would be:', unsafe_query)
# Shows the SQL injection in the query text

cur.close()
conn.close()
"
```

Expected output (yours will differ):

```
Safe query returned: []
Unsafe query would be: SELECT datname FROM pg_database WHERE datname = ''; DROP TABLE students; --'
```

**Rules for parameterized queries:**
- Always use `%s` placeholders (even for integers - psycopg2 handles the type)
- Always pass parameters as a tuple: `(value,)` - note the trailing comma for single values
- NEVER use f-strings, `.format()`, or `+` concatenation to build SQL
- For `IN` clauses, use a tuple: `cur.execute("SELECT ... WHERE id IN %s", ((1,2,3),))`

---

## Step 8: The `with` Pattern - Auto-Closing Connections

**DBA Analogy:** Think of `with` as a transaction block that automatically handles cleanup. Like `BEGIN ... COMMIT/ROLLBACK` but for the connection itself.

Without `with`, you must remember to close:

```python
conn = psycopg2.connect(...)
cur = conn.cursor()
try:
    cur.execute("SELECT 1")
    result = cur.fetchone()
finally:
    cur.close()
    conn.close()
```

With `with`, Python auto-closes for you:

```python
with psycopg2.connect(...) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        result = cur.fetchone()
# Connection commits and cursor closes automatically here
```

**Important psycopg2 detail:** When you use `with` on a connection, exiting the block does a COMMIT if there was no exception, or a ROLLBACK if there was one. It does NOT close the connection. For full auto-close, combine `with` and explicit close, or use this pattern:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(dbname='postgres', user='postgres')
try:
    with conn:
        with conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM pg_stat_activity')
            count = cur.fetchone()[0]
            print(f'Active connections: {count}')
            # Auto-COMMIT happens here if no exception
            # Auto-ROLLBACK happens here if exception
finally:
    conn.close()  # Always close the connection
    print('Connection closed')
"
```

Expected output (yours will differ):

```
Active connections: 5
Connection closed
```

---

## Step 9: Connection as Context Manager - The Clean Pattern

For scripts where you connect, do work, and disconnect, this is the cleanest pattern:

```bash
python3 -c "
import psycopg2
from contextlib import closing

# closing() adds the .close() call that psycopg2's 'with' skips
with closing(psycopg2.connect(dbname='postgres', user='postgres')) as conn:
    with conn.cursor() as cur:
        cur.execute('SELECT datname, pg_database_size(datname) as size FROM pg_database WHERE datistemplate = false ORDER BY size DESC')
        for row in cur:
            size_mb = row[1] / (1024 * 1024)
            print(f'{row[0]}: {size_mb:.1f} MB')
# Connection is fully closed here - no leak possible
print('Done - connection fully closed')
"
```

Expected output (yours will differ):

```
mydb: 11.8 MB
postgres: 7.6 MB
Done - connection fully closed
```

Notice `for row in cur:` - you can iterate directly over the cursor. This is more memory-efficient than `fetchall()` because it fetches rows one at a time.

---

## Step 10: Practical - Connect and List All Databases

Let us put it all together. Create a script that connects to your local PostgreSQL and lists all databases with their sizes.

Open a new file with `vi`:

```bash
vi ~/list_databases.py
```

Enter the following content:

```python
#!/usr/bin/env python3
"""List all PostgreSQL databases with sizes."""

import os
import sys
import psycopg2
from contextlib import closing


def get_connection():
    """Create a database connection using environment variables."""
    try:
        conn = psycopg2.connect(
            host=os.environ.get('PGHOST', 'localhost'),
            port=os.environ.get('PGPORT', '5432'),
            dbname=os.environ.get('PGDATABASE', 'postgres'),
            user=os.environ.get('PGUSER', 'postgres'),
            password=os.environ.get('PGPASSWORD', '')
        )
        return conn
    except psycopg2.OperationalError as e:
        print(f"ERROR: Could not connect to PostgreSQL: {e}")
        sys.exit(1)


def list_databases(conn):
    """Query and display all non-template databases."""
    query = """
        SELECT
            d.datname,
            pg_database_size(d.datname) as size_bytes,
            pg_size_pretty(pg_database_size(d.datname)) as size_pretty,
            r.rolname as owner,
            d.datconnlimit as conn_limit
        FROM pg_database d
        JOIN pg_roles r ON d.datdba = r.oid
        WHERE d.datistemplate = false
        ORDER BY pg_database_size(d.datname) DESC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        rows = cur.fetchall()

    print(f"{'Database':<25} {'Size':<12} {'Owner':<15} {'Conn Limit':<10}")
    print("-" * 62)
    for row in rows:
        datname, size_bytes, size_pretty, owner, conn_limit = row
        limit_str = str(conn_limit) if conn_limit != -1 else "unlimited"
        print(f"{datname:<25} {size_pretty:<12} {owner:<15} {limit_str:<10}")

    print(f"\nTotal databases: {len(rows)}")


def main():
    with closing(get_connection()) as conn:
        list_databases(conn)


if __name__ == '__main__':
    main()
```

Save and exit vi (`:wq`), then run:

```bash
python3 ~/list_databases.py
```

Expected output (yours will differ):

```
Database                  Size         Owner           Conn Limit
--------------------------------------------------------------
mydb                      12 MB        postgres        unlimited
postgres                  7761 kB      postgres        unlimited

Total databases: 2
```

---

## What You Learned

| Concept                    | DBA Analogy                              | Python Code                              |
|----------------------------|------------------------------------------|------------------------------------------|
| Install psycopg2           | Installing a client driver               | `pip3 install psycopg2-binary`           |
| Connect to PostgreSQL      | Opening `psql`                           | `psycopg2.connect(host=..., dbname=...)` |
| Environment variables      | `.pgpass` / `PGPASSWORD`                 | `os.environ['PGHOST']`                   |
| Cursor object              | PL/pgSQL `DECLARE cur CURSOR`            | `conn.cursor()`                          |
| Execute a query            | Typing SQL in psql                       | `cur.execute("SELECT ...")`              |
| fetchone / fetchall        | `FETCH NEXT` / `FETCH ALL`              | `cur.fetchone()` / `cur.fetchall()`      |
| Parameterized queries      | `PREPARE` + `EXECUTE` with `$1`         | `cur.execute("... %s", (val,))`          |
| NEVER use f-strings in SQL | NEVER use string concatenation in SQL    | SQL injection risk                       |
| `with` statement           | Auto `COMMIT`/`ROLLBACK` block           | `with conn:` / `with conn.cursor() as c:`|
| `closing()` wrapper        | Guarantees connection closes             | `from contextlib import closing`         |
