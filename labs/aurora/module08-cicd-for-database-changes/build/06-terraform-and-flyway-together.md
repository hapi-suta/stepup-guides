# BUILD 06: Terraform and Flyway Together

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 60-75 minutes

---

## What You Will Learn

How to combine Terraform (infrastructure provisioning) and Flyway (schema migrations) in a single CI/CD pipeline. Terraform creates the Aurora cluster. Flyway manages what is inside it. By the end, you will have a pipeline that provisions infrastructure and applies schema changes in the correct order.

---

## Prerequisites

- Completed BUILD 01-05
- Terraform installed (`brew install terraform`)
- AWS CLI configured with credentials
- GitHub repository from BUILD 03

---

## Why Combine Them?

Terraform and Flyway solve different problems:

| Concern | Tool | Example |
|---------|------|---------|
| Infrastructure | Terraform | Create Aurora cluster, parameter groups, security groups |
| Schema | Flyway | Create tables, indexes, constraints inside the database |
| Configuration | Terraform | Set `max_connections`, `shared_buffers` via parameter groups |
| Data | Flyway | Seed data, backfill columns, create views |

Without combining them, you have two separate deployment processes. Someone might update the Terraform config (new parameter group) but forget to run the corresponding Flyway migration, or vice versa.

A combined pipeline ensures: infrastructure first, then schema, in every deployment.

---

## Step 1: Project Structure

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/iac-pipeline/terraform
```

```bash
mkdir -p ~/dba-labs/iac-pipeline/migrations/sql
```

```bash
mkdir -p ~/dba-labs/iac-pipeline/scripts
```

```bash
mkdir -p ~/dba-labs/iac-pipeline/.github/workflows
```

```bash
cd ~/dba-labs/iac-pipeline
```

The project structure:

```
iac-pipeline/
  terraform/              # Infrastructure as Code
    main.tf
    variables.tf
    outputs.tf
    terraform.tfvars       # (gitignored - contains secrets)
  migrations/             # Schema migrations
    sql/
      V1__create_tables.sql
      V2__add_indexes.sql
    flyway.conf.template
  scripts/
    validate_schema.sql
    run-migrations.sh
  .github/workflows/
    infra-and-schema.yml
```

---

## Step 2: Write the Terraform Configuration

Create the Terraform files for an Aurora PostgreSQL cluster.

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
vi terraform/variables.tf
```

```hcl
variable "aws_region" {
  description = "AWS region for the Aurora cluster"
  type        = string
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora cluster"
  type        = string
  default     = "devops-lab-cluster"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "postgres"
}

variable "master_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.1"
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for the cluster"
  type        = list(string)
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}
```

- `sensitive = true` on `master_password` prevents Terraform from showing the value in logs.

```bash
vi terraform/main.tf
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

  # Store state remotely (recommended for team use)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "aurora/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region
}

# Aurora cluster parameter group
resource "aws_rds_cluster_parameter_group" "aurora_pg" {
  family      = "aurora-postgresql16"
  name        = "${var.cluster_identifier}-params"
  description = "Parameter group for ${var.cluster_identifier}"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.cluster_identifier
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_pg.name
  db_subnet_group_name            = var.db_subnet_group_name
  vpc_security_group_ids          = var.vpc_security_group_ids

  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = true
  deletion_protection     = false

  # Enable backtrack for rollback capability
  backtrack_window = 86400  # 24 hours in seconds

  tags = {
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

# Aurora writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.cluster_identifier}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = {
    Environment = "lab"
    ManagedBy   = "terraform"
    Role        = "writer"
  }
}
```

```bash
vi terraform/outputs.tf
```

```hcl
output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_port" {
  description = "Port for the Aurora cluster"
  value       = aws_rds_cluster.aurora.port
}

output "database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.aurora.database_name
}
```

---

## Step 3: Write the Migration Runner Script

Create a script that runs Flyway migrations using Terraform outputs for connection details.

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
vi scripts/run-migrations.sh
```

```bash
#!/bin/bash
set -euo pipefail

# run-migrations.sh
# Runs Flyway migrations against the Aurora cluster.
# Reads connection details from environment variables.
#
# Required environment variables:
#   DB_HOST     - Aurora writer endpoint
#   DB_PORT     - Database port (usually 5432)
#   DB_NAME     - Database name
#   DB_USER     - Migration user
#   DB_PASSWORD - Migration user password
#
# Usage: ./scripts/run-migrations.sh [info|migrate|validate|repair]

COMMAND="${1:-migrate}"
MIGRATIONS_DIR="$(cd "$(dirname "$0")/../migrations/sql" && pwd)"

echo "=== Flyway ${COMMAND} ==="
echo "Host: ${DB_HOST}"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Migrations: ${MIGRATIONS_DIR}"
echo ""

# Validate required environment variables
for VAR in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD; do
    if [ -z "${!VAR:-}" ]; then
        echo "ERROR: ${VAR} is not set."
        exit 1
    fi
done

FLYWAY_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

flyway \
    -url="${FLYWAY_URL}" \
    -user="${DB_USER}" \
    -password="${DB_PASSWORD}" \
    -locations="filesystem:${MIGRATIONS_DIR}" \
    -cleanDisabled=true \
    -validateOnMigrate=true \
    "${COMMAND}"

echo ""
echo "=== Flyway ${COMMAND} complete ==="
```

Make it executable:

```bash
chmod +x scripts/run-migrations.sh
```

What the script does:

- `set -euo pipefail` - exit on any error, treat unset variables as errors, and fail on pipe errors.
- `${1:-migrate}` - defaults to `migrate` if no argument is provided.
- Validates that all required environment variables are set before connecting.
- Constructs the JDBC URL from individual components.
- Runs Flyway with `cleanDisabled=true` (never allow clean in this script).

---

## Step 4: Create the Migrations

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
vi migrations/sql/V1__create_core_tables.sql
```

```sql
-- V1: Core application tables
SET lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS customers (
    customer_id  SERIAL PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(255) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
    product_id   SERIAL PRIMARY KEY,
    sku          VARCHAR(50) NOT NULL UNIQUE,
    name         VARCHAR(200) NOT NULL,
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
    order_id     SERIAL PRIMARY KEY,
    customer_id  INTEGER NOT NULL REFERENCES customers(customer_id),
    status       VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    ordered_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
    item_id      SERIAL PRIMARY KEY,
    order_id     INTEGER NOT NULL REFERENCES orders(order_id),
    product_id   INTEGER NOT NULL REFERENCES products(product_id),
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL
);
```

```bash
vi migrations/sql/V2__add_indexes.sql
```

```sql
-- V2: Performance indexes
SET lock_timeout = '5s';

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at ON orders (ordered_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items (product_id);
```

---

## Step 5: Write the Combined Pipeline

This workflow runs Terraform first (infrastructure), then Flyway (schema).

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
vi .github/workflows/infra-and-schema.yml
```

```yaml
name: Infrastructure and Schema Deploy

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'
      - 'migrations/**'
  pull_request:
    branches: [main]

jobs:
  # Job 1: Test migrations against a fresh database (always runs)
  test-migrations:
    name: Test Migrations (CI)
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Run migrations against test database
        env:
          DB_HOST: localhost
          DB_PORT: "5432"
          DB_NAME: test_db
          DB_USER: postgres
          DB_PASSWORD: postgres
        run: |
          chmod +x scripts/run-migrations.sh
          scripts/run-migrations.sh info
          scripts/run-migrations.sh migrate
          scripts/run-migrations.sh validate

  # Job 2: Terraform plan (shows what infrastructure changes will be made)
  terraform-plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.0"
      - name: Terraform init
        working-directory: ./terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: terraform init
      - name: Terraform plan
        working-directory: ./terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          TF_VAR_master_password: ${{ secrets.AURORA_MASTER_PASSWORD }}
          TF_VAR_vpc_security_group_ids: ${{ secrets.VPC_SECURITY_GROUP_IDS }}
          TF_VAR_db_subnet_group_name: ${{ secrets.DB_SUBNET_GROUP_NAME }}
        run: terraform plan -out=tfplan
      - name: Upload plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: terraform-plan
          path: terraform/tfplan

  # Job 3: Apply infrastructure (staging - after plan and test pass)
  apply-staging:
    name: Apply Infrastructure (Staging)
    needs: [test-migrations, terraform-plan]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.0"
      - name: Download plan artifact
        uses: actions/download-artifact@v4
        with:
          name: terraform-plan
          path: terraform/
      - name: Terraform apply
        working-directory: ./terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          TF_VAR_master_password: ${{ secrets.AURORA_MASTER_PASSWORD }}
          TF_VAR_vpc_security_group_ids: ${{ secrets.VPC_SECURITY_GROUP_IDS }}
          TF_VAR_db_subnet_group_name: ${{ secrets.DB_SUBNET_GROUP_NAME }}
        run: terraform apply -auto-approve tfplan

  # Job 4: Run migrations on staging (after infrastructure is ready)
  migrate-staging:
    name: Run Migrations (Staging)
    needs: apply-staging
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Run migrations on staging
        env:
          DB_HOST: ${{ secrets.STAGING_DB_HOST }}
          DB_PORT: "5432"
          DB_NAME: ${{ secrets.STAGING_DB_NAME }}
          DB_USER: ${{ secrets.STAGING_DB_USER }}
          DB_PASSWORD: ${{ secrets.STAGING_DB_PASSWORD }}
        run: |
          chmod +x scripts/run-migrations.sh
          scripts/run-migrations.sh info
          scripts/run-migrations.sh migrate
          scripts/run-migrations.sh validate

  # Job 5: Run migrations on production (manual approval)
  migrate-production:
    name: Run Migrations (Production)
    needs: migrate-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Install Flyway
        run: |
          wget -qO- https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/10.15.0/flyway-commandline-10.15.0-linux-x64.tar.gz | tar xz
          sudo ln -s $(pwd)/flyway-10.15.0/flyway /usr/local/bin/flyway
      - name: Run migrations on production
        env:
          DB_HOST: ${{ secrets.PROD_DB_HOST }}
          DB_PORT: "5432"
          DB_NAME: ${{ secrets.PROD_DB_NAME }}
          DB_USER: ${{ secrets.PROD_DB_USER }}
          DB_PASSWORD: ${{ secrets.PROD_DB_PASSWORD }}
        run: |
          chmod +x scripts/run-migrations.sh
          scripts/run-migrations.sh info
          scripts/run-migrations.sh migrate
          scripts/run-migrations.sh validate
```

---

## Step 6: Understand the Pipeline Flow

The pipeline has five jobs that run in this order:

```
test-migrations ----+
                    |---> apply-staging ---> migrate-staging ---> migrate-production
terraform-plan -----+                                              (manual approval)
```

1. **test-migrations** and **terraform-plan** run in parallel (independent)
2. **apply-staging** waits for both to succeed
3. **migrate-staging** waits for infrastructure to be ready
4. **migrate-production** requires manual approval

### Why This Order Matters

- Terraform must finish before Flyway runs (the database must exist before you can create tables in it)
- Migrations are tested against a fresh database before touching any real environment
- Production always requires explicit approval

---

## Step 7: The Dependency Chain

The `needs:` keyword creates dependencies between jobs:

```yaml
apply-staging:
  needs: [test-migrations, terraform-plan]    # Both must pass

migrate-staging:
  needs: apply-staging                         # Infrastructure must be ready

migrate-production:
  needs: migrate-staging                       # Staging must succeed first
```

If any job fails, all downstream jobs are skipped. A failed migration test prevents any infrastructure or schema changes from reaching staging or production.

---

## Step 8: State Management

### Terraform State

Terraform tracks the current infrastructure state in a state file. For team use, store it remotely:

```hcl
backend "s3" {
  bucket = "your-terraform-state-bucket"
  key    = "aurora/terraform.tfstate"
  region = "us-east-1"
}
```

- State contains sensitive data (passwords, endpoints) - the S3 bucket should be encrypted and access-restricted.
- Use state locking (DynamoDB table) to prevent concurrent applies.

### Flyway State

Flyway tracks its state in the `flyway_schema_history` table inside each database. There is no external state file to manage - the database itself is the source of truth.

### Keeping Them in Sync

The pipeline ensures sync by running both in the correct order. But if someone runs Terraform or Flyway manually (outside the pipeline), they can get out of sync.

Prevention strategies:

- Restrict direct access to Terraform state and database DDL permissions
- Run drift detection on a schedule (nightly GitHub Actions job)
- Use `terraform plan` and `flyway info` to check for unexpected changes

---

## Step 9: Test Locally

Before pushing to GitHub, test the migration runner script locally.

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
export DB_HOST=YOUR_AURORA_ENDPOINT
```

```bash
export DB_PORT=5432
```

```bash
export DB_NAME=cicd_dev
```

```bash
export DB_USER=postgres
```

```bash
export DB_PASSWORD=YOUR_PASSWORD
```

```bash
./scripts/run-migrations.sh info
```

Expected output (yours will differ):
```
=== Flyway info ===
Host: YOUR_AURORA_ENDPOINT
Database: cicd_dev
User: postgres
Migrations: /Users/you/dba-labs/iac-pipeline/migrations/sql

Schema version: << Empty Schema >>
...

=== Flyway info complete ===
```

```bash
./scripts/run-migrations.sh migrate
```

```bash
./scripts/run-migrations.sh validate
```

---

## Step 10: The .gitignore

**On your Mac terminal, in ~/dba-labs/iac-pipeline:**

```bash
vi .gitignore
```

```
# Terraform
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/*.tfvars
terraform/tfplan
terraform/.terraform.lock.hcl

# Flyway
migrations/flyway-*.conf

# Secrets
.env
*.env

# OS
.DS_Store
```

Key items:

- `*.tfvars` - contains variable values, often including passwords
- `*.tfstate` - contains the full infrastructure state including secrets
- `.terraform/` - downloaded provider plugins (large, not needed in Git)
- `flyway-*.conf` - environment-specific configs with credentials

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Terraform + Flyway | Terraform manages infrastructure, Flyway manages schema |
| Pipeline ordering | Infrastructure first, then schema - enforced by job dependencies |
| Migration runner script | Shell script that reads env vars and runs Flyway |
| Combined workflow | Five jobs: test, plan, apply, migrate staging, migrate production |
| State management | Terraform state in S3, Flyway state in the database |
| Secrets handling | All credentials via GitHub Secrets and environment variables |
| Drift prevention | Restrict direct access, run nightly drift detection |
| .gitignore | Never commit state files, tfvars, or environment configs |

---

**Next:** Move on to the [USE exercises](../use/01-migration-writing-exercise.md) to practice these skills with less hand-holding.
