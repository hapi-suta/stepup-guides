# BUILD 06: Modules and Imports - Security Auditor (Security, Privileges, RLS)

## What You're Building

By the end of this guide you will have three files in `~/pgdba/`:
- `pg_utils.py` - a shared utility module (connection helpers)
- `conf_parser.py` - already built in BUILD 04 (reused here)
- `security_audit.py` - the main auditor, which imports from both

Running `python3 ~/pgdba/security_audit.py` will check your local PostgreSQL for: superuser count, password expiry, trust auth in `pg_hba.conf`, dangerous PUBLIC grants, and RLS status.

**Python concepts covered:** `import`, `from X import Y`, `import as alias`, `__name__ == '__main__'`, creating your own importable module, `sys.argv`, `sys.path`

**DBA task:** Build a modular security auditor that reuses code from earlier builds - the same way you'd build a library of PL/pgSQL functions that other procedures call.

---

## Prerequisites

- Completed BUILD 04 (`conf_parser.py` in `~/pgdba/`)
- Completed BUILD 05 (psycopg2 and error handling patterns)
- `psycopg2-binary` installed

---

## Step 1: import - Importing Built-in Modules

**DBA analogy:** `import os` is like `SET search_path TO os_schema, public` - after the import, you can call functions from that module using `os.function_name()`. Python ships with dozens of built-in modules; you get them for free, just like `pg_catalog` functions.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os
import sys

print('Python version:', sys.version)
print('Current directory:', os.getcwd())
print('Home directory:', os.path.expanduser('~'))
print('PATH entries:', len(sys.path))
"
```

- `import os` - load the `os` module (operating system functions: file paths, environment variables, process info)
- `import sys` - load the `sys` module (Python runtime info: version, `sys.path`, `sys.argv`)
- `os.getcwd()` - get current working directory (like `SELECT current_setting('data_directory')`)
- `sys.version` - the Python version string
- After `import os`, every function in that module is accessed as `os.something` - the module name is the prefix

```
Expected output (yours will differ):
Python version: 3.13.0 (main, Oct  7 2024, 05:02:14)
Current directory: /Users/hafopezi
Home directory: /Users/hafopezi
PATH entries: 8
```

---

## Step 2: from X import Y - Import Specific Functions

**DBA analogy:** `from os.path import exists, join` is like creating a synonym for a specific function in another schema - after this import you call `exists()` directly instead of `os.path.exists()`. Same function, shorter name.

On your Mac terminal, as your normal user:

```bash
python3 -c "
from os.path import exists, join, expanduser
from datetime import datetime

home = expanduser('~')
pgdba_path = join(home, 'pgdba')
conf_parser_path = join(pgdba_path, 'conf_parser.py')

print('pgdba dir exists:', exists(pgdba_path))
print('conf_parser.py exists:', exists(conf_parser_path))
print('Current time:', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
"
```

- `from os.path import exists, join, expanduser` - import three specific functions; now call them as `exists()`, not `os.path.exists()`
- `join(home, 'pgdba')` - build a file path safely (handles `/` separators for your OS), like `format('%s/%s', home, 'pgdba')` but OS-aware
- `expanduser('~')` - expand the `~` shortcut to the full home directory path
- `from datetime import datetime` - import the `datetime` class from the `datetime` module (both have the same name, which is a common Python quirk)

```
Expected output (yours will differ):
pgdba dir exists: True
conf_parser.py exists: True
Current time: 2026-06-13 14:32:07
```

---

## Step 3: import as alias - Shorter Names for Long Modules

**DBA analogy:** `import psycopg2 as pg` is exactly like a table alias in SQL - `FROM very_long_schema_name.users u` becomes just `u.id`. The alias is just a shorter name for the same thing.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import psycopg2 as pg
import psycopg2.errors as pgerrors
import getpass as gp

username = gp.getuser()
print('Connecting as:', username)

try:
    conn = pg.connect(host='localhost', port=5432, user=username, dbname='postgres')
    cur = conn.cursor()
    cur.execute('SELECT version()')
    row = cur.fetchone()
    print('PG version:', row[0][:50])
    cur.close()
    conn.close()
except pgerrors.OperationalError as e:
    print('Connection error:', e)
"
```

- `import psycopg2 as pg` - now write `pg.connect()` instead of `psycopg2.connect()`
- `import psycopg2.errors as pgerrors` - alias the errors submodule so you write `pgerrors.DuplicateObject` instead of `psycopg2.errors.DuplicateObject`
- `import getpass as gp` - alias `getpass` to `gp`; `gp.getuser()` returns your Mac username

```
Expected output (yours will differ):
Connecting as: hafopezi
PG version: PostgreSQL 16.4 on aarch64-apple-darwin23.6.0, comp
```

---

## Step 4: Create pg_utils.py - Your First Importable Module

**DBA analogy:** Creating a Python module is like creating a schema full of reusable functions. Any other script can `import pg_utils` and call its functions, the same way any PL/pgSQL function can call another function in a shared schema.

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/pg_utils.py << 'PYEOF'
#!/usr/bin/env python3
"""
pg_utils.py - Shared PostgreSQL connection utilities.
Import this module in other scripts: from pg_utils import get_connection, run_query
"""

import getpass
import psycopg2
import psycopg2.extras


def get_connection(dbname: str = 'postgres') -> psycopg2.extensions.connection:
    """
    Open a connection to local PostgreSQL using the current OS username.
    On Mac Homebrew, the superuser is your Mac username, not 'postgres'.
    """
    username = getpass.getuser()
    return psycopg2.connect(
        host='localhost',
        port=5432,
        user=username,
        dbname=dbname
    )


def run_query(sql: str, params: tuple = (), dbname: str = 'postgres') -> list[dict]:
    """
    Run a SELECT query and return results as a list of dictionaries.
    Each row is a dict where keys are column names - like a list of JSON objects.
    Uses RealDictCursor so column names are preserved.
    """
    conn = None
    cur = None
    try:
        conn = get_connection(dbname)
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(sql, params)
        rows = cur.fetchall()
        return [dict(row) for row in rows]
    finally:
        if cur: cur.close()
        if conn: conn.close()


def run_ddl(sql: str, params: tuple = (), dbname: str = 'postgres') -> None:
    """
    Run a DDL or DML statement (no results returned).
    Commits automatically.
    """
    conn = None
    cur = None
    try:
        conn = get_connection(dbname)
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(sql, params)
    finally:
        if cur: cur.close()
        if conn: conn.close()


if __name__ == '__main__':
    print('pg_utils.py - connection test')
    rows = run_query('SELECT current_user, current_database(), version()')
    for row in rows:
        print('  User:', row['current_user'])
        print('  DB:  ', row['current_database'])
        print('  Ver: ', str(row['version'])[:60])
PYEOF
```

- `pg_utils.py` is now a Python module - any script in the same directory can import it
- `psycopg2.extras.RealDictCursor` - a cursor that returns rows as dictionaries keyed by column name, like `SELECT ... AS json_object` but as native Python dicts
- `[dict(row) for row in rows]` - list comprehension that converts each row to a plain dict (RealDictCursor rows need this conversion to work as standard dicts)
- The `if __name__ == '__main__':` block (covered in Step 6) lets you test the module directly

---

## Step 5: Import pg_utils in a New Script

Now verify the import works. This is the core of the module system: one file imports another.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')

from pg_utils import run_query, get_connection

print('Import succeeded')
rows = run_query('SELECT rolname, rolsuper, rolcanlogin FROM pg_roles ORDER BY rolname LIMIT 5')
for row in rows:
    print(f\"  {row['rolname']:<30} super={row['rolsuper']}  login={row['rolcanlogin']}\")
"
```

- `sys.path.insert(0, '/Users/hafopezi/pgdba')` - add your `~/pgdba/` directory to Python's module search path; replace `hafopezi` with your username. Without this, Python only searches standard library directories
- `from pg_utils import run_query, get_connection` - import specific functions from your module; Python finds `pg_utils.py` in the paths listed in `sys.path`
- After this import, call `run_query(...)` directly - no `pg_utils.` prefix needed

```
Expected output (yours will differ):
Import succeeded
  pg_monitor                     super=False  login=True
  pg_read_all_data               super=False  login=False
  pg_read_all_settings           super=False  login=False
  pg_read_all_stats              super=False  login=False
  pg_read_server_files           super=False  login=False
```

> Note: When you run scripts directly from `~/pgdba/`, Python automatically adds that directory to `sys.path`. The `sys.path.insert` above is only needed for one-liner `-c` commands run from another directory.

---

## Step 6: __name__ == '__main__' - Runnable AND Importable

**DBA analogy:** This is like writing a PL/pgSQL function that can EITHER be called by another function OR executed directly as a DO block. The `if __name__ == '__main__':` guard is the switch.

On your Mac terminal, as your normal user:

```bash
python3 -c "
# When Python imports a module, __name__ is set to the module's filename (without .py)
# When Python runs a file directly, __name__ is set to the string '__main__'
# This lets you write code that only runs when the file is executed directly

import pg_utils   # This import does NOT trigger the test block at the bottom of pg_utils.py

print('Imported pg_utils successfully')
print('Module name:', pg_utils.__name__)

# But if you ran: python3 pg_utils.py
# Python would set __name__ = '__main__' and the test block WOULD run
"
```

- `pg_utils.__name__` - the string `'pg_utils'` (the module name) when imported
- When you run `python3 pg_utils.py` directly, Python sets `__name__ = '__main__'` for THAT file only
- This pattern means: put your test/demo code inside `if __name__ == '__main__':` and it only runs on direct execution, not on import

Now test running pg_utils.py directly:

```bash
python3 ~/pgdba/pg_utils.py
```

```
Expected output (yours will differ):
pg_utils.py - connection test
  User: hafopezi
  DB:   postgres
  Ver:  PostgreSQL 16.4 on aarch64-apple-darwin23.6.0, compiled
```

---

## Step 7: Build check_superusers()

Now build the first security check function. The pattern is: import `pg_utils`, call `run_query`, return results.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')
from pg_utils import run_query

def check_superusers() -> list[dict]:
    sql = '''
        SELECT
            rolname,
            rolsuper,
            rolcanlogin,
            rolconnlimit,
            rolvaliduntil
        FROM pg_roles
        WHERE rolsuper = true
        ORDER BY rolname
    '''
    return run_query(sql)

superusers = check_superusers()
print(f'Superusers found: {len(superusers)}')
for role in superusers:
    expiry = role['rolvaliduntil'] or 'never'
    print(f\"  {role['rolname']:<30} login={role['rolcanlogin']}  expires={expiry}\")

if len(superusers) > 2:
    print(f'  WARNING: {len(superusers)} superusers is high. Standard: 1-2 (postgres + your admin role).')
"
```

- `WHERE rolsuper = true` - PostgreSQL system catalog query; `pg_roles` is like a `SELECT * FROM information_schema.applicable_roles` but more detailed
- `role['rolvaliduntil']` - dictionary key access using the column name from the query
- `or 'never'` - Python short-circuit: if `rolvaliduntil` is `None` (SQL NULL), use `'never'` instead

```
Expected output (yours will differ):
Superusers found: 1
  hafopezi                       login=True  expires=never
```

---

## Step 8: Build check_password_expiry()

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')
from pg_utils import run_query

def check_password_expiry() -> dict[str, list[dict]]:
    sql = '''
        SELECT
            rolname,
            rolcanlogin,
            rolvaliduntil,
            CASE
                WHEN rolpassword IS NULL THEN 'no_password'
                WHEN rolvaliduntil < now() THEN 'expired'
                WHEN rolvaliduntil IS NULL THEN 'no_expiry'
                ELSE 'valid'
            END AS password_status
        FROM pg_authid
        WHERE rolcanlogin = true
        ORDER BY rolname
    '''
    rows = run_query(sql)
    result = {'no_password': [], 'expired': [], 'no_expiry': [], 'valid': []}
    for row in rows:
        status = row['password_status']
        result[status].append(row)
    return result

report = check_password_expiry()
print('--- Password Expiry Report ---')
print(f\"  Roles with no password:  {len(report['no_password'])}\")
print(f\"  Roles with expired pwd:  {len(report['expired'])}\")
print(f\"  Roles with no expiry:    {len(report['no_expiry'])}\")
print(f\"  Roles with valid expiry: {len(report['valid'])}\")

if report['no_password']:
    print('  Roles with no password set:')
    for r in report['no_password']:
        print(f\"    - {r['rolname']}\")
"
```

- `pg_authid` - like `pg_roles` but includes the hashed password column; requires superuser access
- `CASE WHEN ... END AS password_status` - computed column in SQL; Python receives it as a regular column named `password_status`
- `result = {'no_password': [], 'expired': [], 'no_expiry': [], 'valid': []}` - a dictionary where each value is a list; this groups results by category, like `GROUP BY password_status` but keeping the full rows

```
Expected output (yours will differ):
--- Password Expiry Report ---
  Roles with no password:  1
  Roles with expired pwd:  0
  Roles with no expiry:    0
  Roles with valid expiry: 0
  Roles with no password set:
    - hafopezi
```

---

## Step 9: Build check_hba_trust() - Reuse conf_parser from BUILD 04

**DBA analogy:** This is the payoff of the module system. `check_hba_trust()` calls `parse_hba()` from `conf_parser.py` - just like one PL/pgSQL function calling another. No code duplication.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')
from conf_parser import find_conf_file, parse_hba

def check_hba_trust() -> list[dict]:
    '''Find all pg_hba.conf rules using trust authentication.'''
    try:
        hba_path = find_conf_file('pg_hba.conf')
        rules = parse_hba(hba_path)
        trust_rules = [r for r in rules if r['method'] == 'trust']
        return trust_rules
    except FileNotFoundError as e:
        print(f'WARNING: Cannot read pg_hba.conf: {e}')
        return []

trust_rules = check_hba_trust()
if trust_rules:
    print(f'WARNING: {len(trust_rules)} trust rule(s) found (no password required):')
    for r in trust_rules:
        print(f\"  type={r['type']}  db={r['database']}  user={r['user']}  addr={r['address']}\")
    print()
    print('Recommendation: Replace trust with scram-sha-256 for non-local connections.')
else:
    print('OK: No trust rules found in pg_hba.conf')
"
```

- `from conf_parser import find_conf_file, parse_hba` - import two specific functions from your BUILD 04 module; Python finds `conf_parser.py` in `sys.path`
- `[r for r in rules if r['method'] == 'trust']` - list comprehension with a filter; equivalent to `SELECT * FROM hba_rules WHERE method = 'trust'`

```
Expected output (yours will differ):
WARNING: 3 trust rule(s) found (no password required):
  type=local  db=all  user=all  addr=
  type=host   db=all  user=all  addr=127.0.0.1/32
  type=host   db=all  user=all  addr=::1/128

Recommendation: Replace trust with scram-sha-256 for non-local connections.
```

---

## Step 10: Build check_public_grants()

**DBA analogy:** Dangerous PUBLIC grants are a classic PostgreSQL security risk - equivalent to `GRANT ALL ON SCHEMA app TO PUBLIC` which gives every login role access without explicit grants.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')
from pg_utils import run_query

def check_public_grants() -> list[dict]:
    '''Find privileges granted to the PUBLIC role - any authenticated user can use these.'''
    sql = '''
        SELECT
            table_schema,
            table_name,
            privilege_type,
            grantee
        FROM information_schema.role_table_grants
        WHERE grantee = 'PUBLIC'
        ORDER BY table_schema, table_name
    '''
    return run_query(sql)

def check_public_schema_execute() -> list[dict]:
    '''Check if PUBLIC has EXECUTE on functions in public schema (common in older PostgreSQL).'''
    sql = '''
        SELECT
            n.nspname AS schema_name,
            p.proname AS function_name,
            pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE has_function_privilege('PUBLIC', p.oid, 'EXECUTE')
          AND n.nspname = 'public'
        ORDER BY p.proname
        LIMIT 10
    '''
    return run_query(sql)

public_table_grants = check_public_grants()
print(f'Tables with PUBLIC grants: {len(public_table_grants)}')
if public_table_grants:
    for g in public_table_grants[:5]:
        print(f\"  {g['table_schema']}.{g['table_name']} - {g['privilege_type']}\")

public_funcs = check_public_schema_execute()
print(f'Functions in public schema with PUBLIC EXECUTE: {len(public_funcs)}')
if public_funcs:
    for f in public_funcs[:5]:
        print(f\"  {f['schema_name']}.{f['function_name']}({f['args']})\")
"
```

- `information_schema.role_table_grants` - standard SQL information schema view that lists all table-level grants; `grantee = 'PUBLIC'` means ANY connected role has this access
- `has_function_privilege('PUBLIC', p.oid, 'EXECUTE')` - PostgreSQL privilege check function; returns `true` if PUBLIC role has EXECUTE on this function
- `LIMIT 10` - cap the results for display; in production you'd return all rows and write them to a report

```
Expected output (yours will differ):
Tables with PUBLIC grants: 0
Functions in public schema with PUBLIC EXECUTE: 0
```

---

## Step 11: Build the Final security_audit.py

Write the complete security auditor that imports from both `pg_utils.py` and `conf_parser.py`.

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/security_audit.py << 'PYEOF'
#!/usr/bin/env python3
"""
security_audit.py - PostgreSQL security auditor
Checks: superusers, password expiry, trust auth, public grants, RLS status.

Usage:
  python3 security_audit.py           # run all checks
  from security_audit import check_superusers  # import individual checks
"""

import sys
import os
from datetime import datetime

# Add ~/pgdba to path so Python finds pg_utils and conf_parser
sys.path.insert(0, os.path.expanduser('~/pgdba'))

from pg_utils import run_query
from conf_parser import find_conf_file, parse_hba


# ---------------------------------------------------------------------------
# Individual security check functions
# ---------------------------------------------------------------------------

def check_superusers() -> list[dict]:
    """Return all roles with superuser privilege."""
    sql = '''
        SELECT
            rolname,
            rolcanlogin,
            rolconnlimit,
            rolvaliduntil::text AS expires
        FROM pg_roles
        WHERE rolsuper = true
        ORDER BY rolname
    '''
    return run_query(sql)


def check_password_expiry() -> dict[str, list[dict]]:
    """
    Return login roles grouped by password status:
    no_password, expired, no_expiry, valid.
    Requires superuser (reads pg_authid).
    """
    sql = '''
        SELECT
            rolname,
            rolvaliduntil::text AS expires,
            CASE
                WHEN rolpassword IS NULL THEN 'no_password'
                WHEN rolvaliduntil < now() THEN 'expired'
                WHEN rolvaliduntil IS NULL THEN 'no_expiry'
                ELSE 'valid'
            END AS password_status
        FROM pg_authid
        WHERE rolcanlogin = true
        ORDER BY rolname
    '''
    rows = run_query(sql)
    result: dict[str, list[dict]] = {
        'no_password': [],
        'expired': [],
        'no_expiry': [],
        'valid': [],
    }
    for row in rows:
        status = row['password_status']
        if status in result:
            result[status].append(row)
    return result


def check_hba_trust() -> list[dict]:
    """Return pg_hba.conf rules using trust authentication."""
    try:
        hba_path = find_conf_file('pg_hba.conf')
        rules = parse_hba(hba_path)
        return [r for r in rules if r['method'] == 'trust']
    except FileNotFoundError as e:
        print(f'  WARNING: Cannot read pg_hba.conf: {e}')
        return []


def check_public_grants() -> list[dict]:
    """Return table-level privileges granted to the PUBLIC role."""
    sql = '''
        SELECT
            table_schema,
            table_name,
            privilege_type
        FROM information_schema.role_table_grants
        WHERE grantee = 'PUBLIC'
        ORDER BY table_schema, table_name
    '''
    return run_query(sql)


def check_rls_status() -> list[dict]:
    """Return tables that have data and check if RLS is enabled on them."""
    sql = '''
        SELECT
            schemaname,
            tablename,
            rowsecurity AS rls_enabled,
            forcerowsecurity AS rls_forced
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, tablename
    '''
    return run_query(sql)


# ---------------------------------------------------------------------------
# Report printer
# ---------------------------------------------------------------------------

def _section(title: str) -> None:
    print(f'\n{"=" * 60}')
    print(f'  {title}')
    print(f'{"=" * 60}')


def run_audit() -> None:
    print(f'\nPostgreSQL Security Audit')
    print(f'Run time: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')

    # --- Superusers ---
    _section('1. Superuser Roles')
    superusers = check_superusers()
    print(f'  Total superusers: {len(superusers)}')
    for r in superusers:
        expiry = r['expires'] or 'never'
        flag = '  [WARN] ' if len(superusers) > 2 else '  [OK]   '
        print(f"{flag}{r['rolname']:<30} login={r['rolcanlogin']}  expires={expiry}")
    if len(superusers) > 2:
        print(f'  RECOMMENDATION: {len(superusers)} superusers is unusually high.')

    # --- Password expiry ---
    _section('2. Password Expiry')
    try:
        pw_report = check_password_expiry()
        print(f"  No password set:  {len(pw_report['no_password'])}")
        print(f"  Expired:          {len(pw_report['expired'])}")
        print(f"  No expiry set:    {len(pw_report['no_expiry'])}")
        print(f"  Valid:            {len(pw_report['valid'])}")
        if pw_report['no_password']:
            print('  Roles with no password:')
            for r in pw_report['no_password']:
                print(f"    - {r['rolname']}")
        if pw_report['expired']:
            print('  EXPIRED roles (immediate attention required):')
            for r in pw_report['expired']:
                print(f"    - {r['rolname']} (expired: {r['expires']})")
    except Exception as e:
        print(f'  SKIP: {e} (requires superuser)')

    # --- Trust auth ---
    _section('3. Trust Authentication (pg_hba.conf)')
    trust_rules = check_hba_trust()
    if trust_rules:
        print(f'  WARNING: {len(trust_rules)} trust rule(s) - no password required:')
        for r in trust_rules:
            print(f"    type={r['type']:<8} db={r['database']:<12} user={r['user']:<12} addr={r['address']}")
        print('  RECOMMENDATION: Use scram-sha-256 for non-local connections.')
    else:
        print('  OK: No trust rules found.')

    # --- Public grants ---
    _section('4. Dangerous PUBLIC Grants')
    public_grants = check_public_grants()
    if public_grants:
        print(f'  WARNING: {len(public_grants)} table(s) grant privileges to PUBLIC:')
        for g in public_grants[:10]:
            print(f"    {g['table_schema']}.{g['table_name']} - {g['privilege_type']}")
        if len(public_grants) > 10:
            print(f'    ... and {len(public_grants) - 10} more')
    else:
        print('  OK: No table-level PUBLIC grants found.')

    # --- RLS ---
    _section('5. Row Level Security (RLS) Status')
    tables = check_rls_status()
    rls_off = [t for t in tables if not t['rls_enabled']]
    rls_on  = [t for t in tables if t['rls_enabled']]
    print(f'  User tables total:    {len(tables)}')
    print(f'  RLS enabled:          {len(rls_on)}')
    print(f'  RLS NOT enabled:      {len(rls_off)}')
    if rls_on:
        print('  Tables with RLS on:')
        for t in rls_on:
            forced = ' (forced)' if t['rls_forced'] else ''
            print(f"    {t['schemaname']}.{t['tablename']}{forced}")
    print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    run_audit()
PYEOF
```

- `sys.path.insert(0, os.path.expanduser('~/pgdba'))` - adds `~/pgdba/` to the module search path at position 0 (first place Python looks); `expanduser` converts `~` to the actual home directory path
- The `from pg_utils import ...` and `from conf_parser import ...` lines pull functions from the two modules you built in earlier guides
- `if __name__ == '__main__': run_audit()` - the `run_audit()` function only fires when you run the file directly; if another script does `from security_audit import check_superusers`, `run_audit()` does NOT execute

---

## Step 12: Run as Standalone

On your Mac terminal, as your normal user:

```bash
python3 ~/pgdba/security_audit.py
```

```
Expected output (yours will differ):
PostgreSQL Security Audit
Run time: 2026-06-13 14:45:22

============================================================
  1. Superuser Roles
============================================================
  Total superusers: 1
  [OK]   hafopezi                       login=True  expires=never

============================================================
  2. Password Expiry
============================================================
  No password set:  1
  Expired:          0
  No expiry set:    0
  Valid:            0
  Roles with no password:
    - hafopezi

============================================================
  3. Trust Authentication (pg_hba.conf)
============================================================
  WARNING: 3 trust rule(s) - no password required:
    type=local    db=all          user=all        addr=
    type=host     db=all          user=all        addr=127.0.0.1/32
    type=host     db=all          user=all        addr=::1/128
  RECOMMENDATION: Use scram-sha-256 for non-local connections.

============================================================
  4. Dangerous PUBLIC Grants
============================================================
  OK: No table-level PUBLIC grants found.

============================================================
  5. Row Level Security (RLS) Status
============================================================
  User tables total:    0
  RLS enabled:          0
  RLS NOT enabled:      0
```

---

## Step 13: Import security_audit as a Module

The `__name__ == '__main__'` guard means you can import individual check functions without triggering the full audit run.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import sys
sys.path.insert(0, '/Users/hafopezi/pgdba')

from security_audit import check_superusers, check_hba_trust

print('Imported without running full audit')
print()

superusers = check_superusers()
print(f'Superusers: {len(superusers)}')
for r in superusers:
    print(f\"  {r['rolname']}\")

trust_rules = check_hba_trust()
print(f'Trust rules: {len(trust_rules)}')
"
```

- `from security_audit import check_superusers, check_hba_trust` - imports two functions from your module; Python runs all the top-level code in `security_audit.py` EXCEPT the `if __name__ == '__main__':` block
- This is how you build a library: write functions, protect the demo code with `__name__ == '__main__'`, and every other script can safely import what it needs

```
Expected output (yours will differ):
Imported without running full audit

Superusers: 1
  hafopezi
Trust rules: 3
```

---

## What You Built

Three files in `~/pgdba/` that work together as a module system:

| File | Role | Exports |
|---|---|---|
| `pg_utils.py` | Connection utilities | `get_connection`, `run_query`, `run_ddl` |
| `conf_parser.py` | Config file parser (BUILD 04) | `find_conf_file`, `read_conf`, `get_setting`, `parse_hba` |
| `security_audit.py` | Security auditor | `check_superusers`, `check_password_expiry`, `check_hba_trust`, `check_public_grants`, `check_rls_status` |

**Python concepts used:**
- `import module` - load a whole module; access its contents as `module.function()`
- `from module import x, y` - import specific names; call them directly without prefix
- `import module as alias` - shorter name for a module or submodule
- `sys.path.insert(0, path)` - tell Python where to find your custom modules
- `__name__ == '__main__'` - make a file both directly runnable and safely importable
- Composing modules: `security_audit.py` calls functions from `pg_utils.py` and `conf_parser.py`

**Python DBA Toolkit - Complete:**

| Guide | Script | Python Concepts |
|---|---|---|
| BUILD 03 | `db_monitor.py` | psycopg2, dictionaries, f-strings |
| BUILD 04 | `conf_parser.py` | file I/O, strip, split, startswith |
| BUILD 05 | `user_manager.py` | try/except, specific exceptions, finally, raise |
| BUILD 06 | `security_audit.py` | import, modules, __name__ == '__main__' |
