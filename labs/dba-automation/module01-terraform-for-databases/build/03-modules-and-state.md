# BUILD 03: Terraform Modules and State Management

**Module:** DBA Automation & DevOps - Module 01
**Lab Type:** LOCAL + AWS (module creation is local, deployment is AWS)
**Time Estimate:** 60-75 minutes
**Prerequisites:** BUILD 01 and BUILD 02 completed

---

## What You Will Build

You will take the RDS configuration from BUILD 02 and refactor it into a reusable **module** - Terraform's version of a stored procedure. Then you will set up remote state storage so your team can collaborate safely.

---

## Step 1: Understand Modules

In PostgreSQL, when you find yourself writing the same query over and over, you create a function:

```sql
CREATE FUNCTION create_app_database(db_name TEXT, owner TEXT)
RETURNS void AS $$
BEGIN
  EXECUTE format('CREATE DATABASE %I OWNER %I', db_name, owner);
  EXECUTE format('GRANT ALL ON DATABASE %I TO %I', db_name, owner);
END;
$$ LANGUAGE plpgsql;
```

Now you call `SELECT create_app_database('myapp', 'appuser');` instead of repeating those statements every time.

**Terraform modules are the same idea.** Instead of copying VPC + security group + RDS configuration every time you need a database, you bundle them into a module and call it with parameters:

```hcl
module "app_database" {
  source        = "./modules/postgresql-rds"
  db_name       = "myapp"
  instance_class = "db.t3.micro"
  environment   = "dev"
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

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/lab03-modules/modules/postgresql-rds
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
    postgresql-rds/    # The module itself (like a function definition)
      main.tf          # VPC + SG + RDS resources
      variables.tf     # Module input parameters
      outputs.tf       # Module return values
```

---

## Step 3: Build the Module - Variables (Input Parameters)

**In `~/terraform-labs/lab03-modules/modules/postgresql-rds`:**

```bash
vi ~/terraform-labs/lab03-modules/modules/postgresql-rds/variables.tf
```

Enter insert mode (`i`) and type:

```hcl
# modules/postgresql-rds/variables.tf
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
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
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

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "custom_parameters" {
  description = "Map of custom PostgreSQL parameters (postgresql.conf overrides)"
  type        = map(string)
  default     = {}
}
```

Save and exit (`:wq`).

---

## Step 4: Build the Module - Main Resources

**In `~/terraform-labs/lab03-modules/modules/postgresql-rds`:**

```bash
vi ~/terraform-labs/lab03-modules/modules/postgresql-rds/main.tf
```

Enter insert mode (`i`) and type:

```hcl
# modules/postgresql-rds/main.tf
# The module body - all the resources bundled together
# This is the function body that runs when you call the module

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
  name       = "${var.project_name}-${var.environment}-db-subnets"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnets"
  }
}

# --- Security Group (pg_hba.conf as code) ---

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Controls access to RDS PostgreSQL"
  vpc_id      = aws_vpc.this.id

  # Dynamic block - creates one ingress rule per allowed CIDR
  # Like generating multiple pg_hba.conf lines from a list
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
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}

# --- Parameter Group (postgresql.conf as code) ---

resource "aws_db_parameter_group" "this" {
  family = "postgres16"
  name   = "${var.project_name}-${var.environment}-pg-params"

  # Default parameters every DBA wants
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

  # Dynamic custom parameters from the caller
  dynamic "parameter" {
    for_each = var.custom_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-pg-params"
  }
}

# --- RDS Instance ---

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true  # Lab only

  parameter_group_name    = aws_db_parameter_group.this.name
  backup_retention_period = var.backup_retention_period
  multi_az                = var.multi_az

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

Save and exit (`:wq`).

---

## Step 5: Build the Module - Outputs (Return Values)

**In `~/terraform-labs/lab03-modules/modules/postgresql-rds`:**

```bash
vi ~/terraform-labs/lab03-modules/modules/postgresql-rds/outputs.tf
```

Enter insert mode (`i`) and type:

```hcl
# modules/postgresql-rds/outputs.tf
# Return values - like OUT parameters or RETURNING clause

output "endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "hostname" {
  description = "RDS hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master username"
  value       = aws_db_instance.this.username
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.rds.id
}

output "instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}
```

Save and exit (`:wq`).

---

## Step 6: Call the Module from Your Root Configuration

Now we write the "caller" - the code that invokes the module, like calling a stored procedure.

**In `~/terraform-labs/lab03-modules`:**

```bash
vi ~/terraform-labs/lab03-modules/providers.tf
```

Enter insert mode (`i`) and type:

```hcl
# providers.tf

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

Enter insert mode (`i`) and type:

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

Enter insert mode (`i`) and type:

```hcl
# main.tf - Calling the module
# This is like: SELECT * FROM create_app_database('myapp', 'appuser');

module "dev_database" {
  source = "./modules/postgresql-rds"

  # Module inputs (function arguments)
  project_name = "dba-lab"
  environment  = "dev"
  aws_region   = var.aws_region

  db_name     = "devdb"
  db_username = "dbadmin"
  db_password = var.db_password

  instance_class    = "db.t3.micro"
  allocated_storage = 20

  allowed_cidr_blocks = ["${var.my_ip}/32"]

  # Custom postgresql.conf parameters
  custom_parameters = {
    "log_statement"             = "all"
    "log_min_duration_statement" = "1000"  # Log queries over 1 second
  }
}

# Want a staging database too? Just call the module again with different params:
#
# module "staging_database" {
#   source = "./modules/postgresql-rds"
#
#   project_name = "dba-lab"
#   environment  = "staging"
#   aws_region   = var.aws_region
#
#   db_name       = "stagingdb"
#   db_username   = "dbadmin"
#   db_password   = var.db_password
#   instance_class = "db.t3.small"  # Slightly bigger for staging
#   multi_az      = true             # Test HA in staging
#
#   allowed_cidr_blocks = ["${var.my_ip}/32"]
# }
```

Save and exit (`:wq`).

```bash
vi ~/terraform-labs/lab03-modules/outputs.tf
```

Enter insert mode (`i`) and type:

```hcl
# outputs.tf - Surface module outputs at the top level

output "dev_db_endpoint" {
  description = "Dev database endpoint"
  value       = module.dev_database.endpoint
}

output "dev_db_connection_command" {
  description = "psql command to connect to dev database"
  value       = "psql -h ${module.dev_database.hostname} -p ${module.dev_database.port} -U ${module.dev_database.username} -d ${module.dev_database.database_name}"
}
```

Save and exit (`:wq`).

```bash
vi ~/terraform-labs/lab03-modules/terraform.tfvars
```

Enter insert mode (`i`) and type:

```hcl
aws_region  = "us-east-1"
db_password = "ChangeMe123!"
my_ip       = "203.0.113.50"  # Replace with YOUR IP
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
- dev_database in modules/postgresql-rds
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.72.1...

Terraform has been successfully initialized!
```

Notice the new line: `Initializing modules...` - Terraform found and loaded your module.

```bash
terraform plan
```

The plan will show the same 11 resources from BUILD 02, but now they are prefixed with `module.dev_database.` to show they come from the module:

Expected output (yours will differ):

```
  # module.dev_database.aws_db_instance.this will be created
  # module.dev_database.aws_vpc.this will be created
  # module.dev_database.aws_security_group.rds will be created
  ...

Plan: 11 to add, 0 to change, 0 to destroy.
```

**Do not apply this unless you want to incur AWS costs.** The point of this step is to verify the module works. If you want to test it for real, apply, connect with psql, then immediately destroy.

---

## Step 8: Understand Remote State (Shared pg_catalog)

So far, your `terraform.tfstate` file lives on your local machine. This works for solo projects, but what happens when a team manages the same infrastructure?

| Scenario | Problem |
|---|---|
| State on your laptop | Your teammate runs `terraform apply` with their own state - resources get duplicated or overwritten |
| State in Git | Merge conflicts in JSON. Secrets in version control. |

The solution is **remote state** - store the state file in a shared location. For AWS, the standard is S3 + DynamoDB.

| Local State | Remote State (S3) |
|---|---|
| State file on disk | State file in S3 bucket |
| Only you can see it | Whole team shares it |
| No locking | DynamoDB provides locking |
| Like a local SQLite DB | Like a shared PostgreSQL server |

The DynamoDB lock is like **advisory locks** in PostgreSQL. When you run `terraform apply`, it acquires a lock. If a teammate tries to run `terraform apply` at the same time, they get an error saying the state is locked - preventing concurrent modifications.

---

## Step 9: Create the Remote State Backend (Reference Only)

This step shows you the configuration. **Do not apply this unless you have an S3 bucket and DynamoDB table already created.** This is a reference for when you set up real projects.

The backend configuration goes in `providers.tf`:

```hcl
terraform {
  # Remote state backend - shared state storage
  backend "s3" {
    bucket         = "your-company-terraform-state"
    key            = "dba-lab/dev/terraform.tfstate"
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

## Step 10: Terraform Workspaces (Schema-Level Isolation)

Workspaces let you maintain separate state files for different environments using the same configuration. Think of them like PostgreSQL schemas - same database, different namespaces.

**In `~/terraform-labs/lab03-modules`:**

```bash
terraform workspace list
```

Expected output:

```
* default
```

You always start in the `default` workspace.

Create new workspaces:

```bash
terraform workspace new dev
```

Expected output:

```
Created and switched to workspace "dev"!
```

```bash
terraform workspace new staging
```

```bash
terraform workspace new prod
```

List them:

```bash
terraform workspace list
```

Expected output:

```
  default
  dev
* prod
  staging
```

The `*` shows your current workspace.

Switch between them:

```bash
terraform workspace select dev
```

Expected output:

```
Switched to workspace "dev".
```

Each workspace gets its own state file. When using S3 backend, they are stored at different paths:

```
s3://your-bucket/env:/dev/terraform.tfstate
s3://your-bucket/env:/staging/terraform.tfstate
s3://your-bucket/env:/prod/terraform.tfstate
```

You can use `terraform.workspace` in your configuration to customize behavior per environment:

```hcl
resource "aws_db_instance" "this" {
  instance_class = terraform.workspace == "prod" ? "db.r5.large" : "db.t3.micro"
  multi_az       = terraform.workspace == "prod" ? true : false
}
```

---

## Step 11: Data Sources (Querying Existing Infrastructure)

Sometimes you need to reference infrastructure that already exists - resources you did not create with Terraform. Data sources let you query AWS like you query `information_schema`.

| Operation | PostgreSQL | Terraform |
|---|---|---|
| Read existing objects | `SELECT * FROM information_schema.tables` | `data "aws_vpc" "existing" {}` |
| Create new objects | `CREATE TABLE ...` | `resource "aws_instance" ...` |

Example - look up an existing VPC by tag:

```hcl
# Read an existing VPC (does not create anything)
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

# Use it in a new resource
resource "aws_security_group" "new_sg" {
  vpc_id = data.aws_vpc.existing.id  # Reference the data source
  # ...
}
```

Example - get the latest PostgreSQL AMI:

```hcl
data "aws_rds_engine_version" "postgres" {
  engine  = "postgres"
  version = "16"
  # Returns the latest 16.x version available
}
```

Data sources are read-only. They never create, modify, or destroy anything. They are purely `SELECT` statements against the AWS API.

---

## Step 12: depends_on (Explicit Ordering)

Terraform usually figures out the correct order automatically. If resource B references resource A's ID, Terraform knows to create A first. This is like foreign key dependencies - you cannot reference a table that does not exist.

But sometimes dependencies are implicit and Terraform cannot detect them. Use `depends_on` to make them explicit:

```hcl
resource "aws_db_instance" "postgres" {
  # ...

  # Terraform might not know this SG rule must exist before the DB is useful
  depends_on = [aws_security_group_rule.allow_app_servers]
}
```

Use `depends_on` sparingly. If you find yourself using it often, your configuration likely has a design issue. It is like using `ORDER BY` in a subquery - sometimes necessary, but usually a sign of a different problem.

---

## Step 13: Lifecycle Rules (prevent_destroy)

In PostgreSQL, you might revoke DROP privileges to prevent accidental table deletion. Terraform has a similar mechanism.

```hcl
resource "aws_db_instance" "production" {
  # ...

  lifecycle {
    prevent_destroy = true  # terraform destroy will ERROR instead of deleting this
  }
}
```

| Lifecycle Rule | What It Does | DBA Analogy |
|---|---|---|
| `prevent_destroy` | Blocks deletion | `REVOKE DROP ON TABLE` |
| `create_before_destroy` | Create replacement before removing old | Blue-green deployment |
| `ignore_changes` | Ignore specific attribute changes | Ignoring a column in replication |

If someone runs `terraform destroy` with `prevent_destroy = true`, they get:

```
Error: Instance cannot be destroyed

  resource "aws_db_instance" "production"

  This resource has lifecycle prevent_destroy set, which
  prevents it from being destroyed.
```

This is your safety net for production databases. You can still remove it by editing the configuration, but it prevents accidental destruction.

---

## Step 14: Clean Up Workspaces

Before finishing, clean up the workspaces we created:

**In `~/terraform-labs/lab03-modules`:**

```bash
terraform workspace select default
```

```bash
terraform workspace delete dev
```

Expected output:

```
Deleted workspace "dev"!
```

```bash
terraform workspace delete staging
```

```bash
terraform workspace delete prod
```

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
| Environment isolation | Workspaces | Schemas within a database |
| Read existing infra | Data sources | `information_schema` / `pg_catalog` queries |
| Explicit ordering | `depends_on` | Foreign key dependencies |
| Prevent deletion | `lifecycle { prevent_destroy }` | `REVOKE DROP` on critical tables |

---

**Next:** [BUILD 04 - Aurora Clusters and Advanced Terraform Patterns](04-aurora-and-advanced-patterns.md) - Build production-grade Aurora clusters and learn advanced Terraform techniques.
