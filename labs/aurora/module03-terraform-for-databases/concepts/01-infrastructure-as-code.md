# Concepts 01: Infrastructure as Code - Why It Matters for DBAs

**Module:** DevOps DBA Training Track - Module 03
**Reading Time:** 20-25 minutes

---

## The Problem IaC Solves

You have managed databases for years. You know the pain of undocumented infrastructure.

Someone asks: "What instance class is the production Aurora cluster running?" You SSH into a jump box, open the AWS Console, click through five screens, and find the answer. Then someone asks about staging. You repeat the process.

Now multiply that by 15,000 databases across 11 datacenters. That is not sustainable.

**Without Infrastructure as Code:**

- "Who created this Aurora cluster? What settings did they use?"
- "Can we recreate the staging environment? I think it was a db.r6g.large... maybe db.r6g.xlarge?"
- "Someone changed the security group in the console. What was it before?"
- "The DR environment does not match production. When did they diverge?"

**With Infrastructure as Code:**

- Every resource is defined in a `.tf` file, checked into Git
- `git log` shows who changed what and when
- `git diff` shows exactly what changed
- Any environment can be recreated from scratch by running `terraform apply`
- DR is guaranteed to match production because they share the same module

This is the same evolution you went through with database schemas. You stopped creating tables by clicking in pgAdmin and started writing DDL scripts. IaC is that same discipline applied to everything outside the database.

---

## The DBA Analogy - You Already Know IaC

Think about how you manage database schemas. You do not open a GUI, click "New Table," and fill in forms. Instead, you write a DDL script:

```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
);
```

That script is **repeatable**. You can run it on dev, staging, and production and get the exact same table every time. You check it into Git. You review changes in pull requests.

**Infrastructure as Code is the same idea, but for servers, networks, and databases instead of tables and indexes.**

Instead of clicking around in the AWS Console to create an Aurora cluster, you write a configuration file that says "I want an Aurora PostgreSQL 16 cluster, db.r6g.large, with 2 readers, in us-east-1." Terraform reads that file and makes it happen.

| DBA Concept | IaC Equivalent |
|---|---|
| DDL scripts (CREATE TABLE) | `.tf` configuration files |
| Running a migration | `terraform apply` |
| Schema version control | Git + `.tf` files |
| `pg_catalog` (what exists) | `terraform.tfstate` |
| `EXPLAIN ANALYZE` | `terraform plan` |
| `DROP TABLE` | `terraform destroy` |
| `postgresql.conf` | Parameter group in `.tf` file |
| `pg_hba.conf` | Security group in `.tf` file |

The state file (`terraform.tfstate`) deserves special attention. Just like PostgreSQL uses `pg_catalog` to track every table, index, and constraint, Terraform uses its state file to track every resource it manages. Lose `pg_catalog` and PostgreSQL cannot function. Lose `terraform.tfstate` and Terraform does not know what infrastructure exists.

---

## Declarative vs Imperative - Two Approaches

There are two ways to define infrastructure in code. Understanding the difference matters because it affects how you think about changes.

### Imperative (Step-by-Step Instructions)

Imperative code tells the system **how** to get to the desired state. It is a list of commands to execute in order.

```bash
# Imperative: Create an Aurora cluster step by step
aws rds create-db-subnet-group --db-subnet-group-name my-subnets --subnet-ids subnet-abc subnet-def
aws rds create-db-cluster --db-cluster-identifier my-aurora --engine aurora-postgresql --master-username dbadmin --master-password secret123
aws rds create-db-instance --db-instance-identifier my-aurora-writer --db-cluster-identifier my-aurora --engine aurora-postgresql --db-instance-class db.r6g.large
```

If you run this script twice, it fails the second time because the resources already exist. You need to add `if not exists` checks everywhere. You need to handle every possible starting state.

**DBA analogy:** This is like writing raw SQL without migrations. You manually run commands and hope you remember the right order.

### Declarative (Desired End State)

Declarative code tells the system **what** you want the end state to look like. The tool figures out how to get there.

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier = "my-aurora"
  engine             = "aurora-postgresql"
  master_username    = "dbadmin"
  master_password    = var.db_password
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "my-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.main.engine
}
```

Run this once and Terraform creates everything. Run it again and Terraform says "No changes." Change the `instance_class` to `db.r6g.xlarge` and run it again - Terraform modifies only that one attribute. It figures out the diff automatically.

**DBA analogy:** This is like writing a schema migration that checks `IF NOT EXISTS`. Or better - it is like Flyway or Liquibase, where you declare the desired schema and the tool computes the migration.

| Approach | How It Works | Idempotent? | Tools |
|---|---|---|---|
| Imperative | "Run these commands in order" | No (fails if run twice) | Bash scripts, AWS CLI |
| Declarative | "Make it look like this" | Yes (safe to run repeatedly) | Terraform, CloudFormation |

Terraform is declarative. You describe what you want. Terraform computes the diff between desired state and current state, then makes the minimum changes needed.

---

## Terraform vs the Alternatives

There are several IaC tools. Here is how they compare from a DBA perspective.

### Terraform (HashiCorp)

- **Type:** Declarative, multi-cloud
- **Language:** HCL (HashiCorp Configuration Language)
- **State:** Explicit state file (local or remote)
- **Strengths:** Works with AWS, GCP, Azure, and 3,000+ providers. Massive community. Excellent for managing Aurora, RDS, and cloud databases
- **Weaknesses:** State management adds complexity. HCL is yet another language to learn

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier = "prod-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"
}
```

### AWS CloudFormation

- **Type:** Declarative, AWS-only
- **Language:** YAML or JSON
- **State:** Managed by AWS (no state file to worry about)
- **Strengths:** Native AWS integration. No state management headaches. AWS handles rollbacks
- **Weaknesses:** AWS only - useless for GCP, Azure, or on-prem. YAML templates get extremely verbose. Slower to adopt new AWS features than Terraform

```yaml
Resources:
  AuroraCluster:
    Type: AWS::RDS::DBCluster
    Properties:
      DBClusterIdentifier: prod-aurora
      Engine: aurora-postgresql
      EngineVersion: "16.4"
```

### Pulumi

- **Type:** Declarative, multi-cloud
- **Language:** Python, TypeScript, Go, C# (real programming languages)
- **State:** Managed by Pulumi Cloud or self-hosted
- **Strengths:** Use languages you already know. Full programming constructs (loops, conditionals, functions). Great testing support
- **Weaknesses:** Smaller community than Terraform. Vendor lock-in to Pulumi Cloud for state (unless you self-host)

```python
import pulumi_aws as aws

cluster = aws.rds.Cluster("prod-aurora",
    cluster_identifier="prod-aurora",
    engine="aurora-postgresql",
    engine_version="16.4",
)
```

### Ansible

- **Type:** Imperative (with some declarative modules), multi-cloud
- **Language:** YAML playbooks
- **State:** No state file - checks current state on every run
- **Strengths:** Excellent for configuration management (installing packages, editing files). Great for on-prem servers. Agentless
- **Weaknesses:** Not purpose-built for cloud infrastructure. No state tracking means slower execution. Complex cloud deployments get messy

```yaml
- name: Create Aurora cluster
  amazon.aws.rds_cluster:
    db_cluster_identifier: prod-aurora
    engine: aurora-postgresql
    engine_version: "16.4"
    state: present
```

### Which Should a DBA Learn?

| Scenario | Recommended Tool |
|---|---|
| Managing AWS databases (RDS, Aurora) | **Terraform** - most popular, best community support |
| AWS-only shop, team already uses CloudFormation | **CloudFormation** - if everyone uses it, stay consistent |
| Team of developers who know Python/TypeScript | **Pulumi** - leverage existing language skills |
| On-prem servers + database configuration | **Ansible** - best for server-level config management |
| Multi-cloud (AWS + GCP + Azure) | **Terraform** - only tool that handles all three well |

For this training track, we use **Terraform** because:

1. It is the most widely adopted IaC tool in the industry
2. It has the best support for Aurora and AWS database services
3. Most DBA job postings that mention IaC mention Terraform
4. The skills transfer across cloud providers

---

## State Management - The Core Concept

State is what makes Terraform powerful - and what makes it dangerous if mismanaged.

### What Is State?

After you run `terraform apply`, Terraform creates a file called `terraform.tfstate`. This JSON file records every resource Terraform manages, including:

- The resource type and name from your `.tf` file
- The real-world ID (like `db-ABC123DEF`)
- Every attribute of the resource (instance class, engine version, endpoint, etc.)
- Dependencies between resources

### Why Does State Exist?

Terraform needs state for three reasons:

**1. Mapping configuration to reality**

Your `.tf` file says `resource "aws_rds_cluster" "main"`. AWS knows it as `arn:aws:rds:us-east-1:123456789:cluster:prod-aurora`. State connects these two identities.

Without state, Terraform would not know which real AWS resource corresponds to which block in your configuration. It would be like PostgreSQL without `pg_catalog` - the engine would have no idea which files on disk correspond to which tables.

**2. Performance**

Instead of querying the AWS API for every resource in your account, Terraform reads state first and only checks resources it manages. For large infrastructures with hundreds of resources, this saves minutes of API calls.

**3. Collaboration**

When stored remotely (S3 + DynamoDB), state acts as a shared source of truth. The DynamoDB lock works like a PostgreSQL advisory lock - it prevents two engineers from modifying infrastructure simultaneously.

### State Rules

| Rule | Why | DBA Analogy |
|---|---|---|
| Never edit state by hand | Same reason you never manually edit pg_catalog | Direct catalog manipulation corrupts the database |
| Never commit state to Git | State contains secrets (passwords, keys) | You would not commit pg_hba.conf with plaintext passwords |
| Back up your state | Losing state means Terraform forgets everything | Losing pg_catalog means rebuilding the entire catalog |
| One state per environment | Prevents dev changes from affecting prod | Separate databases for dev/staging/prod |
| Use remote state for teams | Local state cannot be shared safely | Shared PostgreSQL vs SQLite on one laptop |

### What Happens When You Lose State?

If you delete `terraform.tfstate`:

1. Terraform thinks no resources exist
2. Running `terraform apply` tries to create everything from scratch
3. Creation fails because the resources already exist in AWS
4. You must `terraform import` every resource one by one to rebuild state

This is the IaC equivalent of losing `pg_catalog`. The data (infrastructure) still exists, but the system that tracks it is gone. Recovery is possible but painful.

---

## The Terraform Workflow

Every Terraform operation follows a predictable pattern:

```
1. Write    - Create/edit .tf files (your desired state)
2. Init     - terraform init (download providers, like CREATE EXTENSION)
3. Plan     - terraform plan (preview changes, like EXPLAIN)
4. Apply    - terraform apply (execute changes, like running the DDL)
5. Verify   - Check that everything works (connect with psql, check Console)
6. Destroy  - terraform destroy (when done with lab/temp resources)
```

### terraform init

Downloads provider plugins (like `CREATE EXTENSION`). Run once per project, or when you add new providers.

### terraform plan

The DBA's best friend. Shows exactly what will change without changing anything. Read the plan like a query execution plan - understand what Terraform will do before letting it do it.

### terraform apply

Executes the changes. Always shows the plan first and asks for confirmation. Type `yes` only after reviewing every line of the plan.

### terraform destroy

Removes everything Terraform created. Like `DROP DATABASE` - powerful and permanent. Always verify you are in the right directory and the right environment before running this.

---

## Key Terminology

| Term | Definition | DBA Analogy |
|---|---|---|
| **Provider** | Plugin that connects Terraform to a cloud platform (AWS, GCP, Azure) | Database driver (libpq, JDBC) |
| **Resource** | A single piece of infrastructure (an Aurora cluster, a security group) | A database object (table, index) |
| **Data Source** | A read-only reference to existing infrastructure | `SELECT` from `information_schema` |
| **Module** | A reusable package of Terraform configuration | Stored procedure / function |
| **State** | JSON file tracking what Terraform manages | `pg_catalog` |
| **Backend** | Where state is stored (local file, S3, etc.) | Where pg_catalog lives (local vs shared storage) |
| **Plan** | Preview of changes Terraform will make | `EXPLAIN ANALYZE` output |
| **Apply** | Execute the planned changes | Running the DDL migration |
| **Workspace** | Named state isolation within a project | Schema within a database |
| **Variable** | Configurable input parameter | Function parameter |
| **Output** | Value exposed after apply | `RETURNING` clause result |
| **HCL** | HashiCorp Configuration Language - Terraform's config syntax | SQL is to databases as HCL is to infrastructure |
| **Drift** | When real infrastructure differs from Terraform state | When a table was altered outside of migrations |

---

## IaC Maturity Model for DBA Teams

Most DBA teams do not go from zero to full IaC overnight. Here is a realistic progression:

### Level 0: Console Cowboys

Everything is done in the AWS Console. No documentation. No repeatability. "It works, do not touch it."

### Level 1: Scripted

Bash scripts wrap AWS CLI commands. Better than clicking, but scripts are fragile and not idempotent. Running a script twice often breaks things.

### Level 2: Basic Terraform

Infrastructure is defined in `.tf` files. State is local. One person runs `terraform apply` from their laptop. Changes are reviewed in Git PRs.

### Level 3: Team Terraform

Remote state (S3 + DynamoDB). Modules for reusable patterns. CI/CD pipelines run `terraform plan` on PRs. Multiple environments managed with separate state files.

### Level 4: Mature IaC

Policy as code (Sentinel, OPA). Automated drift detection. Self-service modules for developers. Automated testing of infrastructure changes. Full audit trail.

Most DBA teams should aim for Level 3. That is where you get the biggest return on investment - repeatable infrastructure, team collaboration, and safety guardrails.

---

## Summary

| Concept | Key Takeaway |
|---|---|
| Infrastructure as Code | Treat infrastructure like database schemas - versioned, reviewed, repeatable |
| Declarative vs Imperative | Declarative (Terraform) describes the end state; the tool computes the diff |
| Terraform vs alternatives | Terraform is the industry standard for cloud database infrastructure |
| State management | State is your pg_catalog - protect it, back it up, never edit it by hand |
| The workflow | Write, init, plan, review, apply, verify - every time, no shortcuts |

---

**Next:** [Concepts 02 - Terraform for DBAs](02-terraform-for-dbas.md) - DBA-specific patterns, parameter groups as code, and production safety.
