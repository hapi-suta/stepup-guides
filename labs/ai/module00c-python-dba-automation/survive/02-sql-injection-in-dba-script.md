# SURVIVE 02: SQL Injection in Your Own DBA Script

**Module:** 00c - Python DBA Automation
**Type:** Chaos Scenario
**Time:** 30-45 minutes

---

## The Setup

Your team uses a Python admin script to manage database users. It takes a username as input and looks up their role details, resets passwords, and drops idle connections. A new hire ran the script with a database name that contained a single quote. Things went sideways.

---

## Symptom

The new hire was trying to check info on a database called `client's_data` (yes, with an apostrophe - a developer created it months ago). They ran:

```bash
python3 admin_tool.py lookup "client's_data"
```

The script crashed with:

```
psycopg2.errors.SyntaxError: unterminated quoted string at or near "'s_data'"
LINE 1: SELECT * FROM pg_database WHERE datname = 'client's_data'
                                                          ^
```

That is a crash - annoying but not catastrophic. The real danger is what COULD happen. Look at this scenario:

Someone runs:

```bash
python3 admin_tool.py drop_idle "'; SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename != 'postgres'; --"
```

If the script uses string interpolation, that input becomes live SQL. It would terminate every non-postgres connection on the server.

---

## Diagnosis

Here is the vulnerable admin script. Find ALL the injection points.

```python
#!/usr/bin/env python3
"""Admin tool for managing PostgreSQL users and connections."""

import sys
import psycopg2

def get_connection():
    return psycopg2.connect(dbname='postgres', user='postgres')


def lookup_database(dbname: str) -> None:
    """Look up database info by name."""
    conn = get_connection()
    cur = conn.cursor()

    # INJECTION POINT 1
    query = f"SELECT datname, pg_database_size(datname), datdba FROM pg_database WHERE datname = '{dbname}'"
    cur.execute(query)
    row = cur.fetchone()

    if row:
        print(f"Database: {row[0]}, Size: {row[1]}, Owner OID: {row[2]}")
    else:
        print(f"Database '{dbname}' not found")

    cur.close()
    conn.close()


def lookup_user(username: str) -> None:
    """Look up role info by name."""
    conn = get_connection()
    cur = conn.cursor()

    # INJECTION POINT 2
    query = "SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname = '%s'" % username
    cur.execute(query)
    row = cur.fetchone()

    if row:
        print(f"Role: {row[0]}, Superuser: {row[1]}, Can Login: {row[2]}")
    else:
        print(f"Role '{username}' not found")

    cur.close()
    conn.close()


def drop_idle_connections(username: str) -> None:
    """Terminate idle connections for a user."""
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    # INJECTION POINT 3
    cur.execute(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE usename = '" + username + "' AND state = 'idle'"
    )
    terminated = cur.rowcount
    print(f"Terminated {terminated} idle connections for {username}")

    cur.close()
    conn.close()


def reset_password(username: str, new_password: str) -> None:
    """Reset a user's password."""
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    # INJECTION POINT 4
    cur.execute(f"ALTER ROLE {username} PASSWORD '{new_password}'")
    print(f"Password reset for {username}")

    cur.close()
    conn.close()


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 admin_tool.py <command> <argument> [extra_args]")
        print("Commands: lookup_db, lookup_user, drop_idle, reset_password")
        sys.exit(1)

    command = sys.argv[1]
    argument = sys.argv[2]

    if command == 'lookup_db':
        lookup_database(argument)
    elif command == 'lookup_user':
        lookup_user(argument)
    elif command == 'drop_idle':
        drop_idle_connections(argument)
    elif command == 'reset_password':
        if len(sys.argv) < 4:
            print("Usage: python3 admin_tool.py reset_password <username> <new_password>")
            sys.exit(1)
        reset_password(argument, sys.argv[3])
    else:
        print(f"Unknown command: {command}")


if __name__ == '__main__':
    main()
```

**Four injection points, four different string interpolation methods - all dangerous:**

1. **f-string:** `f"... WHERE datname = '{dbname}'"` - Python 3.6+ formatted string
2. **% operator:** `"... WHERE rolname = '%s'" % username` - old-style string formatting (the `%s` here is Python string substitution, NOT a psycopg2 placeholder)
3. **+ concatenation:** `"... WHERE usename = '" + username + "' ..."` - string concatenation
4. **f-string with DDL:** `f"ALTER ROLE {username} PASSWORD '{new_password}'"` - the most dangerous because ALTER ROLE changes permissions

**What an attacker could do with injection point 4:**

```bash
python3 admin_tool.py reset_password "postgres' SUPERUSER; --" "anything"
```

This becomes:

```sql
ALTER ROLE postgres' SUPERUSER; --' PASSWORD 'anything'
```

Which fails on syntax - but a slightly more careful input:

```bash
python3 admin_tool.py reset_password "hacker" "x'; CREATE ROLE hacker SUPERUSER LOGIN PASSWORD 'pwned'; --"
```

Becomes:

```sql
ALTER ROLE hacker PASSWORD 'x'; CREATE ROLE hacker SUPERUSER LOGIN PASSWORD 'pwned'; --'
```

That creates a new superuser. Game over.

---

## Fix

**Step 1: Replace ALL string interpolation with parameterized queries.**

For SELECT/DML queries, use `%s` placeholders (psycopg2 parameterized queries):

```python
# BEFORE (vulnerable):
cur.execute(f"SELECT * FROM pg_database WHERE datname = '{dbname}'")

# AFTER (safe):
cur.execute("SELECT * FROM pg_database WHERE datname = %s", (dbname,))
```

**Step 2: For DDL statements (ALTER ROLE, etc.), use psycopg2.sql module.**

DDL statements like `ALTER ROLE` cannot use `%s` placeholders for identifiers (role names, table names). The `%s` placeholder only works for VALUES. For identifiers, use `psycopg2.sql`:

```python
from psycopg2 import sql

# BEFORE (vulnerable):
cur.execute(f"ALTER ROLE {username} PASSWORD '{new_password}'")

# AFTER (safe):
cur.execute(
    sql.SQL("ALTER ROLE {} PASSWORD %s").format(sql.Identifier(username)),
    (new_password,)
)
```

`sql.Identifier()` properly quotes the role name. `%s` safely handles the password value.

**Step 3: Add input validation as a defense-in-depth layer.**

Even with parameterized queries, validate inputs:

```python
import re

def validate_identifier(name: str) -> bool:
    """Check if a string is a valid PostgreSQL identifier."""
    # Only allow alphanumeric, underscore, and dash
    return bool(re.match(r'^[a-zA-Z_][a-zA-Z0-9_-]*$', name))
```

**Step 4: The complete fixed script.**

Create the fixed version with `vi`:

```bash
vi ~/admin_tool_fixed.py
```

```python
#!/usr/bin/env python3
"""Admin tool for managing PostgreSQL users and connections. FIXED version."""

import os
import re
import sys
import logging
import psycopg2
from psycopg2 import sql
from contextlib import closing

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger('admin_tool')


def get_connection():
    """Create connection from environment variables."""
    return psycopg2.connect(
        host=os.environ.get('PGHOST', 'localhost'),
        dbname=os.environ.get('PGDATABASE', 'postgres'),
        user=os.environ.get('PGUSER', 'postgres'),
        password=os.environ.get('PGPASSWORD', '')
    )


def validate_identifier(name: str) -> bool:
    """Validate that a string is safe as a PostgreSQL identifier."""
    if not name:
        return False
    # Allow alphanumeric, underscore, dash, dot (for schema.table)
    if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_.\'-]*$', name):
        return False
    if len(name) > 63:  # PostgreSQL identifier limit
        return False
    return True


def lookup_database(dbname: str) -> None:
    """Look up database info by name."""
    # FIX: Parameterized query
    with closing(get_connection()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT datname, pg_database_size(datname), datdba "
                "FROM pg_database WHERE datname = %s",
                (dbname,)
            )
            row = cur.fetchone()

            if row:
                logger.info(f"Database: {row[0]}, Size: {row[1]}, Owner OID: {row[2]}")
            else:
                logger.info(f"Database not found: {dbname}")


def lookup_user(username: str) -> None:
    """Look up role info by name."""
    # FIX: Parameterized query
    with closing(get_connection()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT rolname, rolsuper, rolcanlogin "
                "FROM pg_roles WHERE rolname = %s",
                (username,)
            )
            row = cur.fetchone()

            if row:
                logger.info(f"Role: {row[0]}, Superuser: {row[1]}, Can Login: {row[2]}")
            else:
                logger.info(f"Role not found: {username}")


def drop_idle_connections(username: str) -> None:
    """Terminate idle connections for a user."""
    # FIX: Input validation + parameterized query
    if not validate_identifier(username):
        logger.error(f"Invalid username format: {username}")
        return

    with closing(get_connection()) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE usename = %s AND state = 'idle' AND pid != pg_backend_pid()",
                (username,)
            )
            terminated = cur.rowcount
            logger.info(f"Terminated {terminated} idle connections for {username}")


def reset_password(username: str, new_password: str) -> None:
    """Reset a user's password."""
    # FIX: Input validation + sql.Identifier for role name + %s for password
    if not validate_identifier(username):
        logger.error(f"Invalid username format: {username}")
        return

    with closing(get_connection()) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            # sql.Identifier() safely quotes the role name
            # %s safely handles the password value
            cur.execute(
                sql.SQL("ALTER ROLE {} PASSWORD %s").format(
                    sql.Identifier(username)
                ),
                (new_password,)
            )
            logger.info(f"Password reset for {username}")


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: python3 admin_tool.py <command> <argument> [extra_args]")
        print("Commands: lookup_db, lookup_user, drop_idle, reset_password")
        sys.exit(1)

    command = sys.argv[1]
    argument = sys.argv[2]

    if command == 'lookup_db':
        lookup_database(argument)
    elif command == 'lookup_user':
        lookup_user(argument)
    elif command == 'drop_idle':
        drop_idle_connections(argument)
    elif command == 'reset_password':
        if len(sys.argv) < 4:
            print("Usage: python3 admin_tool.py reset_password <username> <new_password>")
            sys.exit(1)
        reset_password(argument, sys.argv[3])
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
```

**Step 5: Test that injection no longer works:**

```bash
# This should safely return "not found" instead of crashing or executing injected SQL
python3 ~/admin_tool_fixed.py lookup_db "client's_data"

# This should be rejected by input validation
python3 ~/admin_tool_fixed.py drop_idle "'; DROP TABLE students; --"
```

Expected output:

```
2026-06-09 14:30:00 [INFO] Database not found: client's_data
2026-06-09 14:30:00 [ERROR] Invalid username format: '; DROP TABLE students; --
```

The apostrophe in `client's_data` is handled safely by the parameterized query. The injection attempt in `drop_idle` is caught by input validation before it even reaches the database.

---

## Key Takeaways

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| SQL injection via f-string | User input embedded directly in SQL | Use `%s` parameterized placeholders |
| SQL injection via % operator | Python string formatting looks like psycopg2 but is not | Use `cur.execute(sql, (params,))` - the SECOND argument |
| SQL injection via concatenation | String `+` operator builds SQL from user input | Same fix - parameterized queries |
| Identifier injection in DDL | Cannot use `%s` for role/table names | Use `psycopg2.sql.Identifier()` |
| No input validation | Any string accepted as username | Regex validation as defense-in-depth |

**The three rules:**
1. **NEVER** put user input into SQL strings with f-strings, %, +, or .format()
2. For VALUES: use `%s` placeholders with parameter tuples
3. For IDENTIFIERS (table/role names): use `psycopg2.sql.Identifier()`

This applies to DBA scripts too. "But only DBAs run this script" is not an excuse - a typo, a weird database name, or a copy-paste error can trigger the same damage as a deliberate attack.
