# Scenario 01 - pg_upgrade --check Fails: Incompatible Extension

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: pg_upgrade --check is reporting a fatal error.
The upgrade cannot proceed. Extension compatibility
check has failed.
```

---

## Key Concepts for Revision

- **Extension compatibility check** - `pg_upgrade --check` scans `pg_extension` in every database in the old cluster and verifies that the corresponding `.so` file exists in the new PostgreSQL lib directory (`/usr/pgsql-16/lib/`). If the binary is missing, the check fails with a `fatal` message and writes a `loadable_libraries.txt` file listing the offending extensions.

- **Why extensions block upgrades** - An extension's C code (the `.so` file) is compiled against a specific PostgreSQL major version's internal API. You cannot load a PG15-compiled `.so` into a PG16 server. Each major version requires its own compiled binary.

- **Resolution options** - You have two choices: (1) Install the PG16 version of the extension RPM so the `.so` exists in `/usr/pgsql-16/lib/`, or (2) drop the extension from PG15 before upgrading and reinstall it on PG16 after. Option 1 is preferred when a PG16 package exists. Option 2 is necessary when no PG16 package is available.

- **pg_upgrade output files** - When `pg_upgrade --check` fails, it creates log files in the current working directory (wherever you run the command). `loadable_libraries.txt` lists extensions with missing binaries. Always check this file to understand what needs to be fixed.

- **Idempotent checks** - `pg_upgrade --check` is safe to run repeatedly. It makes no changes. Run it as many times as needed until all checks pass before running the actual upgrade.

---

## Diagnostic Steps

### Step 1 - Run pg_upgrade --check and capture output

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output (yours will differ):

```
Checking for presence of required libraries                   fatal

Your installation references loadable libraries that are missing from the
new installation.  You can add these libraries to the new installation,
or remove the functions using them from the old installation.  A list of
problem libraries is in the file:
    loadable_libraries.txt

Failure, exiting
```

### Step 2 - Read the loadable_libraries.txt file

```
cat loadable_libraries.txt
```

Expected output (yours will differ):

```
could not load library "$libdir/chaos_fake": ERROR:  could not access status of transaction 1
    In database: upgradetest
```

This tells you:
- The extension `chaos_fake` is installed in the `upgradetest` database
- The library `$libdir/chaos_fake` (which maps to `/usr/pgsql-16/lib/chaos_fake.so`) does not exist

```
exit
```

### Step 3 - Find which database has the extension

```
sudo -iu postgres
```

Start PG15 to query the catalog.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT extname, extversion FROM pg_extension WHERE extname NOT IN ('plpgsql');"
```

Expected output (yours will differ):

```
     extname      | extversion
------------------+------------
 chaos_fake       | 1.0
 pg_stat_statements | 1.10
(2 rows)
```

If the extension may be in other databases, repeat the query for each database individually.

### Step 4 - Check if a PG16 package is available

```
exit
```

```
sudo dnf list available 'postgresql16-*' | grep chaos
```

Expected output:

```
(no output - no PG16 package for chaos_fake)
```

Since no PG16 package exists for this extension, you must drop it from PG15.

---

## Resolution

### Step 1 - Document what the extension does

Before dropping an extension, note what it provides so you can handle any dependent objects.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "\dx chaos_fake"
```

Expected output (yours will differ):

```
      Name       | Version |   Schema   |           Description
-----------------+---------+------------+----------------------------------
 chaos_fake      | 1.0     | public     | Fake extension for chaos testing
(1 row)
```

Check what objects the extension owns.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT objid::regclass FROM pg_depend d JOIN pg_extension e ON d.refobjid = e.oid WHERE e.extname = 'chaos_fake' AND d.deptype = 'e';"
```

### Step 2 - Drop the extension

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "DROP EXTENSION IF EXISTS chaos_fake CASCADE;"
```

Expected output:

```
DROP EXTENSION
```

(`CASCADE` = also drop any objects that depend on this extension. Use with caution in production - review dependents first.)

### Step 3 - Stop PG15

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

### Step 4 - Re-run pg_upgrade --check

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output:

```
*Clusters are compatible*
```

```
exit
```

---

## Validation

Run the validation script.

```
./validate.sh
```

Expected checks:
- PG15 cluster is stopped
- PG16 target cluster is stopped
- chaos_fake extension is resolved (dropped or binary provided)
- pg_upgrade --check passes successfully
- PG16 production cluster is still running

---

## Interview Discussion Points

1. **You discover an extension used in production has no PG16-compatible package. How do you handle the upgrade?** - First assess what the extension does and whether your application actively uses it. If usage is minimal, drop it before upgrade and find an alternative (built-in function, different extension, or application-level implementation). If it is critical, delay the upgrade until a PG16 package is available or build the extension from source against PG16 headers.

2. **What is the `loadable_libraries.txt` file and how do you use it?** - pg_upgrade writes this file to the current directory when it detects missing extension binaries. It lists each library path that was referenced in the old cluster's catalogs but could not be found in the new PG lib directory. Use it as your remediation checklist: for each entry, either install the package or drop the extension.

3. **If you drop an extension to resolve a pg_upgrade --check failure, what happens to the functions it provided?** - `DROP EXTENSION` removes the extension and, with `CASCADE`, all objects that depend on it (functions, types, operators defined by the extension). Any SQL code in your application that calls those functions will fail after the upgrade until you install a replacement. This is why you must document extension usage before dropping.

4. **After upgrading, what is the correct way to update an extension to its new version?** - Run `ALTER EXTENSION extname UPDATE;` after the upgrade. This runs the upgrade scripts provided by the extension (e.g. `pg_stat_statements--1.9--1.10.sql`) to migrate internal catalog data to the new version's structure. Do not reinstall the extension from scratch - that would lose any existing statistics or configuration.

5. **How would you proactively discover extension compatibility issues before scheduling the maintenance window?** - Install the PG16 binaries on a test server and run `pg_upgrade --check` against a copy of your production data. Review the output weeks before the planned upgrade. For each extension, check the extension's changelog and package repositories for PG16 support status. Some extensions (like PostGIS, TimescaleDB) have their own version compatibility matrices.
