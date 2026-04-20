# SURVIVE 03 - HA Failover Test Runbook

## Symptom

A failover has been triggered (either by Azure automatically or by an operator). Connections were briefly dropped. The server should be recovering with the standby promoting to primary.

---

## Diagnosis

### Step 1 - Check Server State

Verify the server status and HA health.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, State:state, HAMode:highAvailability.mode, HAState:highAvailability.state, PrimaryZone:availabilityZone, StandbyZone:highAvailability.standbyAvailabilityZone}" \
  --output table
```

If `State` is `Ready` and `HAState` is `Healthy`, the failover completed successfully.

If `State` is `Updating` or `HAState` is `FailingOver`, the failover is still in progress. Wait 1-2 minutes and check again.

### Step 2 - Check Activity Log for Failover Events

```bash
az monitor activity-log list \
  --resource-group suta-pg-lab-rg \
  --offset 1h \
  --query "[?contains(operationName.localizedValue, 'Restart') || contains(operationName.localizedValue, 'Failover')].{Operation:operationName.localizedValue, Status:status.localizedValue, Time:eventTimestamp}" \
  --output table
```

### Step 3 - Test Connectivity

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Once connected, run a quick test:

```sql
SELECT 1 AS connectivity_test;
```

Expected output:

```
 connectivity_test
-------------------
                 1
(1 row)
```

Exit psql:

```sql
\q
```

---

## Fix

If the failover completed (State is Ready), no fix is needed. Verify the environment:

### Step 4 - Verify Data Integrity

Connect and check that data is accessible.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
```

Exit psql.

```sql
\q
```

### Step 5 - Verify Writes Work

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
CREATE TABLE failover_verify (id serial, ts timestamptz DEFAULT now());
```

```sql
INSERT INTO failover_verify DEFAULT VALUES;
```

```sql
SELECT * FROM failover_verify;
```

Expected output (yours will differ):

```
 id |              ts
----+-------------------------------
  1 | 2026-04-19 14:30:00.123456+00
(1 row)
```

```sql
DROP TABLE failover_verify;
```

Exit psql.

```sql
\q
```

### Step 6 - Confirm Zone Swap

Verify the primary and standby zones have swapped.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{PrimaryZone:availabilityZone, StandbyZone:highAvailability.standbyAvailabilityZone}" \
  --output table
```

---

## Prevention

- Ensure applications handle connection drops gracefully with retry logic
- Use connection pooling (PgBouncer is built into Flexible Server)
- Test planned failover during maintenance windows before relying on it in production
- Monitor `highAvailability.state` and alert when it is not `Healthy`
