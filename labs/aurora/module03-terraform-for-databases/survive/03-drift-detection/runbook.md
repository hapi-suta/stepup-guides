# SURVIVE 03: Drift Detection and Reconciliation - Runbook

**Module:** DevOps DBA Training Track - Module 03
**Difficulty:** Intermediate
**Time Estimate:** 30 minutes

---

## What Is Being Tested

Your ability to detect, analyze, and reconcile configuration drift - when real infrastructure differs from what Terraform expects because someone made manual changes.

---

## Why This Matters

Drift is the most common day-to-day Terraform issue in DBA teams. It happens constantly because:

- A DBA opens the AWS Console and changes a security group rule to unblock an urgent application issue
- A developer modifies a parameter group to test a performance theory
- The cost optimization team reduces backup retention to save money
- An automated process (like AWS auto-minor-version-upgrade) changes the engine version

The changes may be valid, but they create a gap between Terraform's configuration and reality. The next `terraform apply` will try to revert those changes, potentially breaking things.

---

## Symptoms

1. `terraform plan` shows unexpected changes (the `~` symbol for in-place updates)
2. Team members report that settings they changed "keep reverting"
3. Security audit finds rules that are not in the Terraform configuration
4. Monitoring alerts fire after a `terraform apply` reverts a parameter change

---

## Diagnostic Steps

### Step 1: Detect all drift

**In your terminal (`~/terraform-labs/survive03-drift-detection/`):**

```bash
terraform plan
```

Read the output carefully. You will see changes Terraform wants to make. For each change, ask:

- **What changed?** (look at the `~` lines)
- **Who changed it?** (check CloudTrail in real AWS)
- **Was the change intentional?**
- **Should the change be kept or reverted?**

Expected: 3 resources show drift, 1 resource is clean.

### Step 2: Analyze each drift

**Drift 1: Security group - added 0.0.0.0/0 rule**

```bash
cat ~/terraform-labs/survive03-drift-detection/security-group.conf
```

Someone added `allow 0.0.0.0/0 port 5432` - this allows the entire internet to connect to the database on port 5432. This is a **critical security issue** and must be reverted.

**Drift 2: Instance parameters - log_statement changed to 'all'**

```bash
cat ~/terraform-labs/survive03-drift-detection/instance-params.conf
```

Someone changed `log_statement` from `ddl` to `all`. This might be intentional (temporary debugging) or might cause performance issues in production (logging every query generates massive log volume). Decision needed.

**Drift 3: Aurora config - backup retention reduced**

```bash
cat ~/terraform-labs/survive03-drift-detection/aurora-config.conf
```

Backup retention was reduced from 35 days to 7 days. This reduces your recovery window significantly. For production, this should be reverted.

---

## Resolution

For each drifted resource, you have two options:

- **Revert the change:** Run `terraform apply` to restore the Terraform-defined configuration
- **Accept the change:** Update your `.tf` file to match the new reality

### Decision Matrix for This Scenario

| Resource | Change | Decision | Reason |
|---|---|---|---|
| Security group | Added 0.0.0.0/0 | **REVERT** | Critical security vulnerability |
| Instance params | log_statement=all | **ACCEPT** (modify to 'ddl') | Revert to original, but document the decision |
| Aurora config | backup_retention=7 | **REVERT** | 7 days is dangerously low for production |

### Step 1: Revert the security group (let Terraform fix it)

The security group has a dangerous rule. We want Terraform's version (without 0.0.0.0/0).

Since our `.tf` file already has the correct configuration (without the 0.0.0.0/0 rule), running `terraform apply` will revert this change.

### Step 2: Handle the instance parameters

For `log_statement`, the original value of `ddl` in our `.tf` file is the correct production setting. A developer may have changed it to `all` for debugging, but `all` in production causes excessive logging. We will let Terraform revert this.

### Step 3: Revert the backup retention

Our `.tf` file specifies 35 days, which is correct for production. Let Terraform revert it.

### Step 4: Apply all fixes at once

Since all three changes should be reverted to the Terraform-defined configuration:

**In your terminal (`~/terraform-labs/survive03-drift-detection/`):**

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
local_file.security_group: Modifying...
local_file.instance_params: Modifying...
local_file.aurora_config: Modifying...

Apply complete! Resources: 0 added, 3 changed, 0 destroyed.
```

### Step 5: Verify no drift remains

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

### Step 6: Verify the security rule is gone

```bash
cat ~/terraform-labs/survive03-drift-detection/security-group.conf
```

Expected: No `0.0.0.0/0` rule. Only the original `10.0.0.0/8` and `172.16.0.0/12` rules.

### Step 7: Verify backup retention is restored

```bash
cat ~/terraform-labs/survive03-drift-detection/aurora-config.conf
```

Expected: `backup_retention=35`

---

## Alternative: Accepting a Change

If you decided that `log_statement=all` was actually the desired state, you would update your `.tf` file instead of letting Terraform revert it:

```bash
vi ~/terraform-labs/survive03-drift-detection/main.tf
```

Change:

```hcl
resource "local_file" "instance_params" {
  content  = "# Instance Parameter Group\nlog_statement=all\nlog_min_duration_statement=1000\nwork_mem=262144\nidle_in_transaction_session_timeout=300000"
```

Then `terraform plan` would show no drift for that resource, and the new setting would be the source of truth going forward.

---

## Prevention

### 1. Tag everything as Terraform-managed

```hcl
tags = {
  ManagedBy = "terraform"
  Warning   = "Do not modify in AWS Console"
}
```

### 2. Restrict Console access for Terraform-managed resources

Use IAM policies that grant read-only access to resources tagged with `ManagedBy = terraform`. Only the Terraform IAM role should have write access.

### 3. Automated drift detection

Run `terraform plan` on a schedule (e.g., every hour via CI/CD) and alert if drift is detected:

```bash
terraform plan -detailed-exitcode
# Exit code 0 = no changes
# Exit code 2 = changes detected (drift)
```

### 4. Use ignore_changes for expected drift

If a specific attribute is managed externally (e.g., password rotation by Secrets Manager):

```hcl
lifecycle {
  ignore_changes = [master_password]
}
```

### 5. Establish a change process

All infrastructure changes must go through Terraform:

1. Update `.tf` files
2. Submit PR for review
3. CI runs `terraform plan`
4. Senior DBA reviews and approves
5. CI runs `terraform apply`

No Console changes for Terraform-managed resources.

---

## Interview Questions

1. **What is configuration drift and how do you detect it?**
   Drift is when real infrastructure differs from Terraform's configuration. Detect it with `terraform plan` - any output other than "No changes" indicates drift. In CI/CD, use `terraform plan -detailed-exitcode` (exit code 2 = drift detected).

2. **A DBA changed a security group rule in the AWS Console to unblock an urgent issue. What should you do?**
   First, determine if the change should be permanent. If yes, update the `.tf` file to include the new rule and commit. If temporary, let Terraform revert it on the next apply. Either way, document the decision and communicate with the team.

3. **How do you prevent drift in a team environment?**
   Tag resources as Terraform-managed. Restrict Console write access. Run automated drift detection. Establish a process where all changes go through Terraform PRs. Use `ignore_changes` for attributes managed by external systems.

---

## Key Terminology

| Term | Definition |
|---|---|
| **Drift** | Difference between Terraform config/state and actual infrastructure |
| **Reconciliation** | Bringing state and reality back into alignment |
| **terraform plan** | Primary tool for detecting drift |
| **terraform apply** | Reverts drift by enforcing the configured state |
| **ignore_changes** | Lifecycle rule to skip specific attributes during drift detection |
| **-detailed-exitcode** | Plan flag that returns exit code 2 when changes are detected |

---

## Red Flags

- Frequent manual changes to Terraform-managed resources
- No automated drift detection in CI/CD
- Team members making Console changes without updating Terraform
- Using `ignore_changes` on too many attributes (hiding drift instead of fixing it)
- Not reviewing `terraform plan` output before applying
- Running `terraform apply` without understanding what drift it will revert

---

## Clean Up

```bash
terraform destroy -auto-approve
```
