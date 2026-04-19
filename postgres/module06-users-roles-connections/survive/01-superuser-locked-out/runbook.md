# Scenario 01 - Superuser Locked Out

**Severity:** CRITICAL
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: postgres superuser cannot connect via TCP.
The password was changed and pg_hba.conf no longer
allows local socket (peer) connections for recovery.
You are locked out of the database.
```

---

## Key Concepts for Revision

- **Peer authentication** - The `peer` method for `local` connections lets the postgres OS user connect as the postgres database role without a password. The OS proves the identity. This is your emergency recovery path when passwords are lost or misconfigured. It requires the connecting process to be running as the postgres OS user.

- **Unix socket vs TCP** - `local` rules in pg_hba.conf match connections through the Unix domain socket at `/run/postgresql`. `host` rules match TCP connections (127.0.0.1 and external IPs). They are evaluated separately. Removing `local` rules does not affect TCP, and vice versa.

- **pg_hba.conf reload is non-destructive to running connections** - When you reload pg_hba.conf, existing connections are not kicked. Only new connection attempts use the new rules. If you lock yourself out, current sessions still work until they disconnect.

- **pg_ctl vs systemctl for pg_hba.conf reload** - Both work. `sudo systemctl reload postgresql-16` sends SIGHUP via systemd. `sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data reload` sends it directly. Either works when you can reach the OS but not the database.

- **ALTER ROLE for password reset** - Once you regain access via the socket, `ALTER ROLE postgres PASSWORD 'newpass';` resets the password. You do not need to know the old password to change it - you just need to be connected as a superuser.

---

## Diagnostic Steps

### Step 1 - Confirm the lockout

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "postgres"
```

### Step 2 - Check the current pg_hba.conf

```bash
sudo cat /opt/pgsql/data/pg_hba.conf
```

Expected output (yours will differ):

```
# chaos injection - all connections require password
host    all    all    127.0.0.1/32    scram-sha-256
host    all    all    ::1/128         scram-sha-256
host    all    all    0.0.0.0/0       scram-sha-256
```

The problem is clear: the `local` rule using `trust` or `peer` is missing. There is no way to connect via the Unix socket.

---

## Resolution

### Step 1 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

This is the key insight: even though the database password is unknown and pg_hba.conf blocks TCP connections, the postgres OS user can edit files and interact with the server process directly.

### Step 2 - Restore the local socket trust rule

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add this line at the TOP of the file, above all host rules:

```
local   all   all   trust
```

The file should look like this:

```
# local socket connections - recovery access
local   all   all   trust

# TCP connections
host    all    all    127.0.0.1/32    scram-sha-256
host    all    all    ::1/128         scram-sha-256
host    all    all    0.0.0.0/0       scram-sha-256
```

Save and exit vi with `:wq`.

### Step 3 - Reload pg_hba.conf

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data reload
```

Expected output:

```
server signaled
```

### Step 4 - Connect via the Unix socket

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

Because you are the postgres OS user and the local line uses `trust`, this succeeds without a password.

Expected output:

```
psql (16.3)
Type "help" for help.

postgres=#
```

### Step 5 - Reset the postgres password

```bash
ALTER ROLE postgres PASSWORD 'pgadminpass123';
```

Expected output:

```
ALTER ROLE
```

### Step 6 - Restore the original pg_hba.conf

For this lab, restore the proper configuration that has scram-sha-256 for TCP and trust for local:

```bash
\q
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Restore the file to:

```
# TYPE  DATABASE  USER  ADDRESS         METHOD
local   all       all                   trust
host    all       all   127.0.0.1/32    scram-sha-256
host    all       all   ::1/128         scram-sha-256
host    all       all   0.0.0.0/0       scram-sha-256
local   replication all                 trust
host    replication all 127.0.0.1/32   scram-sha-256
```

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data reload
```

### Step 7 - Exit the postgres user shell

```bash
exit
```

### Step 8 - Verify TCP connection works

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U postgres -d stepup_store
```

Enter `pgadminpass123` when prompted.

Expected output:

```
psql (16.3)
stepup_store=#
```

```bash
\q
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- postgres can connect via Unix socket
- postgres can connect via TCP with known password
- pg_hba.conf has a local trust rule
- stepup_store database is accessible

---

## Interview Discussion Points

1. **Why does peer authentication provide a recovery path even when the password is unknown?** - Peer auth works at the OS level. The kernel tells PostgreSQL what OS user owns the connecting process. If you are running as the postgres OS user, PostgreSQL trusts that identity without a password. Passwords are a database-level concept; OS user identity is enforced by the kernel and cannot be spoofed by the database.

2. **What if the postgres OS user account was also locked?** - You would need to use `sudo` as root to edit pg_hba.conf and then use `sudo -u postgres` to run pg_ctl reload. If even root access was unavailable, you would need to boot the server in single-user mode or access the filesystem directly (for cloud VMs, this means stopping the instance and mounting the volume elsewhere).

3. **Is it safe to use trust for local connections permanently?** - In most production environments, yes. The Unix socket file is in a directory owned by the postgres OS user with permissions 0700 or similar. Only processes running as postgres can connect through it. If your OS-level security is sound (no unauthorized sudo access to postgres), local trust is acceptable and convenient.

4. **How would you prevent this lockout from happening in the future?** - Always test pg_hba.conf changes with a reload (not restart) while keeping an existing connection open. Never remove the local trust/peer rule as your only change - if the file is broken, your open connection keeps working but new connections fail. Also, restrict who can run `ALTER SYSTEM` or edit pg_hba.conf at the OS level.

5. **What is the difference between using peer and trust for local connections?** - `peer` verifies that the OS username matches the database role name. The postgres OS user can ONLY connect as the postgres database role. `trust` allows any OS user that can reach the socket to connect as any database role. For the postgres socket (which is in a postgres-owned directory), this distinction matters less, but in environments where multiple OS users can reach the socket, `peer` is more secure.
