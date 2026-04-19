# SURVIVE 07 - Multi-AZ Failover

## Symptom

A Multi-AZ failover has occurred. The application experienced a brief outage (typically 60-120 seconds). You need to verify the instance is running on the new AZ, check that the endpoint still works, and confirm no data was lost.

---

## Diagnosis

### Step 1 - Check instance status and AZ

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone,SecondaryAZ:SecondaryAvailabilityZone,MultiAZ:MultiAZ}" \
    --output table
```

The `AvailabilityZone` should be different from the pre-failover AZ. The instance may still show `rebooting` or `modifying` during the failover.

### Step 2 - Wait for the instance if still transitioning

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

### Step 3 - Check failover events

```bash
aws rds describe-events \
    --source-identifier suta-pg-lab \
    --source-type db-instance \
    --duration 30 \
    --query "Events[*].{Time:Date,Message:Message}" \
    --output table
```

Look for messages like:
- "Multi-AZ instance failover started"
- "Multi-AZ instance failover completed"
- "DB instance restarted"

Expected output (yours will differ):

```
-------------------------------------------------------------------
|                        DescribeEvents                           |
+----------------------------+------------------------------------+
|           Time             |              Message               |
+----------------------------+------------------------------------+
| 2024-01-15T15:00:00+00:00 | Multi-AZ instance failover started |
| 2024-01-15T15:01:30+00:00 | Multi-AZ instance failover completed|
| 2024-01-15T15:01:45+00:00 | DB instance restarted              |
+----------------------------+------------------------------------+
```

### Step 4 - Verify the AZ changed

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].AvailabilityZone" \
    --output text
```

This should return a different AZ than where the instance was before the failover.

---

## Fix

The failover itself is automatic - there is nothing to "fix". Your job is to verify everything is working correctly.

### Step 5 - Verify the endpoint still resolves

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
nslookup "${RDS_ENDPOINT}"
```

The endpoint DNS name stays the same after failover, but it resolves to a new IP address (the standby's IP).

### Step 6 - Test database connectivity

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432 --connect-timeout=10
```

Verify the connection:

```sql
SELECT inet_server_addr() AS server_ip, now() AS current_time;
```

The server IP will be different from before the failover. The endpoint is the same, but it now points to the former standby.

Exit psql:

```sql
\q
```

### Step 7 - Verify data integrity

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Check that your tables exist and have the correct data:

```sql
SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
```

If you had test data:

```sql
SELECT count(*) FROM recovery_test;
```

Multi-AZ uses synchronous replication, so no data should be lost during failover.

Exit psql:

```sql
\q
```

### Step 8 - Check application-level impact

If you have CloudWatch alarms, check if they triggered:

```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix suta-rds \
    --query "MetricAlarms[*].{Name:AlarmName,State:StateValue,LastUpdated:StateUpdatedTimestamp}" \
    --output table
```

Check the DatabaseConnections metric to see the reconnection pattern:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Maximum \
    --query "sort_by(Datapoints, &Timestamp)[-10:].{Time:Timestamp,Connections:Maximum}" \
    --output table
```

You should see connections drop to 0 during failover and recover afterward.

---

## Verification

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone,MultiAZ:MultiAZ}" \
    --output table
```

All three should look correct: `available`, a different AZ than before, and `True` for MultiAZ.

Test a write to confirm full functionality:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432 -c "CREATE TABLE failover_test (id int); DROP TABLE failover_test; SELECT 'writes_work' AS status;"
```

Expected output:

```
   status
-----------
 writes_work
(1 row)
```

---

## Discussion Questions

1. How long does a typical Multi-AZ failover take? What factors affect the duration?
2. Does the endpoint change during failover? Does the IP change?
3. How should applications handle the brief outage during failover?
4. What is the difference between Multi-AZ failover and read replica promotion?
