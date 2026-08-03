# BUILD 01: Terraform Fundamentals - Infrastructure as Code

**Module:** DBA Automation & DevOps - Module 01
**Lab Type:** LOCAL (runs on your Mac with local resources)
**Time Estimate:** 45-60 minutes
**Prerequisites:** Python fundamentals (00a-00c), comfortable with terminal, SQL/PostgreSQL experience

---

## What You Will Build

By the end of this guide, you will have Terraform installed on your Mac and will have created, inspected, modified, and destroyed infrastructure using code. No AWS account needed - everything runs locally.

---

## Step 1: Understand Infrastructure as Code (IaC)

You already know IaC - you just call it something different.

Think about how you manage database schemas. You do not open pgAdmin, click "New Table," and fill in a GUI form. Instead, you write a DDL script:

```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
);
```

That script is **repeatable**. You can run it on dev, staging, and production and get the exact same table every time. You check it into Git. You review changes in pull requests.

**Infrastructure as Code is the same idea, but for servers, networks, and databases instead of tables and indexes.**

Instead of clicking around in the AWS Console to create an RDS instance, you write a configuration file that says "I want a PostgreSQL 16 instance, db.r5.large, 100GB storage, in us-east-1." Terraform reads that file and makes it happen.

| DBA Concept | Terraform Equivalent |
|---|---|
| DDL scripts (CREATE TABLE) | .tf configuration files |
| Running a migration | `terraform apply` |
| Schema version control | Git + .tf files |
| pg_catalog (what exists) | terraform.tfstate |
| EXPLAIN ANALYZE | `terraform plan` |
| DROP TABLE | `terraform destroy` |

---

## Step 2: Install Terraform on Your Mac

**In your Mac terminal:**

```bash
brew install terraform
```

Expected output (yours will differ):

```
==> Downloading https://releases.hashicorp.com/terraform/1.9.x/...
==> Installing terraform
==> Summary
  /opt/homebrew/bin/terraform
```

Verify the installation:

```bash
terraform --version
```

Expected output (yours will differ):

```
Terraform v1.9.8
on darwin_arm64
```

If you see a version number, you are good to go. The exact version does not matter for this lab as long as it is 1.5 or higher.

---

## Step 3: Understand HCL - Terraform's Language

Terraform uses a language called **HCL** (HashiCorp Configuration Language). If SQL has `SELECT`, `FROM`, `WHERE` as its keywords, HCL has `resource`, `provider`, `variable`, and `output`.

Here is the mental model:

| SQL | HCL |
|---|---|
| `SELECT ... FROM table` | `data "aws_instance" "my_server" {}` |
| `CREATE TABLE ...` | `resource "aws_instance" "my_server" {}` |
| `USE extension` | `provider "aws" {}` |
| Function parameters | `variable "name" {}` |
| `RETURNING id` | `output "server_id" {}` |

HCL syntax is block-based. Every block has a **type**, an optional **label**, and a body inside curly braces:

```hcl
block_type "label1" "label2" {
  argument = "value"
  nested_block {
    another_argument = true
  }
}
```

This is similar to how SQL has structure:

```sql
CREATE TABLE label (
  column_name data_type,
  CONSTRAINT name ...
);
```

You do not need to memorize the syntax. You will learn it by writing it, just like you learned SQL.

---

## Step 4: Create Your First Terraform Project

Let's create a working directory for this lab.

**In your Mac terminal:**

```bash
mkdir -p ~/terraform-labs/lab01-fundamentals
```

```bash
cd ~/terraform-labs/lab01-fundamentals
```

Now create your first Terraform configuration file. We will use the `local` provider, which creates files on your own machine. No AWS account or cloud credentials needed.

**In `~/terraform-labs/lab01-fundamentals`, open a new file with vi:**

```bash
vi main.tf
```

Type the following content (press `i` to enter insert mode first):

```hcl
# main.tf - Your first Terraform configuration
# Think of this file like a DDL script - it declares what you want to exist

# The "resource" block is like CREATE TABLE - it tells Terraform to create something
# Format: resource "TYPE" "NAME" { ... }
#   TYPE = what kind of thing (local_file = a file on your machine)
#   NAME = your label for it (like a table alias)

resource "local_file" "hello_terraform" {
  content  = "Hello from Terraform! This file was created by infrastructure as code."
  filename = "${path.module}/hello.txt"
}
```

Save and exit vi (press `Esc`, then type `:wq` and press Enter).

Let's break down what you just wrote:

- `resource` - keyword that says "create this thing" (like `CREATE` in SQL)
- `"local_file"` - the resource type. Format is `PROVIDER_RESOURCETYPE`. Here, `local` is the provider and `file` is the resource type
- `"hello_terraform"` - your name for this resource. Used to reference it elsewhere (like a table alias)
- `content` - an argument. The text to put in the file
- `filename` - an argument. Where to create the file. `${path.module}` means "the current directory"

---

## Step 5: Initialize Terraform (terraform init)

Before Terraform can do anything, it needs to download the **providers** your configuration requires. This is like installing a PostgreSQL extension before you can use its functions.

Your `main.tf` uses `local_file`, which comes from the `local` provider. Terraform needs to download that provider plugin.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/local...
- Installing hashicorp/local v2.5.1...
- Installed hashicorp/local v2.5.1 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Notice what happened:

- Terraform read your `main.tf` and saw you need the `local` provider
- It downloaded the provider plugin (like `CREATE EXTENSION`)
- It created a `.terraform/` directory (like a local cache)
- It created `.terraform.lock.hcl` (like a dependency lock file - ensures everyone on your team uses the same provider version)

You only need to run `terraform init` once per project, or when you add new providers.

---

## Step 6: Preview Changes with terraform plan

This is the step DBAs will love. `terraform plan` is like `EXPLAIN ANALYZE` for infrastructure - it shows you exactly what Terraform **will do** without actually doing it.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
terraform plan
```

Expected output (yours will differ):

```
Terraform will perform the following actions:

  # local_file.hello_terraform will be created
  + resource "local_file" "hello_terraform" {
      + content              = "Hello from Terraform! This file was created by infrastructure as code."
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "./hello.txt"
      + id                   = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Read it like an execution plan:

- The `+` signs mean "will be created" (like seeing `INSERT` in a query plan)
- `(known after apply)` means the value will be determined at creation time (like a `SERIAL` column - you do not know the ID until the row exists)
- The summary line tells you: 1 resource will be added, 0 changed, 0 destroyed

**Always run `terraform plan` before `terraform apply`.** This is the same discipline as running `EXPLAIN` before executing an expensive query on production.

---

## Step 7: Apply the Configuration (terraform apply)

Now let's actually create the resource. This is like running your DDL script for real.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
terraform apply
```

Terraform will show you the plan again and then ask for confirmation:

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type `yes` and press Enter.

Expected output (yours will differ):

```
local_file.hello_terraform: Creating...
local_file.hello_terraform: Creation complete after 0s [id=a1b2c3d4...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Verify the file was created:

```bash
cat hello.txt
```

Expected output:

```
Hello from Terraform! This file was created by infrastructure as code.
```

Your first piece of infrastructure, created entirely from code.

---

## Step 8: Understand State Files (terraform.tfstate)

After applying, Terraform created a file called `terraform.tfstate` in your project directory. This is critical to understand.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
cat terraform.tfstate
```

You will see a JSON file that looks something like this (abbreviated):

```json
{
  "version": 4,
  "terraform_version": "1.9.8",
  "resources": [
    {
      "mode": "managed",
      "type": "local_file",
      "name": "hello_terraform",
      "instances": [
        {
          "attributes": {
            "content": "Hello from Terraform! This file was created...",
            "filename": "./hello.txt",
            "id": "a1b2c3d4..."
          }
        }
      ]
    }
  ]
}
```

**The state file is Terraform's `pg_catalog`.** Just like PostgreSQL tracks every table, index, and constraint in `pg_catalog`, Terraform tracks every resource it manages in `terraform.tfstate`.

Key rules about state files:

| Rule | Why |
|---|---|
| Never edit it by hand | Same reason you never manually edit pg_catalog |
| Never commit it to Git | It can contain secrets (passwords, keys) |
| Back it up | Losing state is like losing pg_catalog - Terraform will not know what exists |
| One state per environment | Like separate databases for dev/staging/prod |

Add this to your `.gitignore` if you ever put this in a repo:

```
*.tfstate
*.tfstate.backup
.terraform/
```

---

## Step 9: Use Variables (Reusable Configuration)

Hardcoding values in `main.tf` is like hardcoding connection strings in your application. Variables let you parameterize your configuration.

**In `~/terraform-labs/lab01-fundamentals`, create a variables file:**

```bash
vi variables.tf
```

Enter insert mode (`i`) and type:

```hcl
# variables.tf - Input parameters for your configuration
# Think of these like function parameters or GUC settings

variable "file_content" {
  description = "The content to write to the file"
  type        = string
  default     = "Default content from Terraform"
}

variable "file_name" {
  description = "The name of the output file"
  type        = string
  default     = "output.txt"
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

Save and exit (`:wq`).

Now update `main.tf` to use these variables:

```bash
vi main.tf
```

Replace the entire contents with (delete all lines with `gg` then `dG` in normal mode, then `i` to insert):

```hcl
# main.tf - Now using variables instead of hardcoded values

resource "local_file" "hello_terraform" {
  content  = "Hello from Terraform! This file was created by infrastructure as code."
  filename = "${path.module}/hello.txt"
}

resource "local_file" "dynamic_file" {
  content  = "[${var.environment}] ${var.file_content}"
  filename = "${path.module}/${var.file_name}"
}
```

Save and exit (`:wq`).

Now apply with a variable override. This is like passing a parameter to a function:

```bash
terraform apply -var="file_content=This content came from a variable" -var="environment=dev"
```

Type `yes` when prompted.

Expected output (yours will differ):

```
local_file.hello_terraform: Refreshing state...
local_file.dynamic_file: Creating...
local_file.dynamic_file: Creation complete after 0s [id=...]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Verify:

```bash
cat output.txt
```

Expected output:

```
[dev] This content came from a variable
```

Variable types in Terraform map to concepts you already know:

| Terraform Variable Type | PostgreSQL Analogy |
|---|---|
| `string` | `TEXT` |
| `number` | `INTEGER` / `NUMERIC` |
| `bool` | `BOOLEAN` |
| `list(string)` | `TEXT[]` (array) |
| `map(string)` | `JSONB` (key-value pairs) |
| `object({...})` | Composite type / row type |

---

## Step 10: Add Outputs (RETURNING Clause for Infrastructure)

When you run `INSERT INTO ... RETURNING id`, PostgreSQL gives you back useful information about what it just created. Terraform's `output` blocks do the same thing.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
vi outputs.tf
```

Enter insert mode (`i`) and type:

```hcl
# outputs.tf - Values to display after terraform apply
# Think of these like the RETURNING clause in an INSERT statement

output "hello_file_path" {
  description = "The full path to the hello.txt file"
  value       = local_file.hello_terraform.filename
}

output "dynamic_file_path" {
  description = "The full path to the dynamic file"
  value       = local_file.dynamic_file.filename
}

output "dynamic_file_id" {
  description = "The unique ID Terraform assigned to the dynamic file"
  value       = local_file.dynamic_file.id
}

output "environment" {
  description = "The current deployment environment"
  value       = var.environment
}
```

Save and exit (`:wq`).

Apply again to see the outputs:

```bash
terraform apply -var="file_content=Outputs are like RETURNING" -var="environment=staging"
```

Type `yes` when prompted.

Expected output (yours will differ):

```
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

Outputs:

dynamic_file_id = "e5f6a7b8..."
dynamic_file_path = "./output.txt"
environment = "staging"
hello_file_path = "./hello.txt"
```

You can also view outputs any time without applying:

```bash
terraform output
```

Or get a specific output (useful for scripting):

```bash
terraform output hello_file_path
```

---

## Step 11: Use .tfvars Files (Your postgresql.conf for Infrastructure)

Passing `-var` flags on the command line gets tedious fast. That is like setting every GUC parameter with `SET` commands instead of using `postgresql.conf`.

Terraform has `.tfvars` files - a dedicated place to set variable values.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
vi dev.tfvars
```

Enter insert mode (`i`) and type:

```hcl
# dev.tfvars - Variable values for the dev environment
# Think of this like postgresql.conf - a file full of parameter settings

file_content = "This is the development environment configuration"
file_name    = "dev-output.txt"
environment  = "dev"
```

Save and exit (`:wq`).

Now create one for production:

```bash
vi prod.tfvars
```

Enter insert mode (`i`) and type:

```hcl
# prod.tfvars - Variable values for the prod environment

file_content = "PRODUCTION - Handle with care"
file_name    = "prod-output.txt"
environment  = "prod"
```

Save and exit (`:wq`).

Apply using a specific tfvars file:

```bash
terraform apply -var-file="dev.tfvars"
```

Type `yes` when prompted.

Expected output (yours will differ):

```
local_file.dynamic_file: Refreshing state...
local_file.dynamic_file: Destroying... [id=...]
local_file.dynamic_file: Destruction complete after 0s
local_file.dynamic_file: Creating...
local_file.dynamic_file: Creation complete after 0s [id=...]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

Notice Terraform destroyed the old file (with staging content) and created a new one with dev content. It detected the difference between desired state and actual state, just like a schema migration tool.

Verify:

```bash
cat dev-output.txt
```

Expected output:

```
[dev] This is the development environment configuration
```

**Naming convention:** If you name a file `terraform.tfvars` or `*.auto.tfvars`, Terraform loads it automatically. Any other name (like `dev.tfvars`) requires the `-var-file` flag.

---

## Step 12: Destroy Everything (terraform destroy)

When you are done with a lab or environment, `terraform destroy` removes everything Terraform created. This is like `DROP TABLE` for your entire infrastructure.

**In `~/terraform-labs/lab01-fundamentals`:**

```bash
terraform destroy -var-file="dev.tfvars"
```

Terraform will show you a destruction plan (note the `-` signs, opposite of `+` from the creation plan):

```
Terraform will perform the following actions:

  # local_file.dynamic_file will be destroyed
  - resource "local_file" "dynamic_file" {
      - content  = "[dev] This is the development environment configuration"
      - filename = "./dev-output.txt"
      ...
    }

  # local_file.hello_terraform will be destroyed
  - resource "local_file" "hello_terraform" {
      - content  = "Hello from Terraform! This file was created..."
      - filename = "./hello.txt"
      ...
    }

Plan: 0 to add, 0 to change, 2 to destroy.
```

Type `yes` when prompted.

Expected output (yours will differ):

```
local_file.dynamic_file: Destroying... [id=...]
local_file.dynamic_file: Destruction complete after 0s
local_file.hello_terraform: Destroying... [id=...]
local_file.hello_terraform: Destruction complete after 0s

Destroy complete! Resources: 2 destroyed.
```

Verify the files are gone:

```bash
ls *.txt
```

Expected output (exact message varies by shell):

```
ls: *.txt: No such file or directory       # bash
(eval):1: no matches found: *.txt          # zsh (macOS default)
```

Clean and predictable. Every resource Terraform created, Terraform removed.

---

## Step 13: Review Your Project Structure

Let's look at what a well-organized Terraform project looks like:

```bash
ls -la
```

You should see:

```
.terraform/              # Provider plugins (like node_modules or venv)
.terraform.lock.hcl      # Provider version lock
main.tf                  # Primary resource definitions
variables.tf             # Input variable declarations
outputs.tf               # Output value declarations
dev.tfvars               # Dev environment values
prod.tfvars              # Prod environment values
terraform.tfstate        # State file (current state of resources)
terraform.tfstate.backup # Previous state backup
```

This maps to a pattern you already know:

| Terraform File | DBA Equivalent |
|---|---|
| `main.tf` | Your DDL migration script |
| `variables.tf` | Parameter declarations in a function |
| `outputs.tf` | RETURNING clause definitions |
| `dev.tfvars` | `postgresql.conf` for dev |
| `prod.tfvars` | `postgresql.conf` for prod |
| `terraform.tfstate` | `pg_catalog` snapshot |
| `.terraform/` | Extension binaries |
| `.terraform.lock.hcl` | Extension version pinning |

---

## What You Learned

| Concept | Command / File | DBA Analogy |
|---|---|---|
| Infrastructure as Code | `.tf` files | DDL scripts for infrastructure |
| Initialize project | `terraform init` | `CREATE EXTENSION` - install required plugins |
| Preview changes | `terraform plan` | `EXPLAIN ANALYZE` - see what will happen |
| Apply changes | `terraform apply` | Execute the DDL / run the migration |
| Destroy resources | `terraform destroy` | `DROP TABLE` - remove everything |
| State file | `terraform.tfstate` | `pg_catalog` - tracks what exists |
| Variables | `variable` blocks | Function parameters |
| Outputs | `output` blocks | `RETURNING` clause |
| Variable files | `.tfvars` | `postgresql.conf` - parameter value files |
| Providers | `.terraform/` directory | PostgreSQL extensions |
| HCL | Terraform's config language | SQL is to queries as HCL is to infrastructure |

---

**Next:** [BUILD 02 - Provisioning AWS RDS with Terraform](02-provisioning-aws-rds.md) - Take what you learned here and create a real PostgreSQL database in AWS.
