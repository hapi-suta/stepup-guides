# Concepts: Terraform for Databases - Quick Reference

**Module:** DBA Automation & DevOps - Module 01

---

## IaC Philosophy - Why It Matters for DBAs

Infrastructure as Code means treating your servers, networks, and cloud resources the same way you treat database schemas - as versioned, reviewable, repeatable code.

**Without IaC:**
- "Who created this RDS instance? What settings did they use?"
- "Can we recreate the staging environment? I think it was a db.r5.large... maybe db.r5.xlarge?"
- "Someone changed the security group in the console. What was it before?"

**With IaC:**
- Every resource is defined in a `.tf` file, checked into Git
- `git log` shows who changed what and when
- `git diff` shows exactly what changed
- Any environment can be recreated from scratch by running `terraform apply`

This is the same evolution DBAs went through with database migrations. You stopped creating tables by clicking in pgAdmin and started writing DDL scripts. IaC is the same discipline applied to everything outside the database.

---

## Terraform Workflow Cheat Sheet

```
terraform init      Download providers and modules (run once per project)
terraform plan      Preview changes (EXPLAIN ANALYZE for infrastructure)
terraform apply     Execute changes (run the migration)
terraform destroy   Remove everything (DROP all resources)
terraform output    Show output values
terraform state     Manage state file
terraform import    Bring existing resources under Terraform management
terraform fmt       Format .tf files consistently
terraform validate  Check syntax without connecting to any provider
```

### The Standard Workflow

```
1. Write/edit .tf files
2. terraform plan        (review what will change)
3. terraform apply       (make the changes)
4. Verify in AWS console or via CLI
5. terraform destroy     (when done with lab/temp resources)
```

### State Management Commands

```
terraform state list                    List all resources in state
terraform state show aws_db_instance.x  Show details of one resource
terraform state rm aws_db_instance.x    Remove a resource from state (does NOT delete it)
terraform state pull                    Download remote state to stdout
terraform state push                    Upload local state to remote
terraform import aws_db_instance.x id   Import existing resource into state
```

---

## HCL Syntax Quick Reference

### Block Types

```hcl
# Provider - configures a cloud platform connection
provider "aws" {
  region = "us-east-1"
}

# Resource - declares something to create/manage
resource "aws_db_instance" "mydb" {
  engine         = "postgres"
  instance_class = "db.t3.micro"
}

# Variable - declares an input parameter
variable "db_name" {
  type        = string
  default     = "mydb"
  description = "Database name"
}

# Output - declares a value to display/export
output "endpoint" {
  value       = aws_db_instance.mydb.endpoint
  description = "Database endpoint"
}

# Data source - reads existing infrastructure (SELECT, not CREATE)
data "aws_vpc" "existing" {
  id = "vpc-12345"
}

# Module - calls a reusable configuration package
module "database" {
  source       = "./modules/rds"
  db_name      = "myapp"
  environment  = "prod"
}

# Locals - computed values (like WITH/CTE in SQL)
locals {
  full_name = "${var.project}-${var.environment}"
}
```

### Variable Types

| HCL Type | PostgreSQL Equivalent | Example |
|---|---|---|
| `string` | `TEXT` | `"hello"` |
| `number` | `INTEGER` / `NUMERIC` | `42`, `3.14` |
| `bool` | `BOOLEAN` | `true`, `false` |
| `list(string)` | `TEXT[]` | `["a", "b", "c"]` |
| `map(string)` | `JSONB` (flat) | `{ key = "value" }` |
| `object({...})` | Composite type | `{ name = string, port = number }` |
| `tuple([...])` | Row with mixed types | `[string, number, bool]` |

### Expressions

```hcl
# String interpolation
name = "db-${var.environment}"

# Conditional (ternary)
instance_class = var.environment == "prod" ? "db.r5.large" : "db.t3.micro"

# For expression (list comprehension)
endpoints = [for i in aws_rds_cluster_instance.readers : i.endpoint]

# Splat expression (shorthand for the above)
endpoints = aws_rds_cluster_instance.readers[*].endpoint
```

### Reference Syntax

```hcl
# Reference a variable
var.db_name

# Reference another resource's attribute
aws_vpc.main.id

# Reference a data source
data.aws_vpc.existing.id

# Reference a module output
module.database.endpoint

# Reference the current workspace
terraform.workspace

# Reference the module's directory
path.module
```

---

## AWS RDS / Aurora Resource Reference

### aws_db_instance (RDS)

| Argument | Required | Description | DBA Analogy |
|---|---|---|---|
| `identifier` | Yes | Unique name for the instance | Hostname |
| `engine` | Yes | `"postgres"` | Which RDBMS |
| `engine_version` | Yes | `"16.4"` | `SELECT version()` |
| `instance_class` | Yes | `"db.t3.micro"` | Server hardware specs |
| `allocated_storage` | Yes | Storage in GB | Disk size |
| `db_name` | No | Initial database | `CREATE DATABASE` |
| `username` | Yes | Master user | `postgres` superuser |
| `password` | Yes | Master password | Superuser password |
| `parameter_group_name` | No | Parameter group | `postgresql.conf` |
| `vpc_security_group_ids` | No | Security groups | `pg_hba.conf` |
| `db_subnet_group_name` | No | Subnet group | Network placement |
| `multi_az` | No | HA failover | Synchronous replica |
| `backup_retention_period` | No | Days to keep backups | Backup retention |
| `publicly_accessible` | No | Internet access | Listen address |
| `storage_encrypted` | No | Encryption at rest | TDE |
| `deletion_protection` | No | Prevent destroy | Safety lock |
| `skip_final_snapshot` | No | Skip snapshot on delete | Final backup |

### aws_rds_cluster (Aurora)

| Argument | Required | Description |
|---|---|---|
| `cluster_identifier` | Yes | Cluster name |
| `engine` | Yes | `"aurora-postgresql"` |
| `engine_version` | Yes | `"16.4"` |
| `database_name` | No | Initial database |
| `master_username` | Yes | Master user |
| `master_password` | Yes | Master password |
| `db_cluster_parameter_group_name` | No | Cluster parameter group |
| `vpc_security_group_ids` | No | Security groups |
| `db_subnet_group_name` | No | Subnet group |
| `backup_retention_period` | No | Backup retention days |
| `storage_encrypted` | No | Encryption at rest |
| `deletion_protection` | No | Prevent destroy |

### aws_rds_cluster_instance (Aurora Instance)

| Argument | Required | Description |
|---|---|---|
| `identifier` | Yes | Instance name |
| `cluster_identifier` | Yes | Which cluster to join |
| `instance_class` | Yes | Instance size |
| `engine` | Yes | Must match cluster engine |
| `db_parameter_group_name` | No | Instance parameter group |
| `publicly_accessible` | No | Internet access |

---

## State Management Best Practices

### Do

- Store state remotely (S3 + DynamoDB) for team projects
- Enable state locking to prevent concurrent modifications
- Enable encryption for state files (they contain secrets)
- Use workspaces or separate state files for different environments
- Run `terraform plan` before every `terraform apply`
- Review the plan output carefully before typing `yes`

### Do Not

- Edit `terraform.tfstate` by hand
- Commit state files to Git
- Share state files via email or Slack
- Run `terraform apply` without reviewing the plan
- Use `terraform apply -auto-approve` in production
- Ignore state drift (differences between state and reality)

### State Recovery Scenarios

| Problem | Solution |
|---|---|
| State file deleted | Restore from backup, or re-import all resources |
| State says resource exists but it was manually deleted | `terraform state rm <resource>` to remove from state |
| Resource exists in AWS but not in state | `terraform import <resource> <id>` to add to state |
| State is out of sync | `terraform plan` to see drift, then decide: update config or update resource |
| Two people modified at the same time (no locking) | One person's changes may be overwritten - use remote state with locking |

---

## Common Terraform Commands Table

| Command | What It Does | When to Use |
|---|---|---|
| `terraform init` | Download providers/modules | First time, or after adding providers |
| `terraform plan` | Preview changes | Before every apply |
| `terraform apply` | Execute changes | After reviewing plan |
| `terraform destroy` | Delete all resources | End of lab, decommissioning |
| `terraform fmt` | Auto-format .tf files | Before committing to Git |
| `terraform validate` | Check syntax | After writing new config |
| `terraform output` | Show output values | Get connection strings, IDs |
| `terraform state list` | List managed resources | Audit what Terraform manages |
| `terraform state show X` | Show resource details | Debug a specific resource |
| `terraform state rm X` | Remove from state | Resource was manually deleted |
| `terraform import X id` | Import existing resource | Bring existing infra into Terraform |
| `terraform refresh` | Update state from reality | Detect manual changes (deprecated - use `plan` instead) |
| `terraform workspace list` | List workspaces | See available environments |
| `terraform workspace new X` | Create workspace | Set up new environment |
| `terraform workspace select X` | Switch workspace | Change target environment |
| `terraform graph` | Generate dependency graph | Visualize resource relationships |
| `terraform taint X` | Mark for recreation | Force resource replacement |
| `terraform console` | Interactive expression evaluator | Test expressions and functions |
