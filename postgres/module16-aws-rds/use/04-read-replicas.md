# USE 04 - Read Replicas

## Objective

Create a read replica, verify replication lag, promote the replica to a standalone instance, and understand connection routing between primary and replica.

---

## Exercise

You will:
1. Create a read replica of your RDS instance
2. Verify data replicates from primary to replica
3. Measure replication lag
4. Promote the replica to standalone
5. Verify the promoted instance accepts writes

---

## Step-by-Step

### 1. Create a read replica

```bash
aws rds create-db-instance-read-replica \
    --db-instance-identifier suta-pg-lab-replica \
    --source-db-instance-identifier suta-pg-lab \
    --db-instance-class db.t3.medium \
    --no-publicly-accessible \
    --tags Key=Environment,Value=lab Key=Role,Value=replica
```

Flag breakdown:
- `--db-instance-identifier` - name for the new replica
- `--source-db-instance-identifier` - the primary instance to replicate from
- `--db-instance-class` - can be different from the primary (useful for scaling reads)
- The replica inherits the VPC, subnet group, and storage settings from the primary

Wait for it:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-replica
```

Expected time: 10-20 minutes.

### 2. Get both endpoints

```bash
PRIMARY_EP=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
REPLICA_EP=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab-replica --query "DBInstances[0].Endpoint.Address" --output text)
```

### 3. Write data on the primary

```bash
psql -h "${PRIMARY_EP}" -U sutaadmin -d postgres -p 5432
```

```sql
CREATE TABLE replica_test (
    id serial PRIMARY KEY,
    source text,
    created_at timestamptz DEFAULT now()
);
```

```sql
INSERT INTO replica_test (source) VALUES ('primary-write-1');
```

```sql
INSERT INTO replica_test (source) VALUES ('primary-write-2');
```

```sql
INSERT INTO replica_test (source) VALUES ('primary-write-3');
```

```sql
SELECT * FROM replica_test;
```

Expected output:

```
 id |     source      |          created_at
----+-----------------+-------------------------------
  1 | primary-write-1 | 2024-01-15 14:00:00.123456+00
  2 | primary-write-2 | 2024-01-15 14:00:01.234567+00
  3 | primary-write-3 | 2024-01-15 14:00:02.345678+00
(3 rows)
```

Exit psql:

```sql
\q
```

### 4. Verify data on the replica

```bash
psql -h "${REPLICA_EP}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM replica_test;
```

You should see all 3 rows. Replication typically takes under 1 second.

Try to write on the replica:

```sql
INSERT INTO replica_test (source) VALUES ('replica-write');
```

Expected output:

```
ERROR:  cannot execute INSERT in a read-only transaction
```

The replica is read-only. This confirms replication is working correctly.

Exit psql:

```sql
\q
```

### 5. Check replication lag

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab-replica \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average Maximum \
    --query "sort_by(Datapoints, &Timestamp)[-3:].{Time:Timestamp,AvgLag:Average,MaxLag:Maximum}" \
    --output table
```

The `ReplicaLag` metric is in seconds. This shows the last 3 data points.

Expected output (yours will differ):

```
----------------------------------------------------------
|               GetMetricStatistics                      |
+--------+----------------------------+-----------------+
| AvgLag |           Time             |     MaxLag      |
+--------+----------------------------+-----------------+
|  0.5   | 2024-01-15T14:02:00+00:00  |  1.2            |
|  0.3   | 2024-01-15T14:03:00+00:00  |  0.8            |
|  0.2   | 2024-01-15T14:04:00+00:00  |  0.5            |
+--------+----------------------------+-----------------+
```

Under 5 seconds is healthy. Under 1 second is excellent.

### 6. Promote the replica to standalone

Promotion makes the replica an independent read-write instance. It breaks the replication link permanently.

```bash
aws rds promote-read-replica \
    --db-instance-identifier suta-pg-lab-replica
```

This starts the promotion process. The replica will briefly restart and become a standalone instance.

Wait for it:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-replica
```

### 7. Verify the promoted instance accepts writes

```bash
psql -h "${REPLICA_EP}" -U sutaadmin -d postgres -p 5432
```

```sql
INSERT INTO replica_test (source) VALUES ('after-promotion');
```

Expected output:

```
INSERT 0 1
```

The INSERT succeeds because this is now a standalone instance, not a replica.

```sql
SELECT * FROM replica_test ORDER BY id;
```

Expected output:

```
 id |      source      |          created_at
----+------------------+-------------------------------
  1 | primary-write-1  | 2024-01-15 14:00:00.123456+00
  2 | primary-write-2  | 2024-01-15 14:00:01.234567+00
  3 | primary-write-3  | 2024-01-15 14:00:02.345678+00
  4 | after-promotion  | 2024-01-15 14:15:00.456789+00
(4 rows)
```

Verify replication is broken - write on the original primary:

Exit psql:

```sql
\q
```

```bash
psql -h "${PRIMARY_EP}" -U sutaadmin -d postgres -p 5432
```

```sql
INSERT INTO replica_test (source) VALUES ('after-promotion-primary');
```

```sql
SELECT * FROM replica_test ORDER BY id;
```

Expected output:

```
 id |         source          |          created_at
----+-------------------------+-------------------------------
  1 | primary-write-1         | 2024-01-15 14:00:00.123456+00
  2 | primary-write-2         | 2024-01-15 14:00:01.234567+00
  3 | primary-write-3         | 2024-01-15 14:00:02.345678+00
  5 | after-promotion-primary | 2024-01-15 14:16:00.567890+00
(4 rows)
```

The promoted instance does not have `after-promotion-primary`, and the primary does not have `after-promotion`. They are now independent.

Exit psql:

```sql
\q
```

### 8. Connection routing pattern

In a real application, you would use two connection strings:

- **Writes**: Always connect to the primary endpoint
- **Reads**: Connect to the replica endpoint for read-heavy queries

Example application logic (pseudocode):
```
primary_conn = connect(PRIMARY_ENDPOINT)
replica_conn = connect(REPLICA_ENDPOINT)

# All writes go to primary
primary_conn.execute("INSERT INTO orders ...")

# Read queries go to replica
replica_conn.execute("SELECT * FROM orders WHERE ...")
```

---

## Clean Up

Delete the promoted instance:

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-pg-lab-replica \
    --skip-final-snapshot \
    --delete-automated-backups
```

---

## Key Takeaway

Read replicas use asynchronous streaming replication. Data is eventually consistent (usually within 1 second). Promotion is a one-way operation - you cannot turn a promoted instance back into a replica. For cross-region disaster recovery, create a cross-region replica using `--source-db-instance-identifier` with the source instance ARN and `--region` set to the target region.
