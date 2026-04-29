# SURVIVE Runbook - 01: Exporter Crash

**Scenario:** postgres_exporter is down and its configuration is broken
**Symptom:** No data in Grafana dashboards, Prometheus shows postgres target as DOWN
**Severity:** Critical - metrics collection has stopped

---

## Layer 1: Quick Triage

Check the Prometheus targets page first. Open your browser:

```
http://<your-server-ip>:9090/targets
```

Look at the `postgres` job row. If the **State** column shows **DOWN**, the exporter is not reachable.

Confirm by trying to reach the metrics endpoint directly:

```bash
curl http://localhost:9187/metrics
```

If this command fails or times out, the exporter process is not running.

Check the service status:

```bash
sudo systemctl status postgres_exporter
```

Expected output when broken (yours will differ):

```
● postgres_exporter.service - Prometheus PostgreSQL Exporter
     Active: failed (Result: exit-code) since ...
```

---

## Layer 2: Root Cause Analysis

Check the service logs to understand why it failed:

```bash
sudo journalctl -u postgres_exporter -n 50 --no-pager
```

Look for lines like:

```
msg="Error opening connection to database" err="..."
```

or:

```
level=error msg="Failed to connect to database..."
```

This tells you the exporter started but could not connect to PostgreSQL.

Check what is in the environment file:

```bash
sudo cat /etc/postgres_exporter/postgres_exporter.env
```

If the DATA_SOURCE_NAME has a wrong host, port, user, or password, that is your root cause.

Test the connection string manually as the postgres user:

```bash
sudo -i -u postgres
psql "postgresql://wrong_user:wrong_password@localhost:9999/nonexistent?sslmode=disable"
exit
```

This should fail and show you exactly what is wrong with the connection string.

---

## Layer 3: Fix and Verify

### Step 1 - Restore the correct environment file

Check if a backup exists:

```bash
ls -la /etc/postgres_exporter/
```

If you see `postgres_exporter.env.bak`, restore it:

```bash
sudo cp /etc/postgres_exporter/postgres_exporter.env.bak /etc/postgres_exporter/postgres_exporter.env
```

If no backup exists, rebuild the environment file:

```bash
sudo vi /etc/postgres_exporter/postgres_exporter.env
```

Set the correct content:

```
DATA_SOURCE_NAME=postgresql://postgres_exporter:monitor_secret_2024@localhost:5432/postgres?sslmode=disable
```

### Step 2 - Verify the PostgreSQL monitoring role still exists

```bash
sudo -i -u postgres
psql -c "\du postgres_exporter"
exit
```

Expected output (yours will differ):

```
             List of roles
      Role name       | Attributes
----------------------+------------
 postgres_exporter    |
```

If the role does not exist, recreate it:

```bash
sudo -i -u postgres
psql -c "CREATE ROLE postgres_exporter WITH LOGIN PASSWORD 'monitor_secret_2024';"
psql -c "GRANT pg_monitor TO postgres_exporter;"
exit
```

### Step 3 - Restart postgres_exporter

```bash
sudo systemctl start postgres_exporter
sudo systemctl status postgres_exporter
```

### Step 4 - Verify metrics are flowing

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

Expected output (yours will differ):

```
pg_up 1
```

`pg_up 1` means the exporter successfully connected to PostgreSQL.

### Step 5 - Verify Prometheus sees the target as UP

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A2 '"job": "postgres"'
```

Expected output (yours will differ):

```
            "job": "postgres"
        },
        "health": "up",
```

### Step 6 - Check Grafana dashboards

Open Grafana and verify the PostgreSQL dashboard shows data. It may take 1-2 minutes for Prometheus to scrape and Grafana to display the new data.

---

## Prevention

- Store the environment file in version control (without the password)
- Use a secret manager for the database password
- Set up a test alert (PostgresExporterDown) that fires within 1 minute of the exporter going down
- Keep a record of the correct DATA_SOURCE_NAME in your runbook
