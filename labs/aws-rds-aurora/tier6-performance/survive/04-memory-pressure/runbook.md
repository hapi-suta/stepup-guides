# Runbook: Memory Pressure

**Scenario:** work_mem is set too high (either globally or per-role). With many concurrent sessions, each running sort operations, the total memory consumed exceeds available RAM. FreeableMemory is dropping. Swap may be in use.

**Time limit:** 20 minutes
**Severity:** P1 - Risk of OOM crash

---

## Symptoms

- CloudWatch `FreeableMemory` dropping below 10% of instance RAM
- Enhanced Monitoring shows active memory growing while free memory drops
- Possible swap usage (any swap on RDS = critical)
- Performance Insights: high CPU with large sort operations
- PostgreSQL log may show: `ERROR: out of memory`

---

## Step 1 - Check Current Memory Status

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='15 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Minimum \
  --region "$REGION"
```

Also check via Enhanced Monitoring in the RDS Console (look at the Memory graph).

---

## Step 2 - Find the Current work_mem Setting

```sql
-- Check global setting
SHOW work_mem;

-- Check per-role settings (this is how the injection works)
SELECT
    rolname,
    rolconfig
FROM pg_roles
WHERE rolconfig IS NOT NULL
  AND array_to_string(rolconfig, ',') LIKE '%work_mem%';
```

If `rolconfig` contains `work_mem=512MB`, that is the culprit.

---

## Step 3 - Immediately Reduce work_mem

Kill the background sessions first to stop the memory consumption:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND left(query, 30) LIKE '%generate_series%'
  AND pid != pg_backend_pid();
```

Remove the per-role work_mem setting:

```sql
ALTER ROLE postgres RESET work_mem;
```

Verify it is cleared:

```sql
SELECT rolname, rolconfig FROM pg_roles WHERE rolconfig IS NOT NULL;
```

New connections will now use the global default.

---

## Step 4 - Reset work_mem for Active Sessions

Existing sessions that connected while work_mem was high still have the high setting. Either kill and reconnect those sessions, or wait for them to finish and disconnect.

Kill all active sessions except your own:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
  AND application_name != 'rdsadmin';
```

---

## Step 5 - Verify Memory is Recovering

Watch FreeableMemory in CloudWatch. After terminating the sessions, memory should recover within 1-2 minutes.

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Average \
  --region "$REGION"
```

---

## Step 6 - Calculate and Set the Correct work_mem

```sql
-- Get instance RAM estimate and max_connections
SHOW max_connections;

-- Calculate safe work_mem
-- Formula: (RAM - shared_buffers - 4GB overhead) / (max_connections * 3)
-- On a 32GB instance with shared_buffers=8GB, max_connections=200:
-- (32 - 8 - 4)GB / (200 * 3) = 20 * 1024 MB / 600 = ~34MB

-- Set a safe value in the parameter group:
```

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters "ParameterName=work_mem,ParameterValue=32768,ApplyMethod=immediate" \
  --region "$REGION"
```

`32768 kB = 32MB`. Adjust based on your instance RAM and max_connections calculation.

---

## Step 7 - Prevent Recurrence

1. Never use `ALTER ROLE` to set memory parameters without calculating the safe value.
2. Set a CloudWatch alarm on `FreeableMemory < 10% of instance RAM`.
3. Review pg_roles for rolconfig periodically:

```sql
SELECT rolname, rolconfig FROM pg_roles WHERE rolconfig IS NOT NULL;
```

4. Use `pg_stat_statements` to identify queries with high `temp_blks_written` - those indicate work_mem may need a measured increase.

---

## Emergency: If the Instance Crashes

If work_mem caused an OOM crash and the instance is in an error state:

```bash
# Force restart
aws rds reboot-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --force-failover \
  --region "$REGION"

# After restart, immediately fix work_mem before accepting connections
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters "ParameterName=work_mem,ParameterValue=16384,ApplyMethod=immediate" \
  --region "$REGION"
```
