---
layout: default
title: "BUILD 06 - psql Integration Patterns"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 8
---

# BUILD 06: psql Integration Patterns (35 min)

In this guide you will learn the different ways to run SQL from a shell script using psql. You already know heredocs from the previous guide. Now you will learn single-command mode, file mode, psql variables, connecting to specific databases, idempotent checks, and - critically - error handling.

---

## Why This Matters

Your provisioner script will need to: run SQL against different databases, check if things exist before creating them, and stop immediately if something goes wrong. These patterns are how production DBA scripts work.

---

## Step 1: psql -c for Single SQL Statements

The `-c` flag runs one SQL statement and exits. This is the simplest pattern.

On **pg-lab**, as **ec2-user**:

```bash
sudo su - postgres
```

Now as **postgres** on **pg-lab**:

```bash
psql -c "SELECT version();"
```

Expected output (yours will differ):
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

The `-c` flag takes a single SQL string. It connects, runs the statement, prints the result, and disconnects. Good for quick checks but limited to one statement per call.

You can also suppress column headers and row counts with `-t` (tuples only) and `-A` (unaligned output). This is useful when you want to capture a value into a shell variable.

```bash
psql -tA -c "SELECT current_database();"
```

Expected output (yours will differ):
```
postgres
```

The `-t` flag removes the header and footer. The `-A` flag removes alignment padding. Together they give you just the raw value - perfect for capturing into a variable.

---

## Step 2: psql -f for SQL Files

The `-f` flag runs an entire SQL file. This is what you would use if you kept your SQL in a separate file.

Still as **postgres** on **pg-lab**:

```bash
vi ~/test-commands.sql
```

Type the following:

```sql
SELECT 'Step 1: checking version' AS status;
SELECT version();
SELECT 'Step 2: checking current user' AS status;
SELECT current_user;
```

Save and exit vi (`:wq`).

Run it.

```bash
psql -f ~/test-commands.sql
```

Expected output (yours will differ):
```
         status
--------------------------
 Step 1: checking version
(1 row)

                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x ...
(1 row)

            status
-------------------------------
 Step 2: checking current user
(1 row)

 current_user
--------------
 postgres
(1 row)
```

The `-f` flag is useful when SQL is complex and you want to keep it in version control as a .sql file. But for a parameterized script, heredocs are usually better because variables expand inline.

Clean up the test file.

```bash
rm ~/test-commands.sql
```

---

## Step 3: psql with Heredoc for Multi-line SQL

You learned this in the previous guide. Here is the pattern you will use most often.

Still as **postgres** on **pg-lab**:

```bash
vi ~/heredoc-pattern.sh
```

Type the following:

```bash
#!/bin/bash

psql -d postgres <<SQL
SELECT 'heredoc pattern' AS method;
SELECT now() AS current_time;
SQL
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/heredoc-pattern.sh
```

```bash
~/heredoc-pattern.sh
```

Expected output (yours will differ):
```
     method
-----------------
 heredoc pattern
(1 row)

         current_time
-------------------------------
 2026-06-23 14:30:00.123456+00
(1 row)
```

Clean up.

```bash
rm ~/heredoc-pattern.sh
```

---

## Step 4: Connecting to Different Databases

Your provisioner script must connect to `postgres` (to create the database) and then to the new database (to create schemas and set grants). Use the `-d` flag.

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "SELECT current_database();"
```

Expected output (yours will differ):
```
 current_database
------------------
 postgres
(1 row)
```

```bash
psql -d template1 -c "SELECT current_database();"
```

Expected output (yours will differ):
```
 current_database
------------------
 template1
(1 row)
```

In a script, you will switch databases by using different `-d` values in different psql calls. Unlike the `\connect` command in a .sql file, each `psql -d` call is an independent connection.

---

## Step 5: psql Variables with -v

The `-v` flag passes variables into psql. Inside the SQL, you reference them with `:'variable_name'` (with the colon and quotes). This is psql's own variable system - separate from shell variables.

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -v db_name='promos' <<'SQL'
SELECT :'db_name' AS database_name;
SQL
```

Expected output (yours will differ):
```
 database_name
---------------
 promos
(1 row)
```

Notice two things:

1. The heredoc uses `<<'SQL'` (quoted) so bash does NOT expand variables
2. Inside the SQL, `:'db_name'` is a psql variable reference - psql expands it

This is an alternative to shell variable expansion in heredocs. Both approaches work. For the provisioner script, you will use shell variable expansion (unquoted heredoc) because it is simpler and you are already comfortable with it.

---

## Step 6: Checking If a Role Exists (Idempotent Pattern)

An idempotent script can be run multiple times without error. Your original SQL does NOT have `IF NOT EXISTS` on role creation. Here is the pattern to add it.

Still as **postgres** on **pg-lab**:

```bash
vi ~/check-role.sh
```

Type the following:

```bash
#!/bin/bash

ROLE_NAME="test_role_beverly"

# Check if role exists. psql -tA returns just the value, no headers.
ROLE_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${ROLE_NAME}';")

if [ "${ROLE_EXISTS}" = "1" ]; then
    echo "Role ${ROLE_NAME} already exists. Skipping."
else
    psql -d postgres -c "CREATE ROLE \"${ROLE_NAME}\" WITH NOLOGIN;"
    echo "Role ${ROLE_NAME} created."
fi
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/check-role.sh
```

Run it twice.

```bash
~/check-role.sh
```

Expected output (yours will differ):
```
CREATE ROLE
Role test_role_beverly created.
```

```bash
~/check-role.sh
```

Expected output (yours will differ):
```
Role test_role_beverly already exists. Skipping.
```

No error on the second run. That is idempotency.

An alternative approach uses `DO` blocks:

```bash
vi ~/check-role-do.sh
```

Type the following:

```bash
#!/bin/bash

ROLE_NAME="test_role_beverly_v2"

psql -d postgres <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${ROLE_NAME}') THEN
        CREATE ROLE "${ROLE_NAME}" WITH NOLOGIN;
        RAISE NOTICE 'Role ${ROLE_NAME} created.';
    ELSE
        RAISE NOTICE 'Role ${ROLE_NAME} already exists.';
    END IF;
END
\$\$;
SQL
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/check-role-do.sh
```

```bash
~/check-role-do.sh
```

Expected output (yours will differ):
```
NOTICE:  Role test_role_beverly_v2 created.
DO
```

Notice the `\$\$` escaping - this is because the heredoc is unquoted (`<<SQL`) so bash would try to interpret `$$` as the current process ID. The backslashes prevent that.

For the provisioner, you will use the simpler shell-level check (the first approach) to avoid the escaping complexity.

---

## Step 7: Checking If a Database Exists

The same pattern works for databases.

Still as **postgres** on **pg-lab**:

```bash
vi ~/check-db.sh
```

Type the following:

```bash
#!/bin/bash

DB_NAME="test_db_beverly"

DB_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}';")

if [ "${DB_EXISTS}" = "1" ]; then
    echo "Database ${DB_NAME} already exists. Skipping."
else
    psql -d postgres -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"postgres\";"
    echo "Database ${DB_NAME} created."
fi
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/check-db.sh
```

```bash
~/check-db.sh
```

Expected output (yours will differ):
```
CREATE DATABASE
Database test_db_beverly created.
```

```bash
~/check-db.sh
```

Expected output (yours will differ):
```
Database test_db_beverly already exists. Skipping.
```

---

## Step 8: Error Handling with ON_ERROR_STOP

By default, psql continues running even when a statement fails. This is dangerous in a provisioning script. The `ON_ERROR_STOP=1` variable makes psql exit immediately on the first error.

Still as **postgres** on **pg-lab**:

First, see the default behavior (no error stop).

```bash
vi ~/no-error-stop.sh
```

Type the following:

```bash
#!/bin/bash

psql -d postgres <<SQL
SELECT 'before the error' AS status;
SELECT * FROM table_that_does_not_exist;
SELECT 'after the error - this still runs!' AS status;
SQL

echo "Script exit code: $?"
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/no-error-stop.sh
```

```bash
~/no-error-stop.sh
```

Expected output (yours will differ):
```
     status
------------------
 before the error
(1 row)

ERROR:  relation "table_that_does_not_exist" does not exist
LINE 1: SELECT * FROM table_that_does_not_exist;
                      ^
          status
------------------------------------
 after the error - this still runs!
(1 row)

Script exit code: 0
```

psql hit an error but kept going and returned exit code 0. That is dangerous.

Now add ON_ERROR_STOP.

```bash
vi ~/with-error-stop.sh
```

Type the following:

```bash
#!/bin/bash

psql -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT 'before the error' AS status;
SELECT * FROM table_that_does_not_exist;
SELECT 'after the error - this will NOT run' AS status;
SQL

echo "Script exit code: $?"
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/with-error-stop.sh
```

```bash
~/with-error-stop.sh
```

Expected output (yours will differ):
```
     status
------------------
 before the error
(1 row)

ERROR:  relation "table_that_does_not_exist" does not exist
LINE 1: SELECT * FROM table_that_does_not_exist;
                      ^
Script exit code: 3
```

With `ON_ERROR_STOP=1`, psql stopped at the error, skipped the third query, and returned a non-zero exit code. Combined with `set -e` in your script (which exits on any non-zero return), this gives you safe error handling.

---

## Step 9: Putting It Together - A Small Provisioning Script

Let's combine everything into a script that creates a role and a database.

Still as **postgres** on **pg-lab**:

```bash
vi ~/mini-provisioner.sh
```

Type the following:

```bash
#!/bin/bash
set -euo pipefail

DB_NAME="mini_test"
ROLE_NAME="mini_reader"

echo "=== Step 1: Create role ==="
ROLE_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${ROLE_NAME}';")
if [ "${ROLE_EXISTS}" = "1" ]; then
    echo "Role ${ROLE_NAME} already exists."
else
    psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${ROLE_NAME}\" WITH NOLOGIN;"
    echo "Role ${ROLE_NAME} created."
fi

echo ""
echo "=== Step 2: Create database ==="
DB_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}';")
if [ "${DB_EXISTS}" = "1" ]; then
    echo "Database ${DB_NAME} already exists."
else
    psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"postgres\";"
    echo "Database ${DB_NAME} created."
fi

echo ""
echo "=== Step 3: Grant connect ==="
psql -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE \"${DB_NAME}\" TO \"${ROLE_NAME}\";"
echo "Granted CONNECT on ${DB_NAME} to ${ROLE_NAME}."

echo ""
echo "=== Done ==="
```

Save and exit vi (`:wq`).

```bash
chmod +x ~/mini-provisioner.sh
```

```bash
~/mini-provisioner.sh
```

Expected output (yours will differ):
```
=== Step 1: Create role ===
CREATE ROLE
Role mini_reader created.

=== Step 2: Create database ===
CREATE DATABASE
Database mini_test created.

=== Step 3: Grant connect ===
GRANT
Granted CONNECT on mini_test to mini_reader.

=== Done ===
```

Run it again to test idempotency.

```bash
~/mini-provisioner.sh
```

Expected output (yours will differ):
```
=== Step 1: Create role ===
Role mini_reader already exists.

=== Step 2: Create database ===
Database mini_test already exists.

=== Step 3: Grant connect ===
GRANT
Granted CONNECT on mini_test to mini_reader.

=== Done ===
```

No errors on the second run. The GRANT statement runs again but that is fine - granting a permission that already exists is a no-op in PostgreSQL.

---

## Step 10: Clean Up

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "DROP DATABASE IF EXISTS mini_test;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS mini_reader;"
```

```bash
psql -d postgres -c "DROP DATABASE IF EXISTS test_db_beverly;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS test_role_beverly;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS test_role_beverly_v2;"
```

```bash
rm -f ~/check-role.sh ~/check-role-do.sh ~/check-db.sh
rm -f ~/no-error-stop.sh ~/with-error-stop.sh ~/mini-provisioner.sh
```

Exit back to ec2-user.

```bash
exit
```

---

## What You Learned

- `psql -c "SQL"` runs a single statement - good for quick checks
- `psql -f file.sql` runs an entire SQL file
- `psql <<SQL ... SQL` (heredoc) is the best pattern for inline multi-line SQL in scripts
- `psql -d dbname` connects to a specific database
- `psql -tA` gives raw values without headers - use this to capture results into variables
- `psql -v ON_ERROR_STOP=1` makes psql exit on the first error - always use this
- Check `pg_roles` and `pg_database` catalog tables to make scripts idempotent
- GRANT statements are naturally idempotent - running them twice is safe

In the next guide, you will build the full provisioner script using all of these patterns.
