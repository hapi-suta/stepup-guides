# SURVIVE 02: The Accidental terraform destroy

**Scenario:** A colleague ran `terraform destroy` on what they thought was the dev environment. It was production. The Aurora cluster, parameter groups, and security groups are gone. You must implement safeguards so this never happens again.

**Module:** DBA Automation & DevOps - Module 01
**Time Estimate:** 30-45 minutes
**Difficulty:** Intermediate
**Prerequisites:** BUILD 01-03 completed

---

## The Situation

Monday morning. You open Slack. The message reads:

> "Hey, I was cleaning up the dev environment and ran `terraform destroy` in the wrong terminal window. I think I just destroyed the production Aurora cluster."

The production database is gone. Backups exist (AWS automated backups), but the entire Terraform-managed infrastructure - VPC, subnets, security groups, parameter groups, and the Aurora cluster - has been destroyed.

Your mission: After the immediate crisis is handled (restore from backup - that is a different runbook), implement safeguards to prevent this from ever happening again.

---

## Setup: Create the Lab Scenario

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/survive02-accidental-destroy
```

```bash
cd ~/terraform-labs/survive02-accidental-destroy
```

### Step 1: Create a "production-like" configuration

```bash
vi main.tf
```

Enter insert mode (`i`) and type:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# Simulate a production database (using local files)
resource "local_file" "database_config" {
  content  = "environment=${var.environment}\ncluster=aurora-prod\nendpoint=prod-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"
  filename = "${path.module}/database-${var.environment}.conf"
}

resource "local_file" "security_rules" {
  content  = "# Security group rules for ${var.environment}\nallow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-${var.environment}.conf"
}

resource "local_file" "parameter_group" {
  content  = "# PostgreSQL parameters for ${var.environment}\nshared_buffers=8GB\nwork_mem=256MB\nmax_connections=500"
  filename = "${path.module}/parameters-${var.environment}.conf"
}

resource "local_file" "backup_config" {
  content  = "# Backup configuration for ${var.environment}\nretention=35\nwindow=02:00-03:00\nencryption=AES256"
  filename = "${path.module}/backup-${var.environment}.conf"
}

output "environment" {
  value = var.environment
}

output "files_created" {
  value = [
    local_file.database_config.filename,
    local_file.security_rules.filename,
    local_file.parameter_group.filename,
    local_file.backup_config.filename,
  ]
}
```

Save and exit (`:wq`).

### Step 2: Deploy "production"

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

environment = "prod"
files_created = [
  "./database-prod.conf",
  "./security-prod.conf",
  "./parameters-prod.conf",
  "./backup-prod.conf",
]
```

### Step 3: Simulate the disaster

```bash
terraform destroy -auto-approve
```

Expected output (yours will differ):

```
local_file.database_config: Destroying...
local_file.security_rules: Destroying...
local_file.parameter_group: Destroying...
local_file.backup_config: Destroying...

Destroy complete! Resources: 4 destroyed.
```

Gone. Four resources destroyed in seconds. No confirmation prompt (because `-auto-approve`), no safety net.

---

## The Challenge

Implement multiple layers of protection so this cannot happen again. You will add:

1. `prevent_destroy` lifecycle rules
2. Deletion protection
3. Environment-aware safety checks
4. Approval workflows

---

## Part 1: Add prevent_destroy Lifecycle Rules

The first line of defense. `prevent_destroy` makes Terraform refuse to destroy a resource, even if you run `terraform destroy`.

**In `~/terraform-labs/survive02-accidental-destroy`:**

```bash
vi main.tf
```

Replace the entire contents with:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# PROTECTED: Production database configuration
resource "local_file" "database_config" {
  content  = "environment=${var.environment}\ncluster=aurora-prod\nendpoint=prod-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"
  filename = "${path.module}/database-${var.environment}.conf"

  # SAFETY: Prevent accidental destruction
  # Like REVOKE DROP on a critical table
  lifecycle {
    prevent_destroy = true
  }
}

resource "local_file" "security_rules" {
  content  = "# Security group rules for ${var.environment}\nallow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-${var.environment}.conf"

  lifecycle {
    prevent_destroy = true
  }
}

resource "local_file" "parameter_group" {
  content  = "# PostgreSQL parameters for ${var.environment}\nshared_buffers=8GB\nwork_mem=256MB\nmax_connections=500"
  filename = "${path.module}/parameters-${var.environment}.conf"

  lifecycle {
    prevent_destroy = true
  }
}

resource "local_file" "backup_config" {
  content  = "# Backup configuration for ${var.environment}\nretention=35\nwindow=02:00-03:00\nencryption=AES256"
  filename = "${path.module}/backup-${var.environment}.conf"

  lifecycle {
    prevent_destroy = true
  }
}

output "environment" {
  value = var.environment
}

output "files_created" {
  value = [
    local_file.database_config.filename,
    local_file.security_rules.filename,
    local_file.parameter_group.filename,
    local_file.backup_config.filename,
  ]
}
```

Save and exit (`:wq`).

### Test the protection

First, recreate the resources:

```bash
terraform apply -auto-approve
```

Now try to destroy:

```bash
terraform destroy
```

Expected output:

```
Error: Instance cannot be destroyed

  on main.tf line X:
   X: resource "local_file" "database_config" {

Instance local_file.database_config has lifecycle.prevent_destroy set,
but the plan calls for this resource to be destroyed. To avoid this
error and continue with the plan, either disable lifecycle.prevent_destroy
or reduce the scope of the destroy using the -target flag.
```

Terraform **refuses** to destroy. The `prevent_destroy` lifecycle rule stopped the destruction.

This is the equivalent of:

```sql
-- PostgreSQL: Prevent dropping a critical table
REVOKE DROP ON TABLE production_orders FROM app_user;
```

---

## Part 2: Apply to Real AWS Resources

In a real AWS Terraform configuration, you would use `prevent_destroy` on all critical database resources:

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier = "prod-aurora"
  # ...

  # AWS-level protection
  deletion_protection = true  # AWS will refuse to delete

  # Terraform-level protection
  lifecycle {
    prevent_destroy = true  # Terraform will refuse to plan deletion
  }
}

resource "aws_db_instance" "production" {
  identifier = "prod-primary"
  # ...

  deletion_protection = true

  lifecycle {
    prevent_destroy = true
  }
}
```

**Two layers of protection:**

| Layer | Mechanism | What It Prevents |
|---|---|---|
| Terraform | `lifecycle.prevent_destroy` | `terraform destroy` from removing the resource |
| AWS | `deletion_protection = true` | AWS API / Console from deleting the resource |

Even if someone removes `prevent_destroy` from the config and runs `terraform destroy`, AWS will still block the deletion because of `deletion_protection`. You would have to:

1. Set `deletion_protection = false` in the config
2. Run `terraform apply` to update the setting
3. Then run `terraform destroy`

That is three deliberate steps - not something that happens by accident.

---

## Part 3: Environment-Aware Protection

A smarter approach - only enable protection in production:

```hcl
variable "environment" {
  type = string
}

locals {
  is_production = var.environment == "prod"
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.project}-${var.environment}-aurora"
  # ...

  # Only enable deletion protection in production
  deletion_protection = local.is_production

  # skip_final_snapshot = false in prod, true in dev
  skip_final_snapshot       = !local.is_production
  final_snapshot_identifier = local.is_production ? "${var.project}-${var.environment}-final-${formatdate("YYYY-MM-DD", timestamp())}" : null
}
```

This way:
- **Dev/staging:** Easy to create and destroy for testing
- **Production:** Protected by default, requires deliberate override to destroy

---

## Part 4: Plan Approval Workflows

The nuclear option of `terraform apply -auto-approve` should never be used in production. Here are safer alternatives:

### Manual Plan Review

```bash
# Step 1: Generate a plan file
terraform plan -out=tfplan

# Step 2: Review the plan (even share it with a colleague)
terraform show tfplan

# Step 3: Only apply the exact plan you reviewed
terraform apply tfplan
```

The `-out=tfplan` flag saves the plan to a file. `terraform apply tfplan` applies ONLY that specific plan - not a fresh one. If anything changed between plan and apply, Terraform will detect it.

### CI/CD Pipeline Checks

In a real workflow, `terraform plan` runs in CI (GitHub Actions, GitLab CI, etc.) and the output is posted as a PR comment. A senior DBA reviews the plan and approves the PR before `terraform apply` runs.

```
Developer pushes .tf change
  --> CI runs terraform plan
  --> Plan output posted to PR
  --> Senior DBA reviews and approves
  --> CI runs terraform apply
```

---

## Part 5: S3 State with Versioning (Undo Button)

When using S3 for remote state, enable versioning on the bucket. This gives you an undo button - you can restore a previous state file if something goes wrong.

```hcl
# This is REFERENCE ONLY - do not apply unless you have an S3 bucket

resource "aws_s3_bucket" "terraform_state" {
  bucket = "your-company-terraform-state"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"  # Keep all previous versions of state files
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# Block ALL public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

With versioning enabled, you can recover from a bad `terraform apply` by restoring the previous state version from S3.

---

## Part 6: Clean Up the Lab

To destroy the lab resources with `prevent_destroy` set, you need to temporarily remove the protection.

**In `~/terraform-labs/survive02-accidental-destroy`:**

Edit `main.tf` and remove all four `lifecycle` blocks (or change `prevent_destroy = true` to `prevent_destroy = false`).

```bash
vi main.tf
```

Remove or comment out each `lifecycle` block:

```hcl
  # lifecycle {
  #   prevent_destroy = true
  # }
```

Save and exit (`:wq`).

Now destroy works:

```bash
terraform destroy -auto-approve
```

Expected output (yours will differ):

```
Destroy complete! Resources: 4 destroyed.
```

---

## Production Protection Checklist

| Protection Layer | Implementation | Prevents |
|---|---|---|
| `lifecycle.prevent_destroy` | In `.tf` file | Terraform from planning destruction |
| `deletion_protection = true` | RDS/Aurora setting | AWS from accepting delete requests |
| `skip_final_snapshot = false` | RDS/Aurora setting | Data loss on deletion (creates backup) |
| S3 state versioning | Bucket configuration | Permanent state loss |
| DynamoDB state locking | Backend configuration | Concurrent modifications |
| Plan files (`-out=tfplan`) | Workflow discipline | Applying unexpected changes |
| CI/CD approval gates | Pipeline configuration | Unapproved changes reaching production |
| IAM least privilege | AWS IAM policies | Unauthorized users from running destroy |
| Workspace separation | `terraform workspace` | Targeting wrong environment |
| Separate state files | Different S3 keys per env | Cross-environment contamination |

---

## What You Practiced

| Skill | Implementation | Effect |
|---|---|---|
| Prevent resource destruction | `lifecycle { prevent_destroy = true }` | Terraform refuses to destroy |
| AWS deletion protection | `deletion_protection = true` | AWS API refuses to delete |
| Environment-aware protection | Conditional on `var.environment` | Only protect prod, keep dev flexible |
| Plan approval workflow | `terraform plan -out=tfplan` | Separate plan review from execution |
| State backup strategy | S3 versioning | Recoverable state history |
| Defense in depth | Multiple layers | No single failure can destroy prod |
