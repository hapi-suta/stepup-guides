# Runbook: Storage Full
## Survive Scenario 04

**Symptom:** CloudWatch alarm fires: "FreeStorageSpace < 2 GB". Application may start throwing write errors.
**Severity:** High - write operations will fail when storage hits 0
**Time to resolve:** 20 to 40 minutes

---

## Your Starting Point

You receive a CloudWatch alarm:
```
ALARM: suta-rds-lab-low-storage
State: ALARM
Metric: FreeStorageSpace
Value: 1,234,567,890 bytes (~1.1 GB)
Threshold: 2,147,483,648 bytes (2 GB)
```

The application may still be running, but write operations could start failing soon.

---

## Step 1 - Confirm the Storage Situation

Check the free storage from CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions "Name=DBInstanceIdentifier,Value=suta-rds-lab" \
  --start-time "$(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Minimum \
  --query "sort_by(Datapoints, &Timestamp)[-1].Minimum" \
  --output text
```

Expected output (bytes):
```
1234567890
```

That is about 1.1 GB free. Critical.

Also check total allocated storage:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].AllocatedStorage" \
  --output text
```

Expected output: `20` (GB)

So: 20 GB total, ~1.1 GB free = ~18.9 GB used = 94.5% full.

---

## Step 2 - Find What Is Using the Space

Connect to the database and check table sizes:

```bash
psql -h suta-rds-lab.abc123.us-east-1.rds.amazonaws.com \
  -U postgres -d labdb -p 5432
```

Check the largest tables in the database:

```sql
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename) -
                   pg_relation_size(schemaname || '.' || tablename)) AS index_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 10;
```

Expected output (yours will vary):
```
   table_name   | total_size | data_size | index_size
----------------+------------+-----------+------------
 public.storage_bloat | 11 GB  | 11 GB   | 0 bytes
 public.sales_orders  | 128 MB | 90 MB   | 38 MB
 public.aurora_test   | 8192 bytes | 8192 bytes | 0 bytes
(3 rows)
```

There it is: `storage_bloat` at 11 GB. This is the problem table.

Also check total database size:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
```

---

## Step 3 - Identify the Bloat

For the suspected table, check when it was created and who created it:

```sql
SELECT
    relname AS table_name,
    relkind,
    relpersistence,
    pg_size_pretty(relpages * 8192::bigint) AS estimated_size
FROM pg_class
WHERE relname = 'storage_bloat';
```

Check `relpersistence`:
- `p` = permanent table
- `u` = unlogged table
- `t` = temporary table

`u` (unlogged) means this table does not write to the WAL. It is faster to create but data is lost if PostgreSQL crashes. This is unusual for an application table and suggests it was created for testing or as a mistake.

---

## Step 4 - Option A - Drop the Bloat Table (If It is Safe)

If the table is truly unwanted (test data, bloat, or an error), drop it immediately:

```sql
DROP TABLE IF EXISTS storage_bloat;
```

Expected output:
```
DROP TABLE
```

This immediately frees the space.

> **Concept:** On PostgreSQL, `DROP TABLE` immediately removes the table's files from disk. You do not need to `VACUUM` afterward. The space is available to the OS immediately.

Verify space was freed:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
```

Exit psql:

```sql
\q
```

---

## Step 5 - Option B - Expand Storage (If Data Must Be Kept)

If the table cannot be dropped (real data), you need more storage. You can expand the allocated storage on a live instance without downtime.

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --allocated-storage 50 \
  --apply-immediately
```

What the flags do:
- `--allocated-storage 50` - increase from 20 GB to 50 GB
- `--apply-immediately` - start the modification now (not during maintenance window)

> **Concept:** RDS storage expansion is online. Your database keeps running. AWS expands the EBS volume in the background. You cannot shrink storage after expanding it.

Wait for the modification to complete:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier suta-rds-lab
```

Verify new storage:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].AllocatedStorage" \
  --output text
```

Expected output: `50`

---

## Step 6 - Enable Storage Autoscaling (Prevention)

After resolving the immediate problem, enable storage autoscaling so this never happens again:

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --max-allocated-storage 100 \
  --apply-immediately
```

`--max-allocated-storage 100` sets the maximum the instance can autoscale to (100 GB). AWS will automatically expand storage when it reaches 90% usage.

Verify autoscaling is enabled:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].MaxAllocatedStorage" \
  --output text
```

Expected output: `100`

---

## Step 7 - Verify Storage Health

Check free storage from CloudWatch (may take 5-10 minutes to reflect the change):

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions "Name=DBInstanceIdentifier,Value=suta-rds-lab" \
  --start-time "$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 60 \
  --statistics Minimum \
  --query "sort_by(Datapoints, &Timestamp)[-1].Minimum" \
  --output text
```

The value should be significantly higher than before (> 2 GB, ideally > 5 GB).

---

## Step 8 - Verify Write Operations Work

Connect to the database and confirm writes succeed:

```bash
psql -h suta-rds-lab.abc123.us-east-1.rds.amazonaws.com \
  -U postgres -d labdb -p 5432
```

```sql
CREATE TABLE IF NOT EXISTS storage_health_check (
    id SERIAL,
    ts TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO storage_health_check DEFAULT VALUES;
SELECT count(*) FROM storage_health_check;
DROP TABLE storage_health_check;
```

If these queries succeed, write operations are working normally.

```sql
\q
```

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | Large unlogged table `storage_bloat` consuming ~11 GB |
| Impact | Near-full storage. Writes would fail if storage hit 0. |
| How to detect | CloudWatch FreeStorageSpace alarm |
| Immediate fix | Drop the bloat table (or expand storage if data is needed) |
| Long-term fix | Enable storage autoscaling + set CloudWatch alarm at 20% free |
| Time to recover | 5 minutes (drop table) or 15 minutes (expand storage) |

---

## Prevention

1. **CloudWatch alarm on FreeStorageSpace**: Alert at 20% free (not 5%). This gives you time to react.

2. **Storage autoscaling**: Enable on all production instances. Set `max-allocated-storage` to 2x current size.

3. **Weekly storage review**: Add a weekly job that runs this query and logs the results:
   ```sql
   SELECT tablename, pg_size_pretty(pg_total_relation_size(tablename::regclass))
   FROM pg_tables WHERE schemaname = 'public'
   ORDER BY pg_total_relation_size(tablename::regclass) DESC LIMIT 10;
   ```

4. **Development hygiene**: Never run large data-filling operations against production databases. Use a separate dev/test instance.

---

## Now Run the Validate Script

```bash
bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/04-storage-full/validate.sh
```
