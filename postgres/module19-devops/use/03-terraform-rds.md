# Module 19 - USE 03: Terraform RDS Exercise

## Objective

Write a complete Terraform configuration for an AWS RDS PostgreSQL instance, run plan, understand the output, modify a parameter group, and destroy cleanly.

---

## Setup

Make sure Terraform is installed (see BUILD 03).

```bash
terraform version
```

Set up AWS credentials. Replace with your actual credentials.

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
```

```bash
export AWS_SECRET_ACCESS_KEY="your_secret_key"
```

```bash
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Exercise 1: Create the Terraform Project

```bash
mkdir -p /opt/pgsql/tf-rds-exercise
```

```bash
cd /opt/pgsql/tf-rds-exercise
```

Create the provider configuration.

```bash
vi provider.tf
```

```hcl
terraform {
  required_version = ">= 1.5"

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

---

## Exercise 2: Define Variables

```bash
vi variables.tf
```

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "pg-lab"
}

variable "db_password" {
  description = "Master database password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}
```

---

## Exercise 3: Write the RDS Configuration

```bash
vi main.tf
```

```hcl
# Parameter group with DBA-tuned settings
resource "aws_db_parameter_group" "pg_params" {
  name   = "${var.project_name}-pg16"
  family = "postgres16"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000"
  }

  tags = {
    Name      = "${var.project_name}-pg16"
    ManagedBy = "terraform"
  }
}

# Security group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL access"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "PostgreSQL from private network"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.project_name}-rds-sg"
    ManagedBy = "terraform"
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "16.2"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password

  parameter_group_name   = aws_db_parameter_group.pg_params.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:05:00-sun:06:00"

  performance_insights_enabled = true
  publicly_accessible          = false
  skip_final_snapshot          = true
  deletion_protection          = false

  tags = {
    Name      = "${var.project_name}-postgres"
    ManagedBy = "terraform"
  }
}
```

---

## Exercise 4: Define Outputs

```bash
vi outputs.tf
```

```hcl
output "rds_endpoint" {
  description = "Database endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  description = "Database port"
  value       = aws_db_instance.postgres.port
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.identifier
}

output "parameter_group" {
  description = "Parameter group name"
  value       = aws_db_parameter_group.pg_params.name
}
```

---

## Exercise 5: Initialize and Plan

Set the database password via environment variable.

```bash
export TF_VAR_db_password="LabPassword123!"
```

Initialize Terraform. This downloads the AWS provider plugin.

```bash
terraform init
```

Expected output (yours will differ):
```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.31.0...
Terraform has been successfully initialized!
```

Run a plan.

```bash
terraform plan -out=tfplan
```

The `-out=tfplan` flag saves the plan to a file so you can apply the exact plan you reviewed.

Expected output (yours will differ):
```
Terraform will perform the following actions:

  # aws_db_instance.postgres will be created
  # aws_db_parameter_group.pg_params will be created
  # aws_security_group.rds will be created

Plan: 3 to add, 0 to change, 0 to destroy.

Saved to: tfplan
```

Review the plan carefully. Check:
- Instance class matches what you expect
- Storage is encrypted
- Backup retention is set
- No unexpected resources

---

## Exercise 6: Apply (Optional - Costs Money)

Only run this if you want to create real AWS resources. This will cost approximately $0.02/hour for db.t3.micro.

```bash
terraform apply tfplan
```

Expected output (yours will differ):
```
aws_db_parameter_group.pg_params: Creating...
aws_security_group.rds: Creating...
aws_db_parameter_group.pg_params: Creation complete after 2s
aws_security_group.rds: Creation complete after 3s
aws_db_instance.postgres: Creating...
aws_db_instance.postgres: Still creating... [5m0s elapsed]
aws_db_instance.postgres: Creation complete after 7m23s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

rds_endpoint = "pg-lab-postgres.abc123.us-east-1.rds.amazonaws.com:5432"
rds_port = 5432
...
```

RDS instances take 5-10 minutes to create.

---

## Exercise 7: Modify the Parameter Group

Add a new parameter. Open main.tf.

```bash
vi main.tf
```

Add this parameter block inside the `aws_db_parameter_group` resource:

```hcl
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
```

Plan the change.

```bash
terraform plan
```

Expected output (yours will differ):
```
  # aws_db_parameter_group.pg_params will be updated in-place
  ~ resource "aws_db_parameter_group" "pg_params" {
        id     = "pg-lab-pg16"
      + parameter {
          + name  = "log_lock_waits"
          + value = "1"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Notice "updated in-place" - Terraform will modify the existing parameter group, not destroy and recreate it. This is safe because parameter group changes that do not require reboot are applied immediately.

---

## Exercise 8: Verify State

Check what Terraform is tracking.

```bash
terraform state list
```

Expected output (yours will differ):
```
aws_db_instance.postgres
aws_db_parameter_group.pg_params
aws_security_group.rds
```

Show details for a specific resource.

```bash
terraform state show aws_db_instance.postgres
```

---

## Exercise 9: Destroy Cleanly

When done, destroy all resources to avoid ongoing charges.

```bash
terraform plan -destroy
```

Review the destruction plan. Make sure only your lab resources are listed.

```bash
terraform destroy
```

Type `yes` when prompted.

Expected output (yours will differ):
```
aws_db_instance.postgres: Destroying... [id=pg-lab-postgres]
aws_db_instance.postgres: Still destroying... [1m0s elapsed]
aws_db_instance.postgres: Destruction complete after 5m12s
aws_security_group.rds: Destroying...
aws_db_parameter_group.pg_params: Destroying...
aws_security_group.rds: Destruction complete after 1s
aws_db_parameter_group.pg_params: Destruction complete after 1s

Destroy complete! Resources: 3 destroyed.
```

---

## Cleanup

```bash
rm -rf /opt/pgsql/tf-rds-exercise
```

---

## Checklist

- [ ] Created provider.tf with AWS provider pinned to ~> 5.0
- [ ] Defined variables with `sensitive = true` for passwords
- [ ] Created parameter group with DBA-tuned PostgreSQL settings
- [ ] Created security group restricting access to private network
- [ ] Created RDS instance with encryption and backups enabled
- [ ] Defined outputs for endpoint and connection details
- [ ] Ran terraform plan and reviewed output before applying
- [ ] Successfully modified parameter group via Terraform
- [ ] Verified terraform state list and state show commands
- [ ] Destroyed resources cleanly with no orphans
