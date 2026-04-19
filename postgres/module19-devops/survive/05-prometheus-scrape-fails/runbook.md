# SURVIVE 05: Prometheus Scrape Fails - Runbook

## Symptom

Grafana dashboards show "No data" for all PostgreSQL panels. Prometheus target page shows the postgresql job as DOWN.

---

## Step 1: Check Prometheus Targets

If Prometheus is running, check the target status.

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A5 "postgresql"
```

You should see `"health": "down"` for the postgresql target.

---

## Step 2: Check postgres_exporter Status

```bash
sudo systemctl status postgres_exporter
```

Look for error messages in the output. Common errors:
- "connection refused" - PostgreSQL is not running on that port
- "password authentication failed" - Wrong password in DSN
- "database does not exist" - Wrong database name in DSN

---

## Step 3: Check the Exporter Logs

```bash
sudo journalctl -u postgres_exporter --since "10 minutes ago" --no-pager
```

Expected output (yours will differ):
```
postgres_exporter: error connecting to database: pq: password authentication failed for user "monitoring"
```

Or:

```
postgres_exporter: error connecting to database: pq: database "nonexistent_db" does not exist
```

---

## Step 4: Examine the Current DSN

Look at the service file to find the DATA_SOURCE_NAME.

```bash
sudo cat /etc/systemd/system/postgres_exporter.service | grep DATA_SOURCE_NAME
```

Identify the problems:
- Wrong password: `WRONG_PASSWORD`
- Wrong database: `nonexistent_db`

---

## Step 5: Verify the Correct Credentials

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check that the monitoring user exists.

```bash
psql -c "SELECT rolname FROM pg_roles WHERE rolname = 'monitoring';"
```

Check what databases exist.

```bash
psql -c "\l"
```

Test the correct connection.

```bash
psql -h 127.0.0.1 -U monitoring -d postgres -c "SELECT 1;"
```

If this fails with "password authentication failed," you need to reset the monitoring user's password.

```bash
psql -c "ALTER ROLE monitoring WITH PASSWORD 'MonitorPass123';"
```

Exit the postgres user.

```bash
exit
```

---

## Step 6: Fix the Service File

Edit the postgres_exporter service.

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

Fix the DATA_SOURCE_NAME line. Change:

```
Environment="DATA_SOURCE_NAME=postgresql://monitoring:WRONG_PASSWORD@127.0.0.1:5432/nonexistent_db?sslmode=disable"
```

To:

```
Environment="DATA_SOURCE_NAME=postgresql://monitoring:MonitorPass123@127.0.0.1:5432/postgres?sslmode=disable"
```

---

## Step 7: Restart the Exporter

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl restart postgres_exporter
```

Check the status.

```bash
sudo systemctl status postgres_exporter
```

---

## Step 8: Verify Metrics Are Flowing

Check the exporter's metrics endpoint directly.

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

Expected output:
```
# HELP pg_up Whether the last scrape of metrics from PostgreSQL was able to connect
# TYPE pg_up gauge
pg_up 1
```

The value `1` means the exporter is connected. If it shows `0`, the connection is still broken.

If Prometheus is running, wait 15-30 seconds and check the target status again.

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep health
```

---

## Prevention

1. Store the DSN in a separate environment file, not inline in the service unit
2. Use Ansible Vault or AWS Secrets Manager for the monitoring password
3. Add a startup health check to the exporter service that tests the connection
4. Monitor pg_up metric and alert when it drops to 0
5. Test DSN changes in a staging environment before deploying to production

---

## Discussion Points

- Why use a dedicated monitoring user instead of postgres? Least privilege. If the exporter is compromised, the attacker only gets read access to stats, not superuser.
- What happens to Grafana during the outage? Dashboards show "No data" for the affected time window. Once scraping resumes, new data appears but there is a gap.
- Should you alert on pg_up? Yes. A pg_up=0 alert with a 2-minute `for` duration is one of the most important alerts to have.
