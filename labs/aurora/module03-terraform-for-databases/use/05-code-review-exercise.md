# USE 05: Code Review Exercise - Find the Bugs

**Module:** DevOps DBA Training Track - Module 03
**Time Estimate:** 30-45 minutes
**Prerequisites:** BUILD 01-06 completed
**Lab Type:** Reading exercise (no resources created)

---

## The Scenario

A junior DevOps engineer has submitted a pull request with Terraform code to provision a production Aurora PostgreSQL cluster. As the Lead DBA, you need to review the code and find all the issues before it gets deployed.

There are **15 issues** hidden in the code below. Find them all.

---

## The Code to Review

### File 1: providers.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

### File 2: variables.tf

```hcl
variable "db_password" {
  description = "Master password"
  type        = string
}

variable "environment" {
  type    = string
  default = "production"
}
```

### File 3: aurora.tf

```hcl
resource "aws_rds_cluster" "production" {
  cluster_identifier = "prod-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  database_name   = "proddb"
  master_username = "postgres"
  master_password = "SuperSecret123!"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  backup_retention_period = 1
  storage_encrypted       = false
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "prod-aurora"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "prod-aurora-writer"
  cluster_identifier = aws_rds_cluster.production.id
  instance_class     = "db.t3.micro"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  publicly_accessible = true

  tags = {
    Name = "prod-aurora-writer"
  }
}

resource "aws_rds_cluster_instance" "readers" {
  count = 0

  identifier         = "prod-aurora-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.production.id
  instance_class     = "db.t3.micro"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  publicly_accessible = true
}
```

### File 4: security.tf

```hcl
resource "aws_security_group" "aurora" {
  name   = "prod-aurora-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## Your Task

For each issue you find, document:

1. **File and line** - Which file and which section
2. **Issue** - What is wrong
3. **Risk** - What could happen if this goes to production
4. **Fix** - What the code should say instead

---

## Answer Sheet

Write your findings in this format:

```
Issue 1:
  File: providers.tf
  Issue: [description]
  Risk: [what could happen]
  Fix: [corrected code]
```

Try to find all 15 before looking at the answers below.

---

## Answers

<details>
<summary>Click to reveal all 15 issues</summary>

### Issue 1: No provider version constraint

**File:** providers.tf
**Issue:** The AWS provider has no `version` constraint
**Risk:** A major provider update could break the configuration or change resource behavior
**Fix:** Add `version = "~> 5.0"` to the required_providers block

### Issue 2: Hardcoded AWS credentials

**File:** providers.tf
**Issue:** `access_key` and `secret_key` are hardcoded in the provider block
**Risk:** Credentials are committed to Git. Anyone with repo access has AWS admin access. This is a critical security vulnerability
**Fix:** Remove both lines. Use environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) or AWS profiles instead

### Issue 3: Hardcoded region

**File:** providers.tf
**Issue:** Region is hardcoded as `"us-east-1"` instead of using a variable
**Risk:** Cannot reuse this configuration for other regions without editing the file
**Fix:** Use `region = var.aws_region` and add an `aws_region` variable

### Issue 4: Password variable not marked sensitive

**File:** variables.tf
**Issue:** `db_password` is missing `sensitive = true`
**Risk:** Password will be displayed in plain text in plan/apply output
**Fix:** Add `sensitive = true` to the variable block

### Issue 5: Invalid environment default

**File:** variables.tf
**Issue:** Default environment is `"production"` but the code uses `"prod"` naming
**Risk:** Naming inconsistency. If validation were added, this would fail
**Fix:** Use `"prod"` as the default, and add a validation rule

### Issue 6: Hardcoded master password in resource

**File:** aurora.tf
**Issue:** `master_password = "SuperSecret123!"` is hardcoded instead of using `var.db_password`
**Risk:** Password is in plain text in the `.tf` file, committed to Git. Anyone with repo access knows the production database password
**Fix:** Use `master_password = var.db_password`

### Issue 7: Backup retention too low for production

**File:** aurora.tf
**Issue:** `backup_retention_period = 1` - only 1 day of backups
**Risk:** If corruption or data loss is not detected within 24 hours, recovery is impossible. Production should have 14-35 days
**Fix:** Set `backup_retention_period = 14` or higher

### Issue 8: Storage not encrypted

**File:** aurora.tf
**Issue:** `storage_encrypted = false`
**Risk:** Data at rest is not encrypted. Fails compliance requirements (HIPAA, SOC2, PCI-DSS). If the underlying storage is compromised, data is readable
**Fix:** Set `storage_encrypted = true`

### Issue 9: No final snapshot on deletion

**File:** aurora.tf
**Issue:** `skip_final_snapshot = true` in production
**Risk:** If the cluster is deleted (accidentally or intentionally), there is no final backup. Data loss is permanent
**Fix:** Set `skip_final_snapshot = false` and add `final_snapshot_identifier = "prod-aurora-final-snapshot"`

### Issue 10: No deletion protection

**File:** aurora.tf
**Issue:** `deletion_protection = false` in production
**Risk:** Anyone with AWS access or Terraform permissions can delete the production database with a single command
**Fix:** Set `deletion_protection = true` and add `lifecycle { prevent_destroy = true }`

### Issue 11: db.t3.micro is below Aurora minimum

**File:** aurora.tf
**Issue:** `instance_class = "db.t3.micro"` - this is not a valid Aurora instance class
**Risk:** `terraform apply` will fail with an error. Aurora minimum is `db.t3.medium`
**Fix:** Use `db.t3.medium` or larger. For production, use `db.r6g.large` or bigger

### Issue 12: Zero readers in production

**File:** aurora.tf
**Issue:** `count = 0` for readers - production has no read replicas
**Risk:** No high availability. If the writer fails, failover has no target. The cluster is effectively a single point of failure
**Fix:** Set `count = 1` at minimum, ideally `count = 2` for production

### Issue 13: Publicly accessible instances

**File:** aurora.tf
**Issue:** `publicly_accessible = true` on both writer and readers
**Risk:** The production database is directly accessible from the internet. Combined with the security group issue (below), anyone on the internet can attempt to connect
**Fix:** Set `publicly_accessible = false` for production. Access should go through a VPN or bastion host

### Issue 14: Security group allows all ports from everywhere

**File:** security.tf
**Issue:** Ingress allows ports 0-65535 from `0.0.0.0/0` (everywhere)
**Risk:** The entire internet can connect to ALL ports on the database. This is a critical security vulnerability - effectively no firewall at all
**Fix:** Restrict to port 5432 only, and limit `cidr_blocks` to specific known IPs or CIDR ranges (app servers, DBA VPN)

### Issue 15: No parameter groups defined

**File:** aurora.tf (missing)
**Issue:** No cluster parameter group or instance parameter group is defined
**Risk:** The cluster uses the default parameter group, which cannot be modified. You cannot set `log_connections`, `shared_preload_libraries`, or any other custom parameter. No audit logging, no pg_stat_statements
**Fix:** Create `aws_rds_cluster_parameter_group` and `aws_db_parameter_group` resources with DBA-standard parameters

</details>

---

## Bonus: Write the Corrected Version

After finding all 15 issues, write the corrected Terraform code. This is excellent practice for combining everything you learned in BUILD 01-06.

---

## Scoring Guide

| Issues Found | Score |
|---|---|
| 13-15 issues | Excellent - production DBA ready |
| 10-12 issues | Good - solid understanding of security and best practices |
| 7-9 issues | Adequate - review the security and lifecycle sections |
| 4-6 issues | Needs improvement - re-read BUILD guides |
| 0-3 issues | Review all BUILD guides and concepts before proceeding |

| Category | Issues in Category |
|---|---|
| Security | Issues 2, 6, 13, 14 (credentials, passwords, network access) |
| Data Protection | Issues 7, 8, 9, 10 (backups, encryption, deletion protection) |
| Configuration | Issues 1, 3, 4, 5, 15 (version pinning, variables, parameters) |
| Architecture | Issues 11, 12 (instance sizing, high availability) |
