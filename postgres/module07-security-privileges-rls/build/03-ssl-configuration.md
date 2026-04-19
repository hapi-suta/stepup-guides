# Build 03 - SSL Configuration

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- How to generate a self-signed SSL certificate using openssl
- How to configure PostgreSQL to use SSL
- How to require SSL connections in pg_hba.conf
- How to verify SSL is active in a client session
- How to watch the Pulse dashboard Security panel show SSL: ON

---

> **Concept: Why SSL Matters for PostgreSQL**
> By default, PostgreSQL transmits data including passwords and query results in plaintext. Anyone with access to the network path between your application and the database can read this traffic. SSL (technically TLS in modern versions) encrypts the connection so that even if traffic is intercepted, it cannot be read. SSL also provides server authentication - the client can verify it is talking to the real database server by checking the server's certificate. For production systems, SSL is non-negotiable. PostgreSQL 16 supports TLS 1.2 and 1.3 only.

---

> **Concept: SSL in pg_hba.conf**
> The `pg_hba.conf` file controls which connections are allowed. There are two host record types: `host` allows both SSL and non-SSL connections. `hostssl` allows only SSL-encrypted connections. `hostnossl` allows only non-SSL connections. To enforce encryption, change `host` to `hostssl` for all entries. The client must then use `sslmode=require` or stronger.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

---

## Step 3 - Generate a self-signed SSL certificate

First, navigate to the PostgreSQL data directory where the certs will live:

```bash
cd /opt/pgsql/data
```

Generate the private key:

```bash
openssl genrsa -out server.key 2048
```

`genrsa` generates an RSA private key. The `2048` specifies the key length in bits. 2048 is the minimum acceptable; 4096 is preferred for production.

Expected output (yours will differ):

```
Generating RSA private key, 2048 bit long modulus (2 primes)
..........................+++++
.+++++
e is 65537 (0x010001)
```

---

## Step 4 - Set correct permissions on the private key

```bash
chmod 600 server.key
```

PostgreSQL will refuse to start SSL if the private key file is world-readable. The `600` permission means only the owner (postgres) can read or write the file.

---

## Step 5 - Generate a self-signed certificate

```bash
openssl req -new -x509 -days 365 -key server.key -out server.crt -subj "/CN=pg-node1/O=StepUp/C=US"
```

`req -new -x509` generates a self-signed certificate directly (skipping the CSR step). `-days 365` sets the validity period. `-key server.key` uses the key we just created. `-subj` provides the certificate subject without an interactive prompt. The `CN` (Common Name) should match the hostname clients use to connect.

Expected output: none (the file is created silently).

---

## Step 6 - Verify the certificate was created

```bash
ls -lh server.key server.crt
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 1.7K Apr 19 12:00 server.key
-rw-r--r-- 1 postgres postgres 1.2K Apr 19 12:00 server.crt
```

---

## Step 7 - View certificate details

```bash
openssl x509 -in server.crt -noout -text
```

`x509 -noout -text` prints the certificate contents without the raw base64 data. Look for `Issuer`, `Subject`, and `Validity` sections to confirm the values you set.

Expected output (yours will differ):

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: ...
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=US, O=StepUp, CN=pg-node1
        Validity
            Not Before: Apr 19 12:00:00 2026 GMT
            Not After : Apr 19 12:00:00 2027 GMT
        Subject: C=US, O=StepUp, CN=pg-node1
        ...
```

---

## Step 8 - Exit postgres shell to edit postgresql.conf

```bash
exit
```

---

## Step 9 - Edit postgresql.conf to enable SSL

```bash
sudo vi /opt/pgsql/data/postgresql.conf
```

Find the SSL section (search with `/ssl` in vi). Update or add these three lines:

```
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

The paths are relative to `PG_DATA` (`/opt/pgsql/data`). Save and exit with `:wq`.

---

## Step 10 - Switch back to postgres user

```bash
sudo -iu postgres
```

---

## Step 11 - Restart PostgreSQL to apply SSL settings

SSL parameters require a restart because they affect how the server initializes its listening socket.

```bash
exit
```

```bash
sudo systemctl restart postgresql-16
```

---

## Step 12 - Verify the restart succeeded

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

---

## Step 13 - Confirm SSL is active in the database

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
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

---

## Step 14 - Check the active SSL connections

```sql
SELECT pid, usename, ssl, version, cipher, client_addr
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE ssl = true;
```

This view shows all active connections that are using SSL. The `version` column shows the TLS version (expect TLS 1.3 on modern systems). The `cipher` column shows the cipher suite in use.

Expected output (yours will differ):

```
 pid  | usename  | ssl | version | cipher         | client_addr
------+----------+-----+---------+----------------+-------------
 1234 | postgres | t   | TLSv1.3 | TLS_AES_256... | (null)
```

A null `client_addr` means the connection is through the Unix socket, which does not use SSL. SSL only applies to TCP connections.

---

## Step 15 - Exit psql

```sql
\q
```

---

## Step 16 - Configure pg_hba.conf to require hostssl

To enforce SSL, change `host` to `hostssl` in pg_hba.conf for TCP connections.

```bash
exit
```

```bash
sudo vi /opt/pgsql/data/pg_hba.conf
```

Find any lines starting with `host` (not `local`). Change them to `hostssl`. For example:

Before:
```
host    all             all             0.0.0.0/0               scram-sha-256
```

After:
```
hostssl all             all             0.0.0.0/0               scram-sha-256
```

Save and exit with `:wq`.

---

## Step 17 - Reload PostgreSQL to apply pg_hba.conf changes

pg_hba.conf changes take effect on reload (no restart needed):

```bash
sudo systemctl reload postgresql-16
```

Expected output: none (reload is silent if successful).

---

## Step 18 - Test an SSL connection from the command line

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store sslmode=require"
```

The connection string format passes SSL options inline. `sslmode=require` tells the client to demand SSL and fail if the server does not support it.

Expected output (yours will differ):

```
psql (16.3)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

stepup_store=#
```

The SSL connection line confirms the connection is encrypted. Note the protocol and cipher details.

---

## Step 19 - Test that a non-SSL TCP connection is rejected

Open a new terminal (do not use sudo -iu postgres, connect as ec2-user directly to test TCP rejection):

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store sslmode=disable user=postgres"
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL: no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "stepup_store", no encryption
```

The `hostssl` rule in pg_hba.conf rejects non-SSL TCP connections. The local Unix socket connections still work (they bypass `hostssl` rules).

---

## Step 20 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Summary

| File | Setting | Purpose |
|------|---------|---------|
| postgresql.conf | ssl = on | Enables SSL at the server level |
| postgresql.conf | ssl_cert_file = 'server.crt' | Points to the server certificate |
| postgresql.conf | ssl_key_file = 'server.key' | Points to the private key (must be 600) |
| pg_hba.conf | hostssl instead of host | Rejects non-SSL TCP connections |

---

## Interview Discussion Points

1. **What is the difference between sslmode=require and sslmode=verify-full?** - `sslmode=require` only checks that the connection is encrypted. It does not verify the server's certificate - a man-in-the-middle attack with a different certificate would succeed. `sslmode=verify-full` requires the server certificate to be signed by a trusted CA and the hostname in the certificate to match the server's hostname. This is the only mode that fully prevents impersonation. For production systems, use `sslmode=verify-full` with a CA-signed or properly configured self-signed certificate.

2. **Why does SSL not apply to Unix socket connections?** - Unix domain sockets are filesystem-level communication channels on the same host. Data never leaves the operating system kernel, so there is no network path to intercept. SSL is a transport-layer protocol designed for network connections. Local connections use `local` records in pg_hba.conf, not `host` or `hostssl`. If you want to restrict local connections by authentication method, you do that through the `local` pg_hba.conf entries, not SSL.

3. **What happens to existing connections when you reload pg_hba.conf?** - Existing connections are not affected by a reload. Only new connection attempts are evaluated against the updated pg_hba.conf. If you change a rule from `host` to `hostssl`, already-connected clients continue their session. New connection attempts without SSL will be rejected. This means a pg_hba.conf reload does not disconnect anyone.

4. **How often should SSL certificates be rotated and how do you do it with zero downtime?** - Certificate rotation frequency depends on certificate lifetime and organizational policy - at minimum when the certificate expires, but many teams rotate annually or more often. For zero downtime: generate the new certificate, replace the files in PG_DATA while PostgreSQL is running, then run `pg_ctl reload` or `SELECT pg_reload_conf()`. PostgreSQL re-reads the cert files on reload without dropping existing SSL connections. New connections will use the new certificate immediately.

5. **What PostgreSQL view tells you whether clients are using SSL?** - `pg_stat_ssl` shows one row per active connection with columns for `ssl` (boolean), `version` (TLS version), `cipher`, `bits` (key length), and `compression`. You JOIN it with `pg_stat_activity` using `pid` to see which users are in SSL sessions. This is the authoritative source for auditing whether your SSL enforcement policy is working.
