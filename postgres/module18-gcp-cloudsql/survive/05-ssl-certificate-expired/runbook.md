# RUNBOOK: SSL Certificate Expired / Rotated

## Symptom

SSL connections fail with `SSL error: certificate verify failed` or `server certificate not trusted`. Applications using `sslmode=verify-ca` or `sslmode=verify-full` cannot connect.

---

## Step 1 - Confirm SSL Is Required

Check if the instance requires SSL.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.ipConfiguration.requireSsl)"
```

If `True`, all connections must use SSL.

---

## Step 2 - Check Server CA Certificates

List all server CA certificates.

```bash
gcloud sql ssl server-ca-certs list --instance=suta-pg-lab
```

Look at the `EXPIRATION` dates. If the active cert expired, or if a rotation happened and your app has the old cert, that is the problem.

---

## Step 3 - Download the Current Server CA Certificate

Download the active server CA certificate.

```bash
gcloud sql ssl server-ca-certs list --instance=suta-pg-lab --format="value(cert)" > /tmp/server-ca.pem
```

Verify the certificate contents.

```bash
openssl x509 -in /tmp/server-ca.pem -noout -subject -dates
```

Expected output (yours will differ):
```
subject=CN = Google Cloud SQL Server CA
notBefore=Apr 19 10:00:00 2026 GMT
notAfter=Apr 19 10:00:00 2036 GMT
```

---

## Step 4 - Test Connection with New Certificate

Get the instance IP.

```bash
gcloud sql instances describe suta-pg-lab --format="value(ipAddresses[0].ipAddress)"
```

Connect with the new CA certificate.

```bash
psql "host=[INSTANCE_IP] user=postgres dbname=suta_lab sslmode=verify-ca sslrootcert=/tmp/server-ca.pem"
```

Verify SSL is active.

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):
```
 ssl | version |         cipher
-----+---------+------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

Type `\q` to exit psql.

```
\q
```

---

## Step 5 - Update Application Configuration

Replace the old CA certificate file in your application's configuration with the new one at `/tmp/server-ca.pem`.

If using client certificates, create new ones:

```bash
gcloud sql ssl client-certs create new-client-cert /tmp/new-client-key.pem --instance=suta-pg-lab
```

```bash
gcloud sql ssl client-certs describe new-client-cert --instance=suta-pg-lab --format="value(cert)" > /tmp/new-client-cert.pem
```

```bash
chmod 0600 /tmp/new-client-key.pem
```

---

## Step 6 - Alternative: Use the Auth Proxy

The Auth Proxy handles SSL automatically. No certificate management needed.

```bash
cloud-sql-proxy [CONNECTION_NAME]
```

Connect through the proxy without SSL certificates.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

---

## Prevention

- Use the Auth Proxy to avoid manual certificate management
- Set up alerts for certificate expiration dates
- Automate certificate rotation in your CI/CD pipeline
- Keep certificates in a secret manager, not on disk
- Schedule certificate updates well before expiration
