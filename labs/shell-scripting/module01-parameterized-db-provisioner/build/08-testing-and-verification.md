---
layout: default
title: "BUILD 08 - Testing and Verification"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 10
---

# BUILD 08: Testing and Verification (35 min)

In this guide you will test the provisioner script you built in the previous guide. You will run it with the original SQL values, verify everything was created correctly, test idempotency, provision a second application, clean up, and add a `--dry-run` flag.

---

## Step 1: Verify the Script Is Ready

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/provision-db.sh
```

Expected output (yours will differ):
```
-rwxr-xr-x 1 ec2-user ec2-user 3847 Jun 23 15:00 /home/ec2-user/scripts/provision-db.sh
```

Confirm the file is executable (the `x` in the permissions). If it is not, run:

```bash
chmod +x ~/scripts/provision-db.sh
```

Test that the usage message works.

```bash
~/scripts/provision-db.sh
```

Expected output (yours will differ):
```
ERROR: Expected 4 arguments, got 0.

Usage: provision-db.sh <APP_NAME> <TABLESPACE> <APP_USER> <HUMAN_USER>

Provisions a PostgreSQL database with standard role structure:
  - {APP_NAME}_read_group  (NOLOGIN) - read-only access
  - {APP_NAME}_write_group (NOLOGIN) - read-write access
  - {APP_USER}             (LOGIN)   - application service account
  - Grants read group membership to HUMAN_USER
...
```

Good. The script validates arguments and prints helpful usage.

---

## Step 2: Run with the Original Values

This script must run as the postgres OS user because psql needs to connect as the PostgreSQL superuser.

On **pg-lab**, as **ec2-user**:

First, copy the script to a location the postgres user can access.

```bash
sudo cp ~/scripts/provision-db.sh /tmp/provision-db.sh
```

```bash
sudo chmod +x /tmp/provision-db.sh
```

Now switch to the postgres user.

```bash
sudo su - postgres
```

As **postgres** on **pg-lab**, run the provisioner with the original SQL values:

```bash
/tmp/provision-db.sh promos data promos_app_one lw_promos_l20
```

**NOTE:** Your server likely does not have a tablespace named "data". Use `pg_default` instead. If your production environment does have a "data" tablespace, substitute that.

```bash
/tmp/provision-db.sh promos pg_default promos_app_one lw_promos_l20
```

Expected output (yours will differ):
```
============================================
Database Provisioner
============================================
APP_NAME:    promos
TABLESPACE:  pg_default
APP_USER:    promos_app_one
HUMAN_USER:  lw_promos_l20
READ_GROUP:  promos_read_group
WRITE_GROUP: promos_write_group
============================================

--- Creating roles ---
CREATE ROLE
  Role promos_read_group created.
CREATE ROLE
  Role promos_write_group created.
CREATE ROLE
  Role promos_app_one created.

--- Creating database ---
CREATE DATABASE
  Database promos created.
GRANT
GRANT
GRANT
  CONNECT granted to promos_read_group, promos_write_group, promos_app_one.

--- Creating schema ---
CREATE SCHEMA
  Schema promos created (or already existed).

--- Granting permissions ---
GRANT
ALTER DEFAULT PRIVILEGES
  Read permissions granted to promos_read_group.
GRANT
ALTER DEFAULT PRIVILEGES
GRANT
ALTER DEFAULT PRIVILEGES
  Write permissions granted to promos_write_group.
...
```

The lines like `CREATE ROLE`, `GRANT`, and `ALTER DEFAULT PRIVILEGES` are psql's feedback confirming each SQL statement executed successfully. This is normal and expected.

---

## Step 3: Verify the Roles Exist

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname LIKE 'promos%' OR rolname = 'lw_promos_l20' ORDER BY rolname;"
```

Expected output (yours will differ):
```
      rolname       | rolcanlogin
--------------------+-------------
 promos_app_one     | t
 promos_read_group  | f
 promos_write_group | f
 lw_promos_l20      | t
(4 rows)
```

Confirm:
- `promos_read_group` and `promos_write_group` have `rolcanlogin = f` (NOLOGIN)
- `promos_app_one` and `lw_promos_l20` have `rolcanlogin = t` (LOGIN)

---

## Step 4: Verify the Database Exists

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "SELECT datname, spcname AS tablespace FROM pg_database d JOIN pg_tablespace t ON d.dattablespace = t.oid WHERE datname = 'promos';"
```

Expected output (yours will differ):
```
 datname | tablespace
---------+------------
 promos  | pg_default
(1 row)
```

---

## Step 5: Verify the Schema Exists

Still as **postgres** on **pg-lab**:

```bash
psql -d promos -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'promos';"
```

Expected output (yours will differ):
```
 schema_name
-------------
 promos
(1 row)
```

---

## Step 6: Verify the Grants

Still as **postgres** on **pg-lab**:

Check database-level grants (CONNECT).

```bash
psql -d postgres -c "SELECT grantee, privilege_type FROM information_schema.role_usage_grants WHERE object_name = 'promos' AND object_type = 'DATABASE' ORDER BY grantee;" 2>/dev/null || psql -d promos -c "\l+ promos"
```

A simpler check - verify the roles can connect by listing database access:

```bash
psql -d promos -c "SELECT has_database_privilege('promos_read_group', 'promos', 'CONNECT') AS can_connect;"
```

Expected output (yours will differ):
```
 can_connect
-------------
 t
(1 row)
```

```bash
psql -d promos -c "SELECT has_database_privilege('promos_write_group', 'promos', 'CONNECT') AS can_connect;"
```

Expected output (yours will differ):
```
 can_connect
-------------
 t
(1 row)
```

Check that the human user has the read group membership.

```bash
psql -d postgres -c "SELECT r.rolname AS member, g.rolname AS group_role FROM pg_auth_members m JOIN pg_roles r ON m.member = r.oid JOIN pg_roles g ON m.roleid = g.oid WHERE r.rolname = 'lw_promos_l20';"
```

Expected output (yours will differ):
```
    member     |    group_role
---------------+-------------------
 lw_promos_l20 | promos_read_group
(1 row)
```

The human user `lw_promos_l20` is a member of `promos_read_group`. This is exactly what the original SQL did.

---

## Step 7: Test Idempotency

Run the exact same command again. Nothing should fail.

Still as **postgres** on **pg-lab**:

```bash
/tmp/provision-db.sh promos pg_default promos_app_one lw_promos_l20
```

Expected output (yours will differ):
```
============================================
Database Provisioner
============================================
APP_NAME:    promos
TABLESPACE:  pg_default
APP_USER:    promos_app_one
HUMAN_USER:  lw_promos_l20
READ_GROUP:  promos_read_group
WRITE_GROUP: promos_write_group
============================================

--- Creating roles ---
  Role promos_read_group already exists.
  Role promos_write_group already exists.
  Role promos_app_one already exists.

--- Creating database ---
  Database promos already exists.
GRANT
GRANT
GRANT
  CONNECT granted to promos_read_group, promos_write_group, promos_app_one.

--- Creating schema ---
CREATE SCHEMA
NOTICE:  schema "promos" already exists, skipping
  Schema promos created (or already existed).

--- Granting permissions ---
GRANT
ALTER DEFAULT PRIVILEGES
  Read permissions granted to promos_read_group.
...

--- Assigning human user ---
GRANT ROLE
NOTICE:  role "lw_promos_l20" has already been granted membership in role "promos_read_group" by role "postgres"
  Granted promos_read_group to lw_promos_l20.

============================================
Provisioning complete for promos.
============================================
```

Every role and database says "already exists." The `NOTICE` lines from PostgreSQL confirm it detected duplicates and handled them gracefully. No errors. This is what idempotent means - running the same operation twice produces the same result.

---

## Step 8: Test with Different Values

Now provision a completely separate application to prove the script is truly parameterized.

Still as **postgres** on **pg-lab**:

```bash
/tmp/provision-db.sh inventory pg_default inventory_app lw_inventory_l20
```

Expected output (yours will differ):
```
============================================
Database Provisioner
============================================
APP_NAME:    inventory
TABLESPACE:  pg_default
APP_USER:    inventory_app
HUMAN_USER:  lw_inventory_l20
READ_GROUP:  inventory_read_group
WRITE_GROUP: inventory_write_group
============================================

--- Creating roles ---
  Role inventory_read_group created.
  Role inventory_write_group created.
  Role inventory_app created.

--- Creating database ---
  Database inventory created.
  CONNECT granted to inventory_read_group, inventory_write_group, inventory_app.

--- Creating schema ---
  Schema inventory created (or already existed).

--- Granting permissions ---
  Read permissions granted to inventory_read_group.
  Write permissions granted to inventory_write_group.
  App permissions granted to inventory_app.

--- Assigning human user ---
  WARNING: Role lw_inventory_l20 does not exist. Creating it.
  Role lw_inventory_l20 created with LOGIN.
  Granted inventory_read_group to lw_inventory_l20.

============================================
Provisioning complete for inventory.
============================================
```

---

## Step 9: Verify Both Applications Are Separate

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "SELECT datname FROM pg_database WHERE datname IN ('promos', 'inventory') ORDER BY datname;"
```

Expected output (yours will differ):
```
  datname
-----------
 inventory
 promos
(2 rows)
```

```bash
psql -d postgres -c "SELECT rolname FROM pg_roles WHERE rolname LIKE 'promos%' OR rolname LIKE 'inventory%' OR rolname LIKE 'lw_%' ORDER BY rolname;"
```

Expected output (yours will differ):
```
       rolname
----------------------
 inventory_app
 inventory_read_group
 inventory_write_group
 lw_inventory_l20
 lw_promos_l20
 promos_app_one
 promos_read_group
 promos_write_group
(8 rows)
```

Two completely separate sets of resources from one script. That is the power of parameterization.

---

## Step 10: Clean Up Both Test Runs

Still as **postgres** on **pg-lab**:

Drop the promos resources. The database must be dropped first (you cannot drop roles that own objects).

```bash
psql -d postgres -c "DROP DATABASE IF EXISTS promos;"
```

```bash
psql -d postgres -c "REVOKE ALL PRIVILEGES ON DATABASE postgres FROM promos_read_group, promos_write_group, promos_app_one;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS lw_promos_l20;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS promos_app_one;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS promos_write_group;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS promos_read_group;"
```

Now drop the inventory resources.

```bash
psql -d postgres -c "DROP DATABASE IF EXISTS inventory;"
```

```bash
psql -d postgres -c "REVOKE ALL PRIVILEGES ON DATABASE postgres FROM inventory_read_group, inventory_write_group, inventory_app;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS lw_inventory_l20;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS inventory_app;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS inventory_write_group;"
```

```bash
psql -d postgres -c "DROP ROLE IF EXISTS inventory_read_group;"
```

Verify everything is cleaned up.

```bash
psql -d postgres -c "SELECT datname FROM pg_database WHERE datname IN ('promos', 'inventory');"
```

Expected output (yours will differ):
```
 datname
---------
(0 rows)
```

Exit back to ec2-user.

```bash
exit
```

---

## Step 11: Add a --dry-run Flag

A dry-run mode prints what the script would do without actually executing any SQL. This is essential for production use - you always want to review before running.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-db.sh
```

You need to make three changes:

**Change 1:** Add a DRY_RUN variable near the top of the argument parsing section. Find the line `validate_args "$@"` and add dry-run detection BEFORE it. Replace the argument parsing section with:

```bash
# --- Check for --dry-run flag ---
DRY_RUN=false
ARGS=()
for arg in "$@"; do
    if [ "${arg}" = "--dry-run" ]; then
        DRY_RUN=true
    else
        ARGS+=("${arg}")
    fi
done

validate_args "${ARGS[@]}"

APP_NAME="${ARGS[0]}"
TABLESPACE="${ARGS[1]}"
APP_USER="${ARGS[2]}"
HUMAN_USER="${ARGS[3]}"
```

This loop separates `--dry-run` from the positional arguments so the flag can appear anywhere in the command.

**Change 2:** Add a helper function that either runs psql or prints the SQL. Add this function after `validate_args`:

```bash
run_psql() {
    local db="$1"
    shift
    if [ "${DRY_RUN}" = "true" ]; then
        echo "  [DRY RUN] psql -d ${db} $*"
    else
        psql -d "${db}" -v ON_ERROR_STOP=1 "$@"
    fi
}
```

**Change 3:** Add a dry-run notice to the header output. After the echo block that prints the parameters, add:

```bash
if [ "${DRY_RUN}" = "true" ]; then
    echo "*** DRY RUN MODE - no changes will be made ***"
    echo ""
fi
```

Save and exit vi (`:wq`).

Now test the dry-run mode.

```bash
sudo cp ~/scripts/provision-db.sh /tmp/provision-db.sh
```

```bash
sudo su - postgres
```

As **postgres** on **pg-lab**:

```bash
/tmp/provision-db.sh --dry-run promos data promos_app_one lw_promos_l20
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
*** DRY RUN MODE - no changes will be made ***

--- Creating roles ---
  [DRY RUN] psql -d postgres ...
...
```

The flag also works at the end.

```bash
/tmp/provision-db.sh promos data promos_app_one lw_promos_l20 --dry-run
```

Verify nothing was actually created.

```bash
psql -d postgres -c "SELECT datname FROM pg_database WHERE datname = 'promos';"
```

Expected output (yours will differ):
```
 datname
---------
(0 rows)
```

No database was created. The dry run worked.

Exit back to ec2-user.

```bash
exit
```

---

## Step 12: Clean Up Temp File

On **pg-lab**, as **ec2-user**:

```bash
sudo rm -f /tmp/provision-db.sh
```

Your script stays in `~/scripts/provision-db.sh`.

---

## What You Learned

- How to test a provisioner script with the original values
- How to verify roles, databases, schemas, and grants using catalog queries
- Idempotency testing - running the same script twice should produce no errors
- Parameterization testing - different inputs create completely separate resources
- Clean teardown order - drop databases first, then revoke grants, then drop roles
- Adding a `--dry-run` flag using argument loop parsing

## Next Steps

Your provisioner script is functional but could be improved for production use:

- **Logging**: Write output to a log file with timestamps
- **Error recovery**: If step 3 fails, should the script undo steps 1 and 2?
- **Password management**: The app user has LOGIN but no password - add `ENCRYPTED PASSWORD`
- **Connection parameters**: Accept `-h host -p port` for remote databases
- **Configuration file**: Read defaults from a config file instead of requiring all 4 arguments every time

These are good exercises to try on your own. You now have all the shell scripting skills to implement them.
