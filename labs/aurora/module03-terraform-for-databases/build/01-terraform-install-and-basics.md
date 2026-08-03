# BUILD 01: Terraform Install and Basics

**Module:** DevOps DBA Training Track - Module 03
**Lab Type:** LOCAL (runs on your Mac with local resources - no AWS cost)
**Time Estimate:** 45 minutes
**Prerequisites:** Comfortable with terminal, SQL/PostgreSQL experience

---

## What You Will Build

By the end of this guide, you will have Terraform installed on your Mac and will have created, inspected, modified, and destroyed infrastructure using code. No AWS account needed - everything runs locally.

---

## Step 1: Install Terraform

**In your terminal:**

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

If you see a version number, you are good to go. The exact version does not matter as long as it is 1.5 or higher.

If you are on Linux instead of Mac:

```bash
sudo apt-get update
```

```bash
sudo apt-get install -y gnupg software-properties-common
```

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
```

```bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

```bash
sudo apt-get update
```

```bash
sudo apt-get install terraform
```

---

## Step 2: Understand the Core Workflow

Every Terraform project follows the same cycle. Think of it like a database migration workflow:

| Step | Terraform Command | DBA Analogy |
|---|---|---|
| 1. Write config | Edit `.tf` files | Write your DDL migration script |
| 2. Initialize | `terraform init` | `CREATE EXTENSION` - install required plugins |
| 3. Preview | `terraform plan` | `EXPLAIN ANALYZE` - see what will happen |
| 4. Apply | `terraform apply` | Execute the migration |
| 5. Destroy | `terraform destroy` | `DROP TABLE` - remove everything |

---

## Step 3: Create Your First Terraform Project

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/lab01-basics
```

```bash
cd ~/terraform-labs/lab01-basics
```

Now create your first Terraform configuration file. We will use the `local` provider, which creates files on your own machine. No AWS account or cloud credentials needed.

**In `~/terraform-labs/lab01-basics`, open a new file with vi:**

```bash
vi main.tf
```

Press `i` to enter insert mode, then type the following:

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

## Step 4: Initialize Terraform (terraform init)

Before Terraform can do anything, it needs to download the **providers** your configuration requires. This is like installing a PostgreSQL extension before you can use its functions.

**In `~/terraform-labs/lab01-basics`:**

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

What happened:

- Terraform read your `main.tf` and saw you need the `local` provider
- It downloaded the provider plugin (like `CREATE EXTENSION`)
- It created a `.terraform/` directory to store the plugin (like a local cache)
- It created `.terraform.lock.hcl` to lock the provider version (ensures everyone on your team uses the same version)

You only need to run `terraform init` once per project, or when you add new providers.

---

## Step 5: Preview Changes with terraform plan

`terraform plan` shows you exactly what Terraform **will do** without actually doing it. This is like `EXPLAIN ANALYZE` for infrastructure.

**In `~/terraform-labs/lab01-basics`:**

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

**Always run `terraform plan` before `terraform apply`.** This is the same discipline as running `EXPLAIN` before executing an expensive query.

---

## Step 6: Apply the Configuration (terraform apply)

Now let's create the resource. This is like running your DDL script.

**In `~/terraform-labs/lab01-basics`:**

```bash
terraform apply
```

Terraform will show you the plan again and ask for confirmation:

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
cat ~/terraform-labs/lab01-basics/hello.txt
```

Expected output:

```
Hello from Terraform! This file was created by infrastructure as code.
```

---

## Step 7: Understand the State File

After applying, Terraform created a file called `terraform.tfstate` in your project directory.

**In `~/terraform-labs/lab01-basics`:**

```bash
cat ~/terraform-labs/lab01-basics/terraform.tfstate
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

**The state file is Terraform's `pg_catalog`.** It tracks every resource Terraform manages.

Key rules about state files:

| Rule | Why |
|---|---|
| Never edit it by hand | Same reason you never manually edit pg_catalog |
| Never commit it to Git | It can contain secrets (passwords, keys) |
| Back it up | Losing state means Terraform will not know what exists |
| One state per environment | Like separate databases for dev/staging/prod |

---

## Step 8: Understand the .terraform Directory

Let's look at the directory structure:

```bash
ls -la ~/terraform-labs/lab01-basics/
```

You should see:

```
.terraform/              # Provider plugins (like node_modules or venv)
.terraform.lock.hcl      # Provider version lock
main.tf                  # Your configuration
hello.txt                # The file Terraform created
terraform.tfstate        # State file (what Terraform manages)
```

The `.terraform/` directory contains downloaded provider plugins. It is like Python's `venv` or Node's `node_modules` - a local cache of dependencies. Never commit it to Git.

The `.terraform.lock.hcl` file pins exact provider versions. This is like a `requirements.txt` or `package-lock.json` - it ensures everyone on your team uses the same provider version. This file SHOULD be committed to Git.

---

## Step 9: Add Variables

Hardcoding values in `main.tf` is like hardcoding connection strings in your application. Variables let you parameterize your configuration.

**In `~/terraform-labs/lab01-basics`, create a variables file:**

```bash
vi ~/terraform-labs/lab01-basics/variables.tf
```

Press `i` to enter insert mode and type:

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
vi ~/terraform-labs/lab01-basics/main.tf
```

Replace the entire contents with (delete all lines with `gg` then `dG` in normal mode, then press `i` to insert):

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

Apply with a variable override:

```bash
terraform apply -var="file_content=This content came from a variable" -var="environment=dev"
```

- `-var="file_content=..."` - sets the `file_content` variable to the given value. This overrides the default. Like passing a parameter to a function

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
cat ~/terraform-labs/lab01-basics/output.txt
```

Expected output:

```
[dev] This content came from a variable
```

---

## Step 10: Add Outputs

When you run `INSERT INTO ... RETURNING id`, PostgreSQL gives you back useful information about what it just created. Terraform's `output` blocks do the same thing.

**In `~/terraform-labs/lab01-basics`:**

```bash
vi ~/terraform-labs/lab01-basics/outputs.tf
```

Press `i` to enter insert mode and type:

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

dynamic_file_path = "./output.txt"
environment = "staging"
hello_file_path = "./hello.txt"
```

You can view outputs any time without applying:

```bash
terraform output
```

Or get a specific output (useful for scripting):

```bash
terraform output hello_file_path
```

---

## Step 11: Use .tfvars Files

Passing `-var` flags on the command line gets tedious. Terraform has `.tfvars` files - a dedicated place to set variable values. Think of them like `postgresql.conf` - a file full of parameter settings.

**In `~/terraform-labs/lab01-basics`:**

```bash
vi ~/terraform-labs/lab01-basics/dev.tfvars
```

Press `i` to enter insert mode and type:

```hcl
# dev.tfvars - Variable values for the dev environment

file_content = "This is the development environment configuration"
file_name    = "dev-output.txt"
environment  = "dev"
```

Save and exit (`:wq`).

Apply using the tfvars file:

```bash
terraform apply -var-file="dev.tfvars"
```

- `-var-file="dev.tfvars"` - tells Terraform to read variable values from this file instead of the command line

Type `yes` when prompted.

Verify:

```bash
cat ~/terraform-labs/lab01-basics/dev-output.txt
```

Expected output:

```
[dev] This is the development environment configuration
```

**Naming convention:** If you name a file `terraform.tfvars` or `*.auto.tfvars`, Terraform loads it automatically. Any other name (like `dev.tfvars`) requires the `-var-file` flag.

---

## Step 12: Destroy Everything

When you are done, `terraform destroy` removes everything Terraform created. This is like `DROP TABLE` for your entire infrastructure.

**In `~/terraform-labs/lab01-basics`:**

```bash
terraform destroy -var-file="dev.tfvars"
```

- `-var-file="dev.tfvars"` - needed here because the configuration uses variables that need values. Without it, Terraform would prompt for each variable

Terraform shows a destruction plan (note the `-` signs, opposite of `+` from the creation plan):

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
      - content  = "Hello from Terraform!..."
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

---

## Step 13: Review Your Project Structure

```bash
ls -la ~/terraform-labs/lab01-basics/
```

You should see:

```
.terraform/              # Provider plugins (do not commit to Git)
.terraform.lock.hcl      # Provider version lock (commit to Git)
main.tf                  # Primary resource definitions
variables.tf             # Input variable declarations
outputs.tf               # Output value declarations
dev.tfvars               # Dev environment values
terraform.tfstate        # State file (do not commit to Git)
terraform.tfstate.backup # Previous state backup
```

| Terraform File | DBA Equivalent |
|---|---|
| `main.tf` | Your DDL migration script |
| `variables.tf` | Parameter declarations in a function |
| `outputs.tf` | RETURNING clause definitions |
| `dev.tfvars` | `postgresql.conf` for dev |
| `terraform.tfstate` | `pg_catalog` snapshot |
| `.terraform/` | Extension binaries |
| `.terraform.lock.hcl` | Extension version pinning |

---

## What You Learned

| Concept | Command / File | DBA Analogy |
|---|---|---|
| Infrastructure as Code | `.tf` files | DDL scripts for infrastructure |
| Initialize project | `terraform init` | `CREATE EXTENSION` - install plugins |
| Preview changes | `terraform plan` | `EXPLAIN ANALYZE` - see what will happen |
| Apply changes | `terraform apply` | Execute the DDL / run the migration |
| Destroy resources | `terraform destroy` | `DROP TABLE` - remove everything |
| State file | `terraform.tfstate` | `pg_catalog` - tracks what exists |
| Variables | `variable` blocks | Function parameters |
| Outputs | `output` blocks | `RETURNING` clause |
| Variable files | `.tfvars` | `postgresql.conf` - parameter value files |
| Providers | `.terraform/` directory | PostgreSQL extensions |

---

**Next:** [BUILD 02 - Provision Aurora with Terraform](02-provision-aurora-with-terraform.md) - Take what you learned here and create a real Aurora PostgreSQL cluster in AWS.
