# SURVIVE Runbook - 06: Exporter Permission Denied

**Scenario:** The `pg_monitor` role was revoked from the postgres_exporter database role
**Symptom:** Exporter is running but many metrics return no data or permission errors; pg_up = 1
**Severity:** High - the exporter appears healthy but is collecting incomplete data

---

## Layer 1: Quick Triage

This scenario is subtle because pg_up = 1 (the exporter can log in to PostgreSQL), but the monitoring data is wrong or missing.

Check the metrics endpoint for obvious gaps:

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_activity_count
```

If this returns nothing (no lines) when you expect to see connection counts, permissions are likely the issue.

Check the exporter logs for permission errors:

```bash
sudo journalctl -u postgres_exporter -n 50 --no-pager | grep -i "error\|permission\|denied\|privilege"
```

Expected output when broken (yours will differ):

```
msg="Error scraping with collector" collector=stat_activity err="pq: permission denied for view pg_stat_activity"
```

or:

```
msg="Error scraping" err="pq: permission denied for view pg_stat_replication"
```

If you see "permission denied" in the logs, the database role has lost its monitoring privileges.

---

## Layer 2: Root Cause Analysis

Connect to PostgreSQL and check what roles the exporter account currently has:

```bash
sudo -i -u postgres
psql
```

```sql
\du postgres_exporter
```

Expected output when broken (yours will differ):

```
              List of roles
      Role name       | Attributes | Member of
----------------------+------------+-----------
 postgres_exporter    |            | {}
```

The `Member of` column should include `{pg_monitor}`. An empty `{}` means `pg_monitor` was revoked.

Test what the exporter can actually see:

```sql
SET ROLE postgres_exporter;
SELECT count(*) FROM pg_stat_activity;
```

Expected output when broken:

```
ERROR:  permission denied for view pg_stat_activity
```

```sql
RESET ROLE;
\q
```

```bash
exit
```

---

## Layer 3: Fix and Verify

### Step 1 - Grant pg_monitor back to the exporter role

```bash
sudo -i -u postgres
psql
```

```sql
GRANT pg_monitor TO postgres_exporter;
```

Expected output:

```
GRANT ROLE
```

### Step 2 - Restore access to pg_stat_statements in the application database

```sql
\c stepup_store
GRANT SELECT ON pg_stat_statements TO postgres_exporter;
```

Expected output:

```
GRANT
```

### Step 3 - Verify the role membership

```sql
\du postgres_exporter
```

Expected output:

```
              List of roles
      Role name       | Attributes | Member of
----------------------+------------+-----------
 postgres_exporter    |            | {pg_monitor}
```

### Step 4 - Test access as the exporter role

```sql
SET ROLE postgres_exporter;
SELECT count(*) FROM pg_stat_activity;
```

Expected output:

```
 count
-------
     3
(1 row)
```

```sql
RESET ROLE;
\q
```

```bash
exit
```

### Step 5 - Restart postgres_exporter to clear any cached errors

```bash
sudo systemctl restart postgres_exporter
sleep 5
sudo systemctl status postgres_exporter
```

### Step 6 - Verify metrics are collecting correctly

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_activity_count
```

Expected output (yours will differ):

```
pg_stat_activity_count{datname="postgres",state="active"} 1
pg_stat_activity_count{datname="postgres",state="idle"} 2
```

### Step 7 - Verify pg_stat_statements metrics

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_statements | head -5
```

---

## Prevention

- Grant `pg_monitor` using a migration script that is version-controlled, so it can be re-run if revoked
- Alert when the number of postgres_exporter metrics drops dramatically (a sudden drop in metric count indicates permission problems)
- Periodically audit monitoring role permissions: `SELECT member::regrole, roleid::regrole FROM pg_auth_members WHERE roleid = 'pg_monitor'::regrole;`
