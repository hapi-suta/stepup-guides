# BUILD 02: Provisioning AWS RDS with Terraform

**Module:** DBA Automation & DevOps - Module 01
**Lab Type:** AWS (requires an AWS account - resources will cost money while running)
**Time Estimate:** 60-75 minutes
**Prerequisites:** BUILD 01 completed, AWS account with admin access, AWS CLI installed

**COST WARNING:** RDS instances cost money. A db.t3.micro instance costs roughly $0.02/hour. Always run `terraform destroy` when you finish this lab. Do not leave resources running overnight.

---

## What You Will Build

A production-style PostgreSQL RDS instance in AWS - complete with VPC, security groups, subnet groups, and a custom parameter group. All defined as code, all repeatable, all destroyable with a single command.

---

## Step 1: Configure AWS Credentials

Terraform needs permission to create resources in your AWS account. The safest way is through environment variables - never hardcode credentials in `.tf` files.

**In your Mac terminal:**

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
export AWS_SECRET_ACCESS_KEY="your-secret-key-here"
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

**Never put credentials in `.tf` files.** If you see `access_key = "AKIA..."` in someone's Terraform code, that is the equivalent of hardcoding a database password in application source code. Environment variables or AWS profiles are the correct approach.

---

## Step 2: Understand VPC Basics for DBAs

Before we create an RDS instance, we need to understand where it lives on the network. In the on-prem world, you know this as "which datacenter, which VLAN, which subnet." AWS calls its version a VPC.

| On-Prem / DBA Concept | AWS Equivalent |
|---|---|
| Your datacenter | VPC (Virtual Private Cloud) |
| Network VLAN / subnet | Subnet |
| Server rack location | Availability Zone (AZ) |
| Firewall rules | Security Group |
| `pg_hba.conf` entries | Security Group ingress rules |
| Datacenter has multiple rooms | VPC has multiple subnets across AZs |

A VPC is an isolated network in AWS. Your RDS instance lives inside it. Security groups control who can connect - exactly like `pg_hba.conf` controls which IPs can connect to PostgreSQL.

RDS requires subnets in at least 2 different Availability Zones. Even if you are deploying a single instance, AWS wants the option to fail over.

---

## Step 3: Create the Project Structure

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/lab02-rds
```

```bash
cd ~/terraform-labs/lab02-rds
```

We will create several files. Here is the plan:

| File | Purpose |
|---|---|
| `providers.tf` | AWS provider configuration |
| `variables.tf` | Input variables |
| `vpc.tf` | Network infrastructure |
| `security.tf` | Security group (pg_hba.conf equivalent) |
| `rds.tf` | The RDS instance itself |
| `outputs.tf` | Connection info to display after creation |
| `terraform.tfvars` | Variable values for this lab |

---

## Step 4: Configure the AWS Provider

**In `~/terraform-labs/lab02-rds`:**

```bash
vi providers.tf
```

Enter insert mode (`i`) and type:

```hcl
# providers.tf - Tell Terraform we are working with AWS
# This is like configuring which database engine you are connecting to

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
# We only specify the region here
provider "aws" {
  region = var.aws_region
}
```

Save and exit (`:wq`).

The `~> 5.0` version constraint means "any 5.x version but not 6.0". This is like pinning your PostgreSQL major version - you want patch updates but not surprise major version upgrades.

---

## Step 5: Define Variables

**In `~/terraform-labs/lab02-rds`:**

```bash
vi variables.tf
```

Enter insert mode (`i`) and type:

```hcl
# variables.tf - All configurable parameters for this RDS deployment

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

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true  # Terraform will not display this in output
}

variable "db_instance_class" {
  description = "RDS instance size (like choosing server hardware)"
  type        = string
  default     = "db.t3.micro"  # Smallest/cheapest for lab work
}

variable "db_engine_version" {
  description = "PostgreSQL version to deploy"
  type        = string
  default     = "16.4"
}

variable "db_allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20  # Minimum for gp3
}

variable "my_ip" {
  description = "Your public IP address for security group access (CIDR format)"
  type        = string
  # You will set this in terraform.tfvars
}
```

Save and exit (`:wq`).

Notice the `sensitive = true` on the password variable. This tells Terraform to mask it in plan/apply output - like how PostgreSQL masks passwords in `pg_stat_activity`.

---

## Step 6: Create the VPC and Networking

**In `~/terraform-labs/lab02-rds`:**

```bash
vi vpc.tf
```

Enter insert mode (`i`) and type:

```hcl
# vpc.tf - Network infrastructure
# Think of this as building out the datacenter before you rack the database server

# The VPC is your isolated network - like your own private datacenter
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"  # 65,536 IP addresses
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Subnets are subdivisions of your VPC - like different rooms in the datacenter
# RDS requires subnets in at least 2 Availability Zones for failover capability

resource "aws_subnet" "db_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"  # 256 IPs in AZ-a
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-db-subnet-a"
  }
}

resource "aws_subnet" "db_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"  # 256 IPs in AZ-b
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-db-subnet-b"
  }
}

# Internet Gateway - allows traffic in/out of the VPC
# Without this, nothing in the VPC can reach the internet (or be reached)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route table - tells traffic where to go
# 0.0.0.0/0 -> IGW means "all internet traffic goes through the gateway"
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

# Associate subnets with the route table
resource "aws_route_table_association" "subnet_a" {
  subnet_id      = aws_subnet.db_subnet_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet_b" {
  subnet_id      = aws_subnet.db_subnet_b.id
  route_table_id = aws_route_table.main.id
}

# DB Subnet Group - tells RDS which subnets it can use
# Analogy: which server racks are approved for database servers
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.db_subnet_a.id, aws_subnet.db_subnet_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}
```

Save and exit (`:wq`).

---

## Step 7: Create the Security Group (pg_hba.conf as Code)

This is the part DBAs will immediately recognize. A security group is `pg_hba.conf` at the network level.

**In `~/terraform-labs/lab02-rds`:**

```bash
vi security.tf
```

Enter insert mode (`i`) and type:

```hcl
# security.tf - Network access control
# This is your pg_hba.conf, but at the AWS network level
#
# pg_hba.conf says:   host  all  all  192.168.1.0/24  scram-sha-256
# Security group says: allow TCP port 5432 from 192.168.1.0/24

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL - controls network access"
  vpc_id      = aws_vpc.main.id

  # Ingress rule = inbound traffic allowed
  # This is like a pg_hba.conf line that says "allow connections from this IP"
  ingress {
    description = "PostgreSQL access from my IP"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]  # /32 = single IP address
  }

  # Egress rule = outbound traffic allowed
  # RDS needs to reach out for things like DNS resolution
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}
```

Save and exit (`:wq`).

Compare the mental model:

```
# pg_hba.conf
host    all    dbadmin    203.0.113.50/32    scram-sha-256

# Terraform security group (same thing, network level)
ingress {
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  cidr_blocks = ["203.0.113.50/32"]
}
```

---

## Step 8: Create the RDS Instance

This is the main event - the database itself.

**In `~/terraform-labs/lab02-rds`:**

```bash
vi rds.tf
```

Enter insert mode (`i`) and type:

```hcl
# rds.tf - The PostgreSQL RDS instance
# This is the equivalent of provisioning a new database server

# Parameter group = postgresql.conf as code
# Instead of SSHing into a server and editing postgresql.conf,
# you declare the settings here and Terraform manages them
resource "aws_db_parameter_group" "postgres" {
  family = "postgres16"
  name   = "${var.project_name}-pg-params"

  # Each parameter block is like a line in postgresql.conf
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"  # Some params need a restart, just like PostgreSQL
  }

  tags = {
    Name = "${var.project_name}-pg-params"
  }
}

# The RDS instance itself
resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"  # General purpose SSD

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true  # Lab only! Never in production.

  # Parameter group (our postgresql.conf)
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Backup configuration
  backup_retention_period = 7       # Keep backups for 7 days
  backup_window           = "03:00-04:00"  # UTC - run backups at 3 AM

  # Maintenance window
  maintenance_window = "sun:04:00-sun:05:00"  # UTC

  # Lab settings - DO NOT use these in production
  skip_final_snapshot = true   # Do not create a snapshot when destroying
  deletion_protection = false  # Allow terraform destroy to work

  tags = {
    Name        = "${var.project_name}-postgres"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
```

Save and exit (`:wq`).

Key points for DBAs:

- `parameter_group_name` - This IS your `postgresql.conf`, managed as code
- `backup_retention_period` - Automated daily backups, no cron jobs needed
- `skip_final_snapshot = true` - Lab only. In production, you always want a final snapshot before deletion
- `deletion_protection = false` - Lab only. In production, set to `true` so nobody can accidentally destroy it
- `publicly_accessible = true` - Lab only. In production, your RDS should be in a private subnet

---

## Step 9: Define Outputs (Connection Information)

**In `~/terraform-labs/lab02-rds`:**

```bash
vi outputs.tf
```

Enter insert mode (`i`) and type:

```hcl
# outputs.tf - Display useful information after creation
# Like RETURNING clause - gives you what you need to connect

output "rds_endpoint" {
  description = "RDS instance endpoint (hostname:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_hostname" {
  description = "RDS instance hostname only"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "Name of the default database"
  value       = aws_db_instance.postgres.db_name
}

output "rds_username" {
  description = "Master username"
  value       = aws_db_instance.postgres.username
}

output "connection_command" {
  description = "psql command to connect (add your password)"
  value       = "psql -h ${aws_db_instance.postgres.address} -p ${aws_db_instance.postgres.port} -U ${aws_db_instance.postgres.username} -d ${aws_db_instance.postgres.db_name}"
}

output "vpc_id" {
  description = "VPC ID where RDS lives"
  value       = aws_vpc.main.id
}

output "security_group_id" {
  description = "Security group ID controlling RDS access"
  value       = aws_security_group.rds.id
}
```

Save and exit (`:wq`).

---

## Step 10: Set Variable Values

First, find your public IP address:

**In your Mac terminal:**

```bash
curl -s https://checkip.amazonaws.com
```

Expected output (yours will differ):

```
203.0.113.50
```

Now create the tfvars file with your values:

**In `~/terraform-labs/lab02-rds`:**

```bash
vi terraform.tfvars
```

Enter insert mode (`i`) and type (replace the IP with yours from the previous command):

```hcl
# terraform.tfvars - Variable values for this lab
# This file is automatically loaded by Terraform

aws_region           = "us-east-1"
project_name         = "dba-lab"
db_name              = "labdb"
db_username          = "dbadmin"
db_password          = "ChangeMe123!"  # Lab only - use secrets manager in production
db_instance_class    = "db.t3.micro"
db_engine_version    = "16.4"
db_allocated_storage = 20
my_ip                = "203.0.113.50"  # Replace with YOUR IP from curl command above
```

Save and exit (`:wq`).

**Important:** In a real project, you would NEVER put `db_password` in a `.tfvars` file that gets committed to Git. You would use AWS Secrets Manager, environment variables (`TF_VAR_db_password`), or a secrets management tool. For this lab, it is fine.

---

## Step 11: Initialize and Plan

**In `~/terraform-labs/lab02-rds`:**

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.72.1...
- Installed hashicorp/aws v5.72.1 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Now preview what Terraform will create:

```bash
terraform plan
```

Expected output (yours will differ):

```
Terraform will perform the following actions:

  # aws_db_instance.postgres will be created
  + resource "aws_db_instance" "postgres" {
      + address                    = (known after apply)
      + allocated_storage          = 20
      + engine                     = "postgres"
      + engine_version             = "16.4"
      + identifier                 = "dba-lab-postgres"
      + instance_class             = "db.t3.micro"
      ...
    }

  # aws_db_parameter_group.postgres will be created
  # aws_db_subnet_group.main will be created
  # aws_internet_gateway.main will be created
  # aws_route_table.main will be created
  # aws_route_table_association.subnet_a will be created
  # aws_route_table_association.subnet_b will be created
  # aws_security_group.rds will be created
  # aws_subnet.db_subnet_a will be created
  # aws_subnet.db_subnet_b will be created
  # aws_vpc.main will be created

Plan: 11 to add, 0 to change, 0 to destroy.
```

Read that plan carefully. 11 resources will be created. This is like reviewing a migration script before running it on production. Make sure everything looks right.

---

## Step 12: Apply - Create the RDS Instance

**In `~/terraform-labs/lab02-rds`:**

```bash
terraform apply
```

Review the plan one more time, then type `yes` when prompted.

**This will take 5-10 minutes.** RDS instance creation is not instant - AWS is provisioning a server, installing PostgreSQL, configuring networking, and setting up automated backups. You will see progress updates:

Expected output (yours will differ):

```
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 2s [id=vpc-0abc123...]
aws_subnet.db_subnet_a: Creating...
aws_subnet.db_subnet_b: Creating...
...
aws_db_instance.postgres: Creating...
aws_db_instance.postgres: Still creating... [2m0s elapsed]
aws_db_instance.postgres: Still creating... [4m0s elapsed]
aws_db_instance.postgres: Still creating... [6m0s elapsed]
aws_db_instance.postgres: Creation complete after 7m32s [id=dba-lab-postgres]

Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

connection_command = "psql -h dba-lab-postgres.abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d labdb"
rds_endpoint = "dba-lab-postgres.abc123.us-east-1.rds.amazonaws.com:5432"
rds_hostname = "dba-lab-postgres.abc123.us-east-1.rds.amazonaws.com"
...
```

---

## Step 13: Connect to Your New RDS Instance

Copy the connection command from the output and run it:

**In your Mac terminal:**

```bash
psql -h dba-lab-postgres.abc123.us-east-1.rds.amazonaws.com -p 5432 -U dbadmin -d labdb
```

(Replace the hostname with your actual output.)

Enter the password when prompted (`ChangeMe123!`).

Expected output:

```
psql (16.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384)
Type "help" for help.

labdb=>
```

Run some familiar commands to verify everything is configured:

```sql
SELECT version();
```

```sql
SHOW shared_preload_libraries;
```

Expected output:

```
 shared_preload_libraries
--------------------------
 pg_stat_statements
```

That setting came from our Terraform parameter group - `postgresql.conf` as code, working as expected.

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 all
```

Disconnect when done:

```sql
\q
```

---

## Step 14: Destroy Everything (Critical!)

**Do not skip this step.** RDS instances cost money every hour they run.

**In `~/terraform-labs/lab02-rds`:**

```bash
terraform destroy
```

Review the destruction plan. You should see all 11 resources marked for deletion. Type `yes` when prompted.

Expected output (yours will differ):

```
aws_db_instance.postgres: Destroying... [id=dba-lab-postgres]
aws_db_instance.postgres: Still destroying... [1m0s elapsed]
aws_db_instance.postgres: Still destroying... [2m0s elapsed]
aws_db_instance.postgres: Destruction complete after 3m15s
aws_db_parameter_group.postgres: Destroying...
aws_security_group.rds: Destroying...
...
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 11 destroyed.
```

Verify in the AWS Console if you want - the RDS instance, VPC, and all associated resources are gone.

**Always destroy lab resources when you are done.** Get in the habit now. Forgotten RDS instances are how you get surprise AWS bills.

---

## Step 15: Verify Cleanup

Double check that no resources are left:

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
| Security Group | `aws_security_group` | `pg_hba.conf` at the network level |
| Subnet Group | `aws_db_subnet_group` | Which racks/zones are approved for databases |
| Parameter Group | `aws_db_parameter_group` | `postgresql.conf` as code |
| RDS Instance | `aws_db_instance` | The database server itself |
| `sensitive = true` | Variable flag | Masks passwords in output |
| Destroy workflow | `terraform destroy` | Decommission all infrastructure |
| Cost awareness | Always destroy labs | Cloud resources cost money when running |

---

**Next:** [BUILD 03 - Terraform Modules and State Management](03-modules-and-state.md) - Learn to create reusable infrastructure packages and manage state across teams.
