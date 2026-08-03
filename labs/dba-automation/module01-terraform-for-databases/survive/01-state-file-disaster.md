# SURVIVE 01: The Corrupted State File

**Scenario:** You are on call. A teammate manually deleted an RDS instance through the AWS Console. Terraform state still thinks the instance exists. The next `terraform apply` fails because reality does not match state. You must reconcile.

**Module:** DBA Automation & DevOps - Module 01
**Time Estimate:** 30-45 minutes
**Difficulty:** Intermediate
**Prerequisites:** BUILD 01-02 completed

---

## The Situation

It is 2 AM. PagerDuty fires. Your monitoring shows the `analytics-db` RDS instance is gone. You check the AWS Console - confirmed, someone deleted it. You check CloudTrail logs and find a junior engineer was "cleaning up" resources and deleted it manually.

Your Terraform state file still has the instance recorded. Running `terraform plan` produces errors because Terraform tries to read the instance attributes from AWS and gets "not found."

Your mission: get Terraform state back in sync with reality, then recreate the instance.

---

## Setup: Create the Lab Scenario

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/survive01-state-disaster
```

```bash
cd ~/terraform-labs/survive01-state-disaster
```

### Step 1: Create a simple configuration

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

resource "local_file" "config_file" {
  content  = "database_host=analytics-db.internal\ndatabase_port=5432\ndatabase_name=analytics"
  filename = "${path.module}/config.txt"
}

resource "local_file" "backup_script" {
  content  = "#!/bin/bash\npg_dump -h analytics-db.internal -U dbadmin analytics > /backup/analytics.sql"
  filename = "${path.module}/backup.sh"
}

resource "local_file" "monitoring_config" {
  content  = "check_interval=60\nalert_threshold=90\nendpoint=analytics-db.internal:5432"
  filename = "${path.module}/monitoring.conf"
}

output "config_path" {
  value = local_file.config_file.filename
}

output "backup_path" {
  value = local_file.backup_script.filename
}

output "monitoring_path" {
  value = local_file.monitoring_config.filename
}
```

Save and exit (`:wq`).

### Step 2: Initialize and apply

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
local_file.config_file: Creating...
local_file.backup_script: Creating...
local_file.monitoring_config: Creating...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Step 3: Verify everything is in sync

```bash
terraform state list
```

Expected output:

```
local_file.backup_script
local_file.config_file
local_file.monitoring_config
```

### Step 4: Simulate the disaster - manually delete a resource

Now pretend someone deleted the "database" (in our case, the config file) outside of Terraform:

```bash
rm config.txt
```

And also delete the monitoring config to simulate multiple resources being affected:

```bash
rm monitoring.conf
```

State still thinks both files exist:

```bash
terraform state list
```

Expected output:

```
local_file.backup_script
local_file.config_file
local_file.monitoring_config
```

---

## The Challenge

Terraform state says 3 resources exist. In reality, only 1 does (backup.sh). You need to:

1. Diagnose the state drift
2. Decide the correct remediation for each resource
3. Execute the fix
4. Verify everything is back in sync

---

## Part 1: Diagnose the Drift

Run `terraform plan` to see what Terraform thinks needs to happen:

```bash
terraform plan
```

Expected output (yours will differ):

```
local_file.config_file: Refreshing state... [id=...]
local_file.backup_script: Refreshing state... [id=...]
local_file.monitoring_config: Refreshing state... [id=...]

Terraform will perform the following actions:

  # local_file.config_file will be created
  + resource "local_file" "config_file" {
      ...
    }

  # local_file.monitoring_config will be created
  + resource "local_file" "monitoring_config" {
      ...
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

Terraform detected the drift. It refreshed state, saw the files are missing, and plans to recreate them. In this case, Terraform handles it gracefully because the `local_file` provider checks if the file exists.

**With RDS, the behavior can be different.** If someone deletes an RDS instance and you run `terraform plan`, you might see errors like:

```
Error: reading RDS DB Instance (analytics-db): DBInstanceNotFound
```

In that case, Terraform cannot even plan because it cannot read the missing resource's attributes.

---

## Part 2: Remediation Options

You have three options when state and reality are out of sync:

### Option A: Let Terraform Recreate (Easiest)

If Terraform's plan output looks correct (like above), just apply:

```bash
terraform apply -auto-approve
```

This works when Terraform can detect the drift and the plan is to recreate the missing resources.

### Option B: Remove from State, Then Re-Plan (For Errors)

If Terraform throws errors because the resource is gone, remove it from state first:

```bash
# Remove the missing resource from state
# This does NOT delete anything - it just tells Terraform "forget about this resource"
terraform state rm local_file.config_file
```

Expected output:

```
Removed local_file.config_file
Successfully removed 1 resource instance(s).
```

Now `terraform plan` will show it as a new resource to create, and `terraform apply` will create it fresh.

### Option C: Import an Existing Resource (For Replacements)

If someone deleted the old resource and created a replacement manually (with different settings), you need to import the replacement:

```bash
# terraform import <resource_address> <real_world_id>
# For RDS: terraform import aws_db_instance.analytics analytics-db-v2
```

---

## Part 3: Execute the Fix

For this lab, let's practice Option B (the most common real-world scenario with RDS).

First, let's deliberately break things more to simulate an RDS error. Remove both missing files from state:

```bash
terraform state rm local_file.config_file
```

Expected output:

```
Removed local_file.config_file
Successfully removed 1 resource instance(s).
```

```bash
terraform state rm local_file.monitoring_config
```

Expected output:

```
Removed local_file.monitoring_config
Successfully removed 1 resource instance(s).
```

Check state now:

```bash
terraform state list
```

Expected output:

```
local_file.backup_script
```

Only the backup script remains in state - matching reality (it is the only file that still exists on disk).

Now plan:

```bash
terraform plan
```

Expected output (yours will differ):

```
local_file.backup_script: Refreshing state... [id=...]

Terraform will perform the following actions:

  # local_file.config_file will be created
  + resource "local_file" "config_file" { ... }

  # local_file.monitoring_config will be created
  + resource "local_file" "monitoring_config" { ... }

Plan: 2 to add, 0 to change, 0 to destroy.
```

Apply:

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
local_file.config_file: Creating...
local_file.monitoring_config: Creating...

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

---

## Part 4: Verify Recovery

```bash
terraform state list
```

Expected output:

```
local_file.backup_script
local_file.config_file
local_file.monitoring_config
```

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

All 3 resources exist in state AND in reality. The drift is resolved.

Verify the files:

```bash
ls -la *.txt *.sh *.conf
```

Expected output (yours will differ):

```
-rwxr-xr-x  1 user  staff  73 Jun  9 10:30 backup.sh
-rwxr-xr-x  1 user  staff  68 Jun  9 10:35 config.txt
-rwxr-xr-x  1 user  staff  62 Jun  9 10:35 monitoring.conf
```

---

## Part 5: Prevention - How to Stop This from Happening

### 1. Use lifecycle.prevent_destroy on critical resources

```hcl
resource "aws_db_instance" "production" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

### 2. Enable deletion protection on RDS

```hcl
resource "aws_db_instance" "production" {
  deletion_protection = true
  # ...
}
```

### 3. Restrict AWS Console access

Use IAM policies to prevent manual deletion of Terraform-managed resources. Only Terraform's IAM role should have delete permissions.

### 4. Use remote state with locking

S3 backend + DynamoDB locking prevents concurrent modifications.

### 5. Tag everything as Terraform-managed

```hcl
tags = {
  ManagedBy = "terraform"
  Warning   = "Do not modify in console"
}
```

---

## Clean Up

```bash
terraform destroy -auto-approve
```

---

## State Remediation Decision Tree

```
terraform plan shows error?
  |
  YES --> Resource was deleted outside Terraform
  |       |
  |       Want to recreate it?
  |         YES --> terraform state rm <resource>, then terraform apply
  |         NO  --> terraform state rm <resource>, remove from .tf files
  |
  NO --> terraform plan shows drift?
          |
          YES --> Review the diff
          |       |
          |       Terraform's plan is correct?
          |         YES --> terraform apply
          |         NO  --> Update .tf config to match desired state, re-plan
          |
          NO --> "No changes" - everything is in sync
```

---

## What You Practiced

| Skill | Command | When to Use |
|---|---|---|
| Detect state drift | `terraform plan` | Anytime you suspect manual changes |
| List managed resources | `terraform state list` | Audit what Terraform tracks |
| Inspect a resource | `terraform state show <resource>` | Debug specific resource state |
| Remove from state | `terraform state rm <resource>` | Resource deleted outside Terraform |
| Import existing resource | `terraform import <resource> <id>` | Bring existing infra under management |
| Recreate missing resources | `terraform apply` | After clearing stale state entries |
