# BUILD 04: Aurora Clusters and Advanced Terraform Patterns

**Module:** DBA Automation & DevOps - Module 01
**Lab Type:** AWS (Aurora clusters cost more than RDS - destroy immediately after testing)
**Time Estimate:** 60-90 minutes
**Prerequisites:** BUILD 01-03 completed

**COST WARNING:** Aurora clusters cost more than single RDS instances. A db.t3.medium Aurora instance costs roughly $0.07/hour per instance. A cluster with a writer + 2 readers = $0.21/hour. Always destroy when done.

---

## What You Will Build

A production-ready Aurora PostgreSQL cluster with a writer instance, two reader instances, automated backups, monitoring tags, and advanced Terraform patterns including loops, conditionals, provisioners, and import.

---

## Step 1: Understand Aurora vs RDS

If you have managed PostgreSQL replication, you already understand the core difference.

| Feature | RDS PostgreSQL | Aurora PostgreSQL |
|---|---|---|
| Storage | Each instance has its own EBS | Shared distributed storage layer |
| Replication | Streaming replication (WAL shipping) | Storage-level replication (no WAL shipping) |
| Failover time | 60-120 seconds | Typically under 30 seconds |
| Read replicas | Up to 15, each with own storage | Up to 15, all share storage |
| Storage growth | You pre-allocate | Auto-grows (10GB increments) |

**DBA analogy:** Think of RDS as traditional primary-replica streaming replication - each replica maintains its own copy of the data. Aurora is more like a shared storage architecture where the "disk" itself handles replication, and compute nodes just attach to it.

```
RDS Architecture:
  Primary (data) --WAL--> Replica (data copy)

Aurora Architecture:
  Writer (compute) --\
                      +--> Shared Storage (6 copies across 3 AZs)
  Reader (compute) --/
```

---

## Step 2: Create the Project Structure

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/lab04-aurora
```

```bash
cd ~/terraform-labs/lab04-aurora
```

---

## Step 3: Provider and Variables

**In `~/terraform-labs/lab04-aurora`:**

```bash
vi providers.tf
```

Enter insert mode (`i`) and type:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

Save and exit (`:wq`).

```bash
vi variables.tf
```

Enter insert mode (`i`) and type:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "dba-lab"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "auroradb"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Your public IP for security group access"
  type        = string
}

variable "reader_count" {
  description = "Number of Aurora read replicas to create"
  type        = number
  default     = 2
}

variable "instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.t3.medium"  # Minimum for Aurora
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = false
}
```

Save and exit (`:wq`).

---

## Step 4: Networking (Reuse the Pattern)

**In `~/terraform-labs/lab04-aurora`:**

```bash
vi vpc.tf
```

Enter insert mode (`i`) and type:

```hcl
# vpc.tf - Network infrastructure (same pattern as BUILD 02)

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-b"
  }
}

resource "aws_subnet" "db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-c"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.db_c.id
  route_table_id = aws_route_table.main.id
}

resource "aws_db_subnet_group" "aurora" {
  name = "${var.project_name}-${var.environment}-aurora-subnets"
  subnet_ids = [
    aws_subnet.db_a.id,
    aws_subnet.db_b.id,
    aws_subnet.db_c.id,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-subnets"
  }
}

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-sg"
  description = "Controls access to Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from my IP"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  }
}
```

Save and exit (`:wq`).

---

## Step 5: Create the Aurora Cluster

Aurora has two levels of resources - the **cluster** (shared storage, configuration) and **cluster instances** (compute nodes that attach to the cluster).

| Aurora Concept | PostgreSQL Analogy |
|---|---|
| Cluster | The shared storage + configuration |
| Writer instance | Primary server |
| Reader instance(s) | Read replica(s) |
| Cluster endpoint | Primary connection string |
| Reader endpoint | Load-balanced replica connection string |

**In `~/terraform-labs/lab04-aurora`:**

```bash
vi aurora.tf
```

Enter insert mode (`i`) and type:

```hcl
# aurora.tf - Aurora PostgreSQL cluster

# Cluster parameter group - applies to the entire cluster
# Like postgresql.conf settings that affect replication behavior
resource "aws_rds_cluster_parameter_group" "aurora" {
  family = "aurora-postgresql16"
  name   = "${var.project_name}-${var.environment}-aurora-cluster-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-cluster-params"
  }
}

# Instance parameter group - applies to individual instances
# Like instance-specific postgresql.conf settings
resource "aws_db_parameter_group" "aurora" {
  family = "aurora-postgresql16"
  name   = "${var.project_name}-${var.environment}-aurora-instance-params"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries over 1 second
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-instance-params"
  }
}

# The Aurora cluster itself - shared storage and cluster-level config
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  database_name   = var.db_name
  master_username = var.db_username
  master_password = var.db_password

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Backup configuration
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"

  # Maintenance
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Lab settings
  skip_final_snapshot = true
  deletion_protection = false

  # Storage encryption (always enable, even in labs)
  storage_encrypted = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-aurora"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Writer instance - the primary node
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-${var.environment}-aurora-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name
  publicly_accessible     = true  # Lab only

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-writer"
    Role = "writer"
  }
}

# Reader instances - using for_each for flexible scaling
# This is like generate_series() - create N similar resources from a pattern
resource "aws_rds_cluster_instance" "readers" {
  count = var.reader_count

  identifier         = "${var.project_name}-${var.environment}-aurora-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name
  publicly_accessible     = true  # Lab only

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-reader-${count.index + 1}"
    Role = "reader"
  }
}
```

Save and exit (`:wq`).

---

## Step 6: Understand count and for_each (generate_series for Resources)

In the Aurora config above, we used `count` to create multiple reader instances. Let's understand both looping mechanisms.

### count - Simple Numeric Loop

```hcl
# Like: SELECT generate_series(0, 2) AS index;
resource "aws_rds_cluster_instance" "readers" {
  count = 3  # Creates readers[0], readers[1], readers[2]

  identifier = "reader-${count.index + 1}"  # reader-1, reader-2, reader-3
}
```

`count` is like `generate_series()` - it produces a numbered sequence. Each resource gets a numeric index starting at 0.

### for_each - Map/Set Based Loop

```hcl
# Like iterating over a table of configuration values
resource "aws_db_instance" "databases" {
  for_each = {
    "users"    = "db.t3.micro"
    "orders"   = "db.t3.small"
    "analytics" = "db.r5.large"
  }

  identifier     = each.key      # "users", "orders", "analytics"
  instance_class = each.value    # The corresponding instance size
}
```

| Loop Type | When to Use | DBA Analogy |
|---|---|---|
| `count` | Creating N identical (or numbered) resources | `generate_series(1, N)` |
| `for_each` | Creating resources from a map/set of unique items | Iterating over rows in a lookup table |

**When to prefer `for_each` over `count`:** If you remove item 2 from a `count = 5` list, Terraform renumbers everything and may destroy/recreate items 3-5. `for_each` uses keys, so removing one item only affects that item. This is like the difference between array indexes and primary keys.

---

## Step 7: Provisioners (Post-Creation Actions)

Sometimes you need to run a command after a resource is created - like running a SQL script after creating a database. Terraform calls these **provisioners**.

**Important:** Provisioners are a last resort. Terraform's documentation explicitly says to avoid them when possible. But for DBAs, running a SQL setup script after RDS creation is a legitimate use case.

```hcl
# Example - run a script after the database is created
resource "aws_rds_cluster" "aurora" {
  # ... cluster config ...

  # local-exec runs a command on YOUR machine (where you run terraform)
  # Think of it as a trigger that fires after CREATE
  provisioner "local-exec" {
    command = <<-EOT
      echo "Aurora cluster created!"
      echo "Endpoint: ${self.endpoint}"
      echo "Run your schema migration next."
    EOT
  }
}
```

| Provisioner Type | Runs Where | DBA Analogy |
|---|---|---|
| `local-exec` | Your machine | A post-deploy script on the admin workstation |
| `remote-exec` | On the created resource | A script that runs on the database server itself |

A practical DBA example - run a schema migration after the cluster is ready:

```hcl
provisioner "local-exec" {
  command = "PGPASSWORD=${var.db_password} psql -h ${self.endpoint} -U ${var.db_username} -d ${var.db_name} -f ./migrations/001_initial_schema.sql"
}
```

---

## Step 8: Conditional Resources (CASE WHEN for Infrastructure)

Sometimes you want a resource to exist in one environment but not another. Terraform uses a pattern with `count`:

```hcl
# Only create enhanced monitoring in production
# Like: CASE WHEN environment = 'prod' THEN create_monitoring ELSE skip END

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  count = var.environment == "prod" ? 1 : 0  # 1 = create it, 0 = skip it

  alarm_name = "${var.project_name}-high-cpu"
  # ...
}
```

The pattern `count = condition ? 1 : 0` means:
- If the condition is true, create 1 instance of this resource
- If false, create 0 instances (effectively skipping it)

This is exactly like:

```sql
-- Only create the index in production
DO $$
BEGIN
  IF current_setting('app.environment') = 'prod' THEN
    CREATE INDEX CONCURRENTLY idx_orders_date ON orders(created_at);
  END IF;
END $$;
```

---

## Step 9: Importing Existing Infrastructure (terraform import)

You have 15,000+ databases. They were not all created with Terraform. What happens when you want to bring an existing RDS instance under Terraform management?

`terraform import` is like `pg_dump` for infrastructure - it takes something that already exists and captures it in Terraform state.

**The workflow:**

1. Write the Terraform configuration for the existing resource (the `.tf` file)
2. Run `terraform import` to tell Terraform "this config matches that real resource"
3. Run `terraform plan` to verify there are no differences

```bash
# Step 1: You already wrote the resource block in your .tf file
# Step 2: Import the existing RDS instance into state
terraform import aws_db_instance.existing_db dba-lab-postgres

# Step 3: Check for drift
terraform plan
```

Expected output after import:

```
aws_db_instance.existing_db: Importing...
aws_db_instance.existing_db: Import complete [id=dba-lab-postgres]

Import successful! The resources that were imported are listed above.
```

After importing, `terraform plan` shows any differences between your config and reality. Fix them until the plan shows "No changes."

| Import Scenario | Steps |
|---|---|
| Existing RDS instance | Write config, `terraform import aws_db_instance.name identifier` |
| Existing VPC | Write config, `terraform import aws_vpc.name vpc-id` |
| Existing security group | Write config, `terraform import aws_security_group.name sg-id` |

**Common gotcha:** After import, `terraform plan` often shows differences because your config does not perfectly match the real resource. Iterate: run plan, fix config, run plan again, until it shows no changes.

---

## Step 10: Outputs and Cost Tagging

**In `~/terraform-labs/lab04-aurora`:**

```bash
vi outputs.tf
```

Enter insert mode (`i`) and type:

```hcl
# outputs.tf - Aurora cluster connection information

output "cluster_endpoint" {
  description = "Aurora cluster endpoint (writer)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Aurora reader endpoint (load-balanced across readers)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "writer_instance_endpoint" {
  description = "Writer instance direct endpoint"
  value       = aws_rds_cluster_instance.writer.endpoint
}

output "reader_instance_endpoints" {
  description = "Individual reader instance endpoints"
  value       = [for r in aws_rds_cluster_instance.readers : r.endpoint]
}

output "writer_connection" {
  description = "psql command to connect to writer"
  value       = "psql -h ${aws_rds_cluster.aurora.endpoint} -p ${aws_rds_cluster.aurora.port} -U ${var.db_username} -d ${var.db_name}"
}

output "reader_connection" {
  description = "psql command to connect to reader (load balanced)"
  value       = "psql -h ${aws_rds_cluster.aurora.reader_endpoint} -p ${aws_rds_cluster.aurora.port} -U ${var.db_username} -d ${var.db_name}"
}

output "total_instances" {
  description = "Total number of instances (writer + readers)"
  value       = 1 + var.reader_count
}
```

Save and exit (`:wq`).

---

## Step 11: Create the tfvars File

**In `~/terraform-labs/lab04-aurora`:**

```bash
vi terraform.tfvars
```

Enter insert mode (`i`) and type:

```hcl
aws_region    = "us-east-1"
project_name  = "dba-lab"
environment   = "dev"
db_name       = "auroradb"
db_username   = "dbadmin"
db_password   = "ChangeMe123!"
my_ip         = "203.0.113.50"  # Replace with YOUR IP
reader_count  = 2
instance_class = "db.t3.medium"
```

Save and exit (`:wq`).

---

## Step 12: Initialize and Plan

**In `~/terraform-labs/lab04-aurora`:**

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.72.1...

Terraform has been successfully initialized!
```

```bash
terraform plan
```

Expected output (yours will differ):

```
  # aws_rds_cluster.aurora will be created
  # aws_rds_cluster_instance.writer will be created
  # aws_rds_cluster_instance.readers[0] will be created
  # aws_rds_cluster_instance.readers[1] will be created
  # aws_rds_cluster_parameter_group.aurora will be created
  # aws_db_parameter_group.aurora will be created
  ...

Plan: 17 to add, 0 to change, 0 to destroy.
```

17 resources: VPC networking (10) + security group (1) + subnet group (1) + 2 parameter groups + cluster (1) + writer (1) + 2 readers.

---

## Step 13: Apply and Test (Optional - Costs Money)

**Only do this if you are comfortable with the cost.** Aurora db.t3.medium instances cost about $0.07/hour each. With 3 instances, that is $0.21/hour.

**In `~/terraform-labs/lab04-aurora`:**

```bash
terraform apply
```

Type `yes` when prompted. This will take 10-15 minutes for the full cluster.

Once complete, connect to the writer:

```bash
psql -h dba-lab-dev-aurora.cluster-abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d auroradb
```

Verify the cluster:

```sql
SELECT version();
```

```sql
-- Check if you are on the writer or a reader
SELECT pg_is_in_recovery();
```

Expected output on the writer:

```
 pg_is_in_recovery
-------------------
 f
```

Connect to the reader endpoint and run the same check:

```sql
SELECT pg_is_in_recovery();
```

Expected output on a reader:

```
 pg_is_in_recovery
-------------------
 t
```

The reader correctly reports it is in recovery mode (read-only).

---

## Step 14: Destroy Everything (Critical!)

**In `~/terraform-labs/lab04-aurora`:**

```bash
terraform destroy
```

Type `yes` when prompted. Wait for all 17 resources to be destroyed.

Expected output (yours will differ):

```
aws_rds_cluster_instance.readers[1]: Destroying...
aws_rds_cluster_instance.readers[0]: Destroying...
aws_rds_cluster_instance.writer: Destroying...
...
aws_rds_cluster.aurora: Destroying...
...
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 17 destroyed.
```

---

## Step 15: Production-Ready Checklist

When building Aurora clusters for production (not lab), always include:

| Setting | Lab Value | Production Value |
|---|---|---|
| `deletion_protection` | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| `publicly_accessible` | `true` | `false` |
| `storage_encrypted` | `true` | `true` |
| `backup_retention_period` | 7 | 14-35 |
| `instance_class` | `db.t3.medium` | `db.r5.large` or bigger |
| `lifecycle.prevent_destroy` | not set | `true` |
| Enhanced monitoring | disabled | enabled |
| Performance Insights | disabled | enabled |
| CloudWatch alarms | none | CPU, connections, replication lag |

---

## What You Learned

| Concept | Terraform Feature | DBA Analogy |
|---|---|---|
| Aurora cluster | `aws_rds_cluster` | Shared storage cluster (primary + replicas) |
| Cluster instances | `aws_rds_cluster_instance` | Individual compute nodes |
| Writer endpoint | Cluster endpoint | Primary connection string |
| Reader endpoint | Reader endpoint | Load-balanced replica connection |
| `count` | Create N resources | `generate_series()` |
| `for_each` | Create resources from a map | Iterating over a lookup table |
| Provisioners | `local-exec` / `remote-exec` | Post-deploy scripts / triggers |
| Conditionals | `count = condition ? 1 : 0` | `CASE WHEN` for resources |
| Import | `terraform import` | `pg_dump` for existing infrastructure |
| Cost tagging | Resource tags | Tracking who owns what |
| Production hardening | `prevent_destroy`, encryption, etc. | DBA best practices for production |

---

**Next:** Move on to the [USE exercises](../use/01-terraform-exercises.md) to practice everything you have learned, or review the [concepts reference](../concepts/terraform-for-databases.md) for a quick-reference guide.
