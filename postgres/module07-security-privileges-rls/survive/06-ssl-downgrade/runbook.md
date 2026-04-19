# Scenario 06 - SSL Downgrade

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Security scan detected that the database server
is accepting unencrypted connections on port 5432.
SSL was previously required for all remote connections.
Compliance team flagged this as a critical finding.
```

---

## Key Concepts for Revision

- **ssl = on enables TLS in PostgreSQL** - The `ssl` parameter in `postgresql.conf` controls whether the server offers encrypted connections. When set to `off`, the server cannot accept SSL connections at all. The server needs certificate files (`server.crt` and `server.key`) in the data directory.

- **hostssl vs host in pg_hba.conf** - `hostssl` entries only match SSL connections. `host` entries match both SSL and non-SSL connections. Changing `hostssl` to `host` allows clients to connect without encryption, even if the server supports SSL. To enforce SSL, use `hostssl` for all remote entries.

- **Reload vs restart for SSL changes** - Changing `ssl = on/off` requires a restart. Changing pg_hba.conf entries requires only a reload. To be safe, restart the server after making both changes.

- **Check SSL status at runtime** - Use `SHOW ssl;` to see if SSL is enabled. Use `SELECT * FROM pg_stat_ssl;` to see which connections are using SSL and what cipher they use.

---

## Diagnostic Steps

### Step 1 - Check the current SSL status

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

```sql
SHOW ssl;
```

Expected output:

```
 ssl
-----
 off
(1 row)
```

SSL is disabled. This confirms the alert.

### Step 2 - Check pg_hba.conf for hostssl entries

```sql
\q
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Look for lines that start with `host` vs `hostssl`. You should see lines like:

```
host    all    all    0.0.0.0/0    scram-sha-256
```

These were originally `hostssl` but have been changed to `host`, allowing unencrypted connections.

Exit vi without changes:

```
:q
```

### Step 3 - Check if SSL certificates still exist

```bash
ls -la /opt/pgsql/data/server.crt /opt/pgsql/data/server.key
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 1234 Apr 19 10:00 /opt/pgsql/data/server.crt
-rw------- 1 postgres postgres 1704 Apr 19 10:00 /opt/pgsql/data/server.key
```

The certificates are still there. We just need to re-enable SSL and restore the pg_hba.conf entries.

---

## Resolution

### Step 1 - Re-enable SSL in postgresql.conf

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the line `ssl = off` and change it to:

```
ssl = on
```

Save and exit vi:

```
:wq
```

### Step 2 - Also clear any ALTER SYSTEM override

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

```sql
ALTER SYSTEM RESET ssl;
```

Expected output:

```
ALTER SYSTEM
```

```sql
\q
```

### Step 3 - Restore hostssl entries in pg_hba.conf

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Find all lines that start with `host ` and match remote connections (lines with IP ranges like `0.0.0.0/0` or specific subnets). Change `host` back to `hostssl`.

For example, change:

```
host    all    all    0.0.0.0/0    scram-sha-256
```

To:

```
hostssl all    all    0.0.0.0/0    scram-sha-256
```

Leave `local` entries and `host ... 127.0.0.1/32` entries unchanged - local connections do not need SSL.

Save and exit vi:

```
:wq
```

### Step 4 - Restart PostgreSQL

SSL changes require a restart (not just a reload).

```bash
exit
```

```bash
sudo systemctl restart postgresql-16
```

### Step 5 - Verify SSL is enabled

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

```sql
SHOW ssl;
```

Expected output:

```
 ssl
-----
 on
(1 row)
```

### Step 6 - Verify SSL connections work

```sql
SELECT pid, ssl, version, cipher
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
  pid  | ssl | version |       cipher
-------+-----+---------+--------------------
 12345 | t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

The current connection is using SSL.

### Step 7 - Exit

```sql
\q
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
- SSL is enabled (SHOW ssl returns on)
- pg_hba.conf contains hostssl entries for remote connections
- SSL connections work

---

## Interview Discussion Points

1. **Why is SSL important for database connections?** - Without SSL, all data between the client and server travels in plaintext, including passwords, queries, and results. Anyone who can intercept network traffic (man-in-the-middle, compromised switch, cloud network sniffing) can read everything. SSL encrypts the entire connection. It is mandatory for compliance frameworks like PCI DSS, HIPAA, and SOC 2.

2. **What is the difference between hostssl, host, and hostnossl in pg_hba.conf?** - `hostssl` matches only SSL connections. `host` matches both SSL and non-SSL connections. `hostnossl` matches only non-SSL connections. For security, use `hostssl` for all remote entries to enforce encryption. `hostnossl` is useful for explicitly rejecting non-SSL attempts with a clear error message.

3. **What happens to existing connections when you change ssl from on to off?** - Existing SSL connections continue to work until they disconnect. The change only affects new connections. After setting `ssl = off` and restarting, new connections cannot use SSL but existing ones are unaffected until they close. This is why security scans may detect the issue before users notice.

4. **How do you verify that a client is actually using SSL?** - From the server, query `pg_stat_ssl` to see SSL status per connection. From the client, `psql` shows the SSL status in the connection info when connecting: `SSL connection (protocol: TLSv1.3, cipher: ...)`. You can also run `SELECT ssl_is_used()` from the client's session.

5. **Should local connections also use SSL?** - Generally no. Local connections via Unix socket (`local` entries in pg_hba.conf) do not traverse the network, so encryption is not needed. Connections to `127.0.0.1` are also safe from network interception. SSL adds overhead (TLS handshake), so requiring it for local connections is unnecessary performance cost.
