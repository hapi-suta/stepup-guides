# Use 02 - SSL Verification End-to-End

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 20 minutes

---

## Objective

Verify that SSL is working correctly from multiple angles: the PostgreSQL system views, the psql client, and the openssl command-line tool. You will also inspect certificate details and confirm the cipher suite in use.

---

## Prerequisites

Build 03 (SSL Configuration) must be complete. PostgreSQL should be running with `ssl = on` and pg_hba.conf should have `hostssl` rules.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Check SSL status from the database

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check that ssl is on:

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

Check the certificate file and key file being used:

```sql
SHOW ssl_cert_file;
```

```sql
SHOW ssl_key_file;
```

Expected output (yours will differ):

```
 ssl_cert_file
---------------
 server.crt
(1 row)

 ssl_key_file
--------------
 server.key
(1 row)
```

---

## Step 3 - Check which connections are using SSL

```sql
SELECT pid, usename, ssl, version, cipher, bits, client_addr
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE backend_type = 'client backend';
```

Expected output (yours will differ):

```
 pid  | usename  | ssl | version | cipher                       | bits | client_addr
------+----------+-----+---------+------------------------------+------+-------------
 1234 | postgres | f   |         |                              |      |
```

The current local Unix socket connection shows `ssl = f` (false) because Unix sockets do not use SSL. To see an SSL connection, you need to connect over TCP.

---

## Step 4 - Exit psql and make a TCP SSL connection

```sql
\q
```

Connect over TCP with sslmode=require:

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store sslmode=require"
```

The psql prompt should show the SSL connection banner:

Expected output (yours will differ):

```
psql (16.3)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

stepup_store=#
```

---

## Step 5 - Check pg_stat_ssl from within the SSL session

```sql
SELECT pid, ssl, version, cipher, bits, client_addr
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
 pid  | ssl | version | cipher                       | bits | client_addr
------+-----+---------+------------------------------+------+-------------
 1235 | t   | TLSv1.3 | TLS_AES_256_GCM_SHA384       |  256 | 127.0.0.1
(1 row)
```

All fields are populated for the SSL connection. The `bits` column confirms the key length of the cipher.

---

## Step 6 - Inspect the server certificate from psql

```sql
SELECT sslkey, sslpassword, sslrootcert, sslcert
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
 sslkey | sslpassword | sslrootcert | sslcert
--------+-------------+-------------+---------
        |             |             |
(1 row)
```

These columns are empty for server-side SSL without client certificates. In a mutual TLS setup (client cert authentication), they would be populated.

---

## Step 7 - Exit psql

```sql
\q
```

---

## Step 8 - Inspect the certificate with openssl x509

```bash
openssl x509 -in /opt/pgsql/data/server.crt -noout -subject -issuer -dates
```

`-subject` shows who the certificate was issued to. `-issuer` shows who signed it (same for self-signed). `-dates` shows validity period.

Expected output (yours will differ):

```
subject=C=US, O=StepUp, CN=pg-node1
issuer=C=US, O=StepUp, CN=pg-node1
notBefore=Apr 19 12:00:00 2026 GMT
notAfter=Apr 19 12:00:00 2027 GMT
```

For a self-signed certificate, subject and issuer are identical. Note the notAfter date - this is when the certificate expires.

---

## Step 9 - Check certificate fingerprint

```bash
openssl x509 -in /opt/pgsql/data/server.crt -noout -fingerprint -sha256
```

The fingerprint uniquely identifies a certificate. You can store this fingerprint and verify it has not been replaced (for certificate pinning).

Expected output (yours will differ):

```
SHA256 Fingerprint=AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99
```

---

## Step 10 - Test the SSL handshake with openssl s_client

Open a second terminal and connect to the database port with openssl:

```bash
openssl s_client -connect 127.0.0.1:5432 -starttls postgres
```

`s_client` makes a raw SSL connection. The `-starttls postgres` flag tells openssl to perform the PostgreSQL protocol upgrade to SSL (because PostgreSQL starts in plaintext and upgrades via a handshake before SSL).

Expected output (yours will differ):

```
CONNECTED(00000003)
depth=0 C=US, O=StepUp, CN=pg-node1
verify error:num=18:self-signed certificate
verify return:1
...
SSL handshake has read 1234 bytes and written 567 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
...
---
```

The "self-signed certificate" verify error is expected since we generated our own cert. In production, a CA-signed certificate would not show this error.

Press Ctrl+C to exit openssl s_client.

---

## Step 11 - Verify the certificate will not expire soon

Calculate days until expiry:

```bash
openssl x509 -in /opt/pgsql/data/server.crt -noout -checkend 2592000
```

`-checkend N` checks if the certificate will expire in the next N seconds. `2592000` is 30 days.

Expected output:

```
Certificate will not expire
```

If the certificate is within 30 days of expiry:

```
Certificate will expire
```

This check is useful in monitoring scripts. Add it to your cron or monitoring system so you get advance warning before a certificate expires.

---

## Step 12 - Exit and return to ec2-user

```bash
exit
```

---

## Validation Questions

Answer these before moving to the next exercise:

1. What does `sslmode=prefer` do differently from `sslmode=require`?
2. How would you configure psql to verify the server certificate (not just require SSL)?
3. What pg_stat_ssl column tells you the TLS version a client is using?
4. Why does a self-signed certificate cause an openssl verify error, and when does that matter in practice?
