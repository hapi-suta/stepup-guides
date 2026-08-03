# Interview: Terraform for Database Engineers

**Module:** DBA Automation & DevOps - Module 01
**Format:** 5 questions with detailed answers. Practice explaining these out loud - interviewers want to hear you think through the problem, not recite a textbook.

---

## Question 1: What is Terraform state and why is it critical?

**What the interviewer is looking for:** Understanding of why state exists, what happens without it, and the risks of mismanaging it.

### Strong Answer

Terraform state is a JSON file (`terraform.tfstate`) that maps your configuration to real-world resources. When I write `resource "aws_db_instance" "main"` in my `.tf` file, state records that this maps to RDS instance `dba-prod-postgres` with ID `db-ABC123` in us-east-1.

The best analogy for database people: state is Terraform's `pg_catalog`. Just like PostgreSQL cannot manage tables without `pg_catalog` tracking what exists, Terraform cannot manage infrastructure without state tracking what it created.

State is critical for three reasons:

1. **Mapping** - It links config to reality. Without state, Terraform would not know that `aws_db_instance.main` corresponds to a specific RDS instance in AWS.

2. **Performance** - Instead of querying every AWS API to discover resources, Terraform reads state first and only checks the resources it manages. For large infrastructures with hundreds of resources, this is the difference between a 10-second plan and a 10-minute plan.

3. **Collaboration** - When stored remotely (S3 with DynamoDB locking), state acts as a single source of truth for the team. The DynamoDB lock works like a PostgreSQL advisory lock - it prevents two engineers from modifying infrastructure simultaneously.

The risks: if you lose state, Terraform "forgets" everything it manages. You would have to `terraform import` every resource back in, one by one. If state gets corrupted or out of sync (someone manually changes a resource in the console), `terraform plan` will show drift, and the next `apply` might make unexpected changes.

Best practices: remote state with encryption, versioning (S3 bucket versioning gives you an undo button), and locking. Never commit state to Git because it often contains plaintext secrets like database passwords.

---

## Question 2: How do you handle secrets in Terraform configurations?

**What the interviewer is looking for:** Security awareness. Understanding of multiple approaches and their tradeoffs.

### Strong Answer

There is a hierarchy of approaches, from least to most secure:

**Level 1 - Environment variables (minimum acceptable):**
Set `TF_VAR_db_password` as an environment variable. Terraform reads it automatically. The secret never appears in `.tf` files, but it is in your shell history and process environment.

```bash
export TF_VAR_db_password="the-password"
terraform apply
```

**Level 2 - Terraform variables with sensitive flag:**
Mark the variable as `sensitive = true`. Terraform will mask it in plan/apply output. But it still appears in plaintext in the state file.

```hcl
variable "db_password" {
  type      = string
  sensitive = true
}
```

**Level 3 - External secrets manager (recommended):**
Use AWS Secrets Manager or HashiCorp Vault. Terraform reads the secret at apply time via a data source. The secret lives in a purpose-built secrets store with audit logging, rotation, and access control.

```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/aurora/master-password"
}

resource "aws_rds_cluster" "main" {
  master_password = data.aws_secretsmanager_secret_version.db_password.secret_string
}
```

**Level 4 - Managed credentials (best):**
For RDS, use `manage_master_user_password = true` and let AWS manage the password entirely through Secrets Manager. Terraform never sees the password at all.

The state file concern is real - even with `sensitive = true`, the password is stored in plaintext in `terraform.tfstate`. This is why remote state must be encrypted (S3 with SSE-KMS) and access-controlled.

For database credentials specifically, I prefer Level 3 or 4 because database passwords are high-value targets. Environment variables are acceptable for CI/CD pipelines where the secret comes from the pipeline's secrets store (GitHub Secrets, GitLab CI variables).

What I never do: hardcode secrets in `.tf` files, commit `.tfvars` files containing passwords to Git, or share state files via insecure channels.

---

## Question 3: Explain the difference between terraform plan and terraform apply

**What the interviewer is looking for:** Understanding of the two-phase workflow, why it matters, and practical usage patterns.

### Strong Answer

`terraform plan` and `terraform apply` implement a two-phase commit pattern, similar to a database transaction with explicit review.

**terraform plan** reads your `.tf` configuration, reads the current state, queries the real infrastructure (AWS APIs), and computes the diff. It shows you exactly what will be created, changed, or destroyed - without making any changes. For database people, this is `EXPLAIN ANALYZE` - you see the execution plan before committing to it.

The plan output uses clear markers:
- `+` means create (like INSERT)
- `~` means modify in place (like UPDATE)
- `-` means destroy (like DELETE)
- `-/+` means destroy and recreate (like DROP + CREATE)

**terraform apply** executes the changes. By default, it generates a fresh plan and asks you to type `yes` before proceeding. The critical detail: if something changed between your `plan` and `apply`, the fresh plan in `apply` will reflect that change.

**The safer pattern** is to use plan files:

```bash
terraform plan -out=tfplan   # Generate and save the exact plan
terraform show tfplan        # Review it (or share with a colleague)
terraform apply tfplan       # Apply ONLY that exact plan
```

With `-out=tfplan`, `terraform apply` does not recompute the plan. It applies the exact set of changes you reviewed. If the infrastructure changed between plan and apply, Terraform will detect the conflict and abort.

In production, I always use plan files. In CI/CD, the pipeline runs `plan` on PR creation, posts the output as a comment for review, and only runs `apply` after approval. This is the infrastructure equivalent of requiring code review before merging to main.

One more nuance: `terraform plan` can catch problems that `terraform validate` cannot. Validate checks syntax. Plan checks syntax AND queries real APIs - it will tell you if an instance type does not exist in your region, or if you do not have permission to create a resource.

---

## Question 4: How would you manage multiple environments (dev/staging/prod) with Terraform?

**What the interviewer is looking for:** Understanding of multiple approaches, their tradeoffs, and which you would recommend.

### Strong Answer

There are three common approaches. I have used all three and have a clear preference.

**Approach 1: Workspaces**
Terraform workspaces maintain separate state files for the same configuration. You switch between `dev`, `staging`, and `prod` workspaces and use `terraform.workspace` in your config to vary behavior.

```hcl
resource "aws_db_instance" "main" {
  instance_class = terraform.workspace == "prod" ? "db.r5.large" : "db.t3.micro"
}
```

Pros: Simple, single set of `.tf` files.
Cons: All environments share the same code path. A syntax error in `main.tf` blocks all environments. No way to have staging on a slightly different Terraform version than prod.

**Approach 2: Directory-per-environment**
Separate directories for each environment, each with its own `.tf` files and state:

```
environments/
  dev/
    main.tf, variables.tf, terraform.tfvars
  staging/
    main.tf, variables.tf, terraform.tfvars
  prod/
    main.tf, variables.tf, terraform.tfvars
modules/
  postgresql-rds/
    (shared module code)
```

Pros: Complete isolation. You can change dev without any risk to prod. Each environment can use different module versions.
Cons: Duplication of boilerplate. Drift between environments if someone updates dev but forgets staging.

**Approach 3: Terragrunt (my preference for teams)**
Terragrunt wraps Terraform and provides DRY configuration across environments. You define the module once and have thin environment-specific files that set variables.

**My recommendation** depends on team size:

- Solo / small team (1-3 people): Directory-per-environment with shared modules. Simple, explicit, easy to understand.
- Larger team (4+ people): Terragrunt. Eliminates boilerplate while keeping environment isolation.
- I avoid workspaces for environment separation because the blast radius is too high - one bad apply can affect the wrong environment if you forget to switch workspaces.

For database infrastructure specifically, I want the strongest isolation possible between prod and non-prod. A DBA accidentally running `terraform apply` in the wrong workspace can destroy production. Separate directories make it physically obvious which environment you are targeting because you have to `cd` into the right directory.

---

## Question 5: A colleague manually changed an RDS instance in the AWS console. What happens on the next terraform apply?

**What the interviewer is looking for:** Understanding of state drift, how Terraform detects it, and the remediation workflow.

### Strong Answer

This is one of the most common real-world Terraform issues, especially in database teams where DBAs are used to making changes directly.

**What happens:** When you run `terraform plan`, Terraform reads the current state file, then queries the AWS API to get the actual current configuration of the RDS instance. It compares three things:

1. Your `.tf` configuration (desired state)
2. The state file (what Terraform thinks exists)
3. The actual AWS resource (what really exists)

If the colleague changed the instance class from `db.t3.micro` to `db.r5.large` in the console, `terraform plan` will show:

```
~ aws_db_instance.main
    instance_class: "db.r5.large" -> "db.t3.micro"
```

Terraform wants to change it **back** to what the `.tf` file says. If you `terraform apply`, it will downgrade the instance back to `db.t3.micro`.

**The remediation depends on intent:**

**If the console change was correct (DBA made an emergency scaling change):**
Update your `.tf` file to match the new reality. Set `instance_class = "db.r5.large"`. Now `terraform plan` shows "No changes" and the configuration is back in sync with reality.

**If the console change was a mistake:**
Run `terraform apply` and Terraform will revert the change back to what the `.tf` file specifies.

**If the console change was a different kind of modification (like adding a security group rule):**
You may need to use `terraform import` if a new resource was created, or update your configuration to include the new rule.

**Prevention strategies:**

1. Tag all Terraform-managed resources with `ManagedBy = "terraform"` so everyone knows not to touch them in the console.

2. Use IAM policies that restrict console modifications to read-only for Terraform-managed resources. Only Terraform's IAM role can modify them.

3. Run `terraform plan` on a schedule (CI cron job) to detect drift early. If drift is detected, alert the team.

4. For RDS specifically, some changes are destructive. If someone changes the engine version in the console, `terraform apply` might try to force a replacement (destroy + create), which could cause data loss. Always review `terraform plan` output carefully before applying, especially when drift is detected.

The key lesson: once you adopt Terraform, the `.tf` files are the source of truth. Manual changes create drift. Either update the code to match the change, or let Terraform revert it. Never leave state and reality out of sync.
