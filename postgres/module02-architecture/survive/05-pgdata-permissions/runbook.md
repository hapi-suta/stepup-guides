# Scenario 05 - PGDATA Permissions

**Severity:** CRITICAL
**Expected Recovery Time:** 2-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL failed to start after system maintenance.
Error: data directory has wrong permissions.
Service is DOWN.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **PGDATA must be 0700** - PostgreSQL refuses to start if the data directory is readable by group or others. This is a hard-coded safety check. The data directory contains everything - table data, WAL, authentication config, SSL keys. World-readable permissions would be a severe security vulnerability.
- **File ownership** - All files in PGDATA must be owned by the postgres OS user. If root or another user owns key files (postgresql.conf, pg_hba.conf), PostgreSQL cannot read or write them. This commonly happens when an admin edits config files with sudo and the editor creates a new file owned by root.
- **Permission vs authentication** - Filesystem permissions (chmod/chown) are the OS-level gate. PostgreSQL's own authentication (pg_hba.conf, roles, passwords) is the database-level gate. Both must be correct. A misconfigured filesystem can prevent startup entirely, before authentication even comes into play.
- **Common causes** - Permissions get broken by: backup scripts running as root that overwrite files, system admins editing configs with sudo, automated patching tools, misconfigured Ansible/Chef/Puppet playbooks, or restore operations that do not preserve ownership.

---

## Diagnostic Steps

### Step 1 - Check service status

```bash
sudo systemctl status postgresql-16
```

Look for "failed" status.

### Step 2 - Check PostgreSQL logs

```bash
sudo tail -20 /opt/pgsql/log/postgresql-*.log
```

Look for messages like:
- "data directory has wrong ownership"
- "data directory has group or world access"
- "could not open configuration file"

### Step 3 - Check PGDATA permissions

```bash
ls -la /opt/pgsql/ | grep data
```

The data directory should show `drwx------` (0700). If you see `drwxr-xr-x` (0755), that is the problem.

### Step 4 - Check ownership of key files

```bash
ls -la /opt/pgsql/data/postgresql.conf
ls -la /opt/pgsql/data/pg_hba.conf
ls -la /opt/pgsql/data/PG_VERSION
```

All files should be owned by `postgres:postgres`. If any show `root:root`, that needs fixing.

### Step 5 - Check PGDATA ownership itself

```bash
ls -la /opt/pgsql/ | grep data
stat /opt/pgsql/data
```

The directory itself must be owned by postgres:postgres.

---

## Resolution

### Step 1 - Fix PGDATA directory permissions

```bash
sudo chmod 700 /opt/pgsql/data
```

### Step 2 - Fix file ownership

```bash
sudo chown postgres:postgres /opt/pgsql/data/postgresql.conf
```

If other files are also affected, fix them too:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data
```

### Step 3 - Verify permissions before starting

```bash
ls -la /opt/pgsql/ | grep data
ls -la /opt/pgsql/data/postgresql.conf
```

Confirm data directory is `drwx------` and all files are `postgres:postgres`.

### Step 4 - Start PostgreSQL

If `systemctl start` fails with "Start request repeated too quickly", systemd has hit its restart rate limit. Reset the failed state first:

```bash
sudo systemctl reset-failed postgresql-16
```

Then start:

```bash
sudo systemctl start postgresql-16
```

### Step 5 - Verify it started

```bash
sudo systemctl status postgresql-16
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 'PostgreSQL is back';"
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- /opt/pgsql/data has permissions 0700
- Key files are owned by postgres:postgres
- psql connection succeeds
- State file cleaned up

---

## Interview Discussion Points

1. **Why must PGDATA be exactly 0700?** - PostgreSQL stores everything sensitive in PGDATA: table data (including unencrypted column values), WAL files, SSL private keys (server.key), authentication configuration (pg_hba.conf which defines who can connect), and password hashes (in pg_authid). If any other OS user can read these files, it is a complete security breach. PostgreSQL enforces 0700 at startup as a non-negotiable safety check.

2. **What other permission issues can prevent startup?** - WAL directory permissions (if using a symlink to a separate mount), socket directory permissions (the postgres user must be able to write to /tmp or wherever unix_socket_directories points), log directory permissions (if PostgreSQL cannot write logs, it may still start but you lose visibility), and tablespace directories (must be owned by postgres with 0700).

3. **How do you prevent permission issues from recurring?** - Use configuration management (Ansible, etc.) that always sets the correct permissions. Never edit PostgreSQL config files as root - use `sudo -u postgres vi`. If you must use sudo to edit, run `chown postgres:postgres` afterward. Include permission checks in your monitoring - alert if PGDATA permissions change from 0700.

4. **What is the difference between filesystem permissions and PostgreSQL authentication?** - Filesystem permissions (chmod/chown) control OS-level access to files. They determine whether the postgres OS process can read its own data files. PostgreSQL authentication (pg_hba.conf, roles, passwords, SSL certificates) controls who can connect to the running database and what they can do. Both layers must be correct. Filesystem issues prevent startup entirely. Authentication issues allow startup but block connections.

5. **What would happen if you set PGDATA to 0777?** - PostgreSQL would refuse to start with a clear error message. But even if it somehow started, any OS user could read raw data files directly (bypassing all PostgreSQL authentication), read pg_hba.conf to understand the authentication setup, read server.key to impersonate the server, and modify postgresql.conf to weaken security settings on the next restart. This is why the 0700 check is non-negotiable.
