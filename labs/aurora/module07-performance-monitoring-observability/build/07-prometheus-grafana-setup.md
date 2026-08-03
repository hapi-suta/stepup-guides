# Build 07 - Prometheus and Grafana Setup for Aurora

**Time:** 50 minutes
**Goal:** Deploy an external monitoring stack (Prometheus + postgres_exporter + Grafana) to monitor your Aurora cluster from outside AWS-native tools.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. Docker or Homebrew installed on your Mac. psql access.

---

## Step 1 - Why External Monitoring

CloudWatch and Performance Insights are excellent, but they only work with AWS databases. An external monitoring stack gives you:
- A unified view across AWS, on-premises, and multi-cloud databases
- Custom dashboards that combine database metrics with application metrics
- Long-term metric retention without CloudWatch cost
- Alerting rules that correlate across all systems

The standard open-source stack is:
- **Prometheus** - Metrics collection and storage
- **postgres_exporter** - Translates PostgreSQL stats into Prometheus format
- **Grafana** - Visualization and dashboarding

---

## Step 2 - Create a Monitoring User in Aurora

**On your local machine, connect to your Aurora database:**

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create a dedicated monitoring user with minimal privileges:

```sql
CREATE USER prometheus_exporter WITH PASSWORD 'exporter_secure_2026';
```

```sql
GRANT pg_monitor TO prometheus_exporter;
```

```sql
GRANT CONNECT ON DATABASE postgres TO prometheus_exporter;
```

`pg_monitor` is a built-in role (PostgreSQL 10+) that grants read access to all `pg_stat_*` views and monitoring functions without any write permissions. This is the least-privilege approach.

Exit psql:

```sql
\q
```

---

## Step 3 - Create a Working Directory

**On your Mac, in your terminal:**

```bash
mkdir -p ~/aurora-monitoring
```

---

## Step 4 - Configure and Start postgres_exporter

postgres_exporter connects to your Aurora database and exposes PostgreSQL metrics on an HTTP endpoint.

**Using Docker:**

```bash
docker run -d \
  --name postgres-exporter \
  -p 9187:9187 \
  -e DATA_SOURCE_NAME="postgresql://prometheus_exporter:exporter_secure_2026@${DB_ENDPOINT}:5432/postgres?sslmode=require" \
  quay.io/prometheuscommunity/postgres-exporter:latest
```

Each flag explained:
- `-d`: Run in the background.
- `--name postgres-exporter`: Name the container for easy management.
- `-p 9187:9187`: Map port 9187 (the exporter's default port) from container to host.
- `-e DATA_SOURCE_NAME`: PostgreSQL connection string. Use `sslmode=require` for Aurora.

Verify it is running:

```bash
curl -s http://localhost:9187/metrics | head -20
```

Expected output (yours will differ):
```
# HELP pg_database_size_bytes Disk space used by the database
# TYPE pg_database_size_bytes gauge
pg_database_size_bytes{datname="postgres"} 8.675e+06
# HELP pg_stat_activity_count Number of connections in each state
# TYPE pg_stat_activity_count gauge
pg_stat_activity_count{datname="postgres",state="active"} 2
pg_stat_activity_count{datname="postgres",state="idle"} 5
...
```

If you see metrics, postgres_exporter is working.

---

## Step 5 - Configure and Start Prometheus

Create the Prometheus configuration:

```bash
vi ~/aurora-monitoring/prometheus.yml
```

Add this content:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "postgresql"
    static_configs:
      - targets: ["host.docker.internal:9187"]
        labels:
          cluster: "devops-lab-cluster"
          role: "writer"
          environment: "lab"
```

Note: `host.docker.internal` allows Docker containers to reach services on your Mac. If running Prometheus natively (not Docker), use `localhost:9187`.

**Start Prometheus with Docker:**

```bash
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v ~/aurora-monitoring/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:latest
```

**Or start Prometheus natively (Homebrew):**

```bash
prometheus --config.file=$HOME/aurora-monitoring/prometheus.yml \
  --storage.tsdb.path=$HOME/aurora-monitoring/data \
  --web.listen-address=":9090"
```

Verify Prometheus is running:

Open [http://localhost:9090/targets](http://localhost:9090/targets) in your browser.

You should see two targets:
- `prometheus (1/1 up)` - Prometheus itself
- `postgresql (1/1 up)` - postgres_exporter

If `postgresql` shows as `DOWN`, check that postgres_exporter is running and that Aurora's security group allows connections from your machine.

---

## Step 6 - Test PromQL Queries

Open [http://localhost:9090/graph](http://localhost:9090/graph) and try these queries:

**Database sizes:**

```promql
pg_database_size_bytes{datname!~"template.*"}
```

**Connection count by state:**

```promql
pg_stat_activity_count
```

**Transactions per second:**

```promql
rate(pg_stat_database_xact_commit{datname="postgres"}[5m])
```

**Cache hit ratio:**

```promql
pg_stat_database_blks_hit{datname="postgres"}
  / (pg_stat_database_blks_hit{datname="postgres"} + pg_stat_database_blks_read{datname="postgres"})
  * 100
```

Click the **Graph** tab to see these metrics over time.

---

## Step 7 - Configure and Start Grafana

**Start Grafana with Docker:**

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin123 \
  grafana/grafana:latest
```

Each flag explained:
- `-p 3000:3000`: Map Grafana's web UI port.
- `-e GF_SECURITY_ADMIN_PASSWORD`: Set the admin password. Change this in production.

Open [http://localhost:3000](http://localhost:3000) in your browser.

Log in with:
- Username: `admin`
- Password: `admin123`

---

## Step 8 - Add Prometheus as a Data Source in Grafana

1. Click the gear icon (Settings) in the left sidebar.
2. Click **Data Sources**.
3. Click **Add data source**.
4. Select **Prometheus**.
5. Set the URL to: `http://host.docker.internal:9090`
   (If running Grafana natively, use `http://localhost:9090`)
6. Click **Save & test**.
7. You should see: "Data source is working."

---

## Step 9 - Create a PostgreSQL Dashboard

1. Click the **+** icon in the left sidebar.
2. Click **Dashboard**.
3. Click **Add visualization**.
4. Select **Prometheus** as the data source.

**Panel 1: Connections by State**
- Query: `pg_stat_activity_count{cluster="devops-lab-cluster"}`
- Panel title: "Connections by State"
- Visualization: Time series
- Click **Apply**.

**Panel 2: Database Size**
- Click **Add panel** > **Add visualization**.
- Query: `pg_database_size_bytes{datname!~"template.*", cluster="devops-lab-cluster"}`
- Panel title: "Database Size (bytes)"
- Visualization: Stat
- Click **Apply**.

**Panel 3: Transactions per Second**
- Query: `rate(pg_stat_database_xact_commit{cluster="devops-lab-cluster"}[5m])`
- Panel title: "Commits per Second"
- Visualization: Time series
- Click **Apply**.

**Panel 4: Dead Tuples**
- Query: `pg_stat_user_tables_n_dead_tup{cluster="devops-lab-cluster"} > 0`
- Panel title: "Dead Tuples by Table"
- Visualization: Bar gauge
- Click **Apply**.

**Panel 5: Longest Transaction**
- Query: `pg_stat_activity_max_tx_duration{cluster="devops-lab-cluster"}`
- Panel title: "Longest Transaction (seconds)"
- Visualization: Stat
- Set thresholds: Green < 60, Yellow 60-300, Red > 300
- Click **Apply**.

Save the dashboard:
1. Click the save icon (floppy disk) at the top.
2. Name it: "Aurora - devops-lab-cluster"
3. Click **Save**.

---

## Step 10 - Create Alert Rules in Grafana

1. In your dashboard, click on the "Connections by State" panel.
2. Click **Edit**.
3. Click the **Alert** tab.
4. Click **Create alert rule from this panel**.
5. Set:
   - Condition: `WHEN sum() OF query(A) IS ABOVE 80`
   - Evaluate every: `1m`
   - For: `5m`
6. Add a notification channel (configure email or Slack under Alerting > Notification channels first).
7. Click **Save**.

---

## Cleanup

To stop and remove the Docker containers when you are done:

```bash
docker stop grafana prometheus postgres-exporter
docker rm grafana prometheus postgres-exporter
```

---

## Summary

You have:
- Created a dedicated monitoring user in Aurora
- Deployed postgres_exporter to bridge PostgreSQL stats to Prometheus format
- Configured Prometheus to scrape postgres_exporter
- Deployed Grafana and connected it to Prometheus
- Built a 5-panel PostgreSQL dashboard
- Created a basic alert rule in Grafana

This stack gives you a complete open-source monitoring pipeline that works with any PostgreSQL database - not just Aurora. The same setup works for on-premises, EC2-hosted, and multi-cloud PostgreSQL instances.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| postgres_exporter | Bridge that runs SQL against pg_stat views and exposes results as Prometheus metrics |
| pg_monitor | Built-in PostgreSQL role granting read access to all monitoring views |
| Scrape | Prometheus fetching metrics from an exporter's /metrics endpoint |
| PromQL | Prometheus Query Language - SQL for metrics |
| rate() | PromQL function that calculates per-second rate of a counter metric |
| Data source | Grafana connection to a metrics backend (Prometheus, CloudWatch, etc.) |
| Panel | A single visualization widget in a Grafana dashboard |
| Alert rule | A PromQL expression that fires a notification when true for a duration |
