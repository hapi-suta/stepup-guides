# SURVIVE Scenario 07: Terraform State Corruption - Runbook

## Scenario

The Terraform state file has been corrupted. Aurora resources are missing from state, so `terraform plan` shows it wants to create resources that already exist in AWS. You must re-import existing resources without disrupting the running cluster.

---

## Step 1: Assess the Damage

**On your local workstation:**

```bash
cd ~/capstone-aurora/terraform
```

```bash
terraform plan -var-file=production.tfvars 2>&1 | grep "will be created"
```

List the resources Terraform thinks need to be created. These are the resources missing from state.

---

## Step 2: DO NOT Run Apply

Running `terraform apply` with a corrupted state will attempt to create duplicate resources. This can cause:
- "AlreadyExists" errors (best case)
- Resource conflicts and partial state corruption (worst case)

---

## Step 3: Check for Backup State Files

Look for state backups:

```bash
ls -la ~/capstone-aurora/terraform/*.tfstate.backup
```

```bash
ls -la ~/capstone-aurora/terraform/.terraform-state-backup-*
```

If a recent backup exists, you can restore it:

```bash
cp ~/capstone-aurora/terraform/terraform.tfstate.backup ~/capstone-aurora/terraform/terraform.tfstate
```

Then run `terraform plan` again to verify.

---

## Step 4: Import Resources (If No Backup Available)

If no backup is available, import each missing resource manually.

**Import the cluster parameter group:**

```bash
terraform import \
  -var-file=production.tfvars \
  module.aurora.aws_rds_cluster_parameter_group.aurora \
  devops-lab-cluster-params
```

**Import the instance parameter group:**

```bash
terraform import \
  -var-file=production.tfvars \
  module.aurora.aws_db_parameter_group.aurora \
  devops-lab-instance-params
```

**Import the Aurora cluster:**

```bash
terraform import \
  -var-file=production.tfvars \
  module.aurora.aws_rds_cluster.aurora \
  devops-lab-cluster
```

**Import the writer instance:**

```bash
terraform import \
  -var-file=production.tfvars \
  module.aurora.aws_rds_cluster_instance.writer \
  devops-lab-cluster-w1
```

**Import the reader instance:**

```bash
terraform import \
  -var-file=production.tfvars \
  'module.aurora.aws_rds_cluster_instance.reader[0]' \
  devops-lab-cluster-r1
```

Note the single quotes around the reader resource address - the `[0]` index needs protection from shell expansion.

---

## Step 5: Verify State is Correct

```bash
terraform plan -var-file=production.tfvars
```

The plan should show either:
- "No changes" (ideal)
- Minor attribute differences that can be resolved with `terraform apply` (acceptable)

If the plan shows resources to destroy or recreate, review carefully before proceeding.

---

## Step 6: Prevent Future State Corruption

1. **Use remote state** - Store state in S3 with DynamoDB locking
2. **Enable state versioning** - S3 versioning preserves previous state files
3. **Never edit state files manually** - Use `terraform state` commands
4. **Regular state backups** - Automated backup of the state file

Example S3 backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "devops-lab-terraform-state"
    key            = "aurora/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```
