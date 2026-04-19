# Scenario 04 - Extension Binary Missing in New Version

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: pg_upgrade --check has reported a fatal error.
A required extension library is missing from the new
PostgreSQL installation. The upgrade cannot proceed.
```

---

## Key Concepts for Revision

- **How pg_upgrade finds extension libraries** - `pg_upgrade` scans `pg_proc` in every database in the old cluster looking for functions that reference external C libraries (those with `probin` set). It then checks whether the corresponding `.so` file exists in the new version's lib directory. Even if the extension was installed years ago and the function is rarely used, the binary must be present.

- **Extension package naming conventions** - On RHEL/CentOS, most PostgreSQL extensions are packaged separately. For example, `pg_buffercache` is part of the `postgresql16-contrib` package, not the base `postgresql16` package. Missing binaries are almost always caused by forgetting to install the contrib or third-party package on the new version.

- **loadable_libraries.txt** - When pg_upgrade finds missing libraries, it writes the list to `loadable_libraries.txt` in the current directory. This file maps the library name (as stored in `pg_proc.probin`) to the databases where the issue was found.

- **Two resolution paths** - (1) Install the missing package on the new version so the `.so` appears in the right location. (2) Drop the extension from the old cluster before upgrading and reinstall after. Path 1 is preferred when the extension is actively used. Path 2 is necessary when no compatible package exists for the new version.

- **pg_proc.probin** - This system catalog column stores the path to the shared library (`.so` file) for each C-language function. The path uses `$libdir` as a placeholder for the actual lib directory. pg_upgrade substitutes the new PG lib directory when checking for the file.

---

## Diagnostic Steps

### Step 1 - Run pg_upgrade --check and observe the failure

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

### Step 2 - Read loadable_libraries.txt

```
cat loadable_libraries.txt
```

Expected output (yours will differ):

```
could not load library "$libdir/pg_buffercache": ERROR:  could not access status of transaction 1
    In database: upgradetest
```

This tells you `pg_buffercache` is missing from PG16's lib directory.

### Step 3 - Confirm the file is missing

```
exit
```

```
ls /usr/pgsql-16/lib/pg_buffercache.so
```

Expected output:

```
ls: cannot access '/usr/pgsql-16/lib/pg_buffercache.so': No such file or directory
```

### Step 4 - Identify which package provides this library

```
dnf provides '/usr/pgsql-16/lib/pg_buffercache.so' 2>/dev/null || rpm -qf /usr/pgsql-15/lib/pg_buffercache.so
```

Expected output (yours will differ):

```
postgresql15-contrib-15.7-1PGDG.rhel9.x86_64 : Extension modules distributed with PostgreSQL
```

The library comes from the `postgresql-contrib` package.

---

## Resolution

### Option A: Install the Missing Package (Preferred)

Check if the PG16 contrib package is available.

```
sudo dnf list available postgresql16-contrib
```

Expected output (yours will differ):

```
Available Packages
postgresql16-contrib.x86_64    16.3-1PGDG.rhel9    pgdg16
```

Install it.

```
sudo dnf install -y postgresql16-contrib
```

Expected output (yours will differ):

```
...
Installed:
  postgresql16-contrib-16.3-1PGDG.rhel9.x86_64
...
Complete!
```

Verify the file now exists.

```
ls /usr/pgsql-16/lib/pg_buffercache.so
```

Expected output:

```
/usr/pgsql-16/lib/pg_buffercache.so
```

### Option B: Restore the Hidden File (Lab-Specific Fix)

In this lab scenario, the file was moved rather than truly absent. Restore it.

```
sudo mv /usr/pgsql-16/lib/pg_buffercache.so.hidden /usr/pgsql-16/lib/pg_buffercache.so
```

Verify.

```
ls /usr/pgsql-16/lib/pg_buffercache.so
```

Expected output:

```
/usr/pgsql-16/lib/pg_buffercache.so
```

### Step: Re-run pg_upgrade --check

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

Expected output:

```
*Clusters are compatible*
```

```
exit
```

---

## Validation

```
./validate.sh
```

Expected checks:
- pg_buffercache.so exists in /usr/pgsql-16/lib/
- PG15 cluster is stopped
- pg_upgrade --check passes with binary restored
- PG16 production cluster is still running

---

## Interview Discussion Points

1. **What is `pg_proc.probin` and how does pg_upgrade use it?** - `probin` stores the path to the shared library (`.so` file) for each C-language function, using `$libdir` as a placeholder for the actual library directory. During `pg_upgrade --check`, pg_upgrade queries `pg_proc.probin` in every user database, resolves `$libdir` to the new PostgreSQL lib directory, and checks whether each `.so` file exists there.

2. **Before running pg_upgrade on production, how would you proactively discover all missing extension binaries?** - Run `SELECT DISTINCT probin FROM pg_proc WHERE probin IS NOT NULL AND prolang = (SELECT oid FROM pg_language WHERE lanname = 'c');` in every database in the old cluster. For each unique library path, check whether the `.so` exists in the new PostgreSQL lib directory. This gives you the same information as pg_upgrade --check but lets you remediate before the maintenance window.

3. **An extension you rely on has no PG16 package available from the vendor. What are your options?** - (1) Build the extension from source against PG16 headers. Most C extensions can be compiled with `make USE_PGXS=1 PG_CONFIG=/usr/pgsql-16/bin/pg_config`. (2) Drop the extension before upgrading and implement its functionality in application code or using built-in PostgreSQL features. (3) Delay the upgrade until the vendor releases a PG16-compatible package. (4) Fork the extension and maintain a PG16 build internally.

4. **If a third-party extension's `.so` is in `/usr/lib64/` instead of `/usr/pgsql-16/lib/`, will pg_upgrade find it?** - No. pg_upgrade looks specifically in the PostgreSQL lib directory (`${PG_BIN}/../lib/` which resolves to `/usr/pgsql-16/lib/`). Libraries in other system paths are not found. You must either reinstall the extension package correctly or create a symlink from `/usr/pgsql-16/lib/extname.so` to the actual location.

5. **After installing the missing package and getting pg_upgrade to succeed, what additional step is required for the extension in the new cluster?** - Run `ALTER EXTENSION extname UPDATE;` in each database where the extension is installed after the upgrade. This runs the upgrade scripts that migrate the extension's internal catalog data from the old version's format to the new version's format. Without this step, the extension may work but its catalog entries remain in the old format.
