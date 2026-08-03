# Module 10 - Build Guide 03: Terraform Aurora Cluster

**Objective:** Deploy a production-ready Aurora PostgreSQL cluster using Terraform. Configure the cluster parameter group, writer and reader instances, Secrets Manager integration, automated backups, and deletion protection.
**Time:** 50 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guide 02 completed (VPC, security groups, IAM, and KMS key deployed).

---

## 1. Aurora Module Structure

Create the Aurora Terraform module.

**On your local workstation:**

```bash
mkdir -p ~/capstone-aurora/terraform/modules/aurora
```

---

## 2. Aurora Module Variables

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/aurora/variables.tf
```

Add this content:

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.6"
}

variable "instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs for the cluster"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for storage encryption"
  type        = string
}

variable "monitoring_role_arn" {
  description = "ARN of the IAM role for Enhanced Monitoring"
  type        = string
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 to disable)"
  type        = number
  default     = 60
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 14
}

variable "preferred_backup_window" {
  description = "Daily time range for automated backups (UTC)"
  type        = string
  default     = "02:00-03:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly time range for maintenance (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "reader_count" {
  description = "Number of reader instances"
  type        = number
  default     = 1
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}
```

---

## 3. Aurora Cluster Parameter Group

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/aurora/parameter-group.tf
```

Add this content:

```hcl
# ------------------------------------------------------------------
# Cluster Parameter Group
# ------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-cluster-params"
  family      = "aurora-postgresql16"
  description = "Production parameter group for ${var.project_name}"

  # Security: Force SSL for all connections
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Monitoring: Load pg_stat_statements and pgaudit
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  # Monitoring: Log queries slower than 1 second
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Monitoring: Log connection events
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Monitoring: Log lock waits
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  # Monitoring: Log temp file creation (spill to disk)
  parameter {
    name  = "log_temp_files"
    value = "0"
  }

  # Monitoring: Log all autovacuum runs
  parameter {
    name  = "log_autovacuum_min_duration"
    value = "0"
  }

  # Audit: Configure pgaudit to log DDL, role changes, and writes
  parameter {
    name  = "pgaudit.log"
    value = "ddl,role,write"
  }

  # Safety: Kill idle-in-transaction sessions after 5 minutes
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000"
  }

  # Safety: Kill runaway queries after 60 seconds
  parameter {
    name  = "statement_timeout"
    value = "60000"
  }

  # Performance: pg_stat_statements settings
  parameter {
    name         = "pg_stat_statements.track"
    value        = "all"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pg_stat_statements.max"
    value = "10000"
  }

  tags = {
    Name = "${var.project_name}-cluster-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------
# Instance Parameter Group
# ------------------------------------------------------------------
resource "aws_db_parameter_group" "aurora" {
  name        = "${var.project_name}-instance-params"
  family      = "aurora-postgresql16"
  description = "Instance parameter group for ${var.project_name}"

  # Performance Insights retains data for 7 days (free tier)
  # Instance-level parameters go here if needed

  tags = {
    Name = "${var.project_name}-instance-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

Each parameter is documented with a comment explaining its purpose:
- `rds.force_ssl = 1` - Rejects unencrypted connections
- `shared_preload_libraries` - Loads extensions at startup. Requires reboot to apply.
- `log_min_duration_statement = 1000` - Logs queries taking longer than 1 second
- `idle_in_transaction_session_timeout = 300000` - Kills sessions that leave a transaction open for 5 minutes (300,000 ms). These sessions hold locks and prevent autovacuum.
- `statement_timeout = 60000` - Kills any query running longer than 60 seconds. Prevents runaway queries from consuming resources.
- `pgaudit.log = ddl,role,write` - Logs all DDL statements, role changes, and write operations for audit compliance.

---

## 4. Aurora Cluster Resource

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/aurora/main.tf
```

Add this content:

```hcl
# ------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# ------------------------------------------------------------------
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project_name}-cluster"

  # Engine
  engine         = "aurora-postgresql"
  engine_version = var.engine_version

  # Networking
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids
  availability_zones     = var.availability_zones
  port                   = 5432

  # Authentication
  master_username                     = "dbadmin"
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Backup
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  # Parameter group
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-final-${formatdate("YYYY-MM-DD", timestamp())}"

  # Storage
  storage_type = "aurora"

  tags = {
    Name        = "${var.project_name}-cluster"
    Application = var.project_name
    DataClass   = "confidential"
  }

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      availability_zones,
    ]
  }
}

# ------------------------------------------------------------------
# Writer Instance
# ------------------------------------------------------------------
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-cluster-w1"
  cluster_identifier = aws_rds_cluster.aurora.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  # Parameter group
  db_parameter_group_name = aws_db_parameter_group.aurora.name

  # Monitoring
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_role_arn

  # Network
  publicly_accessible = false

  # Maintenance
  auto_minor_version_upgrade = true
  preferred_maintenance_window = var.preferred_maintenance_window

  # Copy tags
  copy_tags_to_snapshot = true

  # Failover priority (0 = highest)
  promotion_tier = 0

  tags = {
    Name = "${var.project_name}-cluster-w1"
    Role = "writer"
  }
}

# ------------------------------------------------------------------
# Reader Instance(s)
# ------------------------------------------------------------------
resource "aws_rds_cluster_instance" "reader" {
  count = var.reader_count

  identifier         = "${var.project_name}-cluster-r${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  # Parameter group
  db_parameter_group_name = aws_db_parameter_group.aurora.name

  # Monitoring
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_role_arn

  # Network
  publicly_accessible = false

  # Maintenance
  auto_minor_version_upgrade = true
  preferred_maintenance_window = var.preferred_maintenance_window

  # Copy tags
  copy_tags_to_snapshot = true

  # Failover priority (0 = highest)
  promotion_tier = 0

  tags = {
    Name = "${var.project_name}-cluster-r${count.index + 1}"
    Role = "reader"
  }
}
```

Key design decisions in this configuration:

- `manage_master_user_password = true` - Tells RDS to create and manage the master password in Secrets Manager automatically. No password appears in Terraform state.
- `iam_database_authentication_enabled = true` - Allows applications to authenticate with IAM tokens instead of passwords.
- `deletion_protection = true` - Prevents accidental deletion. You must explicitly set this to `false` before destroying.
- `skip_final_snapshot = false` - Forces a final snapshot when the cluster is deleted. This is your last safety net.
- `copy_tags_to_snapshot = true` - Snapshots inherit the cluster's tags, making them identifiable in cost reports and compliance audits.
- `promotion_tier = 0` - Both writer and reader have the highest failover priority. If the writer fails, the reader is the first candidate for promotion.
- `lifecycle.ignore_changes` - The `final_snapshot_identifier` includes a timestamp that changes on every plan. Ignoring it prevents unnecessary diffs.

---

## 5. Aurora Module Outputs

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/aurora/outputs.tf
```

Add this content:

```hcl
output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.aurora.id
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.aurora.arn
}

output "cluster_endpoint" {
  description = "Writer endpoint (use for write operations)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint (use for read operations)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "master_secret_arn" {
  description = "ARN of the master password secret in Secrets Manager"
  value       = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group"
  value       = aws_rds_cluster_parameter_group.aurora.name
}

output "writer_instance_id" {
  description = "Writer instance identifier"
  value       = aws_rds_cluster_instance.writer.id
}

output "reader_instance_ids" {
  description = "Reader instance identifiers"
  value       = aws_rds_cluster_instance.reader[*].id
}

output "port" {
  description = "Database port"
  value       = aws_rds_cluster.aurora.port
}
```

---

## 6. Wire the Aurora Module into Root

**On your local workstation:**

Open the root main.tf and add the Aurora module:

```bash
vi ~/capstone-aurora/terraform/main.tf
```

Add this block after the existing modules:

```hcl
module "aurora" {
  source = "./modules/aurora"

  project_name       = var.project_name
  environment        = var.environment
  availability_zones = var.availability_zones

  # From VPC module
  db_subnet_group_name = module.vpc.db_subnet_group_name

  # From Security module
  vpc_security_group_ids = [module.security.aurora_sg_id]
  kms_key_arn            = module.security.kms_key_arn

  # From IAM module
  monitoring_role_arn = module.iam.rds_monitoring_role_arn

  # Aurora-specific
  engine_version          = "16.6"
  instance_class          = "db.r6g.large"
  reader_count            = 1
  backup_retention_period = 14
  monitoring_interval     = 60
}
```

Add Aurora outputs to the root outputs.tf:

```bash
vi ~/capstone-aurora/terraform/outputs.tf
```

Append these outputs:

```hcl
output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = module.aurora.cluster_endpoint
}

output "reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = module.aurora.reader_endpoint
}

output "master_secret_arn" {
  description = "Master password secret ARN in Secrets Manager"
  value       = module.aurora.master_secret_arn
}

output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = module.aurora.cluster_id
}
```

---

## 7. Plan and Apply

**On your local workstation:**

```bash
cd ~/capstone-aurora/terraform
```

```bash
terraform plan -var-file=production.tfvars -out=aurora.plan
```

Review the plan. You should see approximately 8-10 new resources:
- 1 Cluster parameter group
- 1 Instance parameter group
- 1 Aurora cluster
- 1 Writer instance
- 1 Reader instance

The plan should NOT show any changes to the VPC, security groups, or IAM resources created in Build 02.

```bash
terraform apply aurora.plan
```

The cluster creation takes 10-15 minutes. The writer instance is created first, then the reader.

Expected output (yours will differ):
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com"
cluster_id = "devops-lab-cluster"
master_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!cluster-abc-xyz"
reader_endpoint = "devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com"
...
```

---

## 8. Verify the Cluster

Run these verification commands.

**On your local workstation:**

Check cluster status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[Status,EngineVersion,StorageEncrypted,IAMDatabaseAuthenticationEnabled,DeletionProtection,BackupRetentionPeriod]' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------
|               DescribeDBClusters                        |
+-----------+------+------+------+------+-----------------+
|  available| 16.6 | True | True | True |  14             |
+-----------+------+------+------+------+-----------------+
```

All values should be correct: status `available`, encryption `True`, IAM auth `True`, deletion protection `True`, backup retention `14`.

Check instance status:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,AvailabilityZone,DBInstanceStatus,PubliclyAccessible]' \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------------
|                      DescribeDBInstances                             |
+-------------------------+--------------+--------------+----------+---+
|  devops-lab-cluster-w1  | db.r6g.large | us-east-1a  | available| False |
|  devops-lab-cluster-r1  | db.r6g.large | us-east-1b  | available| False |
+-------------------------+--------------+--------------+----------+---+
```

Verify the writer and reader are in different AZs.

Check parameter group settings:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" \
  --output text
```

Expected output (yours will differ):
```
1
```

Retrieve the master password from Secrets Manager:

```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw master_secret_arn) \
  --query 'SecretString' \
  --output text
```

Expected output (yours will differ):
```json
{"username":"dbadmin","password":"<auto-generated-password>"}
```

This password was generated by RDS and stored in Secrets Manager automatically. It never appeared in your Terraform code or state file.

---

## 9. Test Connectivity

If you have a bastion host deployed, test connectivity through it.

**On your local workstation:**

```bash
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
```

```bash
echo "Cluster endpoint: $CLUSTER_ENDPOINT"
```

If you have `psql` available through an SSH tunnel or bastion:

```bash
psql "host=${CLUSTER_ENDPOINT} port=5432 dbname=postgres user=dbadmin sslmode=require"
```

Once connected, verify the extensions are available:

```sql
SELECT name, default_version FROM pg_available_extensions
WHERE name IN ('pg_stat_statements', 'pgaudit')
ORDER BY name;
```

Expected output (yours will differ):
```
        name        | default_version
--------------------+-----------------
 pg_stat_statements | 1.10
 pgaudit            | 16.0
(2 rows)
```

Create the extensions:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

Verify SSL is enforced:

```sql
SHOW ssl;
```

Expected output (yours will differ):
```
 ssl
-----
 on
(1 row)
```

Exit the psql session:

```sql
\q
```

---

## 10. Commit the Terraform State

Save your Terraform state. For production, use a remote backend (S3 + DynamoDB). For this lab, local state is acceptable.

**On your local workstation:**

```bash
ls -la ~/capstone-aurora/terraform/terraform.tfstate
```

Expected output (yours will differ):
```
-rw-r--r--  1 user  staff  45678  Jun 09 12:00 terraform.tfstate
```

The state file contains sensitive information (secret ARNs, security group IDs). Never commit it to git.

Create a `.gitignore`:

```bash
vi ~/capstone-aurora/terraform/.gitignore
```

Add this content:

```
*.tfstate
*.tfstate.backup
*.tfvars
.terraform/
.terraform.lock.hcl
*.plan
```

---

## Summary

You have deployed a production-ready Aurora PostgreSQL cluster with Terraform:

- **Cluster** with PostgreSQL 16.6, encryption at rest (CMK), SSL enforced, IAM auth enabled
- **Writer instance** in AZ-a with Performance Insights and Enhanced Monitoring
- **Reader instance** in AZ-b with matching instance class for failover readiness
- **Parameter group** with pg_stat_statements, pgaudit, slow query logging, and safety timeouts
- **Secrets Manager** integration for master password (auto-managed, never in code)
- **14-day backup retention** with deletion protection enabled
- **CloudWatch Logs export** for PostgreSQL logs

The cluster is production-ready from a security and availability standpoint. Build Guides 04-08 add monitoring, CI/CD, backup automation, security hardening, and chaos testing.

**Next:** [Build 04 - Monitoring Setup](./04-monitoring-setup.md)
