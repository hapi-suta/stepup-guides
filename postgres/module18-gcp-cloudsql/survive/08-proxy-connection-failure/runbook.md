# RUNBOOK: Auth Proxy Connection Failure

## Symptom

Applications using the Cloud SQL Auth Proxy cannot connect. The proxy logs show errors like `Access Not Configured`, `instance not found`, or `Permission denied`.

---

## Step 1 - Check If the Proxy Is Running

Check for running proxy processes.

```bash
ps aux | grep cloud-sql-proxy | grep -v grep
```

If no output, the proxy is not running.

---

## Step 2 - Get the Correct Connection Name

The connection name format is `project:region:instance`. Get it from gcloud.

```bash
gcloud sql instances describe suta-pg-lab --format="value(connectionName)"
```

Expected output (yours will differ):

```
my-project:us-central1:suta-pg-lab
```

---

## Step 3 - Verify Authentication

Check your current gcloud authentication.

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
```

If using Application Default Credentials:

```bash
gcloud auth application-default print-access-token > /dev/null 2>&1 && echo "ADC valid" || echo "ADC invalid"
```

If ADC is invalid, re-authenticate.

```bash
gcloud auth application-default login
```

---

## Step 4 - Start the Proxy Correctly

Start the proxy with the correct connection name. Use Application Default Credentials (no key file needed if gcloud is authenticated).

```bash
cloud-sql-proxy [CONNECTION_NAME]
```

If using a service account key file, make sure the file is valid JSON and the service account has the `roles/cloudsql.client` role.

```bash
cloud-sql-proxy --credentials-file=/path/to/valid-key.json [CONNECTION_NAME]
```

Expected output (yours will differ):

```
2026/04/19 16:00:00 Authorizing with Application Default Credentials
2026/04/19 16:00:00 [my-project:us-central1:suta-pg-lab] Listening on 127.0.0.1:5432
2026/04/19 16:00:00 The proxy has started successfully and is ready for new connections!
```

---

## Step 5 - Test the Connection

Open a new terminal and connect through the proxy.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Verify the connection works.

```sql
SELECT current_database(), current_user;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 6 - Clean Up Bad Configuration

Remove the bad credentials file.

```bash
rm -f /tmp/bad-proxy-creds.json
```

Remove the bad startup script.

```bash
rm -f /tmp/start-bad-proxy.sh
```

---

## Common Proxy Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `instance not found` | Wrong connection name | Get correct name from `gcloud sql instances describe` |
| `Access Not Configured` | SQL Admin API disabled | `gcloud services enable sqladmin.googleapis.com` |
| `Permission denied` | Service account lacks role | Grant `roles/cloudsql.client` to the service account |
| `address already in use` | Port 5432 already taken | Use `--port 15432` to listen on a different port |
| `credentials file not found` | Wrong path to key file | Verify file exists, or use `gcloud auth application-default login` |

---

## Prevention

- Run the proxy as a systemd service so it auto-restarts
- Use Application Default Credentials instead of key files when possible
- Store proxy configuration in environment variables
- Monitor proxy health with a liveness check on the listening port
- Keep the proxy binary updated
