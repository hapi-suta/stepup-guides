# USE 02: Write a Reusable Aurora Module

**Module:** DevOps DBA Training Track - Module 03
**Time Estimate:** 45-60 minutes
**Prerequisites:** BUILD 01-06 completed (especially BUILD 03)

**COST WARNING:** If you apply this module, it creates AWS resources that cost money. You can complete the module-writing portion without applying.

---

## The Scenario

Your company runs 12 Aurora PostgreSQL clusters across dev, staging, and production. Every time a team needs a new cluster, someone copies and pastes Terraform files from an existing project, tweaks the values, and hopes they did not miss anything.

Last week, a team forgot to enable `storage_encrypted` on their staging cluster. The week before, another team set `backup_retention_period = 1` in production.

Your DBA lead has asked you to create a reusable Terraform module that enforces standards while giving teams flexibility.

---

## Requirements

Build a module at `modules/aurora/` with the following:

### Module Inputs (variables.tf)

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_name` | string | yes | - | Name prefix for all resources |
| `environment` | string | yes | - | Must be dev, staging, or prod |
| `aws_region` | string | no | us-east-1 | AWS region |
| `db_name` | string | yes | - | Initial database name |
| `db_username` | string | no | dbadmin | Master username |
| `db_password` | string (sensitive) | yes | - | Master password |
| `engine_version` | string | no | 16.4 | Aurora PostgreSQL version |
| `writer_instance_class` | string | no | db.t3.medium | Writer instance class |
| `reader_instance_class` | string | no | db.t3.medium | Reader instance class |
| `reader_count` | number | no | 1 | Number of read replicas |
| `allowed_cidr_blocks` | list(string) | no | [] | CIDR blocks for SG ingress |
| `backup_retention_period` | number | no | 7 | Backup retention in days |
| `custom_cluster_parameters` | map(string) | no | {} | Additional cluster parameters |
| `custom_instance_parameters` | map(string) | no | {} | Additional instance parameters |

### Enforced Standards (main.tf)

The module must enforce these regardless of input:

1. `storage_encrypted = true` - always
2. `log_connections = 1` - always in cluster parameter group
3. `log_disconnections = 1` - always in cluster parameter group
4. `shared_preload_libraries = pg_stat_statements` - always in cluster parameter group
5. `backup_retention_period` minimum 7 days - add a validation rule
6. Environment validation - only dev, staging, or prod allowed

### Environment-Aware Defaults

The module should behave differently based on environment:

| Setting | dev | staging | prod |
|---|---|---|---|
| `deletion_protection` | false | false | true |
| `skip_final_snapshot` | true | true | false |
| `publicly_accessible` | true | true | false |

Use a `locals` block with conditions:

```hcl
locals {
  is_production       = var.environment == "prod"
  deletion_protection = local.is_production
  skip_final_snapshot = !local.is_production
  publicly_accessible = !local.is_production
}
```

### Module Outputs (outputs.tf)

| Output | Description |
|---|---|
| `cluster_endpoint` | Writer endpoint |
| `reader_endpoint` | Load-balanced reader endpoint |
| `port` | Cluster port |
| `database_name` | Initial database name |
| `username` | Master username |
| `cluster_id` | Cluster identifier |
| `vpc_id` | VPC ID |
| `security_group_id` | Security group ID |

---

## Directory Structure

```
exercise02/
  main.tf              # Calls the module
  variables.tf         # Top-level variables
  outputs.tf           # Surface module outputs
  providers.tf         # AWS provider
  terraform.tfvars     # Variable values
  modules/
    aurora/
      main.tf          # All resources
      variables.tf     # Module inputs
      outputs.tf       # Module outputs
```

---

## Root Configuration

Your root `main.tf` should call the module like this:

```hcl
module "dev_cluster" {
  source = "./modules/aurora"

  project_name = "ordertracker"
  environment  = "dev"
  aws_region   = var.aws_region

  db_name     = "ordertracker"
  db_password = var.db_password

  reader_count = 1

  allowed_cidr_blocks = ["${var.my_ip}/32"]

  custom_instance_parameters = {
    "log_statement"              = "ddl"
    "log_min_duration_statement" = "5000"
  }
}
```

---

## Verification

### 1. Module structure check

```bash
ls modules/aurora/
```

Expected: `main.tf`, `variables.tf`, `outputs.tf`

### 2. Init and plan

```bash
terraform init
```

Expected: `Initializing modules... - dev_cluster in modules/aurora`

```bash
terraform plan
```

Expected: All resources prefixed with `module.dev_cluster.`

### 3. Test validation rules

```bash
terraform plan -var="db_password=test" -var="my_ip=1.2.3.4"
```

This should succeed (dev environment).

### 4. Test environment validation

In your tfvars, change environment to "test" and verify it fails:

Expected error: `Environment must be dev, staging, or prod.`

### 5. Test backup retention validation

Set `backup_retention_period = 3` in the module call and verify it fails.

---

## Bonus Challenges

### Challenge 1: Add a staging cluster

Add a second module call for staging with different settings:

```hcl
module "staging_cluster" {
  source = "./modules/aurora"

  project_name   = "ordertracker"
  environment    = "staging"
  reader_count   = 2
  # ...
}
```

### Challenge 2: Add tags variable

Add a `tags` variable to the module that lets callers add custom tags, merged with the module's default tags:

```hcl
variable "additional_tags" {
  type    = map(string)
  default = {}
}

locals {
  common_tags = merge({
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.additional_tags)
}
```

### Challenge 3: Dynamic reader instance classes

Instead of a single `reader_instance_class`, accept a map so each reader can have a different size:

```hcl
variable "readers" {
  type = map(string)
  default = {
    "reader-1" = "db.t3.medium"
  }
}
```

---

## Scoring Guide

| Criterion | Points |
|---|---|
| Module directory structure correct | 10 |
| All required variables with types/descriptions | 10 |
| Validation rules (environment, backup retention) | 10 |
| Enforced standards (encryption, logging) | 15 |
| Environment-aware defaults (locals block) | 15 |
| Dynamic blocks for parameters and SG rules | 10 |
| All outputs defined | 10 |
| Root config calls module correctly | 10 |
| terraform init + plan succeeds | 10 |
| **Total** | **100** |
