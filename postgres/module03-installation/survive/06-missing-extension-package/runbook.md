# Runbook 06: Missing Extension Package

## Scenario

A developer reports that `CREATE EXTENSION pgcrypto` is failing in the application. The PostgreSQL 16 server is running, but something happened during a recent OS patching window that removed the contrib extensions. Diagnose and restore extension functionality.

---

## Layer 1: Fix Path

### Step 1 - Confirm PostgreSQL is running

```bash
sudo systemctl status postgresql-16
```

Expected output:
```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

The server is up - this is not a startup failure.

### Step 2 - Try to create the extension and see the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Expected output:
```
ERROR:  could not open extension control file "/usr/pgsql-16/share/extension/pgcrypto.control": No such file or directory
```

```sql
\q
```

```bash
exit
```

> **Concept: Extension control files** - Every PostgreSQL extension has a `.control` file in the `share/extension/` directory. This file tells PostgreSQL the extension's version, schema, dependencies, and which SQL script to run during `CREATE EXTENSION`. Without it, PostgreSQL cannot install the extension at all.

### Step 3 - Check if the extension files exist on disk

```bash
ls /usr/pgsql-16/share/extension/pgcrypto*
```

Expected output:
```
ls: cannot access '/usr/pgsql-16/share/extension/pgcrypto*': No such file or directory
```

The files are gone. Check the shared library directory too:

```bash
ls /usr/pgsql-16/lib/pgcrypto*
```

Expected output:
```
ls: cannot access '/usr/pgsql-16/lib/pgcrypto*': No such file or directory
```

### Step 4 - Check if the contrib package is installed

```bash
rpm -q postgresql16-contrib
```

Expected output:
```
package postgresql16-contrib is not installed
```

This confirms the RPM package that provides extension files was removed.

> **Concept: postgresql-contrib package** - The `contrib` package bundles ~50 additional extensions that ship with PostgreSQL but are not installed by default. These include `pgcrypto`, `pg_stat_statements`, `pg_trgm`, `hstore`, `uuid-ossp`, and many others. Without this package, only the core extensions (like `plpgsql`) are available.

### Step 5 - Check what files the contrib package provides

```bash
dnf repoquery -l postgresql16-contrib | head -20
```

Expected output (partial):
```
/usr/pgsql-16/lib/pgcrypto.so
/usr/pgsql-16/lib/pg_stat_statements.so
/usr/pgsql-16/share/extension/pgcrypto.control
/usr/pgsql-16/share/extension/pgcrypto--1.3.sql
...
```

This shows the .so libraries and .control files that will be restored.

### Step 6 - Reinstall the contrib package

```bash
sudo dnf install -y postgresql16-contrib
```

Expected output (key lines):
```
Installed:
  postgresql16-contrib-16.x-xPGDG.rhel9.x86_64
Complete!
```

### Step 7 - Verify the extension files are back

```bash
ls /usr/pgsql-16/share/extension/pgcrypto.control
```

Expected output:
```
/usr/pgsql-16/share/extension/pgcrypto.control
```

### Step 8 - Create the extension

No restart is needed for CREATE EXTENSION - PostgreSQL loads .so files on demand.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Expected output:
```
CREATE EXTENSION
```

### Step 9 - Verify it works

```sql
SELECT gen_random_uuid();
```

Expected output:
```
           gen_random_uuid
--------------------------------------
 a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d
(1 row)
```

```sql
\q
```

```bash
exit
```

> **Concept: Extension loading vs shared_preload_libraries** - Most extensions (like pgcrypto) are loaded on demand when you run `CREATE EXTENSION`. However, some extensions (like `pg_stat_statements`) must be preloaded at server start via `shared_preload_libraries`. If the .so file for a preloaded extension is missing, PostgreSQL will fail to START. The server stays running here because pgcrypto is demand-loaded.

### Step 10 - Verify pg_stat_statements still works

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

```sql
SELECT count(*) FROM pg_stat_statements;
```

Expected output:
```
 count
-------
    XX
(1 row)
```

If this fails with a missing .so error, restart PostgreSQL:

```sql
\q
```

```bash
exit
```

```bash
sudo systemctl restart postgresql-16
```

> **Concept: Hot reload vs restart** - Removing a .so file while PostgreSQL is running does not crash the server if the library is already loaded into memory. The OS keeps the file's inode alive as long as a process has it open. But after reinstalling, a restart may be needed for `shared_preload_libraries` extensions to pick up the new .so path.

---

## Layer 2: Revision Concepts

### RPM package management for PostgreSQL

The PGDG repository organizes PostgreSQL into several packages:

| Package | Contents |
|---------|----------|
| `postgresql16-server` | Core server (postmaster, initdb, pg_ctl) |
| `postgresql16` | Client tools (psql, pg_dump, pg_restore) |
| `postgresql16-contrib` | Extra extensions (~50 modules) |
| `postgresql16-libs` | Shared libraries (libpq) |
| `postgresql16-devel` | Headers for compiling extensions |

### Useful RPM/DNF commands for DBAs

```bash
# What package provides a specific file?
rpm -qf /usr/pgsql-16/lib/pgcrypto.so

# List all files in a package
rpm -ql postgresql16-contrib

# Check if a package is installed
rpm -q postgresql16-contrib

# Find available PG-related packages
dnf list 'postgresql16*'

# Check package install history
dnf history list | head -20
```

### Extension architecture

Extensions have three components:
1. **Control file** (`.control`) - metadata: version, schema, requires
2. **SQL scripts** (`.sql`) - the DDL that CREATE EXTENSION runs
3. **Shared library** (`.so`) - compiled C code loaded by the backend

When you run `CREATE EXTENSION pgcrypto`:
1. PostgreSQL reads `pgcrypto.control` to find the version and SQL file
2. It executes `pgcrypto--1.3.sql` which contains CREATE FUNCTION statements
3. Those functions reference `pgcrypto.so` via `LANGUAGE C`
4. The backend calls `dlopen()` to load the .so into memory

### Preventing this in production

- Pin critical packages: `dnf versionlock add postgresql16-contrib`
- Monitor with `rpm -V postgresql16-contrib` in a cron job (reports modified/missing files)
- Use `dnf history` to audit what changed during patching windows
- Test OS updates in staging before applying to production databases

---

## Layer 3: Interview Discussion Points

1. **The server is running but extensions are broken - how do you triage?** - Check the specific error message from CREATE EXTENSION. The "could not open extension control file" error points to missing files on disk. Use `rpm -qf` to find which package owns the file, then check if it's installed with `rpm -q`.

2. **What's the difference between extensions that need shared_preload_libraries and those that don't?** - Extensions that need shared memory allocation at startup (pg_stat_statements, auto_explain, pg_cron) must go in shared_preload_libraries. Extensions that only add functions (pgcrypto, uuid-ossp, hstore) load on demand. If a preloaded extension's .so is missing, the server won't start at all.

3. **How would you handle this in a production environment with many databases?** - The contrib package provides the files. CREATE EXTENSION must be run per-database. In production, track which databases use which extensions, reinstall the package, then verify each database's extensions with `SELECT * FROM pg_extension` connected to each one.

4. **How do you prevent package removal from breaking your database?** - Use `dnf versionlock` to protect critical packages, configure `/etc/dnf/dnf.conf` with `exclude=postgresql*` during unattended upgrades, set up monitoring that alerts on missing .so files, and always test OS patches in a staging environment first.

5. **A developer asks you to install a third-party extension not in contrib. What's your process?** - Check the extension's compatibility with your PG version, review the source code for quality, install build dependencies (postgresql16-devel), compile with `make USE_PGXS=1`, test in staging, deploy the .so and .control files, document it in your runbook. Consider using PGXN or trusted language extensions (TLE) for simpler deployment.
