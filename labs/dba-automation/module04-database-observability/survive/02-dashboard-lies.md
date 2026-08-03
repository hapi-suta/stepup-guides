# SURVIVE 02: The Dashboard That Lied

**Module 04 - Database Observability**
**Difficulty:** Intermediate
**Time Limit:** 30 minutes

---

## The Scenario

It is Tuesday morning. Users are reporting that the application is slow - queries that normally take 50ms are taking 2-3 seconds. You pull up your Grafana PostgreSQL dashboard. Everything is green:

- Connection count: 12 (out of 200 max) - green
- Cache hit ratio: 99.8% - green
- Replication lag: 0 seconds - green
- Transactions per second: 450 - normal
- CPU: 15% - green
- Dead tuples: minimal - green

Your dashboard says the database is perfectly healthy. But users are clearly experiencing slowness.

**Your job:** Figure out why the dashboard is lying, fix the monitoring configuration, and add safeguards so this cannot happen again.

---

## The Investigation

### Task 1: Verify the Problem Is Real (5 minutes)

Before blaming the dashboard, confirm users are not imagining things.

1. Connect directly to the primary database and check:
   ```sql
   -- Check currently running queries
   SELECT
     pid,
     now() - query_start AS duration,
     state,
     wait_event_type,
     wait_event,
     left(query, 80) AS query
   FROM pg_stat_activity
   WHERE state = 'active'
   AND pid != pg_backend_pid()
   ORDER BY duration DESC;
   ```

2. If you see queries taking seconds when they should take milliseconds, the problem is confirmed. The database IS slow.

3. Run a simple query and time it:
   ```sql
   \timing on
   SELECT count(*) FROM users;
   ```

   If this takes noticeably longer than usual, the problem is on the primary.

### Task 2: Find Why the Dashboard Is Wrong (10 minutes)

The dashboard shows everything green. The database is slow. Something is wrong with the monitoring, not the database.

**Hypothesis: postgres_exporter is connected to the wrong server.**

1. Check which server postgres_exporter is actually querying:

   ```bash
   curl -s http://localhost:9187/metrics | grep pg_stat_activity_count
   ```

   Look at the labels. Is the `instance` label what you expect?

2. Check the postgres_exporter connection string:

   ```bash
   # If running as a Docker container
   docker inspect postgres-exporter | grep DATA_SOURCE_NAME

   # If running as a process
   ps aux | grep postgres_exporter
   # or check the environment
   cat /etc/default/postgres_exporter  # or wherever your env file is
   ```

3. **The discovery:** The `DATA_SOURCE_NAME` points to the replica, not the primary.

   ```
   DATA_SOURCE_NAME="postgresql://monitor@db-replica-1:5432/postgres"
   ```

   This is why the dashboard looks healthy:
   - The replica has few connections (only read queries routed to it)
   - The replica's cache is warm for read queries
   - Replication lag measured FROM the replica is always 0 (it measures its own lag)
   - CPU is low because the replica handles less traffic

   Meanwhile, the primary:
   - Has high CPU from write-heavy queries
   - Has lock contention from a long-running migration
   - Has connection pooling issues

4. Confirm by querying the metric for `pg_is_in_recovery`:

   ```bash
   curl -s http://localhost:9187/metrics | grep pg_in_recovery
   ```

   If `pg_in_recovery` = 1, the exporter is connected to a replica. For monitoring the primary, it should be 0.

### Task 3: Fix the Configuration (10 minutes)

**Step 1: Update the connection string to point to the primary**

```bash
# If using Docker
docker stop postgres-exporter
docker rm postgres-exporter

docker run -d \
  --name postgres-exporter \
  -p 9187:9187 \
  -e DATA_SOURCE_NAME="postgresql://monitor@db-primary:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter:latest
```

**Step 2: Add a SECOND exporter for the replica**

You should monitor BOTH the primary and replica, but know which is which.

```bash
docker run -d \
  --name postgres-exporter-replica \
  -p 9188:9187 \
  -e DATA_SOURCE_NAME="postgresql://monitor@db-replica-1:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter:latest
```

**Step 3: Update Prometheus to scrape both**

```yaml
scrape_configs:
  - job_name: "postgresql"
    static_configs:
      - targets: ["localhost:9187"]
        labels:
          instance: "db-primary"
          role: "primary"

      - targets: ["localhost:9188"]
        labels:
          instance: "db-replica-1"
          role: "replica"
```

**Step 4: Restart Prometheus**

### Task 4: Add a Monitoring Health Panel (5 minutes)

Add a panel to your Grafana dashboard that catches this problem in the future.

**Panel: "Monitoring Health Check"**

This panel verifies that the primary exporter is actually connected to the primary:

```promql
# Should be 0 for primary, 1 for replica
pg_in_recovery{role="primary"}
```

Create a Stat panel:
- Query: `pg_in_recovery{role="primary"}`
- Value mappings: 0 = "PRIMARY (correct)", 1 = "REPLICA (WRONG!)"
- Thresholds: green = 0, red = 1
- Title: "Primary Exporter Target Check"

**Additional monitoring health checks:**

```promql
# Alert if exporter is scraping the wrong server
- alert: ExporterTargetMismatch
  expr: pg_in_recovery{role="primary"} == 1
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "postgres_exporter labeled as primary is connected to a replica"
    description: "The exporter for {{ $labels.instance }} is querying a server in recovery mode. Fix the DATA_SOURCE_NAME."

# Alert if any exporter is down
- alert: ExporterDown
  expr: up{job="postgresql"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "postgres_exporter for {{ $labels.instance }} is unreachable"
```

---

## Why This Happened

This is a common configuration drift problem. Possible causes:

| Cause | How It Happens |
|---|---|
| DNS change after failover | Primary failed over, DNS updated, but exporter config still has the old hostname |
| Copy-paste error | Someone copied the replica config when setting up the primary exporter |
| Failover without exporter update | Database failed over but nobody updated the monitoring connection |
| Hostname confusion | `db-1` used to be primary, now it is replica after a failover |

---

## Prevention Checklist

- [ ] Add `pg_in_recovery` check to every exporter - alert if role label does not match actual server role
- [ ] Use separate exporters for primary and each replica with explicit role labels
- [ ] Add "Monitoring Health" section to every dashboard
- [ ] After every failover, verify monitoring targets point to the correct servers
- [ ] Use connection strings that reference role-aware endpoints (like Aurora cluster endpoints) instead of hostnames
- [ ] Document exporter configuration in version control, not just in running containers

---

## Validation

You have succeeded when:

1. You identified that postgres_exporter was connected to the replica instead of the primary
2. You reconfigured the exporter to monitor the primary
3. You set up separate exporters for primary and replica with role labels
4. You added a "Monitoring Health Check" panel that detects this misconfiguration
5. You added an alert rule for `pg_in_recovery` mismatch
6. You can explain why monitoring the replica made everything look green while the primary was suffering
