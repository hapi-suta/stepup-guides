# BUILD 03: Modules and State Management

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** LOCAL + AWS (module creation is local, deployment is AWS)
**Time Estimate:** 45 minutes
**Prerequisites:** BUILD 01 and BUILD 02 completed

---

## What You Will Build

You will take the Aurora configuration from BUILD 02 and refactor it into a reusable **module** - Terraform's version of a stored procedure. Then you will set up remote state storage with S3 and learn the essential state management commands.

---

## Step 1: Understand Modules

In PostgreSQL, when you find yourself writing the same query repeatedly, you create a function:

```sql
CREATE FUNCTION create_aurora_cluster(cluster_name TEXT, env TEXT)
RETURNS void AS $$
BEGIN
  -- Create parameter groups, security groups, cluster, instances...
END;
$$ LANGUAGE plpgsql;
```

Now you call `SELECT create_aurora_cluster('myapp', 'dev');` instead of repeating all those statements.

**Terraform modules are the same idea.** Instead of copying VPC + security group + Aurora configuration every time you need a database cluster, you bundle them into a module and call it with parameters:

```hcl
module "app_database" {
  source         = "./modules/aurora"
  cluster_name   = "myapp"
  environment    = "dev"
  instance_class = "db.t3.medium"
}
```

| PostgreSQL | Terraform Modules |
|---|---|
| `CREATE FUNCTION` | Module directory with `.tf` files |
| Function parameters | Module `variable` blocks (inputs) |
| `RETURNS` / `OUT` params | Module `output` blocks |
| `SELECT my_function(args)` | `module "name" { source = "..." }` |
| Schema for organization | Module directory structure |

---

## Step 2: Create the Module Directory Structure

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab03-modules/modules/aurora
```

```bash
cd ~/terraform-labs/lab03-modules
```

The structure will be:

```
lab03-modules/
  main.tf              # Calls the module (like calling a function)
  variables.tf         # Top-level variables
  outputs.tf           # Top-level outputs
  providers.tf         # Provider configuration
  terraform.tfvars     # Variable values
  modules/
    aurora/            # The module itself (like a function definition)
      main.tf          # VPC + SG + Aurora resources
      variables.tf     # Module input parameters
      outputs.tf       # Module return values
```

---

## Step 3: Build the Module - Variables (Input Parameters)

**In `~/terraform-labs/lab03-modules/modules/aurora`:**

```bash
vi ~/terraform-labs/lab03-modules/modules/aurora/variables.tf
```

Press `i` to enter insert mode and type:

```hcl
# modules/aurora/variables.tf
# These are the function parameters - what the caller must provide

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
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

variable "instance_class" {
  description = "Aurora instance type (db.t3.medium minimum)"
  type        = string
  default     = "db.t3.medium"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "reader_count" {
  description = "Number of read replicas"
  type        = number
  default     = 1
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect (like pg_hba.conf entries)"
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "custom_cluster_parameters" {
  description = "Map of custom cluster parameter group settings"
  type        = map(string)
  default     = {}
}

variable "custom_instance_parameters" {
  description = "Map of custom instance parameter group settings"
  type        = map(string)
  default     = {}
}
```

Save and exit (`:wq`).

---

## Step 4: Build the Module - Main Resources

**In `~/terraform-labs/lab03-modules/modules/aurora`:**

```bash
vi ~/terraform-labs/lab03-modules/modules/aurora/main.tf
```

Press `i` to enter insert mode and type:

```hcl
# modules/aurora/main.tf
# The module body - all resources bundled together

# --- Networking ---

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-b"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.this.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.this.id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-aurora-subnets"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-subnets"
  }
}

# --- Security Group ---

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-sg"
  description = "Controls access to Aurora PostgreSQL"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "PostgreSQL from ${ingress.value}"
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

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  }
}

# --- Parameter Groups ---

resource "aws_rds_cluster_parameter_group" "this" {
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

  dynamic "parameter" {
    for_each = var.custom_cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster-params"
  }
}

resource "aws_db_parameter_group" "this" {
  family = "aurora-postgresql16"
  name   = "${var.project_name}-${var.environment}-instance-params"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  dynamic "parameter" {
    for_each = var.custom_instance_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-instance-params"
  }
}

# --- Aurora Cluster ---

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  database_name   = var.db_name
  master_username = var.db_username
  master_password = var.db_password

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  backup_retention_period = var.backup_retention_period
  storage_encrypted       = true
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-aurora"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-${var.environment}-writer"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name
  publicly_accessible     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-writer"
    Role = "writer"
  }
}

# Reader instances
resource "aws_rds_cluster_instance" "readers" {
  count = var.reader_count

  identifier         = "${var.project_name}-${var.environment}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name
  publicly_accessible     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-reader-${count.index + 1}"
    Role = "reader"
  }
}
```

Save and exit (`:wq`).

---

## Step 5: Build the Module - Outputs (Return Values)

```bash
vi ~/terraform-labs/lab03-modules/modules/aurora/outputs.tf
```

Press `i` to enter insert mode and type:

```hcl
# modules/aurora/outputs.tf
# Return values - like OUT parameters or RETURNING clause

output "cluster_endpoint" {
  description = "Aurora cluster endpoint (writer)"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Aurora reader endpoint (load-balanced)"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Aurora port"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.this.database_name
}

output "username" {
  description = "Master username"
  value       = aws_rds_cluster.this.master_username
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.aurora.id
}

output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}
```

Save and exit (`:wq`).

---

## Step 6: Call the Module from Your Root Configuration

Now write the "caller" - the code that invokes the module, like calling a stored procedure.

```bash
vi ~/terraform-labs/lab03-modules/providers.tf
```

Press `i` to enter insert mode and type:

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
vi ~/terraform-labs/lab03-modules/variables.tf
```

Press `i` to enter insert mode and type:

```hcl
# variables.tf - Top-level variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Your public IP address"
  type        = string
}
```

Save and exit (`:wq`).

```bash
vi ~/terraform-labs/lab03-modules/main.tf
```

Press `i` to enter insert mode and type:

```hcl
# main.tf - Calling the module
# This is like: SELECT * FROM create_aurora_cluster('myapp', 'dev');

module "dev_database" {
  source = "./modules/aurora"

  # Module inputs (function arguments)
  project_name = "dba-lab"
  environment  = "dev"
  aws_region   = var.aws_region

  db_name     = "devdb"
  db_username = "dbadmin"
  db_password = var.db_password

  instance_class = "db.t3.medium"
  reader_count   = 1

  allowed_cidr_blocks = ["${var.my_ip}/32"]

  # Custom postgresql.conf parameters
  custom_instance_parameters = {
    "log_min_duration_statement" = "1000"
  }
}

# Want a staging database too? Just call the module again:
#
# module "staging_database" {
#   source = "./modules/aurora"
#
#   project_name = "dba-lab"
#   environment  = "staging"
#   aws_region   = var.aws_region
#
#   db_name       = "stagingdb"
#   db_username   = "dbadmin"
#   db_password   = var.db_password
#   instance_class = "db.t3.medium"
#   reader_count   = 2
#
#   allowed_cidr_blocks = ["${var.my_ip}/32"]
# }
```

Save and exit (`:wq`).

```bash
vi ~/terraform-labs/lab03-modules/outputs.tf
```

Press `i` to enter insert mode and type:

```hcl
# outputs.tf - Surface module outputs at the top level

output "dev_cluster_endpoint" {
  description = "Dev Aurora cluster endpoint"
  value       = module.dev_database.cluster_endpoint
}

output "dev_reader_endpoint" {
  description = "Dev Aurora reader endpoint"
  value       = module.dev_database.reader_endpoint
}

output "dev_writer_connection" {
  description = "psql command to connect to dev writer"
  value       = "psql -h ${module.dev_database.cluster_endpoint} -p ${module.dev_database.port} -U ${module.dev_database.username} -d ${module.dev_database.database_name}"
}
```

Save and exit (`:wq`).

```bash
vi ~/terraform-labs/lab03-modules/terraform.tfvars
```

Press `i` to enter insert mode and type:

```hcl
aws_region  = "us-east-1"
db_password = "ChangeMe123!"
my_ip       = "203.0.113.50"
```

Save and exit (`:wq`).

---

## Step 7: Initialize and Plan the Module

**In `~/terraform-labs/lab03-modules`:**

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...
Initializing modules...
- dev_database in modules/aurora
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.72.1...

Terraform has been successfully initialized!
```

Notice the line `Initializing modules... - dev_database in modules/aurora`. Terraform found and loaded your module.

```bash
terraform plan
```

The plan shows resources prefixed with `module.dev_database.` to show they come from the module:

Expected output (yours will differ):

```
  # module.dev_database.aws_rds_cluster.this will be created
  # module.dev_database.aws_rds_cluster_instance.writer will be created
  # module.dev_database.aws_rds_cluster_instance.readers[0] will be created
  # module.dev_database.aws_vpc.this will be created
  ...

Plan: 15 to add, 0 to change, 0 to destroy.
```

**Do not apply this unless you want to incur AWS costs.** The point of this step is to verify the module works.

---

## Step 8: Understand Remote State

So far, your `terraform.tfstate` lives on your local machine. This works for solo projects, but what happens when a team manages the same infrastructure?

| Scenario | Problem |
|---|---|
| State on your laptop | Teammate runs `terraform apply` with their own state - resources get duplicated |
| State in Git | Merge conflicts in JSON. Secrets in version control |

The solution is **remote state** - store the state file in a shared location. For AWS, the standard is S3 + DynamoDB.

| Local State | Remote State (S3) |
|---|---|
| State file on disk | State file in S3 bucket |
| Only you can see it | Whole team shares it |
| No locking | DynamoDB provides locking |
| Like a local SQLite DB | Like a shared PostgreSQL server |

The DynamoDB lock works like **advisory locks** in PostgreSQL. When you run `terraform apply`, it acquires a lock. If a teammate tries to run `terraform apply` at the same time, they get an error saying the state is locked.

---

## Step 9: Remote State Backend Configuration (Reference)

This step shows you the configuration. **Do not apply this unless you have an S3 bucket and DynamoDB table already created.**

The backend configuration goes in `providers.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-company-terraform-state"
    key            = "aurora/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

| Backend Setting | Purpose | DBA Analogy |
|---|---|---|
| `bucket` | S3 bucket name | Database server hostname |
| `key` | Path within the bucket | Schema + table name |
| `region` | AWS region | Datacenter location |
| `dynamodb_table` | Lock table | Advisory lock mechanism |
| `encrypt` | Encrypt state at rest | Like TDE for your state file |

After adding a backend, run `terraform init` again. Terraform will ask if you want to migrate your local state to S3.

---

## Step 10: State Management Commands

These are the DBA's toolkit for state operations. Practice them on your local project.

### terraform state list

Lists all resources Terraform manages. Like `\dt` in psql.

**In `~/terraform-labs/lab01-basics` (from BUILD 01 - recreate resources first if destroyed):**

```bash
terraform state list
```

Expected output:

```
local_file.dynamic_file
local_file.hello_terraform
```

### terraform state show

Shows all attributes of a single resource. Like `\d+ tablename` in psql.

```bash
terraform state show local_file.hello_terraform
```

Expected output (yours will differ):

```
# local_file.hello_terraform:
resource "local_file" "hello_terraform" {
    content              = "Hello from Terraform!..."
    directory_permission = "0777"
    file_permission      = "0777"
    filename             = "./hello.txt"
    id                   = "a1b2c3d4..."
}
```

### terraform state mv

Renames a resource in state. Like `ALTER TABLE RENAME`. Use this when you rename a resource block in your `.tf` file and do not want Terraform to destroy and recreate it.

```bash
terraform state mv local_file.hello_terraform local_file.greeting
```

Expected output:

```
Move "local_file.hello_terraform" to "local_file.greeting"
Successfully moved 1 object(s).
```

**Important:** After `state mv`, you must also update your `.tf` file to use the new name. Otherwise, `terraform plan` will try to create a resource with the old name and destroy one with the new name.

### terraform state rm

Removes a resource from state WITHOUT deleting it from reality. Like telling Terraform "forget this resource exists."

```bash
terraform state rm local_file.greeting
```

Expected output:

```
Removed local_file.greeting
Successfully removed 1 resource instance(s).
```

The file still exists on disk, but Terraform no longer manages it. Running `terraform plan` now shows it as a new resource to create.

---

## Step 11: Clean Up

If you applied the module in Step 7, destroy it:

**In `~/terraform-labs/lab03-modules`:**

```bash
terraform destroy
```

Type `yes` when prompted.

---

## What You Learned

| Concept | Terraform Feature | DBA Analogy |
|---|---|---|
| Reusable infrastructure | Modules | Stored procedures / functions |
| Module inputs | `variable` blocks in module | Function parameters |
| Module outputs | `output` blocks in module | Function return values |
| Calling a module | `module "name" { source = "..." }` | `SELECT my_function(args)` |
| Shared state | S3 backend | Shared database vs local file |
| State locking | DynamoDB table | Advisory locks (`pg_advisory_lock`) |
| List resources | `terraform state list` | `\dt` in psql |
| Inspect resource | `terraform state show` | `\d+ tablename` |
| Rename in state | `terraform state mv` | `ALTER TABLE RENAME` |
| Remove from state | `terraform state rm` | Remove from catalog without dropping |

---

**Next:** [BUILD 04 - Aurora Advanced Patterns](04-aurora-advanced-patterns.md) - Learn for_each, conditionals, dynamic blocks, and data sources.
