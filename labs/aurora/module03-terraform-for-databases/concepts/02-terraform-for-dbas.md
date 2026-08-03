# Concepts 02: Terraform for DBAs - DBA-Specific Patterns

**Module:** DevOps DBA Training Track - Module 03
**Reading Time:** 15-20 minutes

---

## Why DBAs Need Terraform-Specific Knowledge

General Terraform tutorials teach you to create EC2 instances and S3 buckets. As a DBA, you manage Aurora clusters, parameter groups, security groups, subnet groups, and read replicas. These resources have unique behaviors that generic tutorials skip.

This reference covers the patterns and pitfalls specific to managing databases with Terraform.

---

## Parameter Groups as Code (postgresql.conf in Git)

In the on-prem world, you SSH into a server, edit `postgresql.conf`, and reload. With Aurora, you manage parameters through parameter groups. With Terraform, those parameter groups become code - versioned, reviewed, and repeatable.

### Cluster vs Instance Parameter Groups

Aurora has two levels of parameter groups. This trips up many DBAs on their first Aurora Terraform project.

| Parameter Group Type | Applies To | Example Parameters |
|---|---|---|
| Cluster parameter group | Entire cluster (shared settings) | `shared_preload_libraries`, `log_connections`, replication settings |
| Instance parameter group | Individual instances | `log_statement`, `log_min_duration_statement`, `work_mem` |

```hcl
# Cluster-level parameters (like global postgresql.conf)
resource "aws_rds_cluster_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "prod-aurora-cluster-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
}

# Instance-level parameters (like per-session or instance-specific settings)
resource "aws_db_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "prod-aurora-instance-params"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}
```

### apply_method - The Reboot Question

Some PostgreSQL parameters require a restart. In Terraform, you signal this with `apply_method`:

| apply_method | Meaning | DBA Analogy |
|---|---|---|
| `"immediate"` | Apply now without restart (default) | `ALTER SYSTEM SET` + `pg_reload_conf()` |
| `"pending-reboot"` | Apply on next reboot/failover | Parameters that need `pg_ctl restart` |

If you set a `pending-reboot` parameter, Terraform marks the apply as successful, but the parameter does not take effect until the instance is rebooted. This catches people off guard - always check whether your parameter change actually applied.

---

## Security Groups as Code (pg_hba.conf in Git)

Security groups control network access to your Aurora cluster. They are the cloud equivalent of `pg_hba.conf` - they determine which IP addresses can connect to your database on which ports.

```hcl
resource "aws_security_group" "aurora" {
  name        = "prod-aurora-sg"
  description = "Controls access to production Aurora cluster"
  vpc_id      = aws_vpc.main.id

  # Each ingress rule is like a pg_hba.conf line
  # pg_hba.conf: host all dbadmin 10.0.0.0/8 scram-sha-256
  ingress {
    description = "App servers"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # pg_hba.conf: host all dbadmin 172.16.5.10/32 scram-sha-256
  ingress {
    description = "DBA workstation"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.16.5.10/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Key difference from pg_hba.conf:** Security groups operate at the network layer (TCP/IP). They cannot distinguish between database users or databases - they only know about IP addresses and ports. You still need proper database-level authentication for user access control.

---

## Subnet Groups (Network Placement)

Aurora needs to know which subnets (network segments) it can use. A DB subnet group specifies this. It must include subnets in at least two Availability Zones for failover.

```hcl
resource "aws_db_subnet_group" "aurora" {
  name       = "prod-aurora-subnets"
  subnet_ids = [
    aws_subnet.db_a.id,
    aws_subnet.db_b.id,
    aws_subnet.db_c.id,
  ]
}
```

**DBA analogy:** This is like telling AWS "these are the approved network segments where you can place database servers." In on-prem terms, it is choosing which server racks in which data halls are designated for database workloads.

---

## terraform plan as EXPLAIN for Infrastructure

`terraform plan` is the command DBAs love most. It shows exactly what Terraform will do without doing it.

```
# terraform plan output symbols:
+   Create (like INSERT)
~   Modify in-place (like UPDATE)
-   Destroy (like DELETE)
-/+ Destroy and recreate (like DROP + CREATE)
<=  Read data source (like SELECT)
```

### Reading a Plan Like a DBA

When you see a plan, read it the same way you read a query execution plan:

```
# aws_rds_cluster.main will be updated in-place
~ resource "aws_rds_cluster" "main" {
    ~ engine_version = "16.3" -> "16.4"    # Minor version upgrade
      # (15 unchanged attributes hidden)
  }
```

This tells you:
- The cluster will be modified in place (not destroyed and recreated)
- Only the engine version is changing
- 15 other attributes remain the same

**Watch for `-/+` (destroy and recreate).** This is the dangerous one. Some changes force Terraform to destroy the old resource and create a new one. For databases, this means data loss unless you have backups.

Changes that typically force recreation:
- Changing `cluster_identifier`
- Changing `engine` (e.g., `aurora-postgresql` to `aurora-mysql`)
- Changing `db_subnet_group_name` in some cases

Changes that are safe in-place updates:
- Changing `engine_version` (minor version)
- Changing `instance_class` (vertical scaling)
- Changing `backup_retention_period`
- Adding/removing `tags`

**Always review `terraform plan` before `terraform apply`.** This is the same discipline as running `EXPLAIN` before executing an expensive query.

---

## prevent_destroy - The Production Safety Net

In PostgreSQL, you might revoke DROP privileges to prevent accidental table deletion. Terraform has a similar mechanism called `prevent_destroy`.

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier = "prod-aurora"
  engine             = "aurora-postgresql"
  # ... other settings ...

  lifecycle {
    prevent_destroy = true
  }
}
```

With `prevent_destroy = true`, if anyone runs `terraform destroy` or makes a change that would force recreation, Terraform errors out:

```
Error: Instance cannot be destroyed

  resource "aws_rds_cluster" "production"

  This resource has lifecycle prevent_destroy set, which
  prevents it from being destroyed.
```

### Two Layers of Protection

For production Aurora clusters, use both Terraform-level and AWS-level protection:

| Layer | Mechanism | What It Prevents |
|---|---|---|
| Terraform | `lifecycle { prevent_destroy = true }` | `terraform destroy` from removing the resource |
| AWS | `deletion_protection = true` | AWS Console or API from deleting the resource |

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier  = "prod-aurora"
  deletion_protection = true  # AWS-level protection

  lifecycle {
    prevent_destroy = true    # Terraform-level protection
  }
}
```

To actually destroy a production cluster with both protections, someone would need to:

1. Remove `prevent_destroy` from the `.tf` file (requires a code review)
2. Set `deletion_protection = false` in the `.tf` file
3. Run `terraform apply` to update the AWS setting
4. Run `terraform destroy`

That is four deliberate steps. This does not happen by accident.

---

## ignore_changes - When Reality Must Differ from Code

Sometimes AWS or an external process modifies a resource attribute, and you want Terraform to leave it alone. The `ignore_changes` lifecycle rule tells Terraform to skip specific attributes during planning.

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier = "prod-aurora"
  engine_version     = "16.4"
  master_password    = var.initial_password

  lifecycle {
    # Ignore password changes - managed by Secrets Manager rotation
    ignore_changes = [master_password]
  }
}
```

Common use cases for DBAs:

| Attribute to Ignore | Why |
|---|---|
| `master_password` | Password is rotated by Secrets Manager outside Terraform |
| `engine_version` | Minor version auto-upgrades happen outside Terraform |
| `tags` | Another system (cost allocation, compliance) adds tags |

**Use `ignore_changes` sparingly.** Every ignored attribute is an attribute that can drift without detection. It is like disabling a monitoring check - sometimes necessary, but always a risk.

---

## create_before_destroy - Blue-Green for Infrastructure

When Terraform needs to replace a resource (destroy old, create new), the default order is:

1. Destroy the old resource
2. Create the new resource

For parameter groups or security groups, this means a brief period where the Aurora cluster has no parameter group or no security group. The `create_before_destroy` lifecycle rule reverses the order:

1. Create the new resource
2. Update references to point to the new resource
3. Destroy the old resource

```hcl
resource "aws_db_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "prod-instance-params-v2"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

**DBA analogy:** This is like a blue-green deployment for configuration. The new parameter group exists and is tested before the old one is removed.

---

## Data Sources - Querying Existing Infrastructure

Data sources let you read information about resources that already exist in AWS - resources that Terraform did not create and does not manage. They are read-only `SELECT` statements against the AWS API.

```hcl
# Look up an existing VPC by tag (like SELECT * FROM vpcs WHERE name = 'production')
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

# Use it when creating a security group
resource "aws_security_group" "aurora" {
  vpc_id = data.aws_vpc.existing.id
  # ...
}
```

Common data sources for DBAs:

| Data Source | What It Returns | Use Case |
|---|---|---|
| `aws_vpc` | VPC details | Place Aurora in existing VPC |
| `aws_subnets` | Subnet IDs | Build subnet group from existing subnets |
| `aws_security_group` | SG details | Reference app server SG for ingress rules |
| `aws_rds_engine_version` | Available engine versions | Validate version before deploying |
| `aws_caller_identity` | Current AWS account | Tag resources with account ID |
| `aws_region` | Current region | Use in resource naming |

Data sources never create, modify, or destroy anything. They are purely read operations.

---

## Terraform State Commands for DBAs

These commands are the DBA's toolkit for state management:

```
terraform state list                              List all managed resources
terraform state show aws_rds_cluster.main         Show details of one resource
terraform state rm aws_rds_cluster.main            Remove from state (does NOT delete in AWS)
terraform state mv aws_rds_cluster.old aws_rds_cluster.new   Rename in state
terraform import aws_rds_cluster.main cluster-id   Import existing resource into state
```

### When to Use Each

| Scenario | Command | DBA Analogy |
|---|---|---|
| Audit what Terraform manages | `terraform state list` | `\dt` in psql |
| Debug a specific resource | `terraform state show <resource>` | `\d+ tablename` |
| Resource deleted outside Terraform | `terraform state rm <resource>` | `DROP TABLE IF EXISTS` in catalog |
| Rename a resource in code | `terraform state mv <old> <new>` | `ALTER TABLE RENAME` |
| Bring existing infra under management | `terraform import <resource> <id>` | `pg_dump` to capture existing schema |

---

## Common Pitfalls for DBAs New to Terraform

### 1. Forgetting that destroy means destroy

`terraform destroy` deletes real resources. There is no "undo." For Aurora clusters with `skip_final_snapshot = true`, your data is gone permanently.

**Prevention:** Always set `skip_final_snapshot = false` and `deletion_protection = true` in production.

### 2. Hardcoding credentials

Never put passwords or access keys in `.tf` files. Use environment variables, AWS Secrets Manager, or `manage_master_user_password = true`.

### 3. Not reviewing the plan

Running `terraform apply -auto-approve` is like running `DELETE FROM` without a `WHERE` clause. Always review the plan.

### 4. Ignoring state drift

If someone changes a security group in the AWS Console, the next `terraform apply` will revert it. Either update your `.tf` code to match the change, or let Terraform revert it. Never leave state and reality out of sync.

### 5. Using count when for_each is better

`count` uses numeric indexes. Removing item 2 from a list of 5 renumbers everything and may destroy/recreate items 3-5. `for_each` uses keys, so removing one item only affects that item.

---

## Quick Reference - Aurora Terraform Resources

| Resource Type | Purpose | DBA Analogy |
|---|---|---|
| `aws_rds_cluster` | Aurora cluster (shared storage) | The database cluster |
| `aws_rds_cluster_instance` | Compute node (writer or reader) | Individual server in the cluster |
| `aws_rds_cluster_parameter_group` | Cluster-level parameters | Global `postgresql.conf` |
| `aws_db_parameter_group` | Instance-level parameters | Per-instance `postgresql.conf` |
| `aws_db_subnet_group` | Network placement | Approved network segments |
| `aws_security_group` | Network access control | `pg_hba.conf` at the network level |
| `aws_rds_cluster_endpoint` | Custom endpoint | Connection routing rules |

---

## Summary

| Pattern | What It Does | When to Use |
|---|---|---|
| Parameter groups as code | Version-control `postgresql.conf` settings | Every Aurora deployment |
| Security groups as code | Version-control network access rules | Every Aurora deployment |
| `terraform plan` review | Preview all changes before applying | Every single time, no exceptions |
| `prevent_destroy` | Block accidental deletion | Production databases |
| `deletion_protection` | AWS-level deletion block | Production databases |
| `ignore_changes` | Skip attributes managed externally | Password rotation, auto-upgrades |
| `create_before_destroy` | Replace without downtime gaps | Parameter groups, security groups |
| Data sources | Reference existing infrastructure | Integrating with existing VPCs/subnets |

---

**Next:** [BUILD 01 - Terraform Install and Basics](../build/01-terraform-install-and-basics.md) - Install Terraform and create your first infrastructure with code.
