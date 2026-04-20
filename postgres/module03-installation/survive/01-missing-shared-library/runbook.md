# Scenario 01 - Missing Shared Library

**Severity:** CRITICAL
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start. Service is DOWN.
shared_preload_libraries could not load a required library.
A developer reports pg_stat_statements stopped working after a recent OS patching window.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **Shared libraries (.so files)** - PostgreSQL extensions are compiled into shared object files (`.so` on Linux). These files live in the `lib` directory of the PostgreSQL installation (e.g., `/usr/pgsql-16/lib/`). When PostgreSQL needs an extension, it dynamically loads the `.so` file into its process memory.

- **shared_preload_libraries** - A `postgresql.conf` parameter that lists libraries to load when the postmaster starts. These libraries are loaded into shared memory once and available to all connections. If any library in this list cannot be found or loaded, PostgreSQL refuses to start entirely - it is all or nothing.

- **Extension vs. shared library** - An extension (`CREATE EXTENSION`) is the SQL-level interface: it creates functions, views, and types in a database. The shared library (`.so` file) is the compiled C code that those SQL objects call. You need both: the `.so` on disk and the extension created in the database.

- **Why patching can break libraries** - When you upgrade PostgreSQL packages (e.g., from 16.2 to 16.3), the RPM replaces the `.so` files. If a third-party extension was installed from a separate package and that package was not also updated, the old `.so` may be removed or become incompatible. Similarly, manual file moves during maintenance can cause this.

- **pg_config --pkglibdir** - This command shows the directory where PostgreSQL expects to find shared libraries. Use it to confirm you are looking in the right place instead of guessing.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Look for "failed" status and note any error messages about libraries.

### Step 2 - Check PostgreSQL logs

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Expected output will include something like:

```
FATAL:  could not access file "pg_stat_statements": No such file or directory
LOG:  the database system is shut down
```

This tells you exactly which library is missing.

### Step 3 - Check what shared_preload_libraries expects

```bash
sudo grep shared_preload_libraries /opt/pgsql/data/postgresql.conf
```

Expected output:

```
shared_preload_libraries = 'pg_stat_statements'
```

### Step 4 - Look for the shared library file

```bash
ls -la /usr/pgsql-16/lib/pg_stat_statements*
```

Expected output:

```
-rw-r--r--. 1 root root 94232 ... /usr/pgsql-16/lib/pg_stat_statements.so.bak
```

The `.so` file has been renamed to `.so.bak`. That is why PostgreSQL cannot find it.

### Step 5 - Confirm the expected library directory

```bash
/usr/pgsql-16/bin/pg_config --pkglibdir
```

Expected output:

```
/usr/pgsql-16/lib
```

This confirms PostgreSQL looks in `/usr/pgsql-16/lib/` for shared libraries.

---

## Resolution

### Step 1 - Restore the shared library file

```bash
sudo mv /usr/pgsql-16/lib/pg_stat_statements.so.bak /usr/pgsql-16/lib/pg_stat_statements.so
```

### Step 2 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

### Step 3 - Verify it started

```bash
sudo systemctl status postgresql-16
```

Look for "active (running)" status.

### Step 4 - Confirm shared_preload_libraries loaded

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW shared_preload_libraries;"
```

`-p 5432` connects on port 5432. `-d labdb` connects to the labdb database. `-c` runs a single SQL command and exits.

Expected output:

```
 shared_preload_libraries
--------------------------
 pg_stat_statements
```

### Step 5 - Verify the extension works

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM pg_stat_statements;"
```

Expected output:

```
 count
-------
     0
(1 row)
```

A count of 0 is normal on a fresh start - it means the extension loaded and the view is queryable.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- pg_stat_statements.so exists
- pg_stat_statements.so.bak removed
- shared_preload_libraries includes pg_stat_statements
- pg_stat_statements extension works

---

## Interview Discussion Points

1. **What happens when a library in shared_preload_libraries is missing?** - PostgreSQL refuses to start entirely. Unlike `session_preload_libraries` (which fails per-session), `shared_preload_libraries` is loaded at postmaster startup. If any library in the list fails to load, the entire postmaster shuts down. This is by design - these libraries often manage shared memory structures that must be initialized before any backend starts.

2. **What is the difference between shared_preload_libraries and session_preload_libraries?** - `shared_preload_libraries` loads at server start, allocates shared memory, and is available to all connections. `session_preload_libraries` loads when each connection starts and only affects that session. A third option, `local_preload_libraries`, can be set by unprivileged users but is restricted to libraries in `$libdir/plugins/` for security.

3. **How would you troubleshoot this without the runbook?** - Check the logs first (`/opt/pgsql/log/`). The FATAL message names the exact library. Then use `pg_config --pkglibdir` to find where libraries should be. List the directory to see if the file is missing, renamed, or permission-denied. If truly missing, reinstall the package that provides it (e.g., `dnf install postgresql16-contrib`).

4. **Why not just remove pg_stat_statements from shared_preload_libraries to get PG started?** - That would get PostgreSQL running, but pg_stat_statements is a critical monitoring extension used by almost every production system. Removing it means you lose query performance visibility. The correct fix is to restore the library. If you must start PG urgently, you could temporarily remove it, but you should restore it and restart as soon as possible.

5. **What RPM provides pg_stat_statements.so?** - On PGDG-based installs, it comes from the `postgresql16-contrib` package. You can verify with `rpm -qf /usr/pgsql-16/lib/pg_stat_statements.so`. If the file is missing and not just renamed, `dnf reinstall postgresql16-contrib` will restore it.
