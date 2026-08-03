# BUILD 02: Provision Aurora with Terraform

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** AWS (requires an AWS account - resources will cost money while running)
**Time Estimate:** 60 minutes
**Prerequisites:** BUILD 01 completed, AWS account with admin access, AWS CLI installed

**COST WARNING:** Aurora clusters cost more than single RDS instances. A db.t3.medium Aurora instance costs roughly $0.07/hour per instance. A cluster with a writer + 1 reader = $0.14/hour. Always run `terraform destroy` when you finish this lab. Do not leave resources running overnight.

---

## What You Will Build

A production-style Aurora PostgreSQL cluster in AWS - complete with VPC, subnets, security groups, subnet group, parameter groups (cluster and instance level), an Aurora cluster, a writer instance, and a reader instance. All defined as code, all repeatable, all destroyable with a single command.

---

## Step 1: Configure AWS Credentials

Terraform needs permission to create resources in your AWS account. The safest way is through environment variables - never hardcode credentials in `.tf` files.

**In your terminal:**

First, confirm you have the AWS CLI installed:

```bash
aws --version
```

Expected output (yours will differ):

```
aws-cli/2.17.x Python/3.11.x Darwin/24.6.0 source/arm64
```

If you do not have it, install it:

```bash
brew install awscli
```

Now set your AWS credentials as environment variables. Replace the placeholder values with your actual credentials:

```bash
export AWS_ACCESS_KEY_ID="your-access-key-here"
```

```bash
export AWS_SECRET_ACCESS_KEY="your-secret-key-here"
```

```bash
export AWS_DEFAULT_REGION="us-east-1"
```

Verify they work:

```bash
aws sts get-caller-identity
```

Expected output (yours will differ):

```json
{
    "UserId": "AIDAEXAMPLEID",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

**Never put credentials in `.tf` files.** If you see `access_key = "AKIA..."` in someone's Terraform code, that is the equivalent of hardcoding a database password in application source code.

---

## Step 2: Create the Project Structure

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab02-aurora
```

```bash
cd ~/terraform-labs/lab02-aurora
```

We will create several files:

| File | Purpose |
|---|---|
| `providers.tf` | AWS provider configuration |
| `variables.tf` | Input variables |
| `vpc.tf` | Network infrastructure (VPC, subnets, routing) |
| `security.tf` | Security group (pg_hba.conf equivalent) |
| `aurora.tf` | Aurora cluster, parameter groups, and instances |
| `outputs.tf` | Connection info to display after creation |
| `terraform.tfvars` | Variable values for this lab |

---

## Step 3: Configure the AWS Provider

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/providers.tf
```

Press `i` to enter insert mode and type:

```hcl
# providers.tf - Tell Terraform we are working with AWS

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# The provider block configures HOW to connect to AWS
# Credentials come from environment variables (AWS_ACCESS_KEY_ID, etc.)
provider "aws" {
  region = var.aws_region
}
```

Save and exit (`:wq`).

The `~> 5.0` version constraint means "any 5.x version but not 6.0". This is like pinning your PostgreSQL major version - you want patch updates but not surprise major version upgrades.

---

## Step 4: Define Variables

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/variables.tf
```

Press `i` to enter insert mode and type:

```hcl
# variables.tf - All configurable parameters for this Aurora deployment

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources (like a schema name)"
  type        = string
  default     = "dba-lab"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "auroradb"
}

variable "db_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "cluster_id" {
  description = "Unique identifier for the Aurora cluster"
  type        = string
  default     = "dba-lab-aurora"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Aurora instance size (db.t3.medium is the minimum for Aurora)"
  type        = string
  default     = "db.t3.medium"
}

variable "my_ip" {
  description = "Your public IP address for security group access (without /32)"
  type        = string
}
```

Save and exit (`:wq`).

Notice the `sensitive = true` on the password variable. This tells Terraform to mask it in plan/apply output - like how PostgreSQL masks passwords in `pg_stat_activity`.

---

## Step 5: Create the VPC and Networking

Aurora needs a VPC (Virtual Private Cloud) to live in. This is your isolated network - like your own private datacenter.

| On-Prem / DBA Concept | AWS Equivalent |
|---|---|
| Your datacenter | VPC (Virtual Private Cloud) |
| Network VLAN / subnet | Subnet |
| Server rack location | Availability Zone (AZ) |
| Firewall rules | Security Group |
| `pg_hba.conf` entries | Security Group ingress rules |

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/vpc.tf
```

Press `i` to enter insert mode and type:

```hcl
# vpc.tf - Network infrastructure
# Think of this as building out the datacenter before you rack the database server

# The VPC is your isolated network
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# Subnets in different Availability Zones
# Aurora requires subnets in at least 2 AZs for failover capability
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

# Internet Gateway - allows traffic in/out of the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# Route table - tells traffic where to go
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

# Associate each subnet with the route table
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

# DB Subnet Group - tells Aurora which subnets it can use
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
```

Save and exit (`:wq`).

---

## Step 6: Create the Security Group

This is the part DBAs will immediately recognize. A security group is `pg_hba.conf` at the network level.

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/security.tf
```

Press `i` to enter insert mode and type:

```hcl
# security.tf - Network access control
# This is your pg_hba.conf, but at the AWS network level

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-sg"
  description = "Controls network access to Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id

  # Ingress rule = inbound traffic allowed
  # Like a pg_hba.conf line: host all all <your-ip>/32 scram-sha-256
  ingress {
    description = "PostgreSQL access from my IP"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # Egress rule = outbound traffic allowed
  egress {
    description = "Allow all outbound traffic"
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

## Step 7: Create the Aurora Cluster and Instances

Aurora has two levels of resources:

- **Cluster** - shared storage, cluster-level configuration, endpoints
- **Cluster instances** - compute nodes that attach to the cluster (writer and readers)

| Aurora Concept | PostgreSQL Analogy |
|---|---|
| Cluster | Shared storage + configuration |
| Writer instance | Primary server |
| Reader instance | Read replica |
| Cluster endpoint | Primary connection string |
| Reader endpoint | Load-balanced replica connection string |

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/aurora.tf
```

Press `i` to enter insert mode and type:

```hcl
# aurora.tf - Aurora PostgreSQL cluster and instances

# Cluster parameter group - settings that apply to the entire cluster
# Like postgresql.conf settings that affect replication behavior
resource "aws_rds_cluster_parameter_group" "aurora" {
  family = "aurora-postgresql16"
  name   = "${var.project_name}-${var.environment}-cluster-params"

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
    Name = "${var.project_name}-${var.environment}-cluster-params"
  }
}

# Instance parameter group - settings for individual instances
# Like instance-specific postgresql.conf overrides
resource "aws_db_parameter_group" "aurora" {
  family = "aurora-postgresql16"
  name   = "${var.project_name}-${var.environment}-instance-params"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-instance-params"
  }
}

# The Aurora cluster itself - shared storage and cluster-level config
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.cluster_id
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

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

  # Storage encryption (always enable, even in labs)
  storage_encrypted = true

  # Lab settings - DO NOT use these in production
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name        = var.cluster_id
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Writer instance - the primary node
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.cluster_id}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name
  publicly_accessible     = true

  tags = {
    Name = "${var.cluster_id}-writer"
    Role = "writer"
  }
}

# Reader instance - the read replica
resource "aws_rds_cluster_instance" "reader" {
  identifier         = "${var.cluster_id}-reader-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name
  publicly_accessible     = true

  tags = {
    Name = "${var.cluster_id}-reader-1"
    Role = "reader"
  }
}
```

Save and exit (`:wq`).

Key points for DBAs:

- `aws_rds_cluster_parameter_group` - cluster-level `postgresql.conf`, managed as code
- `aws_db_parameter_group` - instance-level `postgresql.conf`, managed as code
- `apply_method = "pending-reboot"` - some parameters need a restart, just like PostgreSQL
- `storage_encrypted = true` - always encrypt, even in labs
- `skip_final_snapshot = true` - lab only. In production, always keep a final snapshot
- `deletion_protection = false` - lab only. In production, set to `true`
- `publicly_accessible = true` - lab only. In production, use a private subnet

---

## Step 8: Define Outputs

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/outputs.tf
```

Press `i` to enter insert mode and type:

```hcl
# outputs.tf - Connection information for the Aurora cluster

output "cluster_endpoint" {
  description = "Aurora cluster endpoint (connects to writer)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Aurora reader endpoint (load-balanced across readers)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.aurora.port
}

output "database_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.aurora.database_name
}

output "writer_connection" {
  description = "psql command to connect to the writer"
  value       = "psql -h ${aws_rds_cluster.aurora.endpoint} -p ${aws_rds_cluster.aurora.port} -U ${var.db_username} -d ${var.db_name}"
}

output "reader_connection" {
  description = "psql command to connect to a reader (load balanced)"
  value       = "psql -h ${aws_rds_cluster.aurora.reader_endpoint} -p ${aws_rds_cluster.aurora.port} -U ${var.db_username} -d ${var.db_name}"
}

output "vpc_id" {
  description = "VPC ID where Aurora lives"
  value       = aws_vpc.main.id
}

output "security_group_id" {
  description = "Security group ID controlling Aurora access"
  value       = aws_security_group.aurora.id
}
```

Save and exit (`:wq`).

---

## Step 9: Set Variable Values

First, find your public IP address:

```bash
curl -s https://checkip.amazonaws.com
```

Expected output (yours will differ):

```
203.0.113.50
```

Now create the tfvars file:

**In `~/terraform-labs/lab02-aurora`:**

```bash
vi ~/terraform-labs/lab02-aurora/terraform.tfvars
```

Press `i` to enter insert mode and type (replace the IP with yours):

```hcl
# terraform.tfvars - Variable values for this lab

aws_region     = "us-east-1"
project_name   = "dba-lab"
environment    = "dev"
db_name        = "auroradb"
db_username    = "dbadmin"
db_password    = "ChangeMe123!"
cluster_id     = "dba-lab-aurora"
engine_version = "16.4"
instance_class = "db.t3.medium"
my_ip          = "203.0.113.50"
```

Save and exit (`:wq`).

**Important:** In a real project, you would NEVER put `db_password` in a tfvars file committed to Git. Use AWS Secrets Manager, environment variables (`TF_VAR_db_password`), or `manage_master_user_password = true`. For this lab, it is fine.

---

## Step 10: Initialize and Review the Plan

**In `~/terraform-labs/lab02-aurora`:**

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

Now preview what Terraform will create:

```bash
terraform plan
```

Expected output (yours will differ):

```
  # aws_rds_cluster.aurora will be created
  # aws_rds_cluster_instance.writer will be created
  # aws_rds_cluster_instance.reader will be created
  # aws_rds_cluster_parameter_group.aurora will be created
  # aws_db_parameter_group.aurora will be created
  # aws_db_subnet_group.aurora will be created
  # aws_security_group.aurora will be created
  # aws_vpc.main will be created
  # aws_subnet.db_a will be created
  # aws_subnet.db_b will be created
  # aws_subnet.db_c will be created
  # aws_internet_gateway.main will be created
  # aws_route_table.main will be created
  # aws_route_table_association.a will be created
  # aws_route_table_association.b will be created
  # aws_route_table_association.c will be created

Plan: 16 to add, 0 to change, 0 to destroy.
```

Read that plan carefully. 16 resources will be created. This is like reviewing a migration script before running it on production. Make sure everything looks right before proceeding.

---

## Step 11: Apply - Create the Aurora Cluster

**In `~/terraform-labs/lab02-aurora`:**

```bash
terraform apply
```

Review the plan one more time, then type `yes` when prompted.

**This will take 10-15 minutes.** Aurora cluster creation is not instant - AWS is provisioning compute nodes, setting up the shared storage layer, configuring replication, and setting up automated backups. You will see progress updates:

Expected output (yours will differ):

```
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 2s [id=vpc-0abc123...]
aws_subnet.db_a: Creating...
aws_subnet.db_b: Creating...
aws_subnet.db_c: Creating...
...
aws_rds_cluster.aurora: Creating...
aws_rds_cluster.aurora: Still creating... [2m0s elapsed]
aws_rds_cluster.aurora: Creation complete after 3m12s
aws_rds_cluster_instance.writer: Creating...
aws_rds_cluster_instance.writer: Still creating... [5m0s elapsed]
aws_rds_cluster_instance.writer: Creation complete after 7m22s
aws_rds_cluster_instance.reader: Creating...
aws_rds_cluster_instance.reader: Creation complete after 6m45s

Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "dba-lab-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"
reader_endpoint = "dba-lab-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com"
writer_connection = "psql -h dba-lab-aurora.cluster-abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d auroradb"
...
```

---

## Step 12: Connect and Verify

Copy the writer connection command from the output and run it:

**In your terminal:**

```bash
psql -h dba-lab-aurora.cluster-abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d auroradb
```

(Replace the hostname with your actual output.)

Enter the password when prompted (`ChangeMe123!`).

Expected output:

```
psql (16.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384)
Type "help" for help.

auroradb=>
```

Verify you are on the writer:

```sql
SELECT pg_is_in_recovery();
```

Expected output:

```
 pg_is_in_recovery
-------------------
 f
```

`f` (false) means this is the primary/writer. Good.

Check parameter group settings:

```sql
SHOW shared_preload_libraries;
```

Expected output:

```
 shared_preload_libraries
--------------------------
 pg_stat_statements
```

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 all
```

These settings came from our Terraform parameter groups - `postgresql.conf` as code, working as expected.

Disconnect:

```sql
\q
```

Now connect to the reader endpoint and verify it is a read replica:

```bash
psql -h dba-lab-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d auroradb
```

```sql
SELECT pg_is_in_recovery();
```

Expected output:

```
 pg_is_in_recovery
-------------------
 t
```

`t` (true) means this is a reader/replica. The reader endpoint correctly routes to a read-only instance.

```sql
\q
```

---

## Step 13: Destroy Everything (Critical!)

**Do not skip this step.** Aurora instances cost money every hour they run.

**In `~/terraform-labs/lab02-aurora`:**

```bash
terraform destroy
```

Review the destruction plan. You should see all 16 resources marked for deletion. Type `yes` when prompted.

Expected output (yours will differ):

```
aws_rds_cluster_instance.reader: Destroying...
aws_rds_cluster_instance.writer: Destroying...
...
aws_rds_cluster.aurora: Destroying...
...
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 16 destroyed.
```

Verify no resources remain in state:

```bash
terraform state list
```

Expected output:

```
(empty - no output)
```

No resources in state means nothing is running and nothing is costing you money.

---

## What You Learned

| Concept | Terraform Resource | DBA Analogy |
|---|---|---|
| AWS provider | `provider "aws"` | Connection string to AWS |
| VPC | `aws_vpc` | Your datacenter network |
| Subnets | `aws_subnet` | Network segments / VLANs |
| Security Group | `aws_security_group` | `pg_hba.conf` at network level |
| Subnet Group | `aws_db_subnet_group` | Approved network zones for databases |
| Cluster Parameter Group | `aws_rds_cluster_parameter_group` | Cluster-level `postgresql.conf` |
| Instance Parameter Group | `aws_db_parameter_group` | Instance-level `postgresql.conf` |
| Aurora Cluster | `aws_rds_cluster` | Shared storage cluster |
| Writer Instance | `aws_rds_cluster_instance` | Primary server |
| Reader Instance | `aws_rds_cluster_instance` | Read replica |
| Cluster Endpoint | Output value | Primary connection string |
| Reader Endpoint | Output value | Load-balanced replica connection |

---

**Next:** [BUILD 03 - Modules and State](03-modules-and-state.md) - Create reusable infrastructure modules and manage state across teams.
