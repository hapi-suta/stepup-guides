# SURVIVE 05 - SSL Disabled Runbook

## Symptom

A security audit reveals that `require_secure_transport` is set to `off`. Clients can connect without SSL, meaning data flows unencrypted over the network.

---

## Diagnosis

### Step 1 - Check SSL Setting

Check the current value of `require_secure_transport`.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name require_secure_transport \
  --query "{Name:name, Value:value}" \
  --output table
```

If `Value` is `off`, SSL is not enforced.

### Step 2 - Check Minimum TLS Version

Also verify the minimum TLS version has not been downgraded.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name ssl_min_protocol_version \
  --query "{Name:name, Value:value}" \
  --output table
```

### Step 3 - Verify Unencrypted Connection is Possible

Test that the server currently accepts connections without SSL. The `sslmode=disable` flag forces an unencrypted connection.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=disable"
```

If this connects successfully, SSL is not being enforced.

Exit psql.

```sql
\q
```

---

## Fix

### Step 4 - Re-enable SSL Enforcement

Turn `require_secure_transport` back on.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name require_secure_transport \
  --value on
```

### Step 5 - Set Minimum TLS to 1.2

Ensure the minimum TLS version is at least 1.2.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name ssl_min_protocol_version \
  --value TLSv1.2
```

### Step 6 - Verify Unencrypted Connections are Rejected

Try connecting without SSL. It should fail.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=disable"
```

Expected output:

```
psql: error: connection to server at "suta-pg-lab-server.postgres.database.azure.com" (xxx.xxx.xxx.xxx), port 5432 failed: FATAL:  SSL/TLS required
```

### Step 7 - Verify SSL Connection Works

Connect with SSL to confirm everything works.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Once connected, verify SSL details.

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
 ssl | version |       cipher
-----+---------+---------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
```

The `ssl` column shows `t` (true), confirming the connection is encrypted.

Exit psql.

```sql
\q
```

---

## Prevention

- Never disable SSL in production
- Use Azure Policy to enforce `require_secure_transport = on` across all servers
- Set up Activity Log alerts for parameter changes on security-related settings
- Use `sslmode=verify-full` in application connection strings for maximum security
- Audit `require_secure_transport` setting during regular security reviews
