# SURVIVE 02: Accidental Destroy - Runbook

**Module:** DevOps DBA Training Track - Module 03
**Difficulty:** Intermediate
**Time Estimate:** 30 minutes

---

## What Is Being Tested

Your ability to recover from an accidental `terraform destroy` of production resources, and to implement safeguards that prevent it from happening again.

---

## Why This Matters

`terraform destroy` is irreversible for most resources. When someone runs it on production instead of dev, the results are catastrophic:

- Aurora cluster gone - compute instances terminated
- Security groups deleted - network access rules lost
- Parameter groups deleted - custom configurations lost
- If `skip_final_snapshot = true` was set, data is gone permanently

This scenario happens more often than teams admit. Common causes:

- Wrong terminal window (thought they were in dev, were in prod)
- Wrong workspace selected
- Running `terraform destroy -auto-approve` without checking the directory
- CI/CD pipeline misconfiguration

---

## Symptoms

1. `terraform state list` returns empty
2. AWS Console shows the Aurora cluster is gone (status: deleting or deleted)
3. Application connections fail immediately
4. The `.conf` files (or real AWS resources) no longer exist
5. `terraform plan` shows all resources as "will be created"

---

## Diagnostic Steps

### Step 1: Confirm the destruction

**In your terminal (`~/terraform-labs/survive02-accidental-destroy/`):**

```bash
terraform state list
```

Expected: empty output (no resources).

```bash
ls -la ~/terraform-labs/survive02-accidental-destroy/*-prod.conf
```

Expected: files not found (they were destroyed).

### Step 2: Verify the config is intact

```bash
cat ~/terraform-labs/survive02-accidental-destroy/main.tf
```

The `.tf` configuration should still exist. Terraform destroys resources, not configuration files.

---

## Resolution

### Step 1: Recreate the resources

Since the resources were destroyed (not just removed from state), we need to create them again.

**In your terminal (`~/terraform-labs/survive02-accidental-destroy/`):**

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
local_file.aurora_cluster: Creating...
local_file.writer_instance: Creating...
local_file.reader_instance: Creating...
local_file.security_group: Creating...
local_file.parameter_group: Creating...

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

Verify:

```bash
terraform state list
```

Expected: 5 resources listed.

```bash
ls -la ~/terraform-labs/survive02-accidental-destroy/*-prod.conf
```

Expected: 5 .conf files exist.

### Step 2: Add prevent_destroy to critical resources

Now implement safeguards. Edit `main.tf` to add lifecycle rules:

```bash
vi ~/terraform-labs/survive02-accidental-destroy/main.tf
```

Add `lifecycle { prevent_destroy = true }` to the `aurora_cluster`, `writer_instance`, and `reader_instance` resources. For example:

```hcl
resource "local_file" "aurora_cluster" {
  content  = "cluster_id=prod-aurora\nengine=aurora-postgresql\nversion=16.4\nencrypted=true\nbackup_retention=35"
  filename = "${path.module}/aurora-cluster-${var.environment}.conf"

  lifecycle {
    prevent_destroy = true
  }
}
```

Do the same for `writer_instance` and `reader_instance`.

Save and exit (`:wq`).

### Step 3: Apply the lifecycle changes

```bash
terraform apply -auto-approve
```

### Step 4: Verify the protection works

```bash
terraform destroy
```

Expected output:

```
Error: Instance cannot be destroyed

  resource "local_file" "aurora_cluster"

  Instance local_file.aurora_cluster has lifecycle.prevent_destroy set,
  but the plan calls for this resource to be destroyed.
```

Terraform now refuses to destroy the protected resources.

### Step 5: Verify state is correct

```bash
terraform plan
```

Expected: "No changes."

---

## Prevention

### 1. lifecycle.prevent_destroy on all production database resources

```hcl
resource "aws_rds_cluster" "production" {
  lifecycle {
    prevent_destroy = true
  }
}
```

### 2. AWS deletion_protection

```hcl
resource "aws_rds_cluster" "production" {
  deletion_protection = true
}
```

### 3. Never use -auto-approve in production

Always review the plan before typing `yes`:

```bash
# WRONG - dangerous
terraform destroy -auto-approve

# RIGHT - forces you to review
terraform destroy
```

### 4. Separate state files per environment

Use different directories or workspaces so `terraform destroy` in dev cannot touch prod:

```
environments/
  dev/       # terraform destroy here only affects dev
  staging/   # terraform destroy here only affects staging
  prod/      # terraform destroy here only affects prod
```

### 5. Plan files for CI/CD

```bash
terraform plan -out=tfplan
# Review the plan
terraform apply tfplan
```

### 6. IAM least privilege

The Terraform IAM role for non-production environments should NOT have permission to modify production resources.

---

## Interview Questions

1. **A colleague accidentally ran terraform destroy on production. How do you recover?**
   Check if `skip_final_snapshot = false` was set - if so, restore from the final snapshot. Check automated backups. Recreate infrastructure with `terraform apply`. For Aurora, AWS keeps automated backups for the retention period even after cluster deletion.

2. **What safeguards would you implement to prevent accidental destroys?**
   `prevent_destroy` lifecycle rule, `deletion_protection = true`, separate state per environment, never use `-auto-approve` in production, CI/CD with plan review gates, IAM least privilege.

3. **What is the difference between prevent_destroy and deletion_protection?**
   `prevent_destroy` is a Terraform-level check - it prevents Terraform from planning the destruction. `deletion_protection` is an AWS-level check - even if Terraform tries, AWS API will reject the delete request. Use both for defense in depth.

---

## Key Terminology

| Term | Definition |
|---|---|
| **terraform destroy** | Command to delete all resources managed by Terraform |
| **prevent_destroy** | Lifecycle rule that makes Terraform refuse to destroy a resource |
| **deletion_protection** | AWS-level setting that makes the API refuse delete requests |
| **skip_final_snapshot** | If true, no backup is created when the cluster is deleted |
| **-auto-approve** | Flag that skips the confirmation prompt (dangerous) |
| **Plan file** | Saved plan that can be reviewed before applying |

---

## Red Flags

- Using `terraform destroy -auto-approve` in any environment
- Production resources without `prevent_destroy`
- Production Aurora clusters with `deletion_protection = false`
- Production clusters with `skip_final_snapshot = true`
- Same state file for dev and prod
- No CI/CD pipeline for production Terraform changes
- Developers having direct `terraform apply` access to production

---

## Clean Up

To clean up the lab (since prevent_destroy is now set), you need to temporarily remove the lifecycle blocks:

```bash
vi ~/terraform-labs/survive02-accidental-destroy/main.tf
```

Change `prevent_destroy = true` to `prevent_destroy = false` for all three resources.

Save and exit (`:wq`).

```bash
terraform destroy -auto-approve
```
