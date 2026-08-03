# USE 04: Import Exercise

**Module:** DevOps DBA Training Track - Module 03
**Time Estimate:** 30-45 minutes
**Prerequisites:** BUILD 01-06 completed (especially BUILD 05)
**Lab Type:** LOCAL (no AWS cost)

---

## The Scenario

You just joined a company as Lead DBA. They have an Aurora PostgreSQL cluster that was created manually in the AWS Console 18 months ago. Nobody knows the exact settings. The CEO wants "everything in Terraform by end of quarter."

In this exercise, you will practice the import workflow using local files to simulate the real-world process.

---

## Setup: Create the "Legacy Infrastructure"

These files represent the manually-created Aurora infrastructure that exists in AWS but is not in Terraform.

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/use04-import
```

```bash
cd ~/terraform-labs/use04-import
```

Run each command to create the "legacy" files:

```bash
echo "# Aurora Cluster: legacy-prod-aurora
engine=aurora-postgresql
version=16.3
database=appdb
master_user=postgres
encrypted=true
backup_retention=14
backup_window=02:00-03:00
maintenance_window=sun:04:00-sun:05:00
deletion_protection=true" > ~/terraform-labs/use04-import/cluster.conf
```

```bash
echo "# Writer Instance: legacy-prod-aurora-writer
instance_class=db.r6g.large
az=us-east-1a
publicly_accessible=false
parameter_group=legacy-prod-instance-params" > ~/terraform-labs/use04-import/writer.conf
```

```bash
echo "# Reader Instance: legacy-prod-aurora-reader-1
instance_class=db.r6g.large
az=us-east-1b
publicly_accessible=false
parameter_group=legacy-prod-instance-params" > ~/terraform-labs/use04-import/reader.conf
```

```bash
echo "# Security Group: sg-0abc123def456
name=legacy-prod-aurora-sg
vpc=vpc-0xyz789
ingress: 10.0.0.0/8 port 5432 (app servers)
ingress: 172.16.5.0/24 port 5432 (DBA VPN)
ingress: 10.100.0.0/16 port 5432 (monitoring)
egress: 0.0.0.0/0 all" > ~/terraform-labs/use04-import/security-group.conf
```

```bash
echo "# Cluster Parameter Group: legacy-prod-cluster-params
family=aurora-postgresql16
shared_preload_libraries=pg_stat_statements
log_connections=1
log_disconnections=1
rds.force_ssl=1" > ~/terraform-labs/use04-import/cluster-params.conf
```

```bash
echo "# Instance Parameter Group: legacy-prod-instance-params
family=aurora-postgresql16
log_statement=all
log_min_duration_statement=500
work_mem=262144
maintenance_work_mem=524288" > ~/terraform-labs/use04-import/instance-params.conf
```

You now have 6 files representing legacy infrastructure.

---

## Exercise 1: Audit the Existing Infrastructure

Before writing any Terraform, document what exists. In the real world, you would use the AWS Console and CLI. Here, read the files.

**Task:** Create a table documenting every resource:

| Resource Type | Name/ID | Key Settings |
|---|---|---|
| Aurora Cluster | ? | ? |
| Writer Instance | ? | ? |
| Reader Instance | ? | ? |
| Security Group | ? | ? |
| Cluster Parameter Group | ? | ? |
| Instance Parameter Group | ? | ? |

Read each file:

```bash
cat ~/terraform-labs/use04-import/cluster.conf
```

```bash
cat ~/terraform-labs/use04-import/security-group.conf
```

Continue for all 6 files. Fill in the table before proceeding.

---

## Exercise 2: Write Matching HCL

Create a Terraform configuration that exactly matches the existing infrastructure.

```bash
vi ~/terraform-labs/use04-import/main.tf
```

Press `i` to enter insert mode and write a complete configuration that:

1. Declares the `local` provider
2. Has a resource block for each of the 6 files
3. Each resource's `content` must exactly match the existing file content
4. Each resource's `filename` must point to the correct path

**Key challenge:** The content must match character-for-character. Any difference will show up in `terraform plan` after import.

**Hint:** Use `cat` to see the exact content of each file. Pay attention to newlines and special characters.

---

## Exercise 3: Initialize and Import

After writing your HCL:

```bash
terraform init
```

Import each resource one at a time:

```bash
terraform import local_file.cluster ~/terraform-labs/use04-import/cluster.conf
```

```bash
terraform import local_file.writer ~/terraform-labs/use04-import/writer.conf
```

```bash
terraform import local_file.reader ~/terraform-labs/use04-import/reader.conf
```

```bash
terraform import local_file.security_group ~/terraform-labs/use04-import/security-group.conf
```

```bash
terraform import local_file.cluster_params ~/terraform-labs/use04-import/cluster-params.conf
```

```bash
terraform import local_file.instance_params ~/terraform-labs/use04-import/instance-params.conf
```

After each import, check the count:

```bash
terraform state list
```

---

## Exercise 4: Iterate Until No Changes

After importing all 6 resources, run:

```bash
terraform plan
```

If you see changes, it means your HCL content does not exactly match the file content. This is the most common real-world scenario - your first attempt at writing HCL rarely matches the real resource perfectly.

**For each difference:**

1. Read the plan output carefully to see what differs
2. Update your HCL to match reality
3. Run `terraform plan` again

Repeat until you see:

```
No changes. Your infrastructure matches the configuration.
```

---

## Exercise 5: Now Improve the Configuration

Now that everything is imported and in sync, it is time to improve the configuration. This is where you make changes as a DBA.

**Task 1:** The engine version is 16.3. Upgrade to 16.4.

Update the cluster content to change `version=16.3` to `version=16.4`.

```bash
terraform plan
```

You should see the change in the plan output. Apply it:

```bash
terraform apply -auto-approve
```

**Task 2:** Add a missing security group rule for a new microservice.

Update the security group content to add a new ingress line.

Plan and apply.

**Task 3:** Add `idle_in_transaction_session_timeout=300000` to the instance parameter group.

Update the instance params content. Plan and apply.

---

## Exercise 6: Final Verification

```bash
terraform state list
```

Expected: 6 resources

```bash
terraform plan
```

Expected: "No changes."

```bash
cat ~/terraform-labs/use04-import/cluster.conf
```

Verify the engine version is now 16.4.

---

## Cleanup

```bash
terraform destroy -auto-approve
```

---

## Real-World Import Reference

When importing actual AWS Aurora resources:

```bash
# Import Aurora cluster
terraform import aws_rds_cluster.main legacy-prod-aurora

# Import writer instance
terraform import aws_rds_cluster_instance.writer legacy-prod-aurora-writer

# Import reader instance
terraform import aws_rds_cluster_instance.reader legacy-prod-aurora-reader-1

# Import security group
terraform import aws_security_group.aurora sg-0abc123def456

# Import cluster parameter group
terraform import aws_rds_cluster_parameter_group.main legacy-prod-cluster-params

# Import instance parameter group
terraform import aws_db_parameter_group.main legacy-prod-instance-params
```

### Tips for Real-World Imports

1. **Get all settings first.** Use `aws rds describe-db-clusters` and `aws rds describe-db-instances` to get every attribute. Missing an attribute means `terraform plan` will show drift.

2. **Import one resource at a time.** Do not try to import everything at once. Import, plan, fix, repeat.

3. **Use `terraform state show` after import.** This shows you what Terraform learned from the import, which helps you write matching HCL.

4. **Expect 3-5 iterations.** It is normal for the first plan after import to show changes. Some are cosmetic (default values not matching), some are real.

5. **Watch for `ignore_changes`.** Some attributes (like `master_password`) cannot be read back from AWS. You may need `ignore_changes` for those.

---

## Scoring Guide

| Exercise | Points | Key Skill |
|---|---|---|
| 1 - Audit documentation | 10 | Understanding existing infrastructure |
| 2 - Write matching HCL | 25 | Translating infrastructure to code |
| 3 - Import all resources | 20 | `terraform import` workflow |
| 4 - Iterate to no changes | 25 | Debugging plan differences |
| 5 - Improve configuration | 15 | Making changes via Terraform after import |
| 6 - Final verification | 5 | State audit and plan verification |
| **Total** | **100** |
