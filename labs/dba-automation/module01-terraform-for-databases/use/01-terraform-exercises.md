# USE: Terraform Exercises

**Module:** DBA Automation & DevOps - Module 01
**Time Estimate:** 2-3 hours (all 5 exercises)
**Prerequisites:** BUILD 01-04 completed

**COST WARNING:** Exercises 1-5 create AWS resources that cost money. Always `terraform destroy` after each exercise. Do not leave resources running.

---

## Exercise 1: Single RDS Instance with Custom Parameter Group

**Goal:** Provision a PostgreSQL RDS instance with a customized parameter group that reflects real DBA requirements.

### Requirements

Create a Terraform project that provisions:

1. A VPC with 2 subnets in different AZs
2. A security group allowing PostgreSQL access from your IP
3. A custom parameter group with these settings:
   - `shared_preload_libraries` = `pg_stat_statements`
   - `log_statement` = `ddl` (log only DDL statements)
   - `log_min_duration_statement` = `5000` (log queries over 5 seconds)
   - `idle_in_transaction_session_timeout` = `300000` (kill idle-in-transaction after 5 min)
   - `statement_timeout` = `60000` (60 second query timeout)
4. An RDS PostgreSQL 16 instance (db.t3.micro) using that parameter group
5. Outputs showing the connection command and parameter group name

### Verification

After `terraform apply`:

```bash
psql -h <your-endpoint> -U dbadmin -d labdb
```

```sql
SHOW log_statement;
-- Expected: ddl

SHOW log_min_duration_statement;
-- Expected: 5s

SHOW idle_in_transaction_session_timeout;
-- Expected: 5min

SHOW statement_timeout;
-- Expected: 1min
```

**When done:** `terraform destroy`

---

## Exercise 2: Multi-AZ High Availability

**Goal:** Take your Exercise 1 configuration and enable Multi-AZ for high availability.

### Requirements

Modify your Exercise 1 project to:

1. Add a `multi_az` variable (boolean, default `false`)
2. Set `multi_az = true` in your tfvars
3. Add a `storage_encrypted = true` argument (always encrypt in HA setups)
4. Add a `performance_insights_enabled = true` argument
5. Change `backup_retention_period` to `14` (two weeks for HA)
6. Add an output that shows whether Multi-AZ is enabled
7. Add an output showing the AZ the instance is in

### Verification

After `terraform apply`:

```bash
terraform output multi_az_enabled
# Expected: true

terraform output availability_zone
# Expected: something like us-east-1a
```

In the AWS Console, navigate to RDS and verify the instance shows "Multi-AZ: Yes".

**When done:** `terraform destroy`

---

## Exercise 3: Read Replica

**Goal:** Add a read replica to your RDS instance.

### Requirements

Extend your Exercise 2 project to:

1. Create an `aws_db_instance` resource for the read replica
2. The replica must reference the primary's `identifier` via the `replicate_source_db` argument
3. The replica should:
   - Use the same instance class as the primary
   - Be in a different AZ than the primary
   - Have its own parameter group with `hot_standby_feedback = on`
   - NOT specify `db_name`, `username`, or `password` (these come from the primary)
4. Add outputs for:
   - Primary endpoint
   - Replica endpoint
   - A psql command for the replica

### Verification

Connect to the primary:

```sql
SELECT pg_is_in_recovery();
-- Expected: f (false - this is the primary)
```

Connect to the replica:

```sql
SELECT pg_is_in_recovery();
-- Expected: t (true - this is a replica)
```

Create a table on the primary and verify it appears on the replica:

```sql
-- On primary:
CREATE TABLE exercise3_test (id serial, msg text);
INSERT INTO exercise3_test (msg) VALUES ('replication works');

-- On replica (after a few seconds):
SELECT * FROM exercise3_test;
-- Expected: 1 row
```

**When done:** `terraform destroy`

---

## Exercise 4: Module Creation

**Goal:** Extract your RDS configuration into a reusable Terraform module.

### Requirements

1. Create a module at `modules/postgresql-rds/` with:
   - `variables.tf` - Accept at minimum: project_name, environment, db_name, db_username, db_password, instance_class, allowed_cidrs, multi_az, engine_version
   - `main.tf` - VPC, subnets, security group, parameter group, RDS instance
   - `outputs.tf` - endpoint, hostname, port, database_name, username, vpc_id
2. Call the module from a root `main.tf` to create a dev database
3. Add a commented-out block showing how to create a staging database with different parameters
4. The module should apply these DBA-standard parameters automatically:
   - `log_connections = 1`
   - `log_disconnections = 1`
   - `shared_preload_libraries = pg_stat_statements`
5. The module should accept additional custom parameters via a `map(string)` variable

### Verification

```bash
terraform init
# Should show: Initializing modules... - dev_database in modules/postgresql-rds

terraform plan
# All resources should be prefixed with module.dev_database.
```

If you apply (costs money):

```bash
terraform output dev_endpoint
# Should show the RDS endpoint

psql -h <endpoint> -U dbadmin -d devdb -c "SHOW log_connections;"
# Expected: on
```

**When done:** `terraform destroy`

---

## Exercise 5: Full Aurora Cluster

**Goal:** Provision a complete Aurora PostgreSQL cluster with a writer and 2 readers.

### Requirements

1. Create an Aurora PostgreSQL 16 cluster with:
   - 1 writer instance (db.t3.medium - Aurora minimum)
   - 2 reader instances created using `count`
   - Cluster parameter group with `shared_preload_libraries = pg_stat_statements`
   - Instance parameter group with `log_statement = all`
   - Storage encryption enabled
   - 7-day backup retention
2. Use a `reader_count` variable to control the number of readers
3. Add outputs for:
   - Cluster (writer) endpoint
   - Reader (load-balanced) endpoint
   - List of all individual instance endpoints
   - Total instance count
   - A psql command for the writer
   - A psql command for the reader endpoint

### Verification

Connect to the writer endpoint:

```sql
SELECT pg_is_in_recovery();
-- Expected: f

CREATE TABLE aurora_test (id serial, msg text);
INSERT INTO aurora_test (msg) VALUES ('aurora cluster works');
```

Connect to the reader endpoint:

```sql
SELECT pg_is_in_recovery();
-- Expected: t

SELECT * FROM aurora_test;
-- Expected: 1 row (replicated from writer)

INSERT INTO aurora_test (msg) VALUES ('this should fail');
-- Expected: ERROR: cannot execute INSERT in a read-only transaction
```

### Bonus Challenge

After the cluster is running, modify `reader_count` from 2 to 3 and run `terraform apply`. Verify that Terraform adds one reader without touching the existing writer or readers.

```bash
# Edit terraform.tfvars: reader_count = 3
terraform plan
# Expected: 1 to add, 0 to change, 0 to destroy
```

**When done:** `terraform destroy`

---

## Scoring Guide

| Exercise | Difficulty | Key Skills Tested |
|---|---|---|
| 1 - Single RDS | Beginner | Basic resource creation, parameter groups |
| 2 - Multi-AZ | Beginner | Modifying existing config, boolean variables |
| 3 - Read Replica | Intermediate | Resource dependencies, `replicate_source_db` |
| 4 - Module Creation | Intermediate | Module structure, inputs/outputs, reusability |
| 5 - Aurora Cluster | Advanced | Cluster resources, `count`, multiple endpoints |

---

## Common Issues and Solutions

| Issue | Cause | Fix |
|---|---|---|
| "Error: creating DB Instance: DBInstanceAlreadyExists" | Previous destroy did not complete | Check AWS Console, delete manually if needed |
| Security group timeout | Your IP changed (VPN, coffee shop) | Re-run `curl checkip.amazonaws.com` and update tfvars |
| "Error: creating DB Instance: InsufficientDBInstanceCapacity" | Instance type not available in AZ | Try a different AZ or instance type |
| Replica creation fails | Primary not fully available yet | Wait 2-3 minutes and `terraform apply` again |
| Aurora instance class error | db.t3.micro is too small | Aurora minimum is db.t3.medium |
| Parameter group changes not visible | Some params need reboot | Reboot via Console or add `apply_method = "pending-reboot"` |
