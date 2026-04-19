# Scenario 01 - SSL Certificate Expired

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: SSL certificate on pg-node1 is expired.
Application clients connecting with sslmode=verify-full
are being rejected. The certificate CN is wrong and
the validity period has passed.
```

---

## Key Concepts for Revision

- **SSL certificate lifecycle** - Every SSL certificate has a `notBefore` and `notAfter` date. Clients validating the certificate check these dates against the current time. An expired certificate causes clients using `sslmode=verify-full` or `sslmode=verify-ca` to reject the connection with a certificate verification error. Clients using `sslmode=require` only check that SSL is used, not that the cert is valid - they will still connect. Production systems should always use `sslmode=verify-full`.

- **PostgreSQL does not check certificate expiry at startup** - When you restart PostgreSQL, it loads the certificate file but does not reject it if the certificate is expired. The server starts fine. The rejection happens on the client side during the TLS handshake. This means certificate expiry does not cause a database outage directly - it causes application connection failures while the database itself stays up.

- **Certificate rotation without downtime** - Generate the new certificate first. Copy it to PG_DATA. Run `pg_ctl reload` (or `SELECT pg_reload_conf()`). PostgreSQL re-reads the certificate on reload without dropping existing connections. New connections immediately use the new certificate. No restart is required.

- **openssl checkend** - The `openssl x509 -checkend N` command checks if a certificate will expire within N seconds. Use this in monitoring scripts: `openssl x509 -in server.crt -noout -checkend 2592000` checks if expiry is within 30 days. Automate this check and alert well before expiry.

---

## Diagnostic Steps

### Step 1 - Check PostgreSQL is still running

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
```

PostgreSQL is up. The problem is not a database crash - it is client-side certificate rejection.

### Step 2 - Verify the certificate is expired

```bash
sudo -iu postgres
```

```bash
openssl x509 -in /opt/pgsql/data/server.crt -noout -dates
```

Expected output (yours will differ):

```
notBefore=Jan  1 00:00:00 2024 GMT
notAfter=Jan  2 00:00:00 2024 GMT
```

The `notAfter` date is in the past. The certificate is expired.

```bash
exit
```

### Step 3 - Confirm clients are being rejected

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store sslmode=verify-full" -c "SELECT 1;"
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: SSL error: certificate verify failed
```

```bash
exit
```

---

## Resolution

### Step 1 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

### Step 2 - Navigate to the PostgreSQL data directory

```bash
cd /opt/pgsql/data
```

### Step 3 - Back up the expired certificate

```bash
cp server.crt server.crt.expired-$(date +%Y%m%d)
```

### Step 4 - Generate a new private key (optional - reuse existing if key is intact)

Only generate a new key if the existing key is compromised or you want to rotate it:

```bash
openssl genrsa -out server.key.new 2048
```

```bash
chmod 600 server.key.new
```

```bash
mv server.key.new server.key
```

If reusing the existing key, skip this step.

### Step 5 - Generate a new self-signed certificate

```bash
openssl req -new -x509 -days 365 -key server.key -out server.crt -subj "/CN=pg-node1/O=StepUp/C=US"
```

`-days 365` sets validity to one year from today. Adjust to match your organization's policy.

### Step 6 - Set correct permissions on the new certificate

```bash
chmod 644 server.crt
```

### Step 7 - Verify the new certificate looks correct

```bash
openssl x509 -in server.crt -noout -dates
```

Expected output (yours will differ):

```
notBefore=Apr 19 12:00:00 2026 GMT
notAfter=Apr 19 12:00:00 2027 GMT
```

Confirm `notAfter` is one year in the future.

### Step 8 - Reload PostgreSQL to pick up the new certificate

No restart is needed. Reload is sufficient:

```bash
exit
```

```bash
sudo systemctl reload postgresql-16
```

### Step 9 - Verify SSL is working with the new certificate

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store sslmode=require" -c "SELECT version();"
```

Expected output (yours will differ):

```
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
                             version
-----------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, ...
(1 row)
```

### Step 10 - Confirm the certificate is not expired

```bash
openssl x509 -in /opt/pgsql/data/server.crt -noout -checkend 86400
```

Expected output:

```
Certificate will not expire
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
- SSL is enabled in PostgreSQL
- SSL certificate is not expired
- server.crt has correct permissions (644)
- server.key has correct permissions (600)
- TCP SSL connection succeeds with sslmode=require

---

## Interview Discussion Points

1. **Why does an expired certificate not take PostgreSQL offline?** - PostgreSQL does not enforce certificate validity dates itself. It loads the certificate file at startup or reload and uses it in the TLS handshake. The TLS library sends the certificate to the client. The client then validates it, including the expiry date. If the client rejects the cert, the connection fails on the client side. PostgreSQL continues running and serving connections from clients that use `sslmode=require` (which does not verify the cert) or from local Unix socket clients.

2. **What is the difference between certificate rotation and key rotation?** - Certificate rotation generates a new certificate (potentially with a new CA or CN) while keeping the same private key. The certificate is public and can be freely distributed. Key rotation generates a new private key and a new certificate signed with that key. Key rotation is required if you suspect the private key was compromised. Certificate rotation alone is sufficient for expiry - no need to generate a new key if the existing one is secure.

3. **How would you set up monitoring to prevent being paged for an expired certificate?** - Add a cron job or monitoring check that runs `openssl x509 -in /opt/pgsql/data/server.crt -noout -checkend 2592000`. Exit code 1 means expiry within 30 days. Alert on this and set up an auto-renewal process. For production, use CA-signed certificates from Let's Encrypt or your internal CA with automated renewal (certbot or similar). Set alert thresholds at 30 days and again at 7 days.

4. **If you are using a CA-signed certificate in production, how does certificate rotation work differently?** - You cannot generate a CA-signed certificate yourself - you submit a Certificate Signing Request (CSR) to a Certificate Authority which signs it and returns the certificate. The process: generate a new private key, generate a CSR (`openssl req -new`), submit the CSR to your CA, receive the signed certificate, place it in PG_DATA, reload PostgreSQL. The CA validates your identity during signing, which self-signed certs skip entirely.

5. **What does sslmode=verify-full check that sslmode=require does not?** - `sslmode=require` only checks that the connection is encrypted. It does not verify the server's certificate at all - a man-in-the-middle presenting any certificate would succeed. `sslmode=verify-ca` checks that the certificate is signed by a trusted CA but does not check the hostname. `sslmode=verify-full` additionally checks that the certificate's CN (Common Name) or SAN (Subject Alternative Name) matches the hostname used to connect. This is the only mode that prevents both certificate forgery and hostname mismatch attacks.
