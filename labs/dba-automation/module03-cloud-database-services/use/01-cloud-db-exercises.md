# USE: Cloud Database Exercises

**Module 03 - Cloud Database Services**
**Prerequisites:** Completed BUILD 01 through BUILD 04

Each exercise builds on the previous one. Complete them in order.

---

## Exercise 1: Provision and Connect

**Objective:** Create an RDS PostgreSQL instance from scratch using the CLI, connect with psql, and load sample data.

**Tasks:**

1. Create a security group allowing PostgreSQL access from your IP
2. Create a DB subnet group using your default VPC subnets
3. Create an RDS PostgreSQL 16 instance:
   - Instance class: `db.t3.micro`
   - Storage: 20 GB gp3
   - No Multi-AZ (save cost for this exercise)
   - Backup retention: 7 days
   - Publicly accessible: yes
4. Wait for the instance to become available
5. Connect with psql and run `SELECT version();`
6. Create a database called `exercisedb`
7. Create a `customers` table with: id (serial PK), name (text), email (text), created_at (timestamptz default now())
8. Insert 50,000 rows using `generate_series`
9. Run `EXPLAIN ANALYZE` on a query that filters by email
10. Create an index on email and re-run the EXPLAIN to compare

**Verification:**

```sql
SELECT count(*) FROM customers;
-- Should return 50000

SELECT indexname FROM pg_indexes WHERE tablename = 'customers';
-- Should show the email index
```

**Cleanup:** Keep this instance running for the next exercises.

---

## Exercise 2: High Availability

**Objective:** Enable Multi-AZ on your instance, trigger a failover, and measure the downtime.

**Tasks:**

1. Before enabling Multi-AZ, note the current Availability Zone:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier YOUR_INSTANCE \
     --query "DBInstances[0].AvailabilityZone"
   ```

2. Enable Multi-AZ:
   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier YOUR_INSTANCE \
     --multi-az \
     --apply-immediately
   ```

3. Wait for the modification to complete (10-15 minutes)

4. Start a connection loop to measure downtime. In one terminal, run:
   ```bash
   while true; do
     psql -h YOUR_ENDPOINT -U labadmin -d exercisedb \
       -c "SELECT now(), inet_server_addr();" 2>&1 | head -3
     sleep 1
   done
   ```

5. In another terminal, trigger a failover:
   ```bash
   aws rds reboot-db-instance \
     --db-instance-identifier YOUR_INSTANCE \
     --force-failover
   ```

6. Watch the connection loop. Note:
   - When connections start failing
   - When connections resume
   - Total downtime in seconds

7. After failover, check the new Availability Zone:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier YOUR_INSTANCE \
     --query "DBInstances[0].AvailabilityZone"
   ```

**Deliverable:** Record the failover downtime in seconds. Compare to the documented 60-120 seconds.

---

## Exercise 3: Read Replica

**Objective:** Create a read replica, route read queries to it, and observe replication lag.

**Tasks:**

1. Create a read replica:
   ```bash
   aws rds create-db-instance-read-replica \
     --db-instance-identifier YOUR_INSTANCE-replica \
     --source-db-instance-identifier YOUR_INSTANCE \
     --db-instance-class db.t3.micro
   ```

2. Wait for the replica to become available

3. Get the replica endpoint and connect with psql

4. Verify data is replicated:
   ```sql
   SELECT count(*) FROM customers;
   ```

5. Test that the replica is read-only:
   ```sql
   INSERT INTO customers (name, email) VALUES ('test', 'test@test.com');
   -- This should fail with: ERROR: cannot execute INSERT in a read-only transaction
   ```

6. Generate write load on the primary:
   ```sql
   -- On PRIMARY connection:
   INSERT INTO customers (name, email)
   SELECT 'Bulk_' || g, 'bulk' || g || '@test.com'
   FROM generate_series(1, 100000) g;
   ```

7. Measure replication lag:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/RDS \
     --metric-name ReplicaLag \
     --dimensions Name=DBInstanceIdentifier,Value=YOUR_INSTANCE-replica \
     --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 60 \
     --statistics Average Maximum
   ```

8. Verify the new rows appear on the replica:
   ```sql
   -- On REPLICA connection:
   SELECT count(*) FROM customers;
   -- Should be 150000 (50000 original + 100000 new)
   ```

**Deliverable:** Record the maximum replication lag observed during the bulk insert.

---

## Exercise 4: Backup and Restore

**Objective:** Take a snapshot, perform PITR to 5 minutes ago, and verify data integrity.

**Tasks:**

1. Insert a timestamp marker into your database (on the primary):
   ```sql
   CREATE TABLE backup_markers (
       marker_name TEXT PRIMARY KEY,
       created_at TIMESTAMPTZ DEFAULT now()
   );
   INSERT INTO backup_markers VALUES ('before_delete', now());
   SELECT * FROM backup_markers;
   ```

2. Wait 5 minutes (this gives WAL time to archive for PITR)

3. Simulate a disaster - delete all customers:
   ```sql
   DELETE FROM customers;
   SELECT count(*) FROM customers;
   -- Should be 0
   ```

4. Record the timestamp of the delete:
   ```sql
   INSERT INTO backup_markers VALUES ('after_delete', now());
   SELECT * FROM backup_markers;
   ```

5. Perform a PITR to before the delete:
   ```bash
   # Use a time between the two markers
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier YOUR_INSTANCE \
     --target-db-instance-identifier YOUR_INSTANCE-pitr \
     --restore-time "TIMESTAMP_BEFORE_DELETE" \
     --db-instance-class db.t3.micro \
     --publicly-accessible
   ```

6. Wait for the restored instance to become available

7. Connect to the restored instance and verify:
   ```sql
   SELECT count(*) FROM customers;
   -- Should be 150000 (data is back)

   SELECT * FROM backup_markers;
   -- Should show 'before_delete' but NOT 'after_delete'
   ```

8. Clean up the restored instance:
   ```bash
   aws rds delete-db-instance \
     --db-instance-identifier YOUR_INSTANCE-pitr \
     --skip-final-snapshot
   ```

**Deliverable:** Confirm the customer count on the restored instance matches pre-delete count.

---

## Exercise 5: Cost Audit

**Objective:** Analyze the running costs of your lab instances and recommend savings.

**Tasks:**

1. List all running RDS instances and their specs:
   ```bash
   aws rds describe-db-instances \
     --query "DBInstances[*].{ID:DBInstanceIdentifier,Class:DBInstanceClass,Storage:AllocatedStorage,MultiAZ:MultiAZ,Engine:Engine}" \
     --output table
   ```

2. Check CPU utilization for the last 24 hours:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/RDS \
     --metric-name CPUUtilization \
     --dimensions Name=DBInstanceIdentifier,Value=YOUR_INSTANCE \
     --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 3600 \
     --statistics Average Maximum
   ```

3. Check memory utilization:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/RDS \
     --metric-name FreeableMemory \
     --dimensions Name=DBInstanceIdentifier,Value=YOUR_INSTANCE \
     --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 3600 \
     --statistics Average
   ```

4. Calculate current monthly cost estimate:
   - Instance cost: hourly_rate x 730
   - Storage cost: allocated_GB x $0.08
   - Multi-AZ: doubles instance cost (if enabled)
   - Read replica: adds another instance cost

5. Write a cost recommendation report that includes:
   - Current monthly cost estimate
   - CPU and memory utilization summary
   - Is the instance right-sized? (under-utilized, good, or under-provisioned)
   - Would Reserved Instances save money?
   - Any resources that can be deleted?

**Deliverable:** A one-page cost analysis with a recommendation for production sizing.

---

## Final Cleanup

Delete all lab resources to stop billing:

```bash
# Delete read replica
aws rds delete-db-instance \
  --db-instance-identifier YOUR_INSTANCE-replica \
  --skip-final-snapshot

# Wait for replica deletion
aws rds wait db-instance-deleted --db-instance-identifier YOUR_INSTANCE-replica

# Delete primary
aws rds delete-db-instance \
  --db-instance-identifier YOUR_INSTANCE \
  --skip-final-snapshot

# Delete subnet group (after instances are gone)
aws rds delete-db-subnet-group --db-subnet-group-name lab-subnet-group

# Delete security group
aws ec2 delete-security-group --group-name rds-postgres-lab
```
