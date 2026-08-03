# BUILD 05: Terraform Import - Bringing Existing Resources Under Management

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** LOCAL (uses local_file provider to simulate import workflow - no AWS cost)
**Time Estimate:** 30 minutes
**Prerequisites:** BUILD 01-04 completed

---

## What You Will Learn

How to bring existing infrastructure under Terraform management using `terraform import`. This is the workflow you use when you have Aurora clusters, security groups, or other resources that were created manually in the AWS Console and you want Terraform to manage them going forward.

---

## Step 1: Understand the Import Workflow

You have 15,000+ databases. Most were not created with Terraform. When you want to bring an existing resource under Terraform management, the workflow is:

1. **Write the HCL** - Create a resource block in your `.tf` file that describes the existing resource
2. **Import** - Run `terraform import` to link the HCL block to the real resource
3. **Iterate** - Run `terraform plan` to find differences between your HCL and reality
4. **Fix** - Update your HCL until `terraform plan` shows "No changes"

**DBA analogy:** This is like `pg_dump` for infrastructure. The resource already exists - you are capturing its definition in code so Terraform can manage it going forward.

---

## Step 2: Create a "Manually Created" Resource

First, let's simulate creating a resource outside of Terraform (like someone creating an Aurora cluster in the AWS Console).

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab05-import
```

```bash
cd ~/terraform-labs/lab05-import
```

Create files that represent "manually created" infrastructure:

```bash
echo "# Security group created in AWS Console by junior DBA
allow 10.0.1.0/24 port 5432
allow 10.0.2.0/24 port 5432
allow 172.16.5.10/32 port 5432" > ~/terraform-labs/lab05-import/manual-sg.conf
```

```bash
echo "# Aurora cluster created in AWS Console
cluster_id=legacy-aurora-prod
engine=aurora-postgresql
version=16.4
instance_class=db.r6g.large
encrypted=true
backup_retention=14" > ~/terraform-labs/lab05-import/manual-aurora.conf
```

These files exist on disk but Terraform does not know about them. This simulates the real-world scenario where resources exist in AWS but are not in Terraform state.

---

## Step 3: Write the Terraform Configuration

Now write HCL that describes the existing resources. In the real world, you would look at the AWS Console to get the resource's settings and write matching HCL.

```bash
vi ~/terraform-labs/lab05-import/main.tf
```

Press `i` to enter insert mode and type:

```hcl
# main.tf - Configuration for resources we want to import

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# This resource block describes the manually-created security group config
resource "local_file" "security_group" {
  content  = "# Security group created in AWS Console by junior DBA\nallow 10.0.1.0/24 port 5432\nallow 10.0.2.0/24 port 5432\nallow 172.16.5.10/32 port 5432"
  filename = "${path.module}/manual-sg.conf"
}

# This resource block describes the manually-created Aurora cluster config
resource "local_file" "aurora_cluster" {
  content  = "# Aurora cluster created in AWS Console\ncluster_id=legacy-aurora-prod\nengine=aurora-postgresql\nversion=16.4\ninstance_class=db.r6g.large\nencrypted=true\nbackup_retention=14"
  filename = "${path.module}/manual-aurora.conf"
}

output "sg_file" {
  value = local_file.security_group.filename
}

output "aurora_file" {
  value = local_file.aurora_cluster.filename
}
```

Save and exit (`:wq`).

---

## Step 4: Initialize Terraform

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/local versions matching "~> 2.0"...
- Installing hashicorp/local v2.5.1...

Terraform has been successfully initialized!
```

---

## Step 5: See What Happens Without Import

If you run `terraform plan` now, Terraform will want to CREATE these resources because they are not in state:

```bash
terraform plan
```

Expected output (yours will differ):

```
  # local_file.aurora_cluster will be created
  + resource "local_file" "aurora_cluster" { ... }

  # local_file.security_group will be created
  + resource "local_file" "security_group" { ... }

Plan: 2 to add, 0 to change, 0 to destroy.
```

But the files already exist. If these were Aurora clusters, `terraform apply` would fail with "cluster already exists" errors. We need to import instead.

---

## Step 6: Import the Existing Resources

The `terraform import` command tells Terraform "this resource block in my HCL corresponds to this real-world resource."

**Format:**

```
terraform import <resource_address> <real_world_id>
```

For `local_file`, the ID is the file path. For AWS resources, the ID varies by resource type.

Import the security group config:

```bash
terraform import local_file.security_group ~/terraform-labs/lab05-import/manual-sg.conf
```

- `local_file.security_group` - the resource address in your `.tf` file
- `~/terraform-labs/lab05-import/manual-sg.conf` - the real-world identifier of the existing resource

Expected output:

```
local_file.security_group: Importing from ID "..."
local_file.security_group: Import prepared!
  Prepared local_file for import
local_file.security_group: Refreshing state...

Import successful! The resources that were imported are shown above.
```

Import the Aurora cluster config:

```bash
terraform import local_file.aurora_cluster ~/terraform-labs/lab05-import/manual-aurora.conf
```

Expected output:

```
local_file.aurora_cluster: Importing from ID "..."
local_file.aurora_cluster: Import prepared!
local_file.aurora_cluster: Refreshing state...

Import successful!
```

---

## Step 7: Verify - Plan Should Show No Changes

After importing, `terraform plan` should show no changes if your HCL exactly matches the real resource:

```bash
terraform plan
```

Expected output:

```
local_file.security_group: Refreshing state...
local_file.aurora_cluster: Refreshing state...

No changes. Your infrastructure matches the configuration.
```

**This is the goal.** "No changes" means your HCL perfectly describes the existing resource. Terraform can now manage it going forward.

---

## Step 8: Check State After Import

```bash
terraform state list
```

Expected output:

```
local_file.aurora_cluster
local_file.security_group
```

Both resources are now in state. Terraform tracks them.

```bash
terraform state show local_file.security_group
```

Expected output (yours will differ):

```
# local_file.security_group:
resource "local_file" "security_group" {
    content              = "# Security group created in AWS Console..."
    filename             = "./manual-sg.conf"
    id                   = "..."
    ...
}
```

---

## Step 9: What Happens When HCL Does Not Match

In real imports, the first `terraform plan` after import almost always shows differences. Your HCL rarely matches the real resource perfectly on the first try.

Let's simulate this. Edit the HCL to be slightly different from reality:

```bash
vi ~/terraform-labs/lab05-import/main.tf
```

Change the security group content to add a new rule:

```hcl
resource "local_file" "security_group" {
  content  = "# Security group created in AWS Console by junior DBA\nallow 10.0.1.0/24 port 5432\nallow 10.0.2.0/24 port 5432\nallow 172.16.5.10/32 port 5432\nallow 10.0.3.0/24 port 5432"
  filename = "${path.module}/manual-sg.conf"
}
```

Save and exit (`:wq`).

```bash
terraform plan
```

Expected output (yours will differ):

```
  # local_file.security_group must be replaced
-/+ resource "local_file" "security_group" {
      ~ content              = <<-EOT  # forces replacement
            # Security group created in AWS Console by junior DBA
            allow 10.0.1.0/24 port 5432
            allow 10.0.2.0/24 port 5432
            allow 172.16.5.10/32 port 5432
          + allow 10.0.3.0/24 port 5432
        EOT
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Terraform detected the drift between your HCL (desired state) and reality. You have two choices:

**Option A:** Update your HCL to match reality (if the real resource is correct). Revert the content to match the actual file.

**Option B:** Apply the change (if your HCL has the correct desired state). Terraform will update the real resource.

For this lab, revert to the original content so plan shows no changes:

```bash
vi ~/terraform-labs/lab05-import/main.tf
```

Remove the added line (`allow 10.0.3.0/24 port 5432`) so it matches the original file content.

Save and exit (`:wq`).

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

---

## Step 10: AWS Import Reference

When importing real AWS resources, here are the import IDs for common database resources:

| Resource Type | Import Command | ID Format |
|---|---|---|
| Security Group | `terraform import aws_security_group.main sg-0abc123def` | Security Group ID |
| Aurora Cluster | `terraform import aws_rds_cluster.main prod-aurora` | Cluster Identifier |
| Aurora Instance | `terraform import aws_rds_cluster_instance.writer prod-aurora-writer` | Instance Identifier |
| Parameter Group | `terraform import aws_db_parameter_group.main my-params` | Parameter Group Name |
| Cluster PG | `terraform import aws_rds_cluster_parameter_group.main my-cluster-params` | Parameter Group Name |
| Subnet Group | `terraform import aws_db_subnet_group.main my-db-subnets` | Subnet Group Name |
| VPC | `terraform import aws_vpc.main vpc-0abc123def` | VPC ID |
| Subnet | `terraform import aws_subnet.db_a subnet-0abc123def` | Subnet ID |

### Real-World Import Workflow

```bash
# Step 1: Find the resource ID in AWS Console or CLI
aws rds describe-db-clusters --db-cluster-identifier prod-aurora

# Step 2: Write HCL that matches the existing cluster (check Console for all settings)

# Step 3: Import
terraform import aws_rds_cluster.main prod-aurora

# Step 4: Plan and iterate
terraform plan
# Fix any differences in your HCL
# Repeat until plan shows "No changes"
```

---

## Step 11: Clean Up

```bash
terraform destroy -auto-approve
```

Expected output:

```
Destroy complete! Resources: 2 destroyed.
```

---

## What You Learned

| Concept | Command | DBA Analogy |
|---|---|---|
| Import existing resource | `terraform import <addr> <id>` | `pg_dump` to capture existing schema |
| Write matching HCL | Manual process | Writing DDL that matches existing tables |
| Verify with plan | `terraform plan` (should show "No changes") | Schema diff tool showing zero differences |
| Iterate on mismatches | Edit HCL, re-plan | Fixing DDL until it matches production |
| Resource IDs | Varies by resource type | Like knowing the OID of a PostgreSQL object |

---

**Next:** [BUILD 06 - Terraform Destroy and Lifecycle](06-terraform-destroy-and-lifecycle.md) - Learn targeted destroy, prevent_destroy, create_before_destroy, and ignore_changes.
