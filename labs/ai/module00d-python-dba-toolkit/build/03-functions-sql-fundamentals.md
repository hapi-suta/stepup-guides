# BUILD 03: Functions - SQL Runner

**What you will build:** `~/pgdba/sql_runner.py` - a library of reusable functions that connect to PostgreSQL and run queries. By the end you will be able to call `get_version()`, `get_database_list()`, and `get_table_sizes()` from a single script.

**Python concepts covered:** def, parameters, return, default parameters, multiple return values, docstrings, scope

**Time to complete:** ~50 minutes

---

## Prerequisites

- BUILD 01 and BUILD 02 complete
- PostgreSQL running on localhost:5432
- `psycopg2` installed (the standard PostgreSQL adapter for Python)

---

## Step 0: Install psycopg2

`psycopg2` is to Python what `libpq` is to C - the official PostgreSQL client library. `psycopg2-binary` bundles the shared library so you do not need to compile anything.

On your **Mac terminal**, as your **normal user**:

```bash
pip3 install psycopg2-binary
```

Verify the install:

```bash
python3 -c "import psycopg2; print(psycopg2.__version__)"
```

Expected output (yours will differ):

```
2.9.9 (dt dec pq3 ext lo64)
```

---

## Step 1: def - define a reusable function

In PL/pgSQL you write `CREATE OR REPLACE FUNCTION my_func() RETURNS void AS $$ ... $$ LANGUAGE plpgsql`. In Python, `def function_name():` does the same thing - it defines a named block of code you can call later. No `CREATE`, no `LANGUAGE`, no `$$` delimiters.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def greet_dba():
    print('Hello from a Python function')
    print('This runs every time greet_dba() is called')

# Define it once, call it multiple times
greet_dba()
greet_dba()
"
```

What this does:
- `def greet_dba():` - declares the function named `greet_dba` with no parameters
- The indented block (4 spaces) is the function body - equivalent to the `$$ ... $$` block in PL/pgSQL
- `greet_dba()` on an unindented line calls the function

Expected output (yours will differ):

```
Hello from a Python function
This runs every time greet_dba() is called
Hello from a Python function
This runs every time greet_dba() is called
```

---

## Step 2: Parameters - pass values into a function

In PL/pgSQL, `CREATE FUNCTION check_db(p_dbname TEXT)` defines a parameter. In Python, you list parameter names inside the parentheses of `def`. No type declaration required - Python is dynamically typed.

On your **Mac terminal**:

```bash
python3 -c "
def check_database(dbname, host):
    print(f'Checking database: {dbname} on host: {host}')
    print(f'Connection string would be: host={host} dbname={dbname}')

check_database('postgres', 'localhost')
check_database('myapp_prod', 'db-primary-01')
"
```

What this does:
- `def check_database(dbname, host):` - defines two parameters, `dbname` and `host`
- When you call `check_database('postgres', 'localhost')`, Python maps `'postgres'` to `dbname` and `'localhost'` to `host` by position - exactly like positional parameters in PL/pgSQL

Expected output (yours will differ):

```
Checking database: postgres on host: localhost
Connection string would be: host=localhost dbname=postgres
Checking database: myapp_prod on host: db-primary-01
Connection string would be: host=db-primary-01 dbname=myapp_prod
```

---

## Step 3: return - send a value back to the caller

In PL/pgSQL, `RETURN my_value;` sends a value back from a function. In Python, `return value` does the same thing. The calling code receives whatever you return and can store it in a variable.

On your **Mac terminal**:

```bash
python3 -c "
def build_dsn(host, port, dbname, user):
    dsn = f'host={host} port={port} dbname={dbname} user={user}'
    return dsn

# The returned value is stored in the variable 'connection_string'
connection_string = build_dsn('localhost', 5432, 'postgres', 'postgres')
print(connection_string)
print(type(connection_string))
"
```

What this does:
- `return dsn` - sends the string back to the caller
- `connection_string = build_dsn(...)` - the caller stores the returned value
- A function without a `return` statement returns `None` (like a PL/pgSQL `RETURNS void` function)

Expected output (yours will differ):

```
host=localhost port=5432 dbname=postgres user=postgres
<class 'str'>
```

---

## Step 4: Default parameters - optional arguments with fallback values

In PL/pgSQL you write `CREATE FUNCTION connect(p_host TEXT DEFAULT 'localhost')`. In Python, you assign defaults in the function signature with `=`. If the caller does not pass that argument, the default is used automatically.

On your **Mac terminal**:

```bash
python3 -c "
def build_dsn(dbname, host='localhost', port=5432, user='postgres'):
    return f'host={host} port={port} dbname={dbname} user={user}'

# Use all defaults
print(build_dsn('postgres'))

# Override only the dbname and user
print(build_dsn('myapp', user='app_user'))

# Override everything
print(build_dsn('myapp', host='db-primary-01', port=5433, user='app_user'))
"
```

What this does:
- `host='localhost'` in the def line sets the default value
- Required parameters (`dbname`) must come BEFORE parameters with defaults - same rule as PL/pgSQL
- You can pass arguments by name (keyword arguments) to skip optional ones: `build_dsn('myapp', user='app_user')`

Expected output (yours will differ):

```
host=localhost port=5432 dbname=postgres user=postgres
host=localhost port=5432 dbname=myapp user=app_user
host=db-primary-01 port=5433 dbname=myapp user=app_user
```

---

## Step 5: Multiple return values - like OUT parameters or RETURNS TABLE

In PL/pgSQL you use `OUT` parameters or `RETURNS TABLE` to return multiple values. Python can return multiple values separated by commas. The caller receives them as a tuple (an ordered, immutable list).

On your **Mac terminal**:

```bash
python3 -c "
import time

def run_timed_query(label):
    # Simulate query execution time
    start = time.time()
    time.sleep(0.05)   # pretend this is a real query
    end = time.time()

    duration_ms = (end - start) * 1000
    row_count = 42   # pretend we got 42 rows back

    # Return two values - like RETURNS TABLE(row_count INT, duration_ms NUMERIC)
    return row_count, duration_ms

# Unpack both return values in one line
rows, ms = run_timed_query('SELECT count(*) FROM pg_stat_activity')
print(f'Rows returned: {rows}')
print(f'Duration:      {ms:.2f} ms')
"
```

What this does:
- `return row_count, duration_ms` - returns a tuple of two values
- `rows, ms = run_timed_query(...)` - tuple unpacking assigns each value to its own variable in one line
- This is cleaner than building a dict or object just to return two scalars

Expected output (yours will differ):

```
Rows returned: 42
Duration:      50.23 ms
```

---

## Step 6: Docstrings - document your functions

In PostgreSQL you use `COMMENT ON FUNCTION my_func() IS 'what it does';`. In Python, a docstring is a string literal on the first line inside the function body. It documents what the function does, its parameters, and what it returns. Tools like `help()` display it automatically.

On your **Mac terminal**:

```bash
python3 -c "
def run_query(query, host='localhost', port=5432, dbname='postgres', user=None):
    '''
    Execute a SQL query against a PostgreSQL instance and return the results.

    Parameters:
        query (str): The SQL statement to execute.
        host (str):  Database host. Default: localhost.
        port (int):  Database port. Default: 5432.
        dbname (str): Database name. Default: postgres.
        user (str):  Database user. Default: None (auto-detected via getpass.getuser()).

    Returns:
        list: A list of tuples, one per row returned.
    '''
    pass   # implementation comes in Step 7

help(run_query)
"
```

What this does:
- Triple-quoted string `''' ... '''` on the first line of the function body becomes the docstring
- `pass` is a no-op placeholder - it tells Python the function body is intentionally empty for now (like `NULL;` in a stub PL/pgSQL function)
- `help(run_query)` prints the docstring in a formatted way

Expected output (yours will differ):

```
Help on function run_query in module __main__:

run_query(query, host='localhost', port=5432, dbname='postgres', user=None)
    Execute a SQL query against a PostgreSQL instance and return the results.
    ...
```

---

## Step 7: Build run_query() - connect and execute with psycopg2

Now build the real implementation. psycopg2 uses a connection object (like a session handle) and a cursor (like a portal in PostgreSQL's wire protocol).

> **Mac Homebrew note:** On Mac with Homebrew PostgreSQL, the default superuser is your Mac username (e.g. `hafopezi`), not `postgres`. Connecting with `user='postgres'` will fail with "role 'postgres' does not exist". We use `getpass.getuser()` to auto-detect your Mac username so the same code works for everyone.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import getpass

def run_query(query, params=None, host='localhost', port=5432, dbname='postgres', user=None):
    '''
    Execute a SQL query and return (rows, column_names, duration_ms).

    Parameters:
        query (str):       SQL to execute.
        params (tuple):    Query parameters for parameterized queries. Default: None.
        host/port/dbname/user: Connection details with sensible defaults.

    Returns:
        tuple: (rows, col_names, duration_ms)
    '''
    import time
    user = user or getpass.getuser()

    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user)
    cur = conn.cursor()

    start = time.time()
    cur.execute(query, params)
    rows = cur.fetchall()
    duration_ms = (time.time() - start) * 1000

    col_names = [desc[0] for desc in cur.description] if cur.description else []

    cur.close()
    conn.close()

    return rows, col_names, duration_ms

rows, cols, ms = run_query('SELECT version()')
print(f'Columns:  {cols}')
print(f'Result:   {rows[0][0][:60]}...')
print(f'Duration: {ms:.2f} ms')
"
```

What each piece does:
- `psycopg2.connect(...)` - opens a connection (equivalent to `\c dbname` in psql)
- `conn.cursor()` - creates a cursor to send commands (like a portal or prepared statement handle)
- `cur.execute(query, params)` - runs the query; passing `params` as a separate argument uses server-side parameterization (safe from SQL injection, same as using `$1, $2` in PL/pgSQL)
- `cur.fetchall()` - retrieves all rows as a list of tuples
- `cur.description` - metadata about the result columns (name, type code, etc.)
- `[desc[0] for desc in cur.description]` - list comprehension that extracts just the column names

Expected output (yours will differ):

```
Columns:  ['version']
Result:   PostgreSQL 16.3 on aarch64-apple-darwin23.4.0, compiled by Apple clang...
Duration: 3.47 ms
```

---

## Step 8: Build get_version()

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import getpass

def run_query(query, params=None, host='localhost', port=5432, dbname='postgres', user=None):
    import time
    user = user or getpass.getuser()
    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user)
    cur = conn.cursor()
    start = time.time()
    cur.execute(query, params)
    rows = cur.fetchall()
    duration_ms = (time.time() - start) * 1000
    col_names = [desc[0] for desc in cur.description] if cur.description else []
    cur.close()
    conn.close()
    return rows, col_names, duration_ms


def get_version(host='localhost', port=5432):
    '''Return the PostgreSQL server version string.'''
    rows, _, _ = run_query('SELECT version()', host=host, port=port)
    return rows[0][0]


version = get_version()
print(f'Server version: {version}')
"
```

What this does: `get_version()` wraps `run_query()` and extracts just the version string. `rows[0][0]` means: first row (`rows[0]`), first column (`[0]`). This is the same idea as `SELECT version()` returning a single cell.

Expected output (yours will differ):

```
Server version: PostgreSQL 16.3 on aarch64-apple-darwin23.4.0, compiled by Apple clang version 15.0.0 (clang-1500.3.9.4), 64-bit
```

---

## Step 9: Build get_database_list()

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import getpass

def run_query(query, params=None, host='localhost', port=5432, dbname='postgres', user=None):
    import time
    user = user or getpass.getuser()
    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user)
    cur = conn.cursor()
    start = time.time()
    cur.execute(query, params)
    rows = cur.fetchall()
    duration_ms = (time.time() - start) * 1000
    col_names = [desc[0] for desc in cur.description] if cur.description else []
    cur.close()
    conn.close()
    return rows, col_names, duration_ms


def get_database_list(host='localhost', port=5432):
    '''Return a list of databases with their sizes.'''
    query = '''
        SELECT datname,
               pg_size_pretty(pg_database_size(datname)) AS size,
               datallowconn
        FROM pg_database
        WHERE datname NOT IN ('template0', 'template1')
        ORDER BY pg_database_size(datname) DESC
    '''
    rows, col_names, _ = run_query(query, host=host, port=port)
    return rows, col_names


rows, cols = get_database_list()
print(f'{cols[0]:<20} {cols[1]:<12} {cols[2]}')
print('-' * 40)
for row in rows:
    print(f'{row[0]:<20} {row[1]:<12} {row[2]}')
"
```

Expected output (yours will differ):

```
datname              size         datallowconn
----------------------------------------
postgres             8609 kB      True
myapp_dev            3421 kB      True
```

---

## Step 10: Build get_table_sizes()

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import getpass

def run_query(query, params=None, host='localhost', port=5432, dbname='postgres', user=None):
    import time
    user = user or getpass.getuser()
    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user)
    cur = conn.cursor()
    start = time.time()
    cur.execute(query, params)
    rows = cur.fetchall()
    duration_ms = (time.time() - start) * 1000
    col_names = [desc[0] for desc in cur.description] if cur.description else []
    cur.close()
    conn.close()
    return rows, col_names, duration_ms


def get_table_sizes(dbname='postgres', schema='public', host='localhost', port=5432, top_n=10):
    '''
    Return the top N largest tables in a schema by total size.

    Parameters:
        dbname (str):  Database to inspect. Default: postgres.
        schema (str):  Schema to filter. Default: public.
        host/port:     Connection details.
        top_n (int):   How many tables to return. Default: 10.

    Returns:
        tuple: (rows, col_names)
    '''
    query = '''
        SELECT schemaname,
               tablename,
               pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
               pg_size_pretty(pg_relation_size(schemaname || '.' || tablename))       AS table_size,
               pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)
                              - pg_relation_size(schemaname || '.' || tablename))     AS index_size
        FROM pg_tables
        WHERE schemaname = %s
        ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
        LIMIT %s
    '''
    rows, col_names, _ = run_query(query, params=(schema, top_n), dbname=dbname, host=host, port=port)
    return rows, col_names


rows, cols = get_table_sizes()
if rows:
    header = f'{cols[1]:<30} {cols[2]:<12} {cols[3]:<12} {cols[4]}'
    print(header)
    print('-' * 65)
    for row in rows:
        print(f'{row[1]:<30} {row[2]:<12} {row[3]:<12} {row[4]}')
else:
    print('No tables found in public schema (that is OK for a fresh install)')
"
```

What this does: `params=(schema, top_n)` passes the schema name and limit as bind parameters - psycopg2 maps them to `%s` placeholders using server-side parameterization. This is identical to using `$1, $2` in a prepared statement.

Expected output (yours will differ):

```
tablename                      total_size   table_size   index_size
-----------------------------------------------------------------
orders                         142 MB       98 MB        44 MB
customers                      38 MB        22 MB        16 MB
```

---

## Step 11: Combine everything into sql_runner.py

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/sql_runner.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
"""
sql_runner.py - Reusable SQL query functions for PostgreSQL DBA work.
Uses psycopg2. Install with: pip3 install psycopg2-binary
"""

import time
import getpass
import psycopg2

# -------------------------------------------------------
# Connection defaults - change to match your environment
# -------------------------------------------------------
DEFAULT_HOST   = 'localhost'
DEFAULT_PORT   = 5432
DEFAULT_DBNAME = 'postgres'
DEFAULT_USER   = getpass.getuser()  # auto-detects your Mac username


def run_query(
    query,
    params=None,
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    dbname=DEFAULT_DBNAME,
    user=DEFAULT_USER,
):
    """
    Execute a SQL query and return (rows, col_names, duration_ms).

    Parameters:
        query (str):   SQL to execute.
        params (tuple): Bind parameters (%s placeholders). Default: None.
        host, port, dbname, user: Connection details.

    Returns:
        tuple: (rows, col_names, duration_ms)
            rows (list of tuples): One tuple per result row.
            col_names (list of str): Column names from cursor.description.
            duration_ms (float): Query wall-clock time in milliseconds.
    """
    conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user)
    cur = conn.cursor()

    start = time.time()
    cur.execute(query, params)
    rows = cur.fetchall()
    duration_ms = (time.time() - start) * 1000

    col_names = [desc[0] for desc in cur.description] if cur.description else []

    cur.close()
    conn.close()

    return rows, col_names, duration_ms


def get_version(host=DEFAULT_HOST, port=DEFAULT_PORT):
    """Return the PostgreSQL server version string."""
    rows, _, _ = run_query('SELECT version()', host=host, port=port)
    return rows[0][0]


def get_database_list(host=DEFAULT_HOST, port=DEFAULT_PORT):
    """
    Return databases with their sizes (excludes templates).

    Returns:
        tuple: (rows, col_names)
    """
    query = """
        SELECT datname,
               pg_size_pretty(pg_database_size(datname)) AS size,
               datallowconn
        FROM pg_database
        WHERE datname NOT IN ('template0', 'template1')
        ORDER BY pg_database_size(datname) DESC
    """
    rows, col_names, _ = run_query(query, host=host, port=port)
    return rows, col_names


def get_table_sizes(
    dbname=DEFAULT_DBNAME,
    schema='public',
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    top_n=10,
):
    """
    Return the top N largest tables in a schema by total size.

    Parameters:
        dbname (str):  Database to inspect.
        schema (str):  Schema to filter. Default: public.
        top_n (int):   Number of tables to return. Default: 10.

    Returns:
        tuple: (rows, col_names)
    """
    query = """
        SELECT schemaname,
               tablename,
               pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
               pg_size_pretty(pg_relation_size(schemaname || '.' || tablename))       AS table_size,
               pg_size_pretty(
                   pg_total_relation_size(schemaname || '.' || tablename)
                   - pg_relation_size(schemaname || '.' || tablename)
               ) AS index_size
        FROM pg_tables
        WHERE schemaname = %s
        ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
        LIMIT %s
    """
    rows, col_names, _ = run_query(
        query, params=(schema, top_n), dbname=dbname, host=host, port=port
    )
    return rows, col_names


# -------------------------------------------------------
# Main: run a demo when the script is executed directly
# -------------------------------------------------------
if __name__ == '__main__':

    print('=' * 60)
    print('  sql_runner.py - Demo Run')
    print('=' * 60)

    # 1. Server version
    print('\n[1] Server Version')
    print('-' * 40)
    print(get_version())

    # 2. Database list
    print('\n[2] Database List')
    print('-' * 40)
    rows, cols = get_database_list()
    print(f'  {cols[0]:<20} {cols[1]:<12} {cols[2]}')
    for row in rows:
        print(f'  {row[0]:<20} {row[1]:<12} {row[2]}')

    # 3. Table sizes in public schema
    print('\n[3] Table Sizes (public schema, top 5)')
    print('-' * 40)
    rows, cols = get_table_sizes(top_n=5)
    if rows:
        print(f'  {cols[1]:<30} {cols[2]:<12} {cols[3]:<12} {cols[4]}')
        for row in rows:
            print(f'  {row[1]:<30} {row[2]:<12} {row[3]:<12} {row[4]}')
    else:
        print('  No user tables found in public schema.')

    # 4. Custom query
    print('\n[4] Active Connections')
    print('-' * 40)
    rows, cols, ms = run_query("""
        SELECT datname, count(*) AS connections
        FROM pg_stat_activity
        WHERE datname IS NOT NULL
        GROUP BY datname
        ORDER BY connections DESC
    """)
    print(f'  {cols[0]:<20} {cols[1]}')
    for row in rows:
        print(f'  {row[0]:<20} {row[1]}')
    print(f'  (query took {ms:.2f} ms)')

    print('\n' + '=' * 60)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 12: Run the final script

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/sql_runner.py
```

Expected output (yours will differ):

```
============================================================
  sql_runner.py - Demo Run
============================================================

[1] Server Version
----------------------------------------
PostgreSQL 16.3 on aarch64-apple-darwin23.4.0, compiled by Apple clang version 15.0.0, 64-bit

[2] Database List
----------------------------------------
  datname              size         datallowconn
  postgres             8609 kB      True

[3] Table Sizes (public schema, top 5)
----------------------------------------
  No user tables found in public schema.

[4] Active Connections
----------------------------------------
  datname              connections
  postgres             3
  (query took 1.83 ms)

============================================================
```

Now test importing `sql_runner` from a different script (like a module you would `\i` in psql):

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/$(whoami)/pgdba')
import sql_runner
print(sql_runner.get_version())
"
```

Expected output (yours will differ):

```
PostgreSQL 16.3 on aarch64-apple-darwin23.4.0, compiled by Apple clang version 15.0.0, 64-bit
```

---

## What you built

You now have `~/pgdba/sql_runner.py` - a reusable module with four functions you can import into any future DBA script. Every function is documented, has sensible defaults, and uses parameterized queries.

| Python concept          | DBA analogy                                              |
|-------------------------|----------------------------------------------------------|
| `def func():`           | `CREATE OR REPLACE FUNCTION` in PL/pgSQL                |
| Parameters              | Function input parameters in PL/pgSQL                    |
| `return value`          | `RETURN value` in PL/pgSQL                              |
| Default parameters      | `DEFAULT` in PL/pgSQL function signature                |
| Multiple return values  | `OUT` parameters or `RETURNS TABLE` in PL/pgSQL         |
| Docstrings              | `COMMENT ON FUNCTION` in PostgreSQL                     |
| `if __name__ == '__main__':` | Only runs when the file is executed directly, not when imported - like a script guard |
| `psycopg2.connect()`    | Opening a database session / `\c dbname` in psql        |
| `cur.execute(q, params)` | Parameterized query with `$1, $2` bind variables       |
| `cur.fetchall()`        | Fetching all rows from a cursor                         |
| `import sql_runner`     | Reusing the module from another script (like `\i file.sql` in psql) |

Next: BUILD 04 - Data Structures: Connection Pool Manager
