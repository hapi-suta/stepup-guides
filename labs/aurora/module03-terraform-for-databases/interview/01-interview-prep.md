# Interview Prep: Terraform for Database Infrastructure

**Module:** DevOps DBA Training Track - Module 03
**Format:** 18 questions with model answers. Practice explaining these out loud - interviewers want to hear you think through the problem, not recite a textbook.
**Levels:** Questions are organized from Junior to Senior. Start from the top and work your way down.

---

## Junior-Level Questions

### Question 1: What is Terraform and why would a DBA use it?

**What the interviewer is looking for:** Basic understanding of IaC and its relevance to database work.

**Model Answer:**

Terraform is an Infrastructure as Code tool that lets you define cloud resources in configuration files instead of creating them manually in the AWS Console. As a DBA, I use it to manage Aurora clusters, RDS instances, parameter groups, security groups, and all the networking that databases depend on.

The DBA analogy: Terraform configurations are to infrastructure what DDL scripts are to database schemas. Just like I would never create a production table by clicking around in pgAdmin - I write a `CREATE TABLE` statement, version it in Git, and review it in a pull request - I do the same for infrastructure with Terraform.

The main benefits for DBAs:
- Repeatability - I can recreate an entire Aurora cluster from scratch with one command
- Version control - Git history shows who changed what parameter group setting and when
- Consistency - dev, staging, and prod use the same module with different parameters
- Review process - infrastructure changes go through code review like any other change

**Red flags in candidate answers:**
- Cannot explain IaC beyond "it automates things"
- No connection to database-specific use cases
- Does not mention version control or repeatability

---

### Question 2: Explain the Terraform workflow: init, plan, apply, destroy.

**What the interviewer is looking for:** Understanding of the four core commands and when to use each.

**Model Answer:**

The workflow follows a predictable cycle:

**terraform init** downloads provider plugins and initializes the working directory. I only run this once per project, or when I add a new provider. It is like `CREATE EXTENSION` - installing the tools before you can use them.

**terraform plan** is the command I use most. It reads my configuration, checks the current state, queries AWS for the real state of resources, and shows me exactly what will change. I think of it as `EXPLAIN ANALYZE` for infrastructure - I see the execution plan before committing to it. I never skip this step.

**terraform apply** executes the changes. It shows the plan again and asks me to type `yes` before proceeding. For critical changes, I use plan files: `terraform plan -out=tfplan`, review the plan, then `terraform apply tfplan` to apply only what I reviewed.

**terraform destroy** removes all resources Terraform manages. I use this for lab and dev environments. In production, I have `prevent_destroy` lifecycle rules that block this command.

The most important discipline: always run `plan` before `apply`, and always read the entire plan output. A `~` in the plan means in-place update. A `-/+` means destroy and recreate - which for a database means potential data loss.

**Red flags:**
- Skips `terraform plan` and goes straight to `apply`
- Uses `terraform apply -auto-approve` in production
- Does not mention reviewing plan output

---

### Question 3: What is a Terraform state file and why is it important?

**What the interviewer is looking for:** Understanding of state as the mapping between config and reality.

**Model Answer:**

The state file (`terraform.tfstate`) is a JSON file that maps my Terraform configuration to real-world resources. When I write `resource "aws_rds_cluster" "main"`, state records that this corresponds to Aurora cluster `prod-aurora` with ARN `arn:aws:rds:...` in us-east-1.

For database people: state is Terraform's `pg_catalog`. Just like PostgreSQL cannot manage tables without `pg_catalog` tracking what exists, Terraform cannot manage infrastructure without state.

State is critical for three reasons:
1. **Mapping** - Links config to reality. Without it, Terraform does not know which AWS resource to manage.
2. **Performance** - Terraform reads state first instead of scanning all of AWS. For large deployments, this saves minutes.
3. **Collaboration** - Remote state (S3 + DynamoDB) acts as a shared source of truth. DynamoDB provides locking, like PostgreSQL advisory locks.

Key rules: never edit state by hand, never commit it to Git (it contains secrets), always back it up, and use remote state for team projects.

**Red flags:**
- Does not know state exists
- Thinks state is optional
- Has committed state files to Git

---

### Question 4: What is the difference between a Terraform variable and an output?

**What the interviewer is looking for:** Understanding of data flow in Terraform.

**Model Answer:**

Variables are inputs - values you pass INTO a Terraform configuration. Outputs are values that come OUT after resources are created.

DBA analogy: Variables are function parameters. Outputs are the `RETURNING` clause.

```hcl
-- Variables (inputs)
variable "db_name" { type = string }     -- Like a function parameter

-- Outputs (results)
output "endpoint" { value = aws_rds_cluster.main.endpoint }  -- Like RETURNING
```

Variables can have defaults, validation rules, and the `sensitive` flag to mask passwords. Outputs are displayed after `terraform apply` and can be referenced by other Terraform configurations.

---

## Mid-Level Questions

### Question 5: How do you manage Aurora parameter groups with Terraform?

**What the interviewer is looking for:** Knowledge of Aurora-specific Terraform resources and the two-level parameter group model.

**Model Answer:**

Aurora has two levels of parameter groups, and this trips up a lot of people on their first Aurora Terraform project.

**Cluster parameter groups** (`aws_rds_cluster_parameter_group`) apply to the entire cluster - shared settings like `shared_preload_libraries`, `log_connections`, and replication-related parameters.

**Instance parameter groups** (`aws_db_parameter_group`) apply to individual instances - settings like `log_statement`, `work_mem`, and `log_min_duration_statement`.

Both use the `aurora-postgresql16` family (not `postgres16` - that is for regular RDS).

Some parameters require a reboot. I use `apply_method = "pending-reboot"` for those. After `terraform apply`, the parameter is marked as pending but does not take effect until a reboot or failover.

I always include DBA-standard parameters in the cluster parameter group by default (log_connections, log_disconnections, pg_stat_statements) and use dynamic blocks with a `custom_parameters` map variable to let callers add additional parameters.

**Red flags:**
- Does not know the difference between cluster and instance parameter groups
- Uses `postgres16` family for Aurora (wrong family)
- Does not mention apply_method for reboot-required parameters

---

### Question 6: How do you handle secrets in Terraform?

**What the interviewer is looking for:** Security awareness and knowledge of multiple approaches.

**Model Answer:**

There is a hierarchy from least to most secure:

**Level 1 - Environment variables:** Set `TF_VAR_db_password` in the environment. The secret never appears in `.tf` files, but it is in shell history.

**Level 2 - Sensitive variables:** Mark the variable as `sensitive = true`. Terraform masks it in output, but it still appears in plaintext in the state file.

**Level 3 - External secrets manager:** Use a data source to read from AWS Secrets Manager at apply time. The secret is managed in a purpose-built secrets store with audit logging and rotation.

```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/aurora/master-password"
}
```

**Level 4 - AWS-managed credentials:** Use `manage_master_user_password = true` on the RDS/Aurora resource. AWS manages the password entirely through Secrets Manager. Terraform never sees it.

For database credentials, I always use Level 3 or 4. The state file concern is real - even with `sensitive = true`, passwords are plaintext in state. Remote state must be encrypted and access-controlled.

**Red flags:**
- Hardcodes credentials in `.tf` files
- Does not mention state file containing secrets in plaintext
- Only knows one approach

---

### Question 7: Explain Terraform modules. When would you create one?

**What the interviewer is looking for:** Understanding of code reuse and when abstraction is appropriate.

**Model Answer:**

Modules are reusable packages of Terraform configuration - the equivalent of stored procedures in PostgreSQL.

Instead of copying 200 lines of VPC + security group + parameter group + Aurora configuration every time a team needs a database, I create a module with inputs (variables) and outputs, and teams call it with their specific parameters.

I create a module when:
- The same pattern is used 3+ times
- There are standards that must be enforced (encryption, logging, backup retention)
- Teams need self-service but with guardrails

A good Aurora module enforces `storage_encrypted = true`, includes DBA-standard parameter group settings, and uses locals with environment-based conditionals to set `deletion_protection` and `skip_final_snapshot` appropriately.

I structure modules with three files: `variables.tf` (inputs), `main.tf` (resources), `outputs.tf` (return values). The root configuration calls the module with `module "name" { source = "./modules/aurora" }`.

**Red flags:**
- Creates modules for everything (over-abstraction)
- Does not mention enforcing standards
- Cannot explain inputs and outputs

---

### Question 8: What happens when someone changes an Aurora cluster in the AWS Console? How does Terraform handle it?

**What the interviewer is looking for:** Understanding of drift detection and reconciliation.

**Model Answer:**

When someone changes a resource outside of Terraform (in the Console or via CLI), it creates **drift** - the real resource no longer matches what Terraform expects.

On the next `terraform plan`, Terraform reads the state file, queries the AWS API for the actual resource, and compares three things: the `.tf` configuration (desired state), the state file (what Terraform thinks exists), and the real resource (what actually exists).

If a DBA changed the instance class from `db.t3.medium` to `db.r6g.large` in the Console, `terraform plan` will show: `instance_class: "db.r6g.large" -> "db.t3.medium"`. Terraform wants to change it BACK to what the `.tf` file says.

I handle drift based on intent:
- **If the Console change was correct** (emergency scaling): Update the `.tf` file to match, commit, and the drift is resolved.
- **If the Console change was a mistake**: Run `terraform apply` to revert it.
- **If the attribute is externally managed** (password rotation): Add `ignore_changes = [master_password]` to the lifecycle block.

Prevention: tag resources with `ManagedBy = terraform`, restrict Console write access, run automated drift detection in CI/CD.

---

### Question 9: What is the difference between count and for_each?

**What the interviewer is looking for:** Understanding of looping mechanisms and when to use each.

**Model Answer:**

Both create multiple instances of a resource, but they identify resources differently.

**count** uses numeric indexes (0, 1, 2). If you have `count = 3` readers and remove reader 1, Terraform renumbers 2 and 3, potentially destroying and recreating them.

**for_each** uses named keys. If you have readers keyed by name and remove one, only that specific reader is affected.

DBA analogy: `count` is like using array indexes. `for_each` is like using primary keys. Primary keys are always safer for identifying specific items.

For Aurora readers, I use `for_each` when readers have different configurations (different instance classes, different AZs) and `count` when they are all identical.

```hcl
# for_each - each reader has a name and custom instance class
resource "aws_rds_cluster_instance" "readers" {
  for_each       = var.readers  # map of name -> instance_class
  identifier     = "${var.cluster_id}-${each.key}"
  instance_class = each.value
}
```

---

## Senior-Level Questions

### Question 10: How would you manage multiple environments (dev/staging/prod) with Terraform?

**What the interviewer is looking for:** Architecture decisions, tradeoffs, and a clear recommendation.

**Model Answer:**

Three common approaches:

**Workspaces:** Same code, different state files per workspace. Simple, but risky - one bad apply can hit the wrong environment if you forget to switch workspaces. I avoid this for environment separation.

**Directory-per-environment:** Separate directories for dev, staging, prod. Each has its own state. Complete isolation. Drawback: some boilerplate duplication, but shared modules eliminate most of it.

**Terragrunt:** Wraps Terraform with DRY configuration. Thin environment-specific files set variables, shared modules provide resources. Best for teams of 4+.

My recommendation: directory-per-environment with shared modules for database infrastructure. The isolation is worth the small amount of duplication. You physically `cd` into the right directory, so it is obvious which environment you are targeting. Workspaces make it too easy to accidentally apply to production.

For database infrastructure specifically, I want the strongest isolation possible between prod and non-prod. The blast radius of a mistake is too high.

---

### Question 11: How do you implement terraform import for a large existing Aurora deployment?

**What the interviewer is looking for:** Real-world import experience, systematic approach.

**Model Answer:**

I follow a systematic process:

**Phase 1: Inventory.** Document every resource: cluster, instances, parameter groups, security groups, subnet groups, VPCs, subnets. Use `aws rds describe-db-clusters` and related CLI commands.

**Phase 2: Write HCL.** Create `.tf` files that describe each resource. I start with the cluster and work outward to dependencies.

**Phase 3: Import one at a time.** Start with resources that have no dependencies (VPC, subnets), then work up to dependent resources (subnet group, security group, parameter groups, cluster, instances).

**Phase 4: Iterate.** After each import, run `terraform plan`. The first plan almost always shows differences. I fix the HCL to match reality, re-plan, and repeat until "No changes."

**Phase 5: Verify.** Run a final `terraform plan` to confirm zero drift across all resources.

Common gotchas:
- `master_password` cannot be read back from AWS, so I use `ignore_changes = [master_password]`
- Default values differ between the API response and Terraform defaults
- Tags may need exact matching
- Some attributes are computed and should not be in the HCL

For a large deployment, I do this in batches - one cluster at a time, never trying to import everything at once.

---

### Question 12: Describe your approach to Terraform state management for a team of 10 DBAs managing 50+ Aurora clusters.

**What the interviewer is looking for:** Enterprise-scale state management strategy.

**Model Answer:**

At that scale, state management is critical infrastructure itself.

**State storage:** S3 bucket with versioning, encryption (SSE-KMS), and cross-region replication. Access restricted by IAM to the Terraform service role and a break-glass admin group.

**State locking:** DynamoDB table for state locking. Every `terraform apply` acquires a lock. This prevents two DBAs from modifying the same cluster simultaneously.

**State organization:** One state file per Aurora cluster (not one massive state for everything). The S3 key structure: `aurora/{cluster-name}/{environment}/terraform.tfstate`. This limits blast radius - a state corruption only affects one cluster.

**Access pattern:** DBAs do not run Terraform directly. Changes go through Git PRs. CI/CD (GitHub Actions) runs `terraform plan` on PR creation, posts the output as a comment, and runs `terraform apply` after approval. Only the CI/CD service role has write access to state.

**Backup strategy:** S3 versioning provides point-in-time recovery for state. I also run a nightly job that pulls state and archives it to a separate bucket for extra safety.

**Drift detection:** A scheduled CI job runs `terraform plan -detailed-exitcode` against every cluster every hour. If exit code is 2 (drift detected), it opens an alert for the on-call DBA.

---

### Question 13: How do you handle Terraform in a CI/CD pipeline for database infrastructure?

**What the interviewer is looking for:** Production workflow, safety checks, approval gates.

**Model Answer:**

Database infrastructure changes are higher-risk than application deployments, so the pipeline has extra safeguards.

**On PR creation:**
1. `terraform fmt -check` - ensures consistent formatting
2. `terraform validate` - syntax check
3. `terraform plan` - full plan posted as a PR comment
4. Automated checks: no `deletion_protection = false` in prod, no `publicly_accessible = true` in prod

**On PR approval + merge:**
1. `terraform plan -out=tfplan` - generate exact plan
2. Compare with the plan from the PR - if different, alert and abort
3. `terraform apply tfplan` - apply the exact reviewed plan
4. Post-apply verification: query Aurora endpoint, check parameter values

**Safeguards:**
- Production changes require two approvals (DBA + DevOps lead)
- Destructive changes (anything with `-` or `-/+` in the plan) require explicit acknowledgment
- `terraform destroy` is disabled in the prod pipeline - requires manual execution by a senior DBA with MFA

---

### Question 14: What is lifecycle.prevent_destroy and when should it be used?

**What the interviewer is looking for:** Understanding of production safety mechanisms.

**Model Answer:**

`prevent_destroy = true` is a lifecycle rule that makes Terraform refuse to plan any action that would destroy the resource. If someone runs `terraform destroy` or makes a change that forces recreation, Terraform errors out instead of proceeding.

I use it on every production database resource: Aurora clusters, RDS instances, and their critical dependencies (subnet groups, parameter groups). Combined with AWS `deletion_protection = true`, it creates two layers of safety.

To actually destroy a resource with both protections, someone needs to:
1. Remove `prevent_destroy` from the HCL (requires a code review)
2. Set `deletion_protection = false` in the HCL
3. Run `terraform apply` to update the AWS setting
4. Run `terraform destroy`

That is four deliberate steps. It does not happen by accident.

I do NOT use `prevent_destroy` in dev or staging - those environments need to be easily tearable for cost management.

---

### Question 15: How would you handle a Terraform provider upgrade that changes resource behavior?

**What the interviewer is looking for:** Upgrade strategy, risk management.

**Model Answer:**

Provider upgrades can change how resources are managed. My approach:

1. **Pin the version.** Use `version = "~> 5.0"` to allow minor updates but block majors.

2. **Test in dev first.** Update the version constraint in dev, run `terraform plan`, and look for unexpected changes. Some provider versions change default values or add new required attributes.

3. **Read the changelog.** Before upgrading, read the provider's CHANGELOG for breaking changes. The AWS provider has excellent documentation.

4. **Plan before apply.** After upgrading, run `terraform plan` on every environment before applying anything. A clean plan means the upgrade is safe.

5. **Lock file.** Commit `.terraform.lock.hcl` to ensure everyone uses the same provider version. Run `terraform init -upgrade` only when intentionally upgrading.

6. **State backup.** Before applying with a new provider version, back up the state file. If something goes wrong, restore the previous state and downgrade the provider.

---

### Question 16: Describe a production incident involving Terraform that you handled (or how you would handle one).

**What the interviewer is looking for:** Real-world experience, systematic troubleshooting.

**Model Answer:**

Scenario: A colleague ran `terraform apply` on the production Aurora configuration without noticing that someone had changed the engine version in the `.tf` file from `16.3` to `16.4`. The plan showed an in-place update for `engine_version`, which they approved. The minor version upgrade triggered a brief outage during the engine restart.

**What went wrong:**
- No separate PR review for the engine version change
- The apply was done during business hours
- The plan output was not fully reviewed (the `~` for engine_version was missed among other changes)

**How I resolved it:**
1. Confirmed the upgrade completed successfully (Aurora minor version upgrades are non-destructive)
2. Verified application connectivity
3. Checked parameter group compatibility with the new version
4. Monitored performance for anomalies

**What I changed:**
1. Added a CI check that flags engine_version changes and requires explicit DBA approval
2. Established a maintenance window policy - engine changes only during the existing maintenance window
3. Split infrastructure changes into smaller PRs - one change per PR for production
4. Added `engine_version` to a "high-risk attributes" list in our review checklist

---

### Question 17: How do you test Terraform configurations before deploying to production?

**What the interviewer is looking for:** Testing strategy, beyond just "run plan."

**Model Answer:**

I test at multiple levels:

**Static analysis:**
- `terraform validate` - syntax check
- `terraform fmt -check` - formatting consistency
- `tflint` - linter that catches provider-specific issues
- Policy checks (Sentinel or OPA) - enforce organization rules like "all Aurora clusters must have encryption enabled"

**Plan review:**
- `terraform plan` against a dev environment
- Verify resource count matches expectations
- Check for any `-/+` (destroy and recreate) actions on stateful resources
- Verify no unintended changes to existing resources

**Apply to non-prod:**
- Apply to dev first, verify with psql connection
- Apply to staging, run application integration tests
- Only then apply to production

**Post-apply verification:**
- Connect to the Aurora endpoint with psql
- Run `SHOW` commands to verify parameter settings
- Check `pg_is_in_recovery()` to confirm writer/reader roles
- Verify replication is working

---

### Question 18: If you were building a Terraform strategy from scratch for a company with 200 databases, what would you recommend?

**What the interviewer is looking for:** Strategic thinking, architecture, organizational considerations.

**Model Answer:**

I would take a phased approach:

**Phase 1 (Month 1-2): Foundation**
- Set up remote state (S3 + DynamoDB) with proper IAM
- Create a standardized Aurora module with enforced security baselines
- Import 5-10 critical clusters to prove the workflow
- Establish CI/CD pipeline for one team

**Phase 2 (Month 3-4): Scale**
- Create modules for each database engine (Aurora, RDS, ElastiCache, etc.)
- Roll out to all teams, one team at a time
- Import remaining clusters in batches
- Automated drift detection running hourly

**Phase 3 (Month 5-6): Maturity**
- Self-service module catalog for developers
- Policy as code for compliance
- Cost tagging and reporting
- Automated testing for module changes

**Key decisions:**
- Directory-per-cluster state organization (not monolithic)
- One module per engine type with environment-aware defaults
- CI/CD required for production - no direct `terraform apply`
- Import over time - do not try to import everything at once

**Common mistakes to avoid:**
- Trying to import all 200 databases in one sprint
- Building overly complex modules before teams have used basic Terraform
- Not getting buy-in from DBAs who are used to Console access
- Ignoring the cultural change - Terraform adoption is as much about process as technology

---

## Quick Reference: Red Flags in Candidate Answers

| Red Flag | What It Indicates |
|---|---|
| Hardcodes credentials in `.tf` files | Security unawareness |
| Does not know about state files | Has not used Terraform beyond tutorials |
| Uses `apply -auto-approve` in production | Dangerous operational habits |
| Cannot explain plan output symbols | Does not review plans before applying |
| Commits state files to Git | Security risk, does not understand state |
| Uses `count` for everything | Does not know `for_each` |
| No mention of `prevent_destroy` for prod | Missing production safety awareness |
| "Just run terraform destroy and recreate" | Does not understand data persistence |
| Cannot explain modules | Has not worked on team Terraform projects |
| No mention of CI/CD for infrastructure | Manual, unreviewed production changes |
