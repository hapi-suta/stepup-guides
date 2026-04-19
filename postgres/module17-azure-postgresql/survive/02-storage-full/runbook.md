# SURVIVE 02 - Storage Full Runbook

## Symptom

The server is in read-only mode or rejecting writes. Queries return errors like `ERROR: could not extend file` or `ERROR: cannot execute INSERT in a read-only transaction`. Storage utilization is at or near 100%.

---

## Diagnosis

### Step 1 - Check Storage Usage

Check the current storage utilization percentage.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "storage_percent" \
  --interval PT5M \
  --query "value[0].timeseries[0].data[-1].{Time:timeStamp, StoragePercent:average}" \
  --output table
```

Replace `[SUBSCRIPTION_ID]` with your subscription ID.

### Step 2 - Check Storage Configuration

View the total provisioned storage.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Storage_GB:storage.storageSizeGb, AutoGrow:storage.autoGrow}" \
  --output table
```

### Step 3 - Find the Largest Tables

Connect to the server (if still possible in read-only mode) and check table sizes.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 10;
```

Expected output (yours will differ):

```
       table_name       | total_size | data_size
------------------------+------------+-----------
 public.storage_bloat   | 612 MB     | 580 MB
 ...
```

Exit psql.

```sql
\q
```

---

## Fix

### Step 4 - Scale Storage Up

Increase storage to give the server room. Storage can only be increased, never decreased. Double the current size.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --storage-size 64
```

This increases storage to 64 GB. The operation completes online without downtime.

### Step 5 - Enable Auto-Grow

Prevent this from happening again by enabling auto-grow.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --storage-auto-grow Enabled
```

### Step 6 - Clean Up the Bloat

Connect and remove the unnecessary data.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Drop the bloat table.

```sql
DROP TABLE IF EXISTS storage_bloat;
```

Reclaim disk space.

```sql
VACUUM FULL;
```

Check the new database size.

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
```

Exit psql.

```sql
\q
```

### Step 7 - Verify Storage Dropped

Wait a few minutes, then check storage percentage again.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "storage_percent" \
  --interval PT5M \
  --query "value[0].timeseries[0].data[-1].{Time:timeStamp, StoragePercent:average}" \
  --output table
```

---

## Prevention

- Enable storage auto-grow on all servers
- Set an alert at 85% storage utilization
- Monitor table bloat with regular `pg_stat_user_tables` queries
- Schedule regular VACUUM operations
- Archive or partition large tables that grow continuously
