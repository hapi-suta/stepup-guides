# Exercise 05 - Installation Troubleshooting

**Time estimate:** 30-35 minutes
**Prerequisites:** BUILD phase complete - CentOS Stream 9 with PostgreSQL 16 (RPM) running on port 5432, PostgreSQL 15 (RPM) running on port 5433, source-compiled PG at `/opt/pg-src/bin/`. PGDATA at `/opt/pgsql/data`. Database `labdb` exists with extensions installed: pg_stat_statements, pgcrypto, pg_trgm, pageinspect.

---

## Scenario

After a colleague made changes to the server, PostgreSQL will not start properly. You will intentionally break things, diagnose the failures using logs and error messages, and fix them. Each problem is independent - fix one, verify the fix, then move to the next.

**Important:** This exercise is less guided than the previous ones. You are given the symptom and some direction, but you need to figure out the exact fix. This simulates real troubleshooting.

---

## Problem 1 - Missing shared_preload_libraries Entry

Your colleague accidentally commented out the `shared_preload_libraries` line while editing `postgresql.conf`. After restarting PostgreSQL, `pg_stat_statements` stops working.

### Break It

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open the configuration file:

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the line:

```
shared_preload_libraries = 'pg_stat_statements'
```

Comment it out by adding a `#` at the beginning:

```
#shared_preload_libraries = 'pg_stat_statements'
```

Save and exit vi (`:wq`).

Exit the postgres user:

```bash
exit
```

Restart PostgreSQL:

```bash
sudo systemctl restart postgresql-16
```

### Diagnose

PostgreSQL starts successfully (it does not crash on a missing extension). But the extension no longer works. Switch to the postgres user:

```bash
sudo -iu postgres
```

Try to query pg_stat_statements:

```bash
psql -d labdb -c "SELECT count(*) FROM pg_stat_statements;"
```

**Expected error:**

```
ERROR:  pg_stat_statements must be loaded via shared_preload_libraries
```

This tells you exactly what is wrong - the shared library is not loaded. Check the config:

```bash
grep shared_preload_libraries /opt/pgsql/data/postgresql.conf | grep -v '^#'
```

**Expected:** No output. The line is commented out, so nothing matches.

### Fix It

Your task: uncomment the `shared_preload_libraries` line, restart PostgreSQL, and verify `pg_stat_statements` works again.

Hints:
- Edit `/opt/pgsql/data/postgresql.conf` with vi
- Remove the `#` from the `shared_preload_libraries` line
- Exit the postgres user and restart the service
- Reconnect and run the count query again

After fixing, verify:

```bash
psql -d labdb -c "SELECT count(*) FROM pg_stat_statements;"
```

**Expected:** A number (the count of tracked statements). No error.

Exit the postgres user:

```bash
exit
```

> **Concept: shared_preload_libraries Requires a Restart**
> This parameter is read once at server startup. A `reload` (`systemctl reload`) is not enough - you must `restart`. This is because the shared library is loaded into the server's memory address space during initialization. In production, changing this parameter means a brief outage. Plan restarts during maintenance windows.

---

## Problem 2 - Wrong PGDATA Permissions

PostgreSQL refuses to start if the data directory has wrong permissions. It requires exactly mode 0700 (owner-only access).

### Break It

As ec2-user, change the data directory permissions to be world-readable:

```bash
sudo chmod 750 /opt/pgsql/data
```

Restart PostgreSQL:

```bash
sudo systemctl restart postgresql-16
```

**Expected:** The restart fails.

### Diagnose

Check the service status:

```bash
sudo systemctl status postgresql-16
```

**Expected:** You will see `Active: failed` in the output.

Check the journal for the error message:

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20
```

`-u` filters by service name. `--no-pager` prints output directly instead of opening a scrollable view. `-n 20` limits output to the last 20 log entries.

**Expected (key line):**

```
FATAL:  data directory "/opt/pgsql/data" has group or world access
DETAIL:  Permissions should be u=rwx (0700) or u=rwx,g=rx (0750).
```

You can also check the PostgreSQL log directory:

```bash
sudo ls /opt/pgsql/log/
```

If log files exist, read the most recent one for the same error.

### Fix It

Your task: fix the permissions and start PostgreSQL. Think about what the correct permission mode should be and which user should own the directory.

Hints:
- The data directory must be mode 0700
- The owner must be `postgres:postgres`
- After fixing permissions, start the service (not restart - it is already stopped)

After fixing, verify:

```bash
sudo systemctl status postgresql-16
```

**Expected:** `Active: active (running)`.

```bash
pg_isready -p 5432
```

**Expected:**

```
/var/run/postgresql:5432 - accepting connections
```

> **Concept: PostgreSQL Security Model for PGDATA**
> PostgreSQL enforces strict file permissions on the data directory because it contains all your data, configuration, and authentication files. If other users on the system could read `pg_hba.conf`, they would see your authentication rules. If they could read the data files, they would bypass all database-level access controls. The 0700 permission ensures only the `postgres` OS user can access any of it.

---

## Problem 3 - Extension Dependencies Not Met

A developer tries to create an extension but gets an error because the underlying package is not installed.

### Simulate It

Switch to the postgres user:

```bash
sudo -iu postgres
```

Connect to labdb:

```bash
psql -d labdb
```

Try to create an extension that requires an additional package. The `ip4r` extension provides IP address range types, but it is not installed by default:

```sql
CREATE EXTENSION IF NOT EXISTS ip4r;
```

**Expected error:**

```
ERROR:  could not open extension control file "/usr/pgsql-16/share/extension/ip4r.control": No such file or directory
```

### Diagnose

The error message tells you the extension's control file does not exist on the filesystem. This means the extension's RPM package is not installed.

Check what is available vs. installed. Run this query to see if `ip4r` is in the available extensions list:

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'ip4r';
```

**Expected:** Either zero rows (the package is not installed) or a row with `installed_version` being NULL.

Check if the extension's package exists in the PGDG repository. Exit psql first:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

Search for available packages:

```bash
dnf search ip4r 2>/dev/null
```

If a package exists, it will show up in the results. If not, the extension may need to be compiled from source or is not available for your version.

### Understand the Pattern

The general troubleshooting flow for extension errors is:

1. Read the error message - "could not open extension control file" means the `.control` file is missing from the filesystem
2. Check if the extension's RPM package is installed: `rpm -qa | grep extension_name`
3. Search the PGDG repo for the package: `dnf search extension_name`
4. Install it: `sudo dnf install -y package_name`
5. Run `CREATE EXTENSION` again

Verify that your existing extensions are all healthy. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -d labdb -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

**Expected:**

```
      extname       | extversion
--------------------+------------
 pageinspect        | 1.12
 pg_stat_statements | 1.10
 pg_trgm            | 1.6
 pgcrypto           | 1.3
 plpgsql            | 1.0
```

Exit the postgres user:

```bash
exit
```

> **Concept: Two-Step Extension Installation**
> Extensions require two steps: (1) install the OS package that places the `.control` and `.so` files on the filesystem, and (2) run `CREATE EXTENSION` inside each database that needs it. If step 1 is missing, you get the "could not open extension control file" error. If step 1 is done but step 2 is not, the extension is "available" but not "installed" in any database.

---

## Problem 4 - pg_hba.conf Blocking Connections

A new application server cannot connect to PostgreSQL because `pg_hba.conf` does not have an entry allowing its connection.

### Understand the Current Rules

Switch to the postgres user:

```bash
sudo -iu postgres
```

View the current pg_hba.conf rules. The `grep -v '^#' | grep -v '^$'` command filters out comments and blank lines:

```bash
grep -v '^#' /opt/pgsql/data/pg_hba.conf | grep -v '^$'
```

**Expected (your output may vary):**

```
local   all   all                     peer
host    all   all   127.0.0.1/32      scram-sha-256
host    all   all   ::1/128           scram-sha-256
local   replication   all             peer
host    replication   all   127.0.0.1/32   scram-sha-256
host    replication   all   ::1/128        scram-sha-256
```

Each line is a rule that PostgreSQL evaluates top-to-bottom:

| Field | Meaning |
|-------|---------|
| `local` | Unix socket connections (no network) |
| `host` | TCP/IP connections |
| `all` | Matches any database or any user |
| `127.0.0.1/32` | Only connections from localhost |
| `peer` | Authenticate using OS user name (must match PG user name) |
| `scram-sha-256` | Password-based authentication using the SCRAM protocol |

### Test a Rejected Connection

Try to connect using a password from a network address. This simulates what an application server would do:

```bash
psql -h 127.0.0.1 -U postgres -d labdb -c "SELECT 1;"
```

**Expected:** You will be prompted for a password (because the `host` rule for `127.0.0.1/32` uses `scram-sha-256`). If the postgres user does not have a password set, the connection fails:

```
connection to server at "127.0.0.1", port 5432 failed: ...
```

### Set a Password and Test Again

Set a password for the postgres user from a local connection (which uses `peer` auth and does not require a password):

```bash
psql -c "ALTER USER postgres PASSWORD 'labpassword123';"
```

**Expected:**

```
ALTER ROLE
```

Now test the password-based connection:

```bash
PGPASSWORD=labpassword123 psql -h 127.0.0.1 -U postgres -d labdb -c "SELECT 1;"
```

**Expected:**

```
 ?column?
----------
        1
(1 row)
```

The `PGPASSWORD` environment variable passes the password without an interactive prompt. In production, use a `.pgpass` file instead - environment variables can leak into process listings.

### Understand How to Add Rules

If an application server at IP `10.0.1.50` needs to connect, you would add a line to `pg_hba.conf`:

```
host    labdb   appuser   10.0.1.50/32   scram-sha-256
```

This allows the user `appuser` to connect to `labdb` from IP `10.0.1.50` using password authentication. After editing `pg_hba.conf`, you reload (not restart) PostgreSQL:

```bash
psql -c "SELECT pg_reload_conf();"
```

**Expected:**

```
 pg_reload_conf
----------------
 t
(1 row)
```

Verify the configuration was reloaded without errors:

```bash
psql -c "SELECT * FROM pg_hba_file_rules ORDER BY line_number LIMIT 10;"
```

**Expected:** A table showing each rule from `pg_hba.conf` with its line number, type, database, user_name, address, and auth method. If any rule has an error, it will appear in the `error` column.

Exit the postgres user:

```bash
exit
```

> **Concept: pg_hba.conf is Evaluated Top-to-Bottom**
> PostgreSQL reads `pg_hba.conf` from top to bottom and uses the first matching rule. If a broad rule like `host all all 0.0.0.0/0 reject` appears before a specific allow rule, the specific rule is never reached. Order matters. After any edit, always reload the config and verify with `pg_hba_file_rules` that there are no syntax errors. A broken `pg_hba.conf` can lock everyone out - including you.

---

## Checkpoint

Before moving on, confirm you can:

- [ ] Diagnose a missing `shared_preload_libraries` entry from the error message
- [ ] Fix PGDATA permission issues (mode 0700, owner postgres:postgres)
- [ ] Read PostgreSQL error logs with `journalctl -u postgresql-16`
- [ ] Understand the "could not open extension control file" error and its two-step fix
- [ ] Read and interpret `pg_hba.conf` rules
- [ ] Add new connection rules and reload the configuration without restarting
- [ ] Use `pg_hba_file_rules` to verify pg_hba.conf syntax

---

**Next:** Knowledge Checklist
