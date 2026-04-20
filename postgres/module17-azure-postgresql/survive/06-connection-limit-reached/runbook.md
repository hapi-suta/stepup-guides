# SURVIVE 06 - Connection Limit Reached Runbook

## Symptom

New connections are rejected with `FATAL: too many connections for role "pgadmin"` or `FATAL: remaining connection slots are reserved for non-replication superuser connections`. Applications cannot connect to the database.

---

## Diagnosis

### Step 1 - Check max_connections Setting

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name max_connections \
  --query "{Name:name, Value:value}" \
  --output table
```

### Step 2 - Check Active Connections via Metrics

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "active_connections" \
  --interval PT1M \
  --query "value[0].timeseries[0].data[-1].{Time:timeStamp, Connections:average}" \
  --output table
```

Replace `[SUBSCRIPTION_ID]` with your subscription ID.

### Step 3 - Try to Connect and Check Sessions

If you can get a connection (you may need to wait for one to free up):

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Check what connections are doing.

```sql
SELECT pid, usename, datname, state, query, age(clock_timestamp(), query_start) AS query_age
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

Check total connection count.

```sql
SELECT count(*) AS total_connections FROM pg_stat_activity;
```

```sql
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
```

---

## Fix

### Step 4 - Kill Idle Connections

If you can connect, terminate the long-running idle connections.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND query LIKE '%pg_sleep%'
  AND pid != pg_backend_pid();
```

This terminates all connections running `pg_sleep` (the injected ones) except your own session.

Verify connections dropped.

```sql
SELECT count(*) AS remaining FROM pg_stat_activity;
```

Expected output (yours will differ):

```
 remaining
-----------
         3
(1 row)
```

Exit psql.

```sql
\q
```

### Step 5 - Increase max_connections

Set `max_connections` to a reasonable value. This is a static parameter so the server restarts.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name max_connections \
  --value 200
```

Wait for the restart to complete (30-60 seconds).

### Step 6 - Verify New Limit

Connect and confirm the new setting.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SHOW max_connections;
```

Expected output:

```
 max_connections
-----------------
 200
```

Exit psql.

```sql
\q
```

---

## Prevention

- Size `max_connections` based on expected load plus 20% headroom
- Use PgBouncer (built into Flexible Server) for connection pooling
- Set alerts when active_connections exceeds 80% of max_connections
- Implement connection timeouts in application code
- Monitor for connection leaks (idle connections that never close)
