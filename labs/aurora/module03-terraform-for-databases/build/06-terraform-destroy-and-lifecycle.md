# BUILD 06: Terraform Destroy and Lifecycle Rules

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** LOCAL (no AWS cost)
**Time Estimate:** 20 minutes
**Prerequisites:** BUILD 01-05 completed

---

## What You Will Learn

How to safely destroy infrastructure, protect production databases from accidental deletion, and use lifecycle rules to control how Terraform handles resource changes.

---

## Step 1: Create the Lab Environment

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab06-lifecycle
```

```bash
cd ~/terraform-labs/lab06-lifecycle
```

```bash
vi ~/terraform-labs/lab06-lifecycle/main.tf
```

Press `i` to enter insert mode and type:

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
  type    = string
  default = "prod"
}

resource "local_file" "database_config" {
  content  = "cluster=aurora-${var.environment}\nengine=aurora-postgresql\nversion=16.4"
  filename = "${path.module}/database-${var.environment}.conf"
}

resource "local_file" "security_rules" {
  content  = "allow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-${var.environment}.conf"
}

resource "local_file" "parameters" {
  content  = "shared_buffers=8GB\nwork_mem=256MB\nmax_connections=500"
  filename = "${path.module}/parameters-${var.environment}.conf"
}

resource "local_file" "backup_config" {
  content  = "retention=35\nwindow=02:00-03:00\nencryption=AES256"
  filename = "${path.module}/backup-${var.environment}.conf"
}
```

Save and exit (`:wq`).

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output (yours will differ):

```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

---

## Step 2: Full Destroy

`terraform destroy` removes ALL resources Terraform manages. This is like `DROP DATABASE` - everything goes.

```bash
terraform destroy
```

Terraform shows the destruction plan. Note the `-` signs (opposite of `+` from creation):

```
  # local_file.backup_config will be destroyed
  - resource "local_file" "backup_config" { ... }

  # local_file.database_config will be destroyed
  - resource "local_file" "database_config" { ... }

  # local_file.parameters will be destroyed
  - resource "local_file" "parameters" { ... }

  # local_file.security_rules will be destroyed
  - resource "local_file" "security_rules" { ... }

Plan: 0 to add, 0 to change, 4 to destroy.
```

Type `yes` when prompted.

Expected output:

```
Destroy complete! Resources: 4 destroyed.
```

---

## Step 3: Targeted Destroy

Sometimes you want to destroy only one resource, not everything. Use the `-target` flag.

First, recreate everything:

```bash
terraform apply -auto-approve
```

Now destroy only the backup config:

```bash
terraform destroy -target=local_file.backup_config
```

- `-target=local_file.backup_config` - tells Terraform to only destroy this specific resource. Everything else is left alone

Type `yes` when prompted.

Expected output:

```
local_file.backup_config: Destroying...
local_file.backup_config: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

Verify only the backup config was destroyed:

```bash
terraform state list
```

Expected output:

```
local_file.database_config
local_file.parameters
local_file.security_rules
```

Three resources remain. Only the backup config was removed.

**Warning:** Use `-target` sparingly. It can leave your state in an inconsistent condition if resources depend on each other. For Aurora, destroying a security group that the cluster references would cause problems.

---

## Step 4: prevent_destroy - Block Accidental Deletion

The `prevent_destroy` lifecycle rule makes Terraform refuse to destroy a resource. This is your safety net for production databases.

Destroy remaining resources first:

```bash
terraform destroy -auto-approve
```

Now update main.tf to add `prevent_destroy`:

```bash
vi ~/terraform-labs/lab06-lifecycle/main.tf
```

Add a `lifecycle` block to the database_config resource:

```hcl
resource "local_file" "database_config" {
  content  = "cluster=aurora-${var.environment}\nengine=aurora-postgresql\nversion=16.4"
  filename = "${path.module}/database-${var.environment}.conf"

  lifecycle {
    prevent_destroy = true
  }
}
```

Save and exit (`:wq`).

Apply to create the resources:

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
but the plan calls for this resource to be destroyed.
```

Terraform **refuses** to destroy. The `prevent_destroy` rule stopped it.

### Aurora Equivalent

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier  = "prod-aurora"
  deletion_protection = true   # AWS-level protection

  lifecycle {
    prevent_destroy = true     # Terraform-level protection
  }
}
```

---

## Step 5: create_before_destroy - Zero-Gap Replacement

When Terraform needs to replace a resource (destroy old, create new), the default order is destroy first, then create. For things like parameter groups, this means a brief period where the resource does not exist.

`create_before_destroy` reverses the order: create the new one first, then destroy the old one.

Update main.tf. Change `prevent_destroy` to `false` and add `create_before_destroy` to the parameters resource:

```bash
vi ~/terraform-labs/lab06-lifecycle/main.tf
```

Update the database_config lifecycle and add one to parameters:

```hcl
resource "local_file" "database_config" {
  content  = "cluster=aurora-${var.environment}\nengine=aurora-postgresql\nversion=16.4"
  filename = "${path.module}/database-${var.environment}.conf"

  lifecycle {
    prevent_destroy = false
  }
}

resource "local_file" "parameters" {
  content  = "shared_buffers=8GB\nwork_mem=256MB\nmax_connections=500"
  filename = "${path.module}/parameters-${var.environment}.conf"

  lifecycle {
    create_before_destroy = true
  }
}
```

Save and exit (`:wq`).

```bash
terraform apply -auto-approve
```

Now if you change the parameters file in a way that forces replacement, Terraform will create the new one before destroying the old one. This prevents a gap where no parameter group exists.

### Aurora Equivalent

```hcl
resource "aws_db_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "prod-instance-params-v2"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

---

## Step 6: ignore_changes - Skip Externally Managed Attributes

Sometimes an external system modifies a resource attribute, and you want Terraform to leave it alone. The `ignore_changes` rule tells Terraform to skip specific attributes during planning.

Update main.tf to add `ignore_changes` to the security_rules resource:

```bash
vi ~/terraform-labs/lab06-lifecycle/main.tf
```

Update the security_rules resource:

```hcl
resource "local_file" "security_rules" {
  content  = "allow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-${var.environment}.conf"

  lifecycle {
    ignore_changes = [content]
  }
}
```

Save and exit (`:wq`).

```bash
terraform apply -auto-approve
```

Now manually change the file content (simulating an external change):

```bash
echo "allow 10.0.0.0/8 port 5432
allow 172.16.0.0/12 port 5432
allow 192.168.1.0/24 port 5432" > ~/terraform-labs/lab06-lifecycle/security-prod.conf
```

Run plan:

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

Terraform ignores the content change because of `ignore_changes = [content]`. Without this rule, Terraform would want to revert the file to its original content.

### Aurora Equivalent

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier = "prod-aurora"
  master_password    = var.initial_password

  lifecycle {
    # Ignore password changes - managed by Secrets Manager rotation
    ignore_changes = [master_password]
  }
}
```

Common use cases for `ignore_changes`:

| Attribute | Why Ignore It |
|---|---|
| `master_password` | Password rotated by AWS Secrets Manager |
| `engine_version` | Minor version auto-upgrades handled by AWS |
| `tags` | Another system adds cost allocation or compliance tags |

---

## Step 7: Final Cleanup

Remove the `prevent_destroy` rule (or set it to `false`) in main.tf, then destroy:

```bash
vi ~/terraform-labs/lab06-lifecycle/main.tf
```

Make sure `prevent_destroy` is `false` or remove the lifecycle block from database_config.

Save and exit (`:wq`).

```bash
terraform destroy -auto-approve
```

Expected output:

```
Destroy complete! Resources: 4 destroyed.
```

---

## Lifecycle Rules Summary

| Rule | What It Does | When to Use | DBA Analogy |
|---|---|---|---|
| `prevent_destroy = true` | Terraform refuses to destroy the resource | Production databases, critical infrastructure | `REVOKE DROP ON TABLE` |
| `create_before_destroy = true` | Create replacement before removing old | Parameter groups, security groups | Blue-green deployment |
| `ignore_changes = [attr]` | Skip specific attribute changes during plan | Externally managed attributes (password rotation) | Ignoring a column in replication |

## Production Protection Checklist

For every production Aurora cluster, use:

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier  = "prod-aurora"
  deletion_protection = true      # AWS refuses to delete
  skip_final_snapshot = false     # Creates backup before any deletion

  lifecycle {
    prevent_destroy = true        # Terraform refuses to destroy
  }
}
```

---

## What You Learned

| Concept | Command/Config | DBA Analogy |
|---|---|---|
| Full destroy | `terraform destroy` | `DROP DATABASE` |
| Targeted destroy | `terraform destroy -target=<resource>` | `DROP TABLE specific_table` |
| Block destruction | `lifecycle { prevent_destroy = true }` | `REVOKE DROP` |
| Replace safely | `lifecycle { create_before_destroy = true }` | Blue-green config swap |
| Skip attributes | `lifecycle { ignore_changes = [attr] }` | Ignoring externally managed settings |
| AWS protection | `deletion_protection = true` | AWS-level safety net |

---

**Next:** Move on to the [USE exercises](../use/01-terraform-workflow-exercise.md) to practice everything you have learned.
