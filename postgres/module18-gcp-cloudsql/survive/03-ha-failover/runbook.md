# RUNBOOK: HA Failover

## Symptom

Application connections dropped suddenly. Reconnection attempts succeed after 30-120 seconds. Cloud SQL operations log shows a FAILOVER event.

---

## Step 1 - Check Instance State

Verify the instance is running.

```bash
gcloud sql instances describe suta-pg-lab --format="value(state)"
```

Expected output:
```
RUNNABLE
```

If the output shows `MAINTENANCE` or `FAILED`, wait for it to complete.

---

## Step 2 - Identify the Failover

Check recent operations for a failover event.

```bash
gcloud sql operations list --instance=suta-pg-lab --limit=5 --format="table(name,operationType,status,startTime,endTime)"
```

Look for `operationType: FAILOVER`.

---

## Step 3 - Verify Zone Change

Check which zone the primary is now in.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(gceZone,secondaryGceZone)"
```

The primary zone should have changed. The old primary zone is now the standby.

---

## Step 4 - Verify Data Integrity

Connect to the instance.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Check that tables and data are intact.

```sql
SELECT count(*) FROM students;
```

Run a write test to confirm the instance accepts writes.

```sql
INSERT INTO failover_test (note) VALUES ('failover recovery verified');
```

```sql
SELECT * FROM failover_test ORDER BY id DESC LIMIT 3;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 5 - Verify Application Connectivity

If using the Auth Proxy, verify it reconnected automatically.

```bash
cloud-sql-proxy [CONNECTION_NAME]
```

The proxy should reconnect without manual intervention. Check its output for reconnection messages.

For direct connections, verify the IP has not changed.

```bash
gcloud sql instances describe suta-pg-lab --format="value(ipAddresses[0].ipAddress)"
```

The IP stays the same after failover. Applications reconnect to the same address.

---

## Step 6 - Check HA Is Still Active

Confirm the standby is healthy.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.availabilityType,gceZone,secondaryGceZone)"
```

Expected output (yours will differ):
```
gceZone: us-central1-b
secondaryGceZone: us-central1-a
settings:
  availabilityType: REGIONAL
```

Both `gceZone` and `secondaryGceZone` should be populated. If `secondaryGceZone` is missing, HA may need to be re-enabled.

---

## Prevention

- Use the Auth Proxy - it handles reconnection automatically
- Implement retry logic with exponential backoff in applications
- Set `connect_timeout=10` and `target_session_attrs=read-write` in connection strings
- Set up alerts for failover events in Cloud Audit Logs
- Test failovers regularly during maintenance windows
