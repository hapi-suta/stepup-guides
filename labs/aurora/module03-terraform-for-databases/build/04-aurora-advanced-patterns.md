# BUILD 04: Aurora Advanced Patterns

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** LOCAL (all examples use local_file provider - no AWS cost)
**Time Estimate:** 45 minutes
**Prerequisites:** BUILD 01-03 completed

---

## What You Will Learn

Advanced Terraform patterns that make Aurora configurations production-grade: `for_each` for flexible resource creation, `count` with conditionals, data sources to reference existing resources, and dynamic blocks for repeatable configuration.

All examples use the `local_file` provider so you can practice without AWS costs. Each pattern includes the Aurora-equivalent HCL so you know how to apply it for real.

---

## Step 1: for_each - Create Resources from a Map

In BUILD 02 and 03, we used `count` to create reader instances. `count` uses numeric indexes (0, 1, 2). This works, but has a problem: if you remove reader 1 from a list of 3, Terraform renumbers everything and may destroy readers 2 and 3 to recreate them with new indexes.

`for_each` uses named keys instead of numbers. Removing one item only affects that item.

**DBA analogy:** `count` is like using array indexes. `for_each` is like using primary keys. Primary keys are always safer for identifying specific rows.

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab04-advanced
```

```bash
cd ~/terraform-labs/lab04-advanced
```

```bash
vi ~/terraform-labs/lab04-advanced/main.tf
```

Press `i` to enter insert mode and type:

```hcl
# main.tf - for_each example

# Using for_each to create reader configurations
# Each reader has a name (key) and an instance class (value)
variable "readers" {
  description = "Map of reader name to instance class"
  type        = map(string)
  default = {
    "reader-analytics" = "db.r6g.large"
    "reader-reporting" = "db.r6g.xlarge"
    "reader-api"       = "db.t3.medium"
  }
}

# Create one file per reader (simulating Aurora reader instances)
resource "local_file" "reader_configs" {
  for_each = var.readers

  content  = "Reader: ${each.key}\nInstance Class: ${each.value}\nRole: read-replica"
  filename = "${path.module}/${each.key}.conf"
}

# Output all reader file paths
output "reader_files" {
  value = { for name, reader in local_file.reader_configs : name => reader.filename }
}
```

Save and exit (`:wq`).

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
local_file.reader_configs["reader-analytics"]: Creating...
local_file.reader_configs["reader-reporting"]: Creating...
local_file.reader_configs["reader-api"]: Creating...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

reader_files = {
  "reader-analytics" = "./reader-analytics.conf"
  "reader-api"       = "./reader-api.conf"
  "reader-reporting" = "./reader-reporting.conf"
}
```

Now verify the key advantage. Remove one reader from the map:

```bash
vi ~/terraform-labs/lab04-advanced/main.tf
```

Change the `readers` default to remove `reader-reporting`:

```hcl
  default = {
    "reader-analytics" = "db.r6g.large"
    "reader-api"       = "db.t3.medium"
  }
```

Save and exit (`:wq`).

```bash
terraform plan
```

Expected output:

```
  # local_file.reader_configs["reader-reporting"] will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.
```

Only the removed reader is destroyed. The other two are untouched. With `count`, removing reader 1 from the middle would have renumbered everything and potentially destroyed/recreated multiple resources.

### Aurora Equivalent

```hcl
# Real Aurora: for_each to create readers with different instance classes
resource "aws_rds_cluster_instance" "readers" {
  for_each = var.readers

  identifier         = "${var.cluster_id}-${each.key}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = each.value
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}
```

Apply the removal so state is clean:

```bash
terraform apply -auto-approve
```

---

## Step 2: count with Conditionals

Sometimes you want a resource to exist in one environment but not another. The pattern `count = condition ? 1 : 0` creates the resource when true and skips it when false.

**DBA analogy:** This is like `CASE WHEN environment = 'prod' THEN create_monitoring END`.

Update your main.tf:

```bash
vi ~/terraform-labs/lab04-advanced/main.tf
```

Replace the entire contents with:

```hcl
# main.tf - conditional resource creation

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "readers" {
  description = "Map of reader name to instance class"
  type        = map(string)
  default = {
    "reader-analytics" = "db.r6g.large"
    "reader-api"       = "db.t3.medium"
  }
}

# Always create - the database config
resource "local_file" "database_config" {
  content  = "environment=${var.environment}\nengine=aurora-postgresql"
  filename = "${path.module}/database.conf"
}

# Only create in production - monitoring config
# count = 1 means "create it", count = 0 means "skip it"
resource "local_file" "monitoring_config" {
  count = var.environment == "prod" ? 1 : 0

  content  = "alert_threshold=90\ncheck_interval=30\nnotify=dba-team@company.com"
  filename = "${path.module}/monitoring.conf"
}

# Only create in production - backup verification config
resource "local_file" "backup_verification" {
  count = var.environment == "prod" ? 1 : 0

  content  = "verify_interval=daily\nrestore_test=weekly\nretention=35"
  filename = "${path.module}/backup-verify.conf"
}

# Reader configs using for_each
resource "local_file" "reader_configs" {
  for_each = var.readers

  content  = "Reader: ${each.key}\nInstance Class: ${each.value}"
  filename = "${path.module}/${each.key}.conf"
}

output "environment" {
  value = var.environment
}

output "monitoring_enabled" {
  value = var.environment == "prod" ? "yes" : "no"
}
```

Save and exit (`:wq`).

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

environment = "dev"
monitoring_enabled = "no"
```

Only 3 resources created (database config + 2 readers). Monitoring and backup verification were skipped because environment is "dev".

Now switch to prod:

```bash
terraform apply -auto-approve -var="environment=prod"
```

Expected output (yours will differ):

```
Apply complete! Resources: 2 added, 1 changed, 0 destroyed.

Outputs:

environment = "prod"
monitoring_enabled = "yes"
```

Two additional resources created (monitoring + backup verification).

### Aurora Equivalent

```hcl
# Real Aurora: Only create CloudWatch alarm in production
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.environment == "prod" ? 1 : 0

  alarm_name          = "${var.cluster_id}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
}
```

Clean up:

```bash
terraform destroy -auto-approve -var="environment=prod"
```

---

## Step 3: Data Sources - Querying Existing Resources

Data sources let you read information about resources that already exist - resources Terraform did not create. They are read-only `SELECT` statements against the provider.

| Operation | PostgreSQL | Terraform |
|---|---|---|
| Read existing objects | `SELECT * FROM information_schema.tables` | `data "aws_vpc" "existing" {}` |
| Create new objects | `CREATE TABLE ...` | `resource "aws_instance" ...` |

Data sources never create, modify, or destroy anything.

Update your main.tf:

```bash
vi ~/terraform-labs/lab04-advanced/main.tf
```

Replace the entire contents with:

```hcl
# main.tf - data sources example

# Data source: read a local file that already exists
# This is like SELECT - it reads but does not create
data "local_file" "existing_hosts" {
  filename = "/etc/hosts"
}

# Use the data source in a resource
resource "local_file" "hosts_backup" {
  content  = "# Backup of /etc/hosts taken by Terraform\n# Lines: ${length(split("\n", data.local_file.existing_hosts.content))}\n\n${data.local_file.existing_hosts.content}"
  filename = "${path.module}/hosts-backup.txt"
}

output "hosts_line_count" {
  value = length(split("\n", data.local_file.existing_hosts.content))
}
```

Save and exit (`:wq`).

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
data.local_file.existing_hosts: Reading...
local_file.hosts_backup: Creating...

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

hosts_line_count = 12
```

The data source read `/etc/hosts` (which already exists) and we used its contents in a new file. The original file was not modified.

### Aurora Equivalent

```hcl
# Look up an existing VPC by tag
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

# Look up existing subnets in that VPC
data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["database"]
  }
}

# Use them for Aurora
resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-subnets"
  subnet_ids = data.aws_subnets.database.ids
}

resource "aws_rds_cluster" "main" {
  cluster_identifier   = "prod-aurora"
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [data.aws_security_group.app.id]
  # ...
}
```

Clean up:

```bash
terraform destroy -auto-approve
```

---

## Step 4: Dynamic Blocks - Repeating Nested Configuration

Some Terraform resources have nested blocks that repeat (like security group ingress rules). Instead of writing each one by hand, `dynamic` blocks generate them from a list or map.

**DBA analogy:** This is like generating multiple `pg_hba.conf` lines from a list of allowed IPs.

```bash
vi ~/terraform-labs/lab04-advanced/main.tf
```

Replace the entire contents with:

```hcl
# main.tf - dynamic blocks example

variable "allowed_ips" {
  description = "Map of team name to CIDR block"
  type        = map(string)
  default = {
    "app-servers"    = "10.0.1.0/24"
    "dba-workstation" = "172.16.5.10/32"
    "vpn-users"      = "192.168.100.0/24"
    "monitoring"     = "10.0.50.0/24"
  }
}

variable "postgresql_parameters" {
  description = "Map of PostgreSQL parameter names to values"
  type        = map(string)
  default = {
    "log_statement"                = "ddl"
    "log_min_duration_statement"   = "1000"
    "idle_in_transaction_session_timeout" = "300000"
    "statement_timeout"            = "60000"
    "shared_preload_libraries"     = "pg_stat_statements"
  }
}

# Simulate security group rules using local files
resource "local_file" "security_rules" {
  content = join("\n", [
    "# Security Group Rules (pg_hba.conf equivalent)",
    "# Generated by Terraform from allowed_ips map",
    "",
    join("\n", [for team, cidr in var.allowed_ips :
      "allow ${cidr} port 5432  # ${team}"
    ])
  ])
  filename = "${path.module}/security-rules.conf"
}

# Simulate parameter group using local files
resource "local_file" "parameter_group" {
  content = join("\n", [
    "# PostgreSQL Parameter Group",
    "# Generated by Terraform from postgresql_parameters map",
    "",
    join("\n", [for param, value in var.postgresql_parameters :
      "${param} = ${value}"
    ])
  ])
  filename = "${path.module}/parameters.conf"
}

output "rule_count" {
  value = length(var.allowed_ips)
}

output "parameter_count" {
  value = length(var.postgresql_parameters)
}
```

Save and exit (`:wq`).

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

parameter_count = 5
rule_count = 4
```

Verify the generated files:

```bash
cat ~/terraform-labs/lab04-advanced/security-rules.conf
```

Expected output:

```
# Security Group Rules (pg_hba.conf equivalent)
# Generated by Terraform from allowed_ips map

allow 10.0.1.0/24 port 5432  # app-servers
allow 172.16.5.10/32 port 5432  # dba-workstation
allow 10.0.50.0/24 port 5432  # monitoring
allow 192.168.100.0/24 port 5432  # vpn-users
```

### Aurora Equivalent

```hcl
# Real Aurora: dynamic block for security group ingress rules
resource "aws_security_group" "aurora" {
  name   = "aurora-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.allowed_ips
    content {
      description = "PostgreSQL from ${ingress.key}"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Real Aurora: dynamic block for parameter group
resource "aws_db_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "custom-params"

  dynamic "parameter" {
    for_each = var.postgresql_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }
}
```

---

## Step 5: Combining Patterns

Real Aurora configurations combine all these patterns. Here is a complete example showing how they work together:

```hcl
# Combined patterns for a production Aurora setup (REFERENCE ONLY)

variable "readers" {
  type = map(object({
    instance_class = string
    az             = string
  }))
  default = {
    "analytics" = { instance_class = "db.r6g.large",  az = "us-east-1a" }
    "api"       = { instance_class = "db.r6g.large",  az = "us-east-1b" }
    "reporting" = { instance_class = "db.r6g.xlarge", az = "us-east-1c" }
  }
}

# for_each with complex objects
resource "aws_rds_cluster_instance" "readers" {
  for_each = var.readers

  identifier          = "${var.cluster_id}-${each.key}"
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = each.value.instance_class
  availability_zone   = each.value.az
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version
  publicly_accessible = false

  tags = {
    Name = "${var.cluster_id}-${each.key}"
    Role = "reader"
    Team = each.key
  }
}

# Conditional monitoring
resource "aws_cloudwatch_metric_alarm" "reader_cpu" {
  for_each = var.environment == "prod" ? var.readers : {}

  alarm_name = "${var.cluster_id}-${each.key}-cpu"
  # ...
}
```

---

## Step 6: Clean Up

```bash
terraform destroy -auto-approve
```

Expected output:

```
Destroy complete! Resources: 2 destroyed.
```

---

## What You Learned

| Pattern | When to Use | DBA Analogy |
|---|---|---|
| `for_each` (map) | Create named resources from a map | Primary key-based identification |
| `for_each` (set) | Create resources from a set of strings | DISTINCT values |
| `count` conditional | Create/skip resource based on condition | `CASE WHEN` for resources |
| Data sources | Reference existing resources | `SELECT` from `information_schema` |
| Dynamic blocks | Generate repeated nested blocks | Generating pg_hba.conf from a table |
| Combined patterns | Production configurations | Full database deployment automation |

| Pattern | Prefer Over | Because |
|---|---|---|
| `for_each` | `count` for named items | Removing one item does not renumber others |
| `count` | `for_each` for identical items | Simpler when items are truly identical |
| Data sources | Hardcoded IDs | IDs change between environments |
| Dynamic blocks | Copy-pasted blocks | DRY, maintainable, driven by variables |

---

**Next:** [BUILD 05 - Terraform Import](05-terraform-import-existing.md) - Bring existing AWS resources under Terraform management.
