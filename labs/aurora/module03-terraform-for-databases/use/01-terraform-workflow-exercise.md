# USE 01: Terraform Workflow Exercise

**Module:** DevOps DBA Training Track - Module 03
**Time Estimate:** 45-60 minutes
**Prerequisites:** BUILD 01-06 completed

**COST WARNING:** This exercise creates AWS resources that cost money. Always run `terraform destroy` when you finish. Do not leave resources running.

---

## The Scenario

Your team has a new application called "OrderTracker" that needs an Aurora PostgreSQL cluster. The application architect has provided the following requirements:

```
Application: OrderTracker
Environment: dev
Database Engine: Aurora PostgreSQL 16.4
Writer: 1 instance (db.t3.medium)
Readers: 1 instance (db.t3.medium)
Initial Database: ordertracker
Master User: ot_admin
Backup Retention: 7 days

Required PostgreSQL Parameters:
  - shared_preload_libraries = pg_stat_statements (cluster level)
  - log_connections = 1 (cluster level)
  - log_disconnections = 1 (cluster level)
  - log_statement = ddl (instance level)
  - log_min_duration_statement = 5000 (instance level)
  - idle_in_transaction_session_timeout = 300000 (instance level)

Network Access:
  - Your IP address (for DBA access)
  - 10.0.0.0/8 (for application servers)

Tags:
  - Application = OrderTracker
  - Environment = dev
  - Team = backend
  - ManagedBy = terraform
```

---

## Your Task

Write a complete Terraform project from scratch that provisions this architecture. Use separate files for organization:

| File | Contents |
|---|---|
| `providers.tf` | AWS provider with version constraint |
| `variables.tf` | All input variables with descriptions, types, and defaults |
| `vpc.tf` | VPC, subnets (3 AZs), internet gateway, route table, subnet group |
| `security.tf` | Security group with the two ingress rules |
| `aurora.tf` | Cluster parameter group, instance parameter group, cluster, writer, reader |
| `outputs.tf` | Cluster endpoint, reader endpoint, writer psql command, reader psql command |
| `terraform.tfvars` | Variable values |

---

## Requirements Checklist

Before running `terraform plan`, verify your configuration meets all requirements:

- [ ] Provider version pinned to `~> 5.0`
- [ ] All passwords marked as `sensitive = true`
- [ ] VPC with 3 subnets across 3 AZs
- [ ] Security group allows port 5432 from your IP and 10.0.0.0/8
- [ ] Cluster parameter group has `shared_preload_libraries`, `log_connections`, `log_disconnections`
- [ ] Instance parameter group has `log_statement`, `log_min_duration_statement`, `idle_in_transaction_session_timeout`
- [ ] Aurora cluster uses `aurora-postgresql` engine, version 16.4
- [ ] `storage_encrypted = true`
- [ ] `skip_final_snapshot = true` (lab only)
- [ ] `deletion_protection = false` (lab only)
- [ ] Writer instance created with explicit identifier
- [ ] Reader instance created with explicit identifier
- [ ] All resources tagged with Application, Environment, Team, ManagedBy
- [ ] Outputs include psql connection commands

---

## Verification Steps

After `terraform apply` succeeds:

### 1. Check the plan summary

```bash
terraform plan
```

Expected: "No changes. Your infrastructure matches the configuration."

### 2. Connect to the writer

```bash
psql -h <cluster-endpoint> -p 5432 -U ot_admin -d ordertracker
```

### 3. Verify parameters

```sql
SHOW shared_preload_libraries;
```

Expected: `pg_stat_statements`

```sql
SHOW log_statement;
```

Expected: `ddl`

```sql
SHOW log_min_duration_statement;
```

Expected: `5s`

```sql
SHOW idle_in_transaction_session_timeout;
```

Expected: `5min`

### 4. Verify writer vs reader

On the writer:

```sql
SELECT pg_is_in_recovery();
```

Expected: `f`

On the reader:

```sql
SELECT pg_is_in_recovery();
```

Expected: `t`

### 5. Test replication

On the writer:

```sql
CREATE TABLE ot_test (id serial, msg text);
INSERT INTO ot_test (msg) VALUES ('replication works');
```

On the reader (after a few seconds):

```sql
SELECT * FROM ot_test;
```

Expected: 1 row

---

## When Done

```bash
terraform destroy
```

Type `yes` when prompted. Wait for all resources to be destroyed.

---

## Scoring Guide

| Criterion | Points |
|---|---|
| All files properly organized | 10 |
| Variables have descriptions and types | 10 |
| Password marked sensitive | 5 |
| VPC with 3 AZs | 10 |
| Security group correct | 10 |
| Cluster parameter group correct | 10 |
| Instance parameter group correct | 10 |
| Aurora cluster with all settings | 15 |
| Writer and reader instances | 10 |
| Outputs with psql commands | 5 |
| All resources tagged | 5 |
| **Total** | **100** |

---

## Hints (Try Without These First)

<details>
<summary>Hint 1: Cluster parameter group family</summary>

The parameter group family for Aurora PostgreSQL 16 is `aurora-postgresql16`. This is different from regular RDS PostgreSQL which uses `postgres16`.

</details>

<details>
<summary>Hint 2: Instance parameter group family</summary>

Aurora instance parameter groups also use `aurora-postgresql16` as the family - not `postgres16`.

</details>

<details>
<summary>Hint 3: Cluster instance engine</summary>

Aurora cluster instances must reference the cluster's engine and engine_version. Use `aws_rds_cluster.main.engine` and `aws_rds_cluster.main.engine_version` instead of hardcoding.

</details>

<details>
<summary>Hint 4: apply_method for shared_preload_libraries</summary>

The `shared_preload_libraries` parameter requires a reboot. Add `apply_method = "pending-reboot"` to that parameter block.

</details>
