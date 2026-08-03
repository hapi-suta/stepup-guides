---
layout: default
title: "BUILD 07 - Building the Provisioner"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 9
---

# BUILD 07: Building the Database Provisioner (45 min)

In this guide you will build the full `provision-db.sh` script. You will take the original SQL provisioning script and convert it into a parameterized, idempotent shell script with proper structure, error handling, and clear output.

---

## The Original SQL Script

Before writing code, read through the original SQL and identify every value that should become a parameter. Here is the SQL with annotations:

```sql
-- "promos" appears everywhere -> APP_NAME parameter
-- "data" tablespace -> TABLESPACE parameter
-- "promos_app_one" login role -> APP_USER parameter
-- "lw_promos_l20" human user -> HUMAN_USER parameter

CREATE ROLE "promos_read_group"  WITH NOLOGIN;       -- derived: {APP_NAME}_read_group
CREATE ROLE "promos_write_group" WITH NOLOGIN;       -- derived: {APP_NAME}_write_group
CREATE ROLE "promos_app_one"     WITH LOGIN;         -- APP_USER (not derived - could be anything)

CREATE DATABASE "promos" OWNER "postgres" TABLESPACE "data";  -- APP_NAME + TABLESPACE
-- ... grants use APP_NAME, APP_USER ...
-- schema name matches APP_NAME

GRANT "promos_read_group" TO "lw_promos_l20";        -- HUMAN_USER gets read access
```

Four parameters. Everything else is derived from them. Now you will build the script.

---

## Step 1: Create the Script File

On **pg-lab**, as **ec2-user**:

```bash
mkdir -p ~/scripts
```

```bash
vi ~/scripts/provision-db.sh
```

Start with the shebang and safety settings.

```bash
#!/bin/bash
set -euo pipefail
```

- `set -e` exits immediately if any command fails
- `set -u` treats unset variables as errors (catches typos)
- `set -o pipefail` catches failures in piped commands

Save and exit vi (`:wq`) after each step. You will keep reopening the file to add more.

---

## Step 2: Add the Usage Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add the usage function after `set -euo pipefail`:

```bash
#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: provision-db.sh <APP_NAME> <TABLESPACE> <APP_USER> <HUMAN_USER>

Provisions a PostgreSQL database with standard role structure:
  - {APP_NAME}_read_group  (NOLOGIN) - read-only access
  - {APP_NAME}_write_group (NOLOGIN) - read-write access
  - {APP_USER}             (LOGIN)   - application service account
  - Grants read group membership to HUMAN_USER

Arguments:
  APP_NAME    Database name, schema name, and role prefix (e.g. promos)
  TABLESPACE  Tablespace for the database (e.g. data, pg_default)
  APP_USER    Application login role name (e.g. promos_app_one)
  HUMAN_USER  Human user to receive read access (e.g. lw_promos_l20)

Example:
  ./provision-db.sh promos data promos_app_one lw_promos_l20
USAGE
    exit 1
}
```

Notice the heredoc uses `<<'USAGE'` (quoted) so that `{APP_NAME}` prints literally instead of bash trying to expand it as a variable.

Save and exit vi (`:wq`).

---

## Step 3: Add Argument Validation

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add the validate_args function and argument parsing after the usage function:

```bash
validate_args() {
    if [ $# -ne 4 ]; then
        echo "ERROR: Expected 4 arguments, got $#."
        echo ""
        usage
    fi
}

# --- Parse arguments ---
validate_args "$@"

APP_NAME="$1"
TABLESPACE="$2"
APP_USER="$3"
HUMAN_USER="$4"

# Derived role names
READ_GROUP="${APP_NAME}_read_group"
WRITE_GROUP="${APP_NAME}_write_group"

echo "============================================"
echo "Database Provisioner"
echo "============================================"
echo "APP_NAME:    ${APP_NAME}"
echo "TABLESPACE:  ${TABLESPACE}"
echo "APP_USER:    ${APP_USER}"
echo "HUMAN_USER:  ${HUMAN_USER}"
echo "READ_GROUP:  ${READ_GROUP}"
echo "WRITE_GROUP: ${WRITE_GROUP}"
echo "============================================"
echo ""
```

The `"$@"` passes all script arguments to the function. Each argument is individually quoted, which is important if any value contains spaces (unlikely for database names but good practice).

Save and exit vi (`:wq`).

Let's test what we have so far.

```bash
chmod +x ~/scripts/provision-db.sh
```

```bash
~/scripts/provision-db.sh
```

Expected output (yours will differ):
```
ERROR: Expected 4 arguments, got 0.

Usage: provision-db.sh <APP_NAME> <TABLESPACE> <APP_USER> <HUMAN_USER>
...
```

```bash
~/scripts/provision-db.sh promos data promos_app_one lw_promos_l20
```

Expected output (yours will differ):
```
============================================
Database Provisioner
============================================
APP_NAME:    promos
TABLESPACE:  data
APP_USER:    promos_app_one
HUMAN_USER:  lw_promos_l20
READ_GROUP:  promos_read_group
WRITE_GROUP: promos_write_group
============================================
```

The skeleton works. Now add the real functions.

---

## Step 4: Add the create_roles Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add this function BEFORE the `# --- Parse arguments ---` line. All functions should be defined before they are called.

```bash
create_roles() {
    local read_group="$1"
    local write_group="$2"
    local app_user="$3"

    echo "--- Creating roles ---"

    # Read group (NOLOGIN)
    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${read_group}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${read_group} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${read_group}\" WITH NOLOGIN;"
        echo "  Role ${read_group} created."
    fi

    # Write group (NOLOGIN)
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${write_group}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${write_group} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${write_group}\" WITH NOLOGIN;"
        echo "  Role ${write_group} created."
    fi

    # App user (LOGIN)
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${app_user}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${app_user} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${app_user}\" WITH LOGIN;"
        echo "  Role ${app_user} created."
    fi

    echo ""
}
```

The `local` keyword makes variables scoped to the function - they do not leak into the rest of the script.

Save and exit vi (`:wq`).

---

## Step 5: Add the create_database Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add this function after `create_roles`:

```bash
create_database() {
    local db_name="$1"
    local tablespace="$2"
    local read_group="$3"
    local write_group="$4"
    local app_user="$5"

    echo "--- Creating database ---"

    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '${db_name}';")
    if [ "${exists}" = "1" ]; then
        echo "  Database ${db_name} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c \
            "CREATE DATABASE \"${db_name}\" OWNER \"postgres\" TABLESPACE \"${tablespace}\";"
        echo "  Database ${db_name} created."
    fi

    # Grant CONNECT to all three roles
    psql -d postgres -v ON_ERROR_STOP=1 <<SQL
GRANT CONNECT ON DATABASE "${db_name}" TO "${read_group}";
GRANT CONNECT ON DATABASE "${db_name}" TO "${write_group}";
GRANT CONNECT ON DATABASE "${db_name}" TO "${app_user}";
SQL
    echo "  CONNECT granted to ${read_group}, ${write_group}, ${app_user}."
    echo ""
}
```

The backslash (`\`) at the end of the CREATE DATABASE line continues the command on the next line. This keeps lines readable.

Save and exit vi (`:wq`).

---

## Step 6: Add the create_schema Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add this function after `create_database`:

```bash
create_schema() {
    local db_name="$1"
    local schema_name="$2"

    echo "--- Creating schema ---"

    psql -d "${db_name}" -v ON_ERROR_STOP=1 -c \
        "CREATE SCHEMA IF NOT EXISTS \"${schema_name}\";"
    echo "  Schema ${schema_name} created (or already existed)."
    echo ""
}
```

This function connects to the new database (not postgres) using `-d "${db_name}"`. The `IF NOT EXISTS` clause makes it idempotent without needing a separate check.

Save and exit vi (`:wq`).

---

## Step 7: Add the grant_permissions Function

This is the largest function. It mirrors the GRANT and ALTER DEFAULT PRIVILEGES statements from the original SQL.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add this function after `create_schema`:

```bash
grant_permissions() {
    local db_name="$1"
    local schema_name="$2"
    local read_group="$3"
    local write_group="$4"
    local app_user="$5"

    echo "--- Granting permissions ---"

    # Read group: SELECT on tables
    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT SELECT ON ALL TABLES IN SCHEMA "${schema_name}" TO "${read_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT ON TABLES TO "${read_group}";
SQL
    echo "  Read permissions granted to ${read_group}."

    # Write group: full DML on tables + sequences
    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE
    ON ALL TABLES IN SCHEMA "${schema_name}" TO "${write_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE ON TABLES TO "${write_group}";
GRANT SELECT, UPDATE, USAGE
    ON ALL SEQUENCES IN SCHEMA "${schema_name}" TO "${write_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO "${write_group}";
SQL
    echo "  Write permissions granted to ${write_group}."

    # App user: full DML on tables + sequences (same as write group)
    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE
    ON ALL TABLES IN SCHEMA "${schema_name}" TO "${app_user}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE ON TABLES TO "${app_user}";
GRANT SELECT, UPDATE, USAGE
    ON ALL SEQUENCES IN SCHEMA "${schema_name}" TO "${app_user}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO "${app_user}";
SQL
    echo "  App permissions granted to ${app_user}."
    echo ""
}
```

Each heredoc is an unquoted `<<SQL` so the shell variables expand into the SQL. The GRANT statements are naturally idempotent - granting a privilege that already exists does nothing.

Save and exit vi (`:wq`).

---

## Step 8: Add the assign_human_user Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add this function after `grant_permissions`:

```bash
assign_human_user() {
    local read_group="$1"
    local human_user="$2"

    echo "--- Assigning human user ---"

    # Check that the human user role exists
    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${human_user}';")
    if [ "${exists}" != "1" ]; then
        echo "  WARNING: Role ${human_user} does not exist. Creating it."
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${human_user}\" WITH LOGIN;"
        echo "  Role ${human_user} created with LOGIN."
    fi

    psql -d postgres -v ON_ERROR_STOP=1 -c \
        "GRANT \"${read_group}\" TO \"${human_user}\";"
    echo "  Granted ${read_group} to ${human_user}."
    echo ""
}
```

This function adds a safety check: if the human user does not exist yet, it creates the role first. The original SQL assumed the human user already existed - this version is more defensive.

Save and exit vi (`:wq`).

---

## Step 9: Wire Everything Together in main

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

Add the main function and call it at the bottom of the script, after the argument parsing section:

```bash
main() {
    create_roles "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    create_database "${APP_NAME}" "${TABLESPACE}" "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    create_schema "${APP_NAME}" "${APP_NAME}"
    grant_permissions "${APP_NAME}" "${APP_NAME}" "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    assign_human_user "${READ_GROUP}" "${HUMAN_USER}"

    echo "============================================"
    echo "Provisioning complete for ${APP_NAME}."
    echo "============================================"
}

main
```

Notice `create_schema "${APP_NAME}" "${APP_NAME}"` - the database name and schema name are both APP_NAME. This matches the original SQL where the schema has the same name as the database.

Save and exit vi (`:wq`).

---

## Step 10: Review the Complete Script

Let's verify the file looks correct. On **pg-lab**, as **ec2-user**:

```bash
cat -n ~/scripts/provision-db.sh
```

The complete script should look like this (line numbers will vary):

```bash
#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: provision-db.sh <APP_NAME> <TABLESPACE> <APP_USER> <HUMAN_USER>

Provisions a PostgreSQL database with standard role structure:
  - {APP_NAME}_read_group  (NOLOGIN) - read-only access
  - {APP_NAME}_write_group (NOLOGIN) - read-write access
  - {APP_USER}             (LOGIN)   - application service account
  - Grants read group membership to HUMAN_USER

Arguments:
  APP_NAME    Database name, schema name, and role prefix (e.g. promos)
  TABLESPACE  Tablespace for the database (e.g. data, pg_default)
  APP_USER    Application login role name (e.g. promos_app_one)
  HUMAN_USER  Human user to receive read access (e.g. lw_promos_l20)

Example:
  ./provision-db.sh promos data promos_app_one lw_promos_l20
USAGE
    exit 1
}

create_roles() {
    local read_group="$1"
    local write_group="$2"
    local app_user="$3"

    echo "--- Creating roles ---"

    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${read_group}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${read_group} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${read_group}\" WITH NOLOGIN;"
        echo "  Role ${read_group} created."
    fi

    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${write_group}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${write_group} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${write_group}\" WITH NOLOGIN;"
        echo "  Role ${write_group} created."
    fi

    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${app_user}';")
    if [ "${exists}" = "1" ]; then
        echo "  Role ${app_user} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${app_user}\" WITH LOGIN;"
        echo "  Role ${app_user} created."
    fi

    echo ""
}

create_database() {
    local db_name="$1"
    local tablespace="$2"
    local read_group="$3"
    local write_group="$4"
    local app_user="$5"

    echo "--- Creating database ---"

    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '${db_name}';")
    if [ "${exists}" = "1" ]; then
        echo "  Database ${db_name} already exists."
    else
        psql -d postgres -v ON_ERROR_STOP=1 -c \
            "CREATE DATABASE \"${db_name}\" OWNER \"postgres\" TABLESPACE \"${tablespace}\";"
        echo "  Database ${db_name} created."
    fi

    psql -d postgres -v ON_ERROR_STOP=1 <<SQL
GRANT CONNECT ON DATABASE "${db_name}" TO "${read_group}";
GRANT CONNECT ON DATABASE "${db_name}" TO "${write_group}";
GRANT CONNECT ON DATABASE "${db_name}" TO "${app_user}";
SQL
    echo "  CONNECT granted to ${read_group}, ${write_group}, ${app_user}."
    echo ""
}

create_schema() {
    local db_name="$1"
    local schema_name="$2"

    echo "--- Creating schema ---"

    psql -d "${db_name}" -v ON_ERROR_STOP=1 -c \
        "CREATE SCHEMA IF NOT EXISTS \"${schema_name}\";"
    echo "  Schema ${schema_name} created (or already existed)."
    echo ""
}

grant_permissions() {
    local db_name="$1"
    local schema_name="$2"
    local read_group="$3"
    local write_group="$4"
    local app_user="$5"

    echo "--- Granting permissions ---"

    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT SELECT ON ALL TABLES IN SCHEMA "${schema_name}" TO "${read_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT ON TABLES TO "${read_group}";
SQL
    echo "  Read permissions granted to ${read_group}."

    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE
    ON ALL TABLES IN SCHEMA "${schema_name}" TO "${write_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE ON TABLES TO "${write_group}";
GRANT SELECT, UPDATE, USAGE
    ON ALL SEQUENCES IN SCHEMA "${schema_name}" TO "${write_group}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO "${write_group}";
SQL
    echo "  Write permissions granted to ${write_group}."

    psql -d "${db_name}" -v ON_ERROR_STOP=1 <<SQL
GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE
    ON ALL TABLES IN SCHEMA "${schema_name}" TO "${app_user}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT DELETE, INSERT, SELECT, TRUNCATE, UPDATE ON TABLES TO "${app_user}";
GRANT SELECT, UPDATE, USAGE
    ON ALL SEQUENCES IN SCHEMA "${schema_name}" TO "${app_user}";
ALTER DEFAULT PRIVILEGES IN SCHEMA "${schema_name}"
    GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO "${app_user}";
SQL
    echo "  App permissions granted to ${app_user}."
    echo ""
}

assign_human_user() {
    local read_group="$1"
    local human_user="$2"

    echo "--- Assigning human user ---"

    local exists
    exists=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '${human_user}';")
    if [ "${exists}" != "1" ]; then
        echo "  WARNING: Role ${human_user} does not exist. Creating it."
        psql -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE \"${human_user}\" WITH LOGIN;"
        echo "  Role ${human_user} created with LOGIN."
    fi

    psql -d postgres -v ON_ERROR_STOP=1 -c \
        "GRANT \"${read_group}\" TO \"${human_user}\";"
    echo "  Granted ${read_group} to ${human_user}."
    echo ""
}

validate_args() {
    if [ $# -ne 4 ]; then
        echo "ERROR: Expected 4 arguments, got $#."
        echo ""
        usage
    fi
}

# --- Parse arguments ---
validate_args "$@"

APP_NAME="$1"
TABLESPACE="$2"
APP_USER="$3"
HUMAN_USER="$4"

READ_GROUP="${APP_NAME}_read_group"
WRITE_GROUP="${APP_NAME}_write_group"

echo "============================================"
echo "Database Provisioner"
echo "============================================"
echo "APP_NAME:    ${APP_NAME}"
echo "TABLESPACE:  ${TABLESPACE}"
echo "APP_USER:    ${APP_USER}"
echo "HUMAN_USER:  ${HUMAN_USER}"
echo "READ_GROUP:  ${READ_GROUP}"
echo "WRITE_GROUP: ${WRITE_GROUP}"
echo "============================================"
echo ""

main() {
    create_roles "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    create_database "${APP_NAME}" "${TABLESPACE}" "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    create_schema "${APP_NAME}" "${APP_NAME}"
    grant_permissions "${APP_NAME}" "${APP_NAME}" "${READ_GROUP}" "${WRITE_GROUP}" "${APP_USER}"
    assign_human_user "${READ_GROUP}" "${HUMAN_USER}"

    echo "============================================"
    echo "Provisioning complete for ${APP_NAME}."
    echo "============================================"
}

main
```

If your script does not match, fix it now before moving on.

---

## What You Learned

- How to analyze an existing SQL script and identify parameters vs derived values
- Script structure: shebang, set -euo pipefail, functions, argument parsing, main
- Each function handles one logical task: roles, database, schema, grants, human user
- Idempotent patterns: check `pg_roles`/`pg_database` before creating, use `IF NOT EXISTS`
- The `local` keyword scopes variables to functions
- All psql calls use `-v ON_ERROR_STOP=1` to fail fast on errors
- GRANT statements are safe to re-run (naturally idempotent)

In the next guide, you will test this script thoroughly - running it with the original values, running it again to test idempotency, testing with different values, and adding a dry-run mode.
