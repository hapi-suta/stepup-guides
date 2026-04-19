# Scenario 02 - Wrong PG Binary in PATH

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL appears to be unreachable.
A developer reports 'psql: connection refused' when logging in as the
postgres user and running psql. The DBA team confirms PG16 service is active.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **PATH variable** - A colon-separated list of directories the shell searches (left to right) when you type a command without a full path. If `/opt/pg-src/bin` appears before `/usr/pgsql-16/bin`, the shell finds the wrong `psql` first. The first match wins.

- **Multiple PostgreSQL installations** - Production servers often have multiple PG versions installed (RPM packages, source-compiled, contrib builds). Each has its own `bin/` directory with identically named binaries (`psql`, `pg_dump`, `pg_isready`). Running the wrong version's binary can cause silent connection failures or version mismatches.

- **which vs. type** - `which psql` shows the first `psql` found in PATH (external lookup). `type psql` is a shell builtin that also reveals aliases and shell functions. Use both when debugging - `type` catches cases where an alias overrides the binary.

- **alternatives system** - On RHEL/CentOS, `alternatives --display pgsql-psql` shows which `psql` is configured as the system default via symlinks. This is separate from the user's PATH and affects `/usr/bin/psql`. Understanding both layers prevents confusion.

- **.bash_profile vs. .bashrc** - `.bash_profile` runs on login shells (SSH, `sudo -iu`). `.bashrc` runs on interactive non-login shells. PATH changes in `.bash_profile` only take effect on new login sessions, which is why the DBA might not notice until they log out and back in.

---

## Diagnostic Steps

### Step 1 - Confirm the PG16 service is actually running

```bash
sudo systemctl status postgresql-16
```

Expected output shows "active (running)". The service is fine - this is a client-side problem.

### Step 2 - Switch to the postgres user

```bash
sudo -iu postgres
```

### Step 3 - Try the failing command

```bash
psql -d labdb -c "SELECT 1;"
```

Expected output:

```
psql: error: connection to server on socket "/tmp/.s.PGSQL.5555" failed: No such file or directory
	Is the server running locally and accepting connections on that socket?
```

Note the port number (5555) - that is not our PG16 port (5432). This is the key clue.

### Step 4 - Check which psql is being used

```bash
which psql
```

Expected output:

```
/opt/pg-src/bin/psql
```

This is the wrong binary. Our PG16 psql should be at `/usr/pgsql-16/bin/psql`.

### Step 5 - Double-check with type

```bash
type psql
```

Expected output:

```
psql is /opt/pg-src/bin/psql
```

### Step 6 - Examine the PATH

```bash
echo $PATH
```

Look for `/opt/pg-src/bin` appearing before `/usr/pgsql-16/bin`. The wrong directory takes priority.

### Step 7 - Find where PATH is being set

```bash
cat ~/.bash_profile
```

Expected output:

```
# .bash_profile - modified
export PATH=/opt/pg-src/bin:$PATH
export PGDATA=/opt/pgsql/data
[ -f ~/.bashrc ] && . ~/.bashrc
```

The line `export PATH=/opt/pg-src/bin:$PATH` is the problem. It prepends the source-compiled directory, overriding the RPM-installed binaries.

```bash
exit
```

---

## Resolution

### Step 1 - Switch to postgres user

```bash
sudo -iu postgres
```

### Step 2 - Fix .bash_profile

Edit the file to use the correct PG16 path:

```bash
vi ~/.bash_profile
```

Change the file to:

```
# .bash_profile
export PATH=/usr/pgsql-16/bin:$PATH
export PGDATA=/opt/pgsql/data
[ -f ~/.bashrc ] && . ~/.bashrc
```

Remove or replace the `/opt/pg-src/bin` entry with `/usr/pgsql-16/bin`.

### Step 3 - Exit and log back in to reload the profile

```bash
exit
```

```bash
sudo -iu postgres
```

### Step 4 - Verify the correct psql is now in PATH

```bash
which psql
```

Expected output:

```
/usr/pgsql-16/bin/psql
```

### Step 5 - Test the connection

```bash
psql -p 5432 -d labdb -c "SELECT 'Connected to PG16' AS status;"
```

Expected output:

```
      status
-------------------
 Connected to PG16
(1 row)
```

### Step 6 - Verify the port

```bash
psql -p 5432 -d labdb -c "SHOW port;"
```

Expected output:

```
 port
------
 5432
```

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
- psql resolves to /usr/pgsql-16/bin/psql
- psql connects to the correct port
- .bash_profile does not prioritize /opt/pg-src/bin
- psql works from postgres login shell

---

## Interview Discussion Points

1. **How do you determine which psql binary you are running?** - Use `which psql` to see the resolved path, `type psql` to also check for aliases, and `psql --version` to see the version number. For absolute certainty, use the full path: `/usr/pgsql-16/bin/psql --version`. In production, always use full paths in scripts to avoid PATH surprises.

2. **What problems can arise from using a mismatched psql version?** - Minor version mismatches (16.2 client vs 16.3 server) are usually fine. Major version mismatches (15 client vs 16 server) can cause issues: psql may not understand new SQL syntax, `\d` output may differ, and pg_dump from an older version may silently skip new features. Always use a client version >= the server version.

3. **How does the alternatives system work on RHEL/CentOS?** - `alternatives` manages symlinks in `/usr/bin/` for programs with multiple providers. Run `alternatives --display pgsql-psql` to see the current default. Run `sudo alternatives --config pgsql-psql` to change it. This affects the system-wide `/usr/bin/psql` symlink but does not override a user's PATH if their PATH has a more specific directory first.

4. **Why is it important to use full paths in cron jobs and scripts?** - Cron jobs run with a minimal PATH (usually just `/usr/bin:/bin`). If your backup script calls `pg_dump` without a full path, it may find no binary at all or find the wrong version. Always use full paths like `/usr/pgsql-16/bin/pg_dump` in automation. Never rely on the user's `.bash_profile` - cron does not source it.

5. **What is the best practice for managing PATH on a multi-version PG server?** - Set the PATH explicitly in `.bash_profile` or `.pgsql_profile` for the postgres user, putting the active production version first. In scripts and cron, always use absolute paths. Document which version is installed where. Consider using `update-alternatives` to set a sensible system default for ad-hoc use.
