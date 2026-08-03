---
layout: default
title: "Functions, Heredocs, and psql Integration"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 2
---

# Functions, Here Documents, and psql Integration

## The Big Picture

In the previous chapter, you learned how to receive parameters, store them in
variables, and set up safety nets. But a script that is just a flat list of commands
gets messy fast - especially when you are provisioning a database that needs roles,
grants, schemas, and default privileges.

This chapter covers three concepts that organize your script into clean, reusable
pieces:

1. **Functions** - Named, callable blocks of commands
2. **Here documents** - Multi-line SQL fed to `psql` directly from your script
3. **psql integration** - The different ways to run SQL from Bash

---

## Bash Functions

### Defining and Calling Functions

A function is a named block of commands. Think of it like a stored procedure in
PostgreSQL, but simpler.

```bash
create_roles() {
    echo "Creating roles for $APP_NAME..."
    psql -c "CREATE ROLE \"${APP_NAME}_read_group\" WITH NOLOGIN;"
    psql -c "CREATE ROLE \"${APP_NAME}_write_group\" WITH NOLOGIN;"
    psql -c "CREATE ROLE \"${APP_NAME}_app_one\" WITH LOGIN;"
}
```

To call it:

```bash
create_roles
```

No parentheses when calling. No `CALL` keyword. Just the function name.

**Important: functions must be defined before they are called.** Bash reads top to
bottom. The common pattern is to define all functions at the top, call them at the
bottom.

### Function Arguments

Functions accept arguments through positional parameters, just like scripts. But here
is the part that confuses people: **`$1` inside a function is the function's first
argument, not the script's first argument.**

```bash
grant_connect() {
    local db_name="$1"
    local role_name="$2"
    psql -c "GRANT CONNECT ON DATABASE \"$db_name\" TO \"$role_name\";"
}

# Calling with arguments:
grant_connect "promos" "promos_read_group"
grant_connect "promos" "promos_write_group"
```

Inside `grant_connect`, `$1` is `"promos"` and `$2` is `"promos_read_group"`. The
script's original `$1` is not visible unless you saved it to a named variable first.

This is why the previous chapter told you to assign `$1` to `APP_NAME` at the top.
Named variables are accessible everywhere. Positional parameters are scoped to
whatever is currently running.

### Local Variables

By default, every variable in Bash is **global**. If you set `RESULT="done"` inside a
function, it is visible everywhere else in the script. That leads to subtle bugs when
two functions use the same variable name.

The fix is the `local` keyword:

```bash
create_database() {
    local db_name="$1"
    local tablespace="$2"
    local owner="$3"

    psql -c "CREATE DATABASE \"$db_name\" OWNER \"$owner\" TABLESPACE \"$tablespace\";"
}
```

Variables declared with `local` only exist inside that function. When the function
returns, they disappear.

**Rule of thumb: always use `local` for variables inside functions.**

### Return Values vs Echo for Output

Functions can "return" data in two ways:

**The `return` statement sets an exit code (0-255 only):**

```bash
check_db_exists() {
    local db_name="$1"
    psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | grep -q 1
    return $?
}

if check_db_exists "promos"; then
    echo "Database already exists"
fi
```

`return` is for signaling success or failure. You cannot `return "promos"` - it only
accepts integers.

**Echo for returning data:**

```bash
get_db_owner() {
    local db_name="$1"
    psql -tAc "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = '$db_name'"
}

# Capture the output with command substitution:
CURRENT_OWNER=$(get_db_owner "promos")
echo "Current owner: $CURRENT_OWNER"
```

The `$(...)` syntax captures whatever the function prints to stdout.

**Key insight: if a function uses stdout for its "return value," do not also print
debug messages to stdout.** Send debug output to stderr with `>&2`:

```bash
get_db_owner() {
    local db_name="$1"
    echo "Looking up owner for $db_name..." >&2    # stderr, not captured
    psql -tAc "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = '$db_name'"
}
```

---

## Here Documents

### What Is a Here Document?

A here document (heredoc) lets you embed a multi-line block of text directly in your
script. Instead of building long strings with concatenation or escaping newlines, you
write the text naturally.

```bash
cat <<EOF
Database Provisioning Report
-----------------------------
Application: $APP_NAME
Tablespace:  $TABLESPACE
Owner:       $OWNER
EOF
```

Everything between `<<EOF` and `EOF` is sent to `cat` as input. `EOF` can be any word
you choose - `SQL`, `END`, `MARKER` all work. The closing marker must appear alone on
its own line with no leading spaces.

### Quoting Inside Heredocs: <<EOF vs <<'EOF'

This is critical. There are two forms:

**`<<EOF` (unquoted) - Variables ARE expanded:**

```bash
APP_NAME="promos"

psql <<EOF
CREATE ROLE "${APP_NAME}_read_group" WITH NOLOGIN;
CREATE ROLE "${APP_NAME}_write_group" WITH NOLOGIN;
EOF
```

psql receives:

```sql
CREATE ROLE "promos_read_group" WITH NOLOGIN;
CREATE ROLE "promos_write_group" WITH NOLOGIN;
```

Bash substitutes the variables before the text reaches psql. This is what you want
most of the time for provisioning scripts.

**`<<'EOF'` (quoted) - Variables are NOT expanded:**

```bash
APP_NAME="promos"

psql <<'EOF'
CREATE ROLE "${APP_NAME}_read_group" WITH NOLOGIN;
EOF
```

psql receives the literal text `${APP_NAME}_read_group` - no substitution. Use this
when the content contains dollar signs that are not Bash variables (like PL/pgSQL
`$$` delimiters or function body `$1` references).

---

## Here Documents with psql

This is where everything comes together for DBA work. You can feed a heredoc directly
to `psql`:

```bash
psql -h localhost -U postgres <<EOF
CREATE ROLE "${APP_NAME}_read_group" WITH NOLOGIN;
CREATE ROLE "${APP_NAME}_write_group" WITH NOLOGIN;
CREATE ROLE "${APP_NAME}_app_one" WITH LOGIN;
EOF
```

Bash expands `${APP_NAME}`, then sends the resulting SQL to `psql` as standard input.
psql executes each statement in order.

You can connect to a specific database:

```bash
psql -h localhost -U postgres -d "$APP_NAME" <<EOF
CREATE SCHEMA IF NOT EXISTS "$APP_NAME";
GRANT SELECT ON ALL TABLES IN SCHEMA "$APP_NAME" TO "${APP_NAME}_read_group";
ALTER DEFAULT PRIVILEGES IN SCHEMA "$APP_NAME"
    GRANT SELECT ON TABLES TO "${APP_NAME}_read_group";
EOF
```

---

## psql's -v Flag for Variable Passing

The `-v` flag passes variables on the psql side rather than the Bash side:

```bash
psql -v app_name="promos" <<'EOF'
CREATE ROLE :"app_name" WITH NOLOGIN;
\echo Creating role for :app_name
EOF
```

Notice: the heredoc uses `<<'EOF'` (quoted) so Bash does not expand anything. The `-v`
flag sets `app_name` as a psql variable. Inside the SQL:

| Syntax            | Expands to         | Use for              |
|-------------------|--------------------|----------------------|
| `:app_name`       | `promos`           | Meta-commands, bare  |
| `:'app_name'`     | `'promos'`         | SQL string literals  |
| `:"app_name"`     | `"promos"`         | SQL identifiers      |

For database provisioning, you typically use `:"app_name"` since role names and
database names are identifiers.

The `-v` flag is clean for one or two variables. But with five or six values, the
command line gets unwieldy. At that point, Bash variable expansion with an unquoted
heredoc is often more readable.

---

## When to Use Heredoc vs -c vs -f

### `psql -c` - Single Statement

```bash
psql -c "CREATE ROLE \"${APP_NAME}_read_group\" WITH NOLOGIN;"
```

Quick and simple for one statement. But escaping double quotes inside double quotes
gets ugly fast. If your statement has multiple quotes, use a heredoc instead.

### `psql <<EOF` - Heredoc for Multi-Statement Blocks

```bash
psql <<EOF
CREATE ROLE "${APP_NAME}_read_group" WITH NOLOGIN;
CREATE ROLE "${APP_NAME}_write_group" WITH NOLOGIN;
EOF
```

The SQL reads naturally without escaping. All statements run in a single psql session,
so you can use meta-commands like `\connect` between them. Usually the best choice for
provisioning scripts.

### `psql -f` - SQL File

```bash
psql -f provision-template.sql
```

Best for standalone `.sql` files. You can combine with `-v` to inject variables:

```bash
psql -v app_name="promos" -f provision-template.sql
```

### Decision Guide

| Situation                           | Best approach                    |
|-------------------------------------|----------------------------------|
| Single simple statement             | `-c`                             |
| Multiple statements with Bash vars  | Heredoc (`<<EOF`)                |
| Multiple statements, psql vars      | Heredoc (`<<'EOF'`) + `-v`       |
| Static SQL file, no variables       | `-f`                             |
| SQL file with variables             | `-f` + `-v`                      |
| Need `\connect` between databases   | Heredoc                          |

---

## Combining It All: Functions + Heredocs + psql

Here is the structure your parameterized provisioning script will follow:

```bash
#!/bin/bash
set -euo pipefail

# ── Parameters ──────────────────────────────────────────
APP_NAME="${1:?Usage: $0 <app_name> [tablespace] [owner]}"
TABLESPACE="${2:-pg_default}"
OWNER="${3:-postgres}"

PG_HOST="${PG_HOST:-localhost}"
PG_USER="${PG_USER:-postgres}"

PSQL="psql -h $PG_HOST -U $PG_USER -X --set ON_ERROR_STOP=on"

# ── Functions ───────────────────────────────────────────
create_roles() {
    local app="$1"
    echo "Creating roles for $app..."

    $PSQL <<EOF
CREATE ROLE "${app}_read_group"  WITH NOLOGIN;
CREATE ROLE "${app}_write_group" WITH NOLOGIN;
CREATE ROLE "${app}_app_one"     WITH LOGIN;
EOF
}

create_database() {
    local app="$1"
    local tblspc="$2"
    local owner="$3"
    echo "Creating database $app..."

    $PSQL <<EOF
SELECT 'CREATE DATABASE "${app}" OWNER "${owner}" TABLESPACE "${tblspc}"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${app}')
\gexec
EOF
}

grant_connect() {
    local app="$1"
    echo "Granting connect on $app..."

    $PSQL <<EOF
GRANT CONNECT ON DATABASE "${app}" TO "${app}_read_group";
GRANT CONNECT ON DATABASE "${app}" TO "${app}_write_group";
GRANT CONNECT ON DATABASE "${app}" TO "${app}_app_one";
EOF
}

setup_schema() {
    local app="$1"
    echo "Setting up schema in $app..."

    $PSQL -d "$app" <<EOF
CREATE SCHEMA IF NOT EXISTS "${app}";
GRANT SELECT ON ALL TABLES IN SCHEMA "${app}" TO "${app}_read_group";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${app}"
    GRANT SELECT ON TABLES TO "${app}_read_group";
EOF
}

# ── Main ────────────────────────────────────────────────
echo "=== Provisioning database: $APP_NAME ==="
create_roles "$APP_NAME"
create_database "$APP_NAME" "$TABLESPACE" "$OWNER"
grant_connect "$APP_NAME"
setup_schema "$APP_NAME"
echo "=== Done ==="
```

A few things to notice about this structure:

**PSQL variable** - The connection string is defined once. `-X` skips the user's
`.psqlrc` so the script behaves the same regardless of who runs it. `ON_ERROR_STOP=on`
makes psql exit on the first SQL error - without this, psql returns exit code 0 even
when SQL fails, which means `set -e` would not catch it.

**One function per task** - Each function does one thing. If the connect grants fail,
you know exactly where to look.

**Functions take arguments** - Even though `APP_NAME` is global, functions accept it as
a parameter. This makes each function self-documenting and easier to reuse.

**Heredocs for SQL** - The SQL reads naturally. No backslash escaping, no string
concatenation. You can copy a block out of the script, paste it into psql, and test it.

**Main section at the bottom** - Five lines that tell you the entire workflow at a
glance.

---

## Making Scripts Idempotent

A good provisioning script can run multiple times without errors. Check before acting:

```bash
db_exists() {
    local db_name="$1"
    $PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" | grep -q 1
}

create_database() {
    local app="$1"
    if db_exists "$app"; then
        echo "Database $app already exists - skipping"
        return 0
    fi
    $PSQL -c "CREATE DATABASE \"$app\" OWNER \"$OWNER\" TABLESPACE \"$TABLESPACE\";"
}
```

This check-first pattern is essential for operational scripts that might get
interrupted and restarted.

---

## Quick Reference

| Concept                    | Syntax                              | Notes                              |
|----------------------------|-------------------------------------|------------------------------------|
| Define function            | `func_name() { ... }`              | Must be defined before called      |
| Call function              | `func_name arg1 arg2`              | No parentheses when calling        |
| Local variable             | `local var="value"`                 | Scoped to function only            |
| Return exit code           | `return 0` or `return 1`            | 0-255 only, for success/failure    |
| Return data                | `echo "$value"`                     | Captured with `$(func_name)`       |
| Heredoc (with expansion)   | `command <<EOF ... EOF`             | Bash expands `$VAR` inside         |
| Heredoc (literal)          | `command <<'EOF' ... EOF`           | No expansion, pass-through         |
| psql single statement      | `psql -c "SQL"`                     | One command, quotes get messy      |
| psql heredoc               | `psql <<EOF ... EOF`                | Multi-statement, clean SQL         |
| psql from file             | `psql -f file.sql`                  | Static SQL, no Bash vars           |
| psql variable              | `psql -v name="val"`                | Use `:"name"` in SQL               |
| Stop on SQL error          | `--set ON_ERROR_STOP=on`            | Essential for provisioning          |

---

## What You Have Now

Between this chapter and the previous one, you have every concept needed to build the
parameterized database provisioner:

- **Chapter 1**: Variables, parameters, quoting, exit codes, safety flags
- **Chapter 2**: Functions for organization, heredocs for clean SQL, psql integration

The SQL script you started with - the one that creates `promos_read_group`,
`promos_write_group`, the database, the schema, and all the grants - can now be
wrapped in functions, parameterized with `$1`, and run for any application name:

```bash
./provision-db.sh promos
./provision-db.sh inventory
./provision-db.sh analytics
```

Same script, different name, different database. That is the power of parameterization.
