# BUILD 05: Error Handling - User Manager (Users, Roles, Connections)

## What You're Building

By the end of this guide you will have a working script called `user_manager.py` in `~/pgdba/` that creates, alters, and drops PostgreSQL roles with proper error handling. It gracefully handles duplicate role errors, missing roles, active connections, and invalid input - the same problems you hit in real DBA work.

**Python concepts covered:** `try/except`, catching specific exceptions, `except as e`, multiple `except` blocks, `finally`, `raise`

**DBA task:** Automate role lifecycle management with the same safety you'd build into a PL/pgSQL procedure - but in Python, so it runs from your terminal or a cron job.

---

## Prerequisites

- Completed BUILD 03 (psycopg2 connections)
- PostgreSQL running locally
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)

---

## Step 1: try/except Basics

**DBA analogy:** `try/except` in Python is identical in purpose to `BEGIN...EXCEPTION WHEN...END` in PL/pgSQL. The `try` block is your normal code path. The `except` block is your `WHEN OTHERS THEN` handler that catches anything that goes wrong.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import getpass

username = getpass.getuser()
try:
    conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
    print('Connected successfully')
    conn.close()
except Exception as e:
    print('Connection failed:', e)
"
```

- `try:` - everything inside runs normally; if any line raises an error, Python jumps to `except`
- `except Exception as e:` - catch ANY exception and store it in the variable `e`
- `print('Connection failed:', e)` - print the error message the same way you'd use `RAISE NOTICE '%', SQLERRM` in PL/pgSQL

```
Expected output (yours will differ):
Connected successfully
```

Now break it on purpose to see the exception path:

```bash
python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(host='localhost', port=5432, user='nonexistent_user', dbname='postgres')
    print('Connected')
    conn.close()
except Exception as e:
    print('Caught error:', e)
"
```

```
Expected output (yours will differ):
Caught error: FATAL:  role "nonexistent_user" does not exist
```

---

## Step 2: Catching Specific Errors - DuplicateObject

**DBA analogy:** In PL/pgSQL you write `WHEN duplicate_object THEN` to catch a specific SQLSTATE. In Python with psycopg2, you catch `psycopg2.errors.DuplicateObject` - the same SQLSTATE `42710`, just a Python class name instead.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

username = getpass.getuser()
conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute('CREATE ROLE test_py_role LOGIN')
    print('Role created')
except psycopg2.errors.DuplicateObject as e:
    print('Role already exists - caught DuplicateObject')
    print('Error detail:', e)
finally:
    cur.close()
    conn.close()
"
```

- `conn.autocommit = True` - run each SQL statement as its own transaction; without this, a failed statement would block the entire connection
- `psycopg2.errors.DuplicateObject` - a specific exception class that maps to PostgreSQL SQLSTATE `42710`; catching this means you ONLY catch duplicate errors, not all errors
- `finally:` - this block ALWAYS runs, even if an exception occurred; used for cleanup (covered in Step 5)

Run it a second time to trigger the duplicate:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

username = getpass.getuser()
conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute('CREATE ROLE test_py_role LOGIN')
    print('Role created')
except psycopg2.errors.DuplicateObject:
    print('Role already exists - skipping (safe to ignore)')
finally:
    cur.close()
    conn.close()
"
```

```
Expected output (yours will differ):
Role already exists - skipping (safe to ignore)
```

---

## Step 3: except as e - Capture Error Details

**DBA analogy:** `except SomeError as e` is like `SQLERRM` in PL/pgSQL - it gives you the full error message, the SQLSTATE code, and diagnostic details you can log or display.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

username = getpass.getuser()
conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute('CREATE ROLE test_py_role LOGIN')
    print('Role created')
except psycopg2.errors.DuplicateObject as e:
    print('--- Exception Details ---')
    print('Type:    ', type(e).__name__)
    print('Message: ', str(e).strip())
    print('PGCODE:  ', e.pgcode)
    print('DIAG:    ', e.diag.message_primary)
finally:
    cur.close()
    conn.close()
"
```

- `type(e).__name__` - the class name of the exception (like `DuplicateObject`)
- `str(e).strip()` - the full error message as a string (same as `SQLERRM`)
- `e.pgcode` - the PostgreSQL SQLSTATE code (e.g., `42710`)
- `e.diag.message_primary` - the primary error message from PostgreSQL diagnostics

```
Expected output (yours will differ):
--- Exception Details ---
Type:     DuplicateObject
Message:  role "test_py_role" already exists
PGCODE:   42710
DIAG:     role "test_py_role" already exists
```

---

## Step 4: Multiple except Blocks - Handle Different Error Types

**DBA analogy:** Multiple `except` blocks are like multiple `WHEN condition THEN` clauses in PL/pgSQL's `EXCEPTION` section. Python checks them top-to-bottom and runs the FIRST one that matches - just like PL/pgSQL.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

def try_create_role(role_name: str) -> None:
    username = getpass.getuser()
    try:
        conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'CREATE ROLE {role_name} LOGIN')
        print(f'Created role: {role_name}')
        cur.close()
        conn.close()
    except psycopg2.errors.DuplicateObject:
        print(f'Role {role_name} already exists - skipping')
    except psycopg2.errors.InvalidName as e:
        print(f'Invalid role name: {e}')
    except psycopg2.OperationalError as e:
        print(f'Could not connect to PostgreSQL: {e}')
    except Exception as e:
        print(f'Unexpected error: {type(e).__name__}: {e}')

try_create_role('test_py_role')
try_create_role('test_py_role')
"
```

- Each `except` block handles one specific error class
- `psycopg2.OperationalError` - catches connection failures (server down, wrong port, etc.)
- `except Exception as e:` at the end - a catch-all for anything not handled above (like `WHEN OTHERS THEN` in PL/pgSQL); always put the most specific exceptions first, generic ones last

```
Expected output (yours will differ):
Role test_py_role already exists - skipping
Role test_py_role already exists - skipping
```

---

## Step 5: finally - Always Close Connections

**DBA analogy:** `finally` is like the cleanup section in a PL/pgSQL `EXCEPTION` block - it runs whether or not an exception occurred. Use it to close connections and cursors so you never leak handles, even when errors happen.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import getpass

username = getpass.getuser()
conn = None
cur = None
try:
    conn = psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')
    cur = conn.cursor()
    cur.execute('SELECT 1/0')
    print('This will never print')
except Exception as e:
    print('Caught:', e)
finally:
    if cur is not None:
        cur.close()
        print('Cursor closed')
    if conn is not None:
        conn.close()
        print('Connection closed')
print('Script continues after finally')
"
```

- `conn = None` - initialize to `None` before `try` so `finally` can safely check if they were created
- `if cur is not None:` - only close if the object was actually created; `is not None` is the correct Python idiom for this check
- `SELECT 1/0` - triggers a `division_by_zero` error to demonstrate that `finally` still runs

```
Expected output (yours will differ):
Caught: division by zero
Cursor closed
Connection closed
Script continues after finally
```

---

## Step 6: Build create_role() with Duplicate Handling

Now build the first real function. Write this to a temporary file and test it.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

def get_connection():
    username = getpass.getuser()
    return psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')

def create_role(role_name: str, login: bool = True, password: str = '') -> None:
    conn = None
    cur = None
    try:
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        login_clause = 'LOGIN' if login else 'NOLOGIN'
        if password:
            cur.execute(f\"CREATE ROLE {role_name} {login_clause} PASSWORD %s\", (password,))
        else:
            cur.execute(f'CREATE ROLE {role_name} {login_clause}')
        print(f'[OK] Role created: {role_name}')
    except psycopg2.errors.DuplicateObject:
        print(f'[SKIP] Role already exists: {role_name}')
    except Exception as e:
        print(f'[ERROR] Failed to create {role_name}: {e}')
    finally:
        if cur: cur.close()
        if conn: conn.close()

create_role('app_user_py')
create_role('app_user_py')
create_role('readonly_py', login=False)
"
```

- `login: bool = True` - function parameter with a default value; callers can override it
- `'LOGIN' if login else 'NOLOGIN'` - Python ternary expression (like `CASE WHEN login THEN 'LOGIN' ELSE 'NOLOGIN' END`)
- `PASSWORD %s` with `(password,)` - parameterized query for the password value; the trailing comma makes it a tuple

```
Expected output (yours will differ):
[OK] Role created: app_user_py
[SKIP] Role already exists: app_user_py
[OK] Role created: readonly_py
```

---

## Step 7: Build alter_role() with "Role Not Found" Handling

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

def get_connection():
    username = getpass.getuser()
    return psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')

def alter_role(role_name: str, option: str) -> None:
    '''
    Alter a role. option examples: 'SUPERUSER', 'NOSUPERUSER',
    'CONNECTION LIMIT 10', 'VALID UNTIL 2027-01-01'
    '''
    conn = None
    cur = None
    try:
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'ALTER ROLE {role_name} {option}')
        print(f'[OK] Altered role {role_name}: {option}')
    except psycopg2.errors.UndefinedObject as e:
        print(f'[ERROR] Role not found: {role_name}')
    except psycopg2.errors.InsufficientPrivilege as e:
        print(f'[ERROR] Permission denied to alter {role_name}: {e}')
    except Exception as e:
        print(f'[ERROR] Failed to alter {role_name}: {type(e).__name__}: {e}')
    finally:
        if cur: cur.close()
        if conn: conn.close()

alter_role('app_user_py', 'CONNECTION LIMIT 5')
alter_role('ghost_role_xyz', 'CONNECTION LIMIT 5')
"
```

- `psycopg2.errors.UndefinedObject` - SQLSTATE `42704`; raised when the role doesn't exist
- `psycopg2.errors.InsufficientPrivilege` - SQLSTATE `42501`; raised when your user lacks permission

```
Expected output (yours will differ):
[OK] Altered role app_user_py: CONNECTION LIMIT 5
[ERROR] Role not found: ghost_role_xyz
```

---

## Step 8: Build drop_role() with Active Connections Handling

**DBA analogy:** `DROP ROLE` fails with `SQLSTATE 2BP01` if the role owns objects, or with a dependency error if it has active connections. This is one of the most common errors in DBA automation.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

def get_connection():
    username = getpass.getuser()
    return psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')

def drop_role(role_name: str, force: bool = False) -> None:
    conn = None
    cur = None
    try:
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()

        if force:
            cur.execute(
                'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = %s',
                (role_name,)
            )
            terminated = cur.rowcount
            if terminated > 0:
                print(f'[INFO] Terminated {terminated} connection(s) for {role_name}')

        cur.execute(f'DROP ROLE IF EXISTS {role_name}')
        print(f'[OK] Dropped role: {role_name}')
    except psycopg2.errors.DependentObjectsStillExist as e:
        print(f'[ERROR] Cannot drop {role_name} - role owns objects')
        print(f'        Detail: {e.diag.message_detail}')
        print(f'        Hint: Reassign ownership first with REASSIGN OWNED BY')
    except Exception as e:
        print(f'[ERROR] Failed to drop {role_name}: {type(e).__name__}: {e}')
    finally:
        if cur: cur.close()
        if conn: conn.close()

drop_role('app_user_py')
drop_role('readonly_py')
drop_role('nonexistent_role_xyz')
"
```

- `DROP ROLE IF EXISTS` - the PostgreSQL `IF EXISTS` guard means no error if the role is missing (Python's `except` catches DB-level errors; SQL-level guards prevent them entirely)
- `psycopg2.errors.DependentObjectsStillExist` - SQLSTATE `2BP01`; raised when the role owns tables, sequences, or other objects
- `e.diag.message_detail` - the `DETAIL:` line from the PostgreSQL error message, which lists the owned objects

```
Expected output (yours will differ):
[OK] Dropped role: app_user_py
[OK] Dropped role: readonly_py
[OK] Dropped role: nonexistent_role_xyz
```

---

## Step 9: Build grant_privileges() with Permission Error Handling

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2
import psycopg2.errors
import getpass

def get_connection():
    username = getpass.getuser()
    return psycopg2.connect(host='localhost', port=5432, user=username, dbname='postgres')

def grant_privileges(role_name: str, dbname: str, schema: str = 'public', privilege: str = 'SELECT') -> None:
    conn = None
    cur = None
    try:
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()

        cur.execute(f'GRANT CONNECT ON DATABASE {dbname} TO {role_name}')
        cur.execute(f'GRANT USAGE ON SCHEMA {schema} TO {role_name}')
        cur.execute(f'GRANT {privilege} ON ALL TABLES IN SCHEMA {schema} TO {role_name}')
        print(f'[OK] Granted {privilege} on {schema}.* in {dbname} to {role_name}')
    except psycopg2.errors.UndefinedObject as e:
        print(f'[ERROR] Role or object not found: {e}')
    except psycopg2.errors.InsufficientPrivilege as e:
        print(f'[ERROR] You do not have GRANT OPTION for these privileges')
    except Exception as e:
        print(f'[ERROR] Grant failed: {type(e).__name__}: {e}')
    finally:
        if cur: cur.close()
        if conn: conn.close()

# Create a test role first, then grant
conn = psycopg2.connect(host='localhost', port=5432, user=getpass.getuser(), dbname='postgres')
conn.autocommit = True
cur = conn.cursor()
cur.execute('CREATE ROLE test_grant_role LOGIN')
cur.close()
conn.close()

grant_privileges('test_grant_role', 'postgres', 'public', 'SELECT')
grant_privileges('ghost_role_xyz', 'postgres', 'public', 'SELECT')

# Cleanup
conn = psycopg2.connect(host='localhost', port=5432, user=getpass.getuser(), dbname='postgres')
conn.autocommit = True
cur = conn.cursor()
cur.execute('DROP ROLE IF EXISTS test_grant_role')
cur.close()
conn.close()
print('[OK] Cleanup done')
import getpass
"
```

```
Expected output (yours will differ):
[OK] Granted SELECT on public.* in postgres to test_grant_role
[ERROR] Role or object not found: role "ghost_role_xyz" does not exist
[OK] Cleanup done
```

---

## Step 10: raise - Raise Your Own Errors for Invalid Input

**DBA analogy:** `raise` in Python is like `RAISE EXCEPTION` in PL/pgSQL. Use it to reject invalid input before it hits the database - the same way you'd validate parameters at the top of a PL/pgSQL procedure.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

SAFE_ROLE_PATTERN = re.compile(r'^[a-zA-Z][a-zA-Z0-9_]{0,62}$')

def validate_role_name(role_name: str) -> None:
    if not role_name:
        raise ValueError('Role name cannot be empty')
    if len(role_name) > 63:
        raise ValueError(f'Role name too long: {len(role_name)} chars (PostgreSQL max is 63)')
    if not SAFE_ROLE_PATTERN.match(role_name):
        raise ValueError(f'Invalid role name: {role_name!r}. Use only letters, digits, underscores. Must start with a letter.')

test_names = ['valid_role', '', 'role with spaces', 'x' * 64, '123starts_with_digit', 'good_role_2']
for name in test_names:
    try:
        validate_role_name(name)
        print(f'[OK]    {name!r}')
    except ValueError as e:
        print(f'[FAIL]  {name!r} -> {e}')
"
```

- `raise ValueError('message')` - throw a `ValueError` exception with your custom message (like `RAISE EXCEPTION 'message'`)
- `re.compile(r'^[a-zA-Z][a-zA-Z0-9_]{0,62}$')` - a regular expression pattern that validates safe PostgreSQL identifier characters
- `SAFE_ROLE_PATTERN.match(role_name)` - test the role name against the pattern; returns `None` (falsy) if it does not match
- Validating at the Python layer means bad input never reaches the database - cleaner than handling SQL errors downstream

```
Expected output (yours will differ):
[OK]    'valid_role'
[FAIL]  '' -> Role name cannot be empty
[FAIL]  'role with spaces' -> Invalid role name: 'role with spaces'. Use only letters, digits, underscores. Must start with a letter.
[FAIL]  'xxxxxxxx...' -> Role name too long: 64 chars (PostgreSQL max is 63)
[FAIL]  '123starts_with_digit' -> Invalid role name: '123starts_with_digit'. Use only letters, digits, underscores. Must start with a letter.
[OK]    'good_role_2'
```

---

## Step 11: Build the Final user_manager.py Script

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/user_manager.py << 'PYEOF'
#!/usr/bin/env python3
"""
user_manager.py - PostgreSQL role lifecycle manager
Handles create, alter, drop, and grant with proper error handling.
"""

import re
import getpass
import psycopg2
import psycopg2.errors

SAFE_ROLE_PATTERN = re.compile(r'^[a-zA-Z][a-zA-Z0-9_]{0,62}$')


def get_connection(dbname: str = 'postgres') -> psycopg2.extensions.connection:
    """Open a connection to local PostgreSQL using the current OS user."""
    username = getpass.getuser()
    return psycopg2.connect(host='localhost', port=5432, user=username, dbname=dbname)


def validate_role_name(role_name: str) -> None:
    """Validate role name before sending to PostgreSQL. Raises ValueError on invalid input."""
    if not role_name:
        raise ValueError('Role name cannot be empty')
    if len(role_name) > 63:
        raise ValueError(f'Role name too long: {len(role_name)} chars (max 63)')
    if not SAFE_ROLE_PATTERN.match(role_name):
        raise ValueError(
            f'Invalid role name: {role_name!r}. '
            f'Use only letters, digits, underscores. Must start with a letter.'
        )


def create_role(role_name: str, login: bool = True, password: str = '') -> bool:
    """
    Create a PostgreSQL role. Returns True on success, False on skip/error.
    Handles: duplicate role (skip gracefully).
    """
    conn = None
    cur = None
    try:
        validate_role_name(role_name)
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        login_clause = 'LOGIN' if login else 'NOLOGIN'
        if password:
            cur.execute(f'CREATE ROLE {role_name} {login_clause} PASSWORD %s', (password,))
        else:
            cur.execute(f'CREATE ROLE {role_name} {login_clause}')
        print(f'[OK] Role created: {role_name}')
        return True
    except ValueError as e:
        print(f'[INVALID] {e}')
        return False
    except psycopg2.errors.DuplicateObject:
        print(f'[SKIP] Role already exists: {role_name}')
        return False
    except psycopg2.OperationalError as e:
        print(f'[ERROR] Cannot connect to PostgreSQL: {e}')
        return False
    except Exception as e:
        print(f'[ERROR] Failed to create {role_name}: {type(e).__name__}: {e}')
        return False
    finally:
        if cur: cur.close()
        if conn: conn.close()


def alter_role(role_name: str, option: str) -> bool:
    """
    Alter a role. option examples: 'SUPERUSER', 'CONNECTION LIMIT 10'.
    Handles: role not found, insufficient privilege.
    """
    conn = None
    cur = None
    try:
        validate_role_name(role_name)
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'ALTER ROLE {role_name} {option}')
        print(f'[OK] Altered {role_name}: {option}')
        return True
    except ValueError as e:
        print(f'[INVALID] {e}')
        return False
    except psycopg2.errors.UndefinedObject:
        print(f'[ERROR] Role not found: {role_name}')
        return False
    except psycopg2.errors.InsufficientPrivilege:
        print(f'[ERROR] Permission denied to alter role: {role_name}')
        return False
    except Exception as e:
        print(f'[ERROR] Failed to alter {role_name}: {type(e).__name__}: {e}')
        return False
    finally:
        if cur: cur.close()
        if conn: conn.close()


def drop_role(role_name: str, force: bool = False) -> bool:
    """
    Drop a role. If force=True, terminates active connections first.
    Handles: role not found (silent), owned objects (error with hint).
    """
    conn = None
    cur = None
    try:
        validate_role_name(role_name)
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        if force:
            cur.execute(
                'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = %s',
                (role_name,)
            )
            if cur.rowcount > 0:
                print(f'[INFO] Terminated {cur.rowcount} connection(s) for {role_name}')
        cur.execute(f'DROP ROLE IF EXISTS {role_name}')
        print(f'[OK] Dropped role: {role_name}')
        return True
    except ValueError as e:
        print(f'[INVALID] {e}')
        return False
    except psycopg2.errors.DependentObjectsStillExist as e:
        print(f'[ERROR] Role {role_name} owns objects - cannot drop')
        print(f'        Detail: {e.diag.message_detail}')
        print(f'        Fix: REASSIGN OWNED BY {role_name} TO postgres; DROP OWNED BY {role_name};')
        return False
    except Exception as e:
        print(f'[ERROR] Failed to drop {role_name}: {type(e).__name__}: {e}')
        return False
    finally:
        if cur: cur.close()
        if conn: conn.close()


def grant_privileges(role_name: str, dbname: str, schema: str = 'public', privilege: str = 'SELECT') -> bool:
    """
    Grant schema-level privileges to a role.
    Handles: role not found, insufficient privilege.
    """
    conn = None
    cur = None
    try:
        validate_role_name(role_name)
        conn = get_connection()
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'GRANT CONNECT ON DATABASE {dbname} TO {role_name}')
        cur.execute(f'GRANT USAGE ON SCHEMA {schema} TO {role_name}')
        cur.execute(f'GRANT {privilege} ON ALL TABLES IN SCHEMA {schema} TO {role_name}')
        print(f'[OK] Granted {privilege} on {schema}.* in {dbname} to {role_name}')
        return True
    except ValueError as e:
        print(f'[INVALID] {e}')
        return False
    except psycopg2.errors.UndefinedObject as e:
        print(f'[ERROR] Role or schema not found: {e}')
        return False
    except psycopg2.errors.InsufficientPrivilege:
        print(f'[ERROR] You do not have GRANT OPTION on these privileges')
        return False
    except Exception as e:
        print(f'[ERROR] Grant failed: {type(e).__name__}: {e}')
        return False
    finally:
        if cur: cur.close()
        if conn: conn.close()


def main() -> None:
    print('=== user_manager.py - Role Lifecycle Test ===\n')

    print('--- Step 1: Create roles ---')
    create_role('demo_app_user')
    create_role('demo_readonly', login=False)
    create_role('demo_app_user')       # duplicate - should skip
    create_role('')                    # invalid name - should reject
    create_role('bad name!')           # invalid chars - should reject

    print('\n--- Step 2: Alter roles ---')
    alter_role('demo_app_user', 'CONNECTION LIMIT 10')
    alter_role('ghost_role_xyz', 'CONNECTION LIMIT 10')   # not found

    print('\n--- Step 3: Grant privileges ---')
    grant_privileges('demo_app_user', 'postgres', 'public', 'SELECT')
    grant_privileges('ghost_role_xyz', 'postgres', 'public', 'SELECT')  # not found

    print('\n--- Step 4: Drop roles ---')
    drop_role('demo_app_user')
    drop_role('demo_readonly')
    drop_role('already_gone_role')     # IF EXISTS - should succeed silently

    print('\nDone.')


if __name__ == '__main__':
    main()
PYEOF
```

---

## Step 12: Run user_manager.py

On your Mac terminal, as your normal user:

```bash
python3 ~/pgdba/user_manager.py
```

```
Expected output (yours will differ):
=== user_manager.py - Role Lifecycle Test ===

--- Step 1: Create roles ---
[OK] Role created: demo_app_user
[OK] Role created: demo_readonly
[SKIP] Role already exists: demo_app_user
[INVALID] Role name cannot be empty
[INVALID] Invalid role name: 'bad name!'. Use only letters, digits, underscores. Must start with a letter.

--- Step 2: Alter roles ---
[OK] Altered demo_app_user: CONNECTION LIMIT 10
[ERROR] Role not found: ghost_role_xyz

--- Step 3: Grant privileges ---
[OK] Granted SELECT on public.* in postgres to demo_app_user
[ERROR] Role or schema not found: role "ghost_role_xyz" does not exist

--- Step 4: Drop roles ---
[OK] Dropped role: demo_app_user
[OK] Dropped role: demo_readonly
[OK] Dropped role: already_gone_role

Done.
```

---

## What You Built

Your script `~/pgdba/user_manager.py` handles the full role lifecycle with production-grade error handling:

- Creates roles, catches duplicates without crashing
- Alters roles, reports when the role doesn't exist
- Drops roles with `IF EXISTS` and detects owned-object conflicts
- Grants privileges with permission error detection
- Validates input with `raise` before hitting the database

**Python concepts used:**
- `try/except` - catch errors without crashing (PL/pgSQL `EXCEPTION WHEN`)
- Specific exception classes - `psycopg2.errors.DuplicateObject`, `UndefinedObject`, etc.
- `except SomeError as e` - access error details like `SQLERRM` and SQLSTATE
- Multiple `except` blocks - handle different failure modes separately
- `finally` - always close connections, regardless of outcome
- `raise` - reject invalid input before it reaches the database

**Next:** BUILD 06 covers modules and imports using a security auditor that imports functions from `conf_parser.py` (built in BUILD 04).
