# SURVIVE 01: State File Disaster - Runbook

**Module:** DevOps DBA Training Track - Module 03
**Difficulty:** Intermediate
**Time Estimate:** 30 minutes

---

## What Is Being Tested

Your ability to recover when Terraform's state file is lost or corrupted. State is Terraform's `pg_catalog` - without it, Terraform does not know what infrastructure exists.

---

## Why This Matters

State file loss is one of the most common Terraform disasters in the real world. It happens when:

- Someone deletes `terraform.tfstate` thinking it is not important
- A laptop dies with local state and no backup
- S3 state bucket is accidentally emptied
- State file gets corrupted by concurrent modifications without locking
- A botched migration between state backends

Without state, Terraform thinks no infrastructure exists. Running `terraform apply` would try to create everything from scratch, which fails because the real resources already exist in AWS.

---

## Symptoms

You know state is lost when you see one or more of these:

1. `terraform state list` returns nothing (empty output)
2. `terraform plan` shows all resources as "will be created" even though they already exist
3. `terraform apply` fails with "resource already exists" errors
4. The `terraform.tfstate` file is missing, empty, or contains invalid JSON
5. `terraform state show <resource>` returns "No instance found"

---

## Diagnostic Steps

### Step 1: Confirm the state file is gone

**In your terminal (`~/terraform-labs/survive01-state-disaster/`):**

```bash
ls -la ~/terraform-labs/survive01-state-disaster/terraform.tfstate
```

If the file does not exist, state is lost.

If the file exists but is empty or corrupted:

```bash
cat ~/terraform-labs/survive01-state-disaster/terraform.tfstate
```

An empty file or invalid JSON confirms corruption.

### Step 2: Confirm resources still exist in reality

```bash
ls -la ~/terraform-labs/survive01-state-disaster/*.conf
```

The `.conf` files should still exist on disk (simulating Aurora resources still running in AWS).

### Step 3: Check what Terraform thinks

```bash
terraform state list
```

Expected: empty output (no resources tracked).

```bash
terraform plan
```

Expected: Terraform wants to CREATE all resources - it does not know they exist.

---

## Resolution

### Option A: Restore from Backup (Best Case)

If you have a backup of the state file:

**Check for automatic backup:**

```bash
ls -la ~/terraform-labs/survive01-state-disaster/terraform.tfstate.backup
```

If the backup exists, restore it:

```bash
cp ~/terraform-labs/survive01-state-disaster/terraform.tfstate.backup ~/terraform-labs/survive01-state-disaster/terraform.tfstate
```

Verify:

```bash
terraform state list
```

If resources appear, you are recovered.

**For S3 remote state:** S3 versioning lets you restore previous versions of the state file. Use the S3 console or CLI to restore the previous version.

### Option B: Re-import All Resources (Most Common)

When there is no backup, you must import each resource back into state one at a time.

**Step 1:** Make sure your `.tf` configuration is still intact:

```bash
cat ~/terraform-labs/survive01-state-disaster/main.tf
```

The `.tf` files define your desired configuration. You need these to import against.

**Step 2:** Import each resource:

```bash
terraform import local_file.aurora_config ~/terraform-labs/survive01-state-disaster/aurora-config.conf
```

Expected output:

```
local_file.aurora_config: Importing...
local_file.aurora_config: Import prepared!
local_file.aurora_config: Refreshing state...

Import successful!
```

```bash
terraform import local_file.security_group ~/terraform-labs/survive01-state-disaster/security-group.conf
```

```bash
terraform import local_file.parameter_group ~/terraform-labs/survive01-state-disaster/parameter-group.conf
```

```bash
terraform import local_file.backup_policy ~/terraform-labs/survive01-state-disaster/backup-policy.conf
```

**Step 3:** Verify all resources are in state:

```bash
terraform state list
```

Expected output:

```
local_file.aurora_config
local_file.backup_policy
local_file.parameter_group
local_file.security_group
```

**Step 4:** Verify no drift:

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

If the plan shows changes, your `.tf` file does not exactly match reality. Fix the differences and re-plan until you see "No changes."

### Option C: Let Terraform Recreate (Nuclear Option)

If the resources can be safely destroyed and recreated (for example, in dev/staging):

```bash
terraform apply
```

Terraform will create new resources. This works ONLY if:
- The old resources were actually deleted (not just missing from state)
- Or the provider handles "already exists" gracefully

**Do not use this option for production databases.** It will either fail or create duplicate resources.

---

## Prevention

### 1. Use remote state (S3 + DynamoDB)

```hcl
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "aurora/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

### 2. Enable S3 versioning

Versioning gives you an undo button for state. You can restore any previous version.

### 3. Never commit state to Git

State contains secrets. Use `.gitignore`:

```
*.tfstate
*.tfstate.backup
.terraform/
```

### 4. Restrict access to state

Use IAM policies to limit who can read/write the state bucket.

### 5. Regular state backups

Even with S3 versioning, consider cross-region replication for the state bucket.

---

## Interview Questions

1. **What is Terraform state and why is it important?**
   State maps your configuration to real-world resources. Without it, Terraform cannot manage infrastructure.

2. **Your team lost the state file for a production Aurora cluster. Walk me through the recovery.**
   Check for backups (state backup file, S3 versions). If none exist, use `terraform import` for each resource. Write matching HCL, import, plan, iterate until "No changes."

3. **How do you prevent state file loss?**
   Remote state with S3 + DynamoDB locking. S3 versioning enabled. Encryption at rest. Restricted IAM access. Cross-region replication for critical state.

---

## Key Terminology

| Term | Definition |
|---|---|
| **State file** | JSON file mapping Terraform config to real resources |
| **State backup** | Automatic copy Terraform makes before modifying state |
| **Remote state** | State stored in a shared backend (S3, GCS, Terraform Cloud) |
| **State locking** | Preventing concurrent modifications (DynamoDB for S3 backend) |
| **terraform import** | Command to bring existing resources into Terraform state |
| **State drift** | When state and reality are out of sync |

---

## Red Flags

- Running Terraform with local state and no backups in production
- Multiple team members with copies of state on their laptops
- State files committed to Git repositories
- No locking mechanism on remote state
- Using `terraform state rm` without understanding the consequences
- Running `terraform apply` after state loss without importing first

---

## Clean Up

After completing the exercise:

```bash
terraform destroy -auto-approve
```
