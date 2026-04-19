# Build 02 - Authentication Methods

**Module:** 06 - Users, Roles & Connections
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- How pg_hba.conf controls who can connect and how
- The difference between trust, peer, scram-sha-256, md5, and cert authentication
- How to change the server from trust to scram-sha-256 for TCP connections
- How to set and verify passwords with ALTER ROLE
- How to observe the Pulse dashboard failing when authentication breaks

---

> **Concept: pg_hba.conf evaluation order**
> PostgreSQL reads pg_hba.conf from top to bottom and uses the FIRST rule that matches the connection attempt (connection type + database + role + source address). Once a match is found, that authentication method is applied. If authentication fails, the connection is rejected - PostgreSQL does NOT try the next rule. Order matters enormously. Always put more specific rules above more general ones.

---

> **Concept: trust vs scram-sha-256**
> With `trust`, PostgreSQL allows the connection with no password check. Anyone who can reach the socket or port can connect as any role. This is safe only on a local dev machine or for the postgres OS user connecting via Unix socket. With `scram-sha-256`, PostgreSQL challenges the client with a cryptographic handshake. The password is never sent in plaintext. md5 sends a hashed password which is weaker. Always use scram-sha-256 for production TCP connections.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - View the current pg_hba.conf

```bash
sudo cat /opt/pgsql/data/pg_hba.conf
```

Expected output (yours will differ):

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
# Allow replication connections from localhost
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
```

Right now, all connections are trusted. No passwords are checked.

---

## Step 3 - Understand the pg_hba.conf columns

Each non-comment line has five fields:

| Field | Meaning |
|-------|---------|
| TYPE | `local` (Unix socket), `host` (TCP, plain or SSL), `hostssl` (SSL only), `hostnossl` (plain TCP only) |
| DATABASE | Which database(s) this rule applies to. `all` matches every database. |
| USER | Which role(s) this rule applies to. `all` matches every role. |
| ADDRESS | Source IP range (CIDR). Only used for `host` type rules. |
| METHOD | Authentication method: trust, peer, scram-sha-256, md5, cert, reject |

---

## Step 4 - Set passwords for existing roles

You must set passwords before switching to password-based authentication. If you switch first, nobody will be able to connect.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER ROLE app_user PASSWORD 'apppass123';
```

```sql
ALTER ROLE readonly_user PASSWORD 'readpass123';
```

```sql
ALTER ROLE admin_user PASSWORD 'adminpass123';
```

```sql
ALTER ROLE postgres PASSWORD 'pgadminpass123';
```

Expected output for each:

```
ALTER ROLE
```

---

> **Concept: Password storage**
> When you run ALTER ROLE ... PASSWORD, PostgreSQL hashes the password and stores the hash in pg_authid. The actual password is never stored. If `password_encryption` is set to `scram-sha-256` (the default in PG16), a SCRAM verifier is stored. If set to `md5`, an md5 hash is stored. You can check with: `SELECT rolname, rolpassword FROM pg_authid WHERE rolname = 'app_user';` - you will see the verifier prefix `SCRAM-SHA-256$...` or `md5...`.

---

## Step 5 - Verify password_encryption setting

```sql
SHOW password_encryption;
```

Expected output:

```
 password_encryption
---------------------
 scram-sha-256
(1 row)
```

Good. PG16 defaults to scram-sha-256. This means ALTER ROLE ... PASSWORD stores a SCRAM verifier, not an md5 hash.

---

## Step 6 - Exit psql

```bash
\q
```

```bash
exit
```

---

## Step 7 - Back up pg_hba.conf before editing

```bash
sudo cp /opt/pgsql/data/pg_hba.conf /opt/pgsql/data/pg_hba.conf.backup
```

Always back up before editing authentication configuration. A mistake here locks everyone out.

---

## Step 8 - Edit pg_hba.conf

```bash
sudo vi /opt/pgsql/data/pg_hba.conf
```

Change the `host` lines (TCP connections) from `trust` to `scram-sha-256`. Leave the `local` lines as `trust` so the postgres OS user can still connect via Unix socket without a password.

The file should look like this after your edits:

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Unix socket connections - postgres OS user can connect without password
local   all             all                                     trust

# TCP connections require password authentication
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# Allow connections from application servers
host    all             app_user        0.0.0.0/0               scram-sha-256

# Replication connections
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256
```

Save and exit vi with `:wq`.

---

## Step 9 - Reload PostgreSQL to apply the changes

You do NOT need a full restart for pg_hba.conf changes. A reload is enough.

```bash
sudo systemctl reload postgresql-16
```

This sends a SIGHUP to the postmaster process, which re-reads pg_hba.conf without closing existing connections.

---

## Step 10 - Test that the postgres OS user can still connect via socket

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT current_user;"
```

This works because the `local` line still uses `trust`, and the Unix socket (`/run/postgresql`) matches `local` rules.

Expected output:

```
 current_user
--------------
 postgres
(1 row)
```

```bash
exit
```

---

## Step 11 - Test that TCP connection now requires a password

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U postgres -d stepup_store -c "SELECT 1;"
```

You should be prompted for a password now. Enter `pgadminpass123`.

Expected output (yours will differ):

```
Password for user postgres:
 ?column?
----------
        1
(1 row)
```

---

## Step 12 - Observe the Pulse dashboard

Open your browser and go to `http://NODE1:8080`. The Pulse app connects to PostgreSQL using TCP (host connection). If the app's config still uses the old `trust` method or has no password configured, you will see connection errors on the dashboard.

The dashboard will show something like:

```
ERROR: password authentication failed for user "app_user"
```

or the app may show a red "Database Offline" indicator depending on your setup.

---

## Step 13 - Fix the Pulse app connection

The Pulse app configuration is typically in an environment file or app config. Update the connection string or password for `app_user` in the app configuration, then restart the app.

```bash
sudo systemctl restart pulse-dashboard
```

Check the dashboard again. It should show green status once the correct password is configured.

---

## Step 14 - Test peer authentication

The `peer` method works for Unix socket connections. PostgreSQL checks the OS username of the connecting process and verifies it matches the database role name.

As `ec2-user`, try to connect as `ec2-user` (this will fail because there is no `ec2-user` role):

```bash
/usr/pgsql-16/bin/psql -d stepup_store -U ec2-user -c "SELECT 1;"
```

Expected output:

```
psql: error: connection to server on socket "/run/postgresql/.s.PGSQL.5432" failed: FATAL:  role "ec2-user" does not exist
```

The `peer` method is what makes `sudo -iu postgres` + psql work without a password - the OS user `postgres` matches the database role `postgres`.

---

> **Concept: cert authentication**
> The `cert` method requires the client to present an SSL certificate signed by a trusted CA. The `cn` (common name) field in the certificate maps to the database role name. This is the strongest authentication method and is used in environments where managing passwords is impractical or where non-repudiation is required. It requires `hostssl` connection type and proper SSL setup on both client and server.

---

## Step 15 - View pg_hba_file_rules (PG16+)

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules;
```

This view shows the parsed rules from pg_hba.conf. It is useful for verifying your edits took effect.

Expected output (yours will differ):

```
 line_number | type  |  database   | user_name |  address  |   auth_method
-------------+-------+-------------+-----------+-----------+-----------------
           6 | local | {all}       | {all}     |           | trust
           9 | host  | {all}       | {all}     | 127.0.0.1 | scram-sha-256
          11 | host  | {all}       | {all}     | ::1       | scram-sha-256
```

---

## Step 16 - Exit

```bash
\q
```

```bash
exit
```

---

## Summary

| Method | Connection Type | Password Required | Security Level |
|--------|----------------|-------------------|----------------|
| trust | local or host | No | None (dev only) |
| peer | local only | No | OS username match |
| md5 | host | Yes (hashed) | Low (vulnerable to replay) |
| scram-sha-256 | host | Yes (SCRAM) | High (production standard) |
| cert | hostssl | No (uses certificate) | Highest |

---

## Interview Discussion Points

1. **Why is `trust` acceptable on local Unix sockets but not TCP?** - The Unix socket is a file in `/run/postgresql/`. Access to that file is controlled by OS-level file permissions and user ownership. Only processes running as the `postgres` OS user or users explicitly granted socket access can connect. TCP connections bypass this OS-level control, so anyone who can reach the port can attempt a connection.

2. **How does PostgreSQL apply pg_hba.conf changes?** - A reload (SIGHUP) causes the postmaster to re-read pg_hba.conf. Existing connections are not affected. New connection attempts use the new rules immediately after the reload completes. No restart is required.

3. **What is the difference between md5 and scram-sha-256?** - md5 hashes the password with the username and a random salt, then sends the hash. If an attacker captures the hash, they can replay it. scram-sha-256 uses a challenge-response protocol where the client proves knowledge of the password without sending the hash. Even if traffic is captured, the verifier cannot be replayed. PG16 defaults to scram-sha-256.

4. **How can you lock out a specific user without dropping them?** - Use `ALTER ROLE rolename NOLOGIN;`. This prevents the role from opening new connections while preserving all their privileges and owned objects. Re-enable with `ALTER ROLE rolename LOGIN;`.

5. **What happens if pg_hba.conf has a syntax error?** - PostgreSQL logs a warning but continues running with the PREVIOUS valid configuration. A reload with a broken pg_hba.conf does not crash the server or lock anyone out. However, a restart with a broken pg_hba.conf will prevent the server from starting. Always test with a reload first, then check pg_hba_file_rules to confirm the rules parsed correctly.
