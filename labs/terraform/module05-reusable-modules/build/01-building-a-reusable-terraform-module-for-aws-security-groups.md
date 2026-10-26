# Building a Reusable Terraform Module for AWS Security Groups

**Objective:** Install Terraform, write a reusable module that creates an AWS security group, and deploy it for two environments (dev and prod) from a single root configuration.

**Estimated Time:** 60 minutes

**Prerequisites:**
- An EC2 instance running Amazon Linux 2023 or RHEL 9, with sudo access as ec2-user
- The instance must have an IAM role attached that allows creating EC2 security groups (the engineer confirmed this via the instance metadata service)
- Basic familiarity with the Linux terminal

---

## Part 1: Install Terraform

### Step 1

On the server, as ec2-user: check whether Terraform is already installed.

```
terraform version
```

This asks the shell to find and run the `terraform` program and print its version. If you see `command not found`, Terraform is not installed and you must complete Steps 2 through 5.

```
Expected output (yours will differ):
bash: line 1: terraform: command not found
```

Check it worked: if you see a version number instead of `command not found`, Terraform is already installed - skip to Step 6.

---

### Step 2

On the server, as ec2-user: install the `yum-utils` package, which provides the `yum-config-manager` tool you need in the next step.

```
sudo yum install -y yum-utils
```

`-y` answers "yes" automatically to any prompts so the install does not wait for your input.

```
Expected output (yours will differ):
Package yum-utils-4.3.0-27.el9.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
```

Check it worked: you should see the word `Complete!` at the end of the output.

---

### Step 3

On the server, as ec2-user: add the official HashiCorp package repository so that `yum` knows where to download Terraform from.

Why this step: by default, the standard Amazon Linux repos do not include Terraform. This command tells `yum` about HashiCorp's own repo.

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`--add-repo` takes a URL pointing to a `.repo` file and saves it under `/etc/yum.repos.d/` on your system.

```
Expected output (yours will differ):
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line `Adding repo from:` followed by the HashiCorp URL.

---

### Step 4

On the server, as ec2-user: install Terraform.

```
sudo yum -y install terraform
```

`-y` automatically confirms the install. `yum` will now find Terraform in the HashiCorp repo you just added.

```
Expected output (yours will differ):
  Verifying        : terraform-1.17.0-1.x86_64                              9/9

Installed:
  terraform-1.17.0-1.x86_64

Complete!
```

Check it worked: you should see `terraform-1.17.0` (or a newer version) listed under `Installed:`.

---

### Step 5

On the server, as ec2-user: confirm Terraform is now available and check its version.

```
terraform version
```

This prints the installed version. If it runs without error, Terraform is correctly installed and on your PATH.

```
Expected output (yours will differ):
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a line starting with `Terraform v`.

---

## Part 2: Create the Directory Structure

### Step 6

On the server, as ec2-user: create the project folder and the module subfolder in one command.

Why this step: Terraform modules live in their own subdirectory. The `-p` flag creates every folder in the path, including any that do not yet exist.

```
mkdir -p /home/ec2-user/tf-lab/modules/db-sg
```

`-p` means "parents" - it creates `tf-lab`, then `modules`, then `db-sg` inside it, without complaining if any already exist.

```
Expected output (yours will differ):
(no output - silence means success)
```

Check it worked: no error message is printed. You can confirm with `ls /home/ec2-user/tf-lab/modules/` and you should see `db-sg` listed.

---

## Part 3: Write the Module Files

A Terraform module is just a folder containing `.tf` files. This module will have three files: `variables.tf` (inputs), `main.tf` (resources), and `outputs.tf` (outputs).

### Step 7

On the server, as ec2-user: open a new file called `variables.tf` inside the module folder.

```
vi /home/ec2-user/tf-lab/modules/db-sg/variables.tf
```

Press `i` to enter insert mode, then type the content below exactly. When finished, press `Escape`, then type `:wq` and press `Enter` to save and quit.

```
variable "env" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "port" {
  description = "TCP port to allow in the ingress rule"
  type        = number
}
```

What each part means:
- `variable "env"` - declares an input named `env`. The root config will pass in a value like `"dev"` or `"prod"`.
- `type = string` - enforces that the value must be text.
- `variable "port"` - declares an input named `port` for the TCP port number (for example, 5432 for PostgreSQL).
- `type = number` - enforces that the value must be a number.

```
Expected output (yours will differ):
(no output - the file is saved silently)
```

Check it worked: run `cat /home/ec2-user/tf-lab/modules/db-sg/variables.tf` and you should see both variable blocks printed.

---

### Step 8

On the server, as ec2-user: open a new file called `main.tf` inside the module folder.

```
vi /home/ec2-user/tf-lab/modules/db-sg/main.tf
```

Press `i` to enter insert mode, type the content below, then press `Escape` and type `:wq` to save.

```
resource "aws_security_group" "this" {
  name_prefix = "db-${var.env}-"
  description = "Database security group for ${var.env} environment"

  ingress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  tags = {
    Env = var.env
  }
}
```

What each part means:
- `resource "aws_security_group" "this"` - tells Terraform to create an AWS security group. `"this"` is just the local name Terraform uses to refer to it inside this module.
- `name_prefix = "db-${var.env}-"` - AWS will generate a unique name starting with this prefix, for example `db-dev-abc123`. The `${var.env}` part inserts whatever was passed in for the `env` variable.
- `ingress` block - defines a rule for incoming network traffic.
- `from_port` and `to_port` - both set to `var.port`, meaning only the single port passed in is allowed.
- `protocol = "tcp"` - only TCP traffic is allowed (not UDP or ICMP).
- `cidr_blocks = ["10.0.0.0/8"]` - traffic is only allowed from private IP addresses in the `10.x.x.x` range (your internal network). This is not open to the public internet.
- `tags` - attaches a label to the AWS resource so you can identify which environment it belongs to.

Note: there is no `provider` block in this file. Provider configuration belongs only in the root module. Modules should not include it.

```
Expected output (yours will differ):
(no output - the file is saved silently)
```

Check it worked: run `cat /home/ec2-user/tf-lab/modules/db-sg/main.tf` and you should see the full resource block printed.

---

### Step 9

On the server, as ec2-user: open a new file called `outputs.tf` inside the module folder.

```
vi /home/ec2-user/tf-lab/modules/db-sg/outputs.tf
```

Press `i`, type the content below, then press `Escape` and type `:wq` to save.

```
output "security_group_id" {
  description = "The ID of the database security group"
  value       = aws_security_group.this.id
}
```

What each part means:
- `output "security_group_id"` - declares a value that this module will expose to whoever calls it.
- `value = aws_security_group.this.id` - reads the `id` attribute from the security group resource defined in `main.tf`. After Terraform creates the group, AWS assigns it an ID like `sg-0abc123`. This output makes that ID available to the root config.

```
Expected output (yours will differ):
(no output - the file is saved silently)
```

Check it worked: run `cat /home/ec2-user/tf-lab/modules/db-sg/outputs.tf` and you should see the output block printed.

---

## Part 4: Write the Root Configuration

The root configuration ties everything together. It calls the module twice - once for dev and once for prod - with different input values each time.

### Step 10

On the server, as ec2-user: open a new file called `main.tf` in the root `tf-lab` folder (not inside the module).

```
vi /home/ec2-user/tf-lab/main.tf
```

Press `i`, type the content below, then press `Escape` and type `:wq` to save.

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "suta-cb-spike"
    }
  }
}

module "dev" {
  source = "./modules/db-sg"
  env    = "dev"
  port   = 5432
}

module "prod" {
  source = "./modules/db-sg"
  env    = "prod"
  port   = 5432
}

output "dev_sg_id" {
  description = "Dev database security group ID"
  value       = module.dev.security_group_id
}

output "prod_sg_id" {
  description = "Prod database security group ID"
  value       = module.prod.security_group_id
}
```

What each part means:
- `terraform { required_providers ... }` - tells Terraform which plugin to download. `source = "hashicorp/aws"` points to the official AWS provider. `version = "~> 5.0"` means "any 5.x version".
- `provider "aws" { region = "us-east-1" }` - configures the AWS plugin to create resources in the US East 1 region.
- `default_tags` - attaches the `Project` tag to every AWS resource created in this run, automatically.
- `module "dev"` - calls the reusable module once, passing `env = "dev"` and `port = 5432` (the default PostgreSQL port).
- `module "prod"` - calls the same module a second time with `env = "prod"`. The module code runs twice, creating two separate security groups.
- `source = "./modules/db-sg"` - tells Terraform where to find the module files (the folder you just created).
- `output "dev_sg_id"` and `output "prod_sg_id"` - print the security group IDs after Terraform finishes, by reading from the module outputs you defined in `outputs.tf`.

```
Expected output (yours will differ):
(no output - the file is saved silently)
```

Check it worked: run `cat /home/ec2-user/tf-lab/main.tf` and you should see the full file content printed.

---

## Part 5: Initialize, Plan, and Apply

### Step 11

On the server, as ec2-user: move into the root project folder.

```
cd /home/ec2-user/tf-lab
```

This changes your working directory so that all following Terraform commands run from the right place.

```
Expected output (yours will differ):
(no output)
```

Check it worked: your prompt should now show `tf-lab` as the current directory, or run `pwd` and confirm it prints `/home/ec2-user/tf-lab`.

---

### Step 12

On the server, as ec2-user: initialize the Terraform project.

Why this step: `terraform init` downloads the AWS provider plugin and sets up the module references. You must run this before any other Terraform command.

```
terraform init
```

Terraform reads your `main.tf`, sees you need the `hashicorp/aws` provider, downloads it into a hidden `.terraform` folder, and records the exact version in `.terraform.lock.hcl`.

```
Expected output (yours will differ):
Initializing the backend...

Initializing modules...
- dev in modules/db-sg
- prod in modules/db-sg

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Check it worked: you should see the line `Terraform has been successfully initialized!`.

---

### Step 13

On the server, as ec2-user: preview what Terraform will create, without actually creating anything.

```
terraform plan
```

Terraform reads your configuration, connects to AWS using the IAM role attached to this instance, and prints a list of every resource it would create. Green `+` lines mean "will be created". Nothing is changed in AWS at this point.

```
Expected output (yours will differ):
Terraform will perform the following actions:

  # module.dev.aws_security_group.this will be created
  + resource "aws_security_group" "this" {
      + description = "Database security group for dev environment"
      + name_prefix = "db-dev-"
      + ingress = [
          {
            + from_port   = 5432
            + to_port     = 5432
            + protocol    = "tcp"
            + cidr_blocks = ["10.0.0.0/8"]
          },
        ]
      ...
    }
...
```

Check it worked: you should see two resources listed, one for `module.dev` and one for `module.prod`, both showing `+ create`.

---

### Step 14

On the server, as ec2-user: apply the configuration to create the real AWS resources.

Why this step: `terraform apply` is what actually creates things in AWS. The `-auto-approve` flag skips the manual yes/no confirmation prompt. In a real production workflow you would omit that flag and review the plan before typing `yes` - but for this lab it is fine.

```
terraform apply -auto-approve
```

Terraform re-runs the plan and then creates the two security groups in AWS. When it finishes it prints the output values.

```
Expected output (yours will differ):
module.dev.aws_security_group.this: Creating...
module.prod.aws_security_group.this: Creating...
module.dev.aws_security_group.this: Creation complete after 2s [id=sg-042239cafd7c1b3e4]
module.prod.aws_security_group.this: Creation complete after 2s [id=sg-02ba230ae10fb0f82]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

dev_sg_id  = "sg-042239cafd7c1b3e4"
prod_sg_id = "sg-02ba230ae10fb0f82"
```

Check it worked: you should see `Apply complete! Resources: 2 added` and two `sg-` IDs printed under `Outputs`.

---

## Part 6: Verify the Result

### Step 15

On the server, as ec2-user: list all resources that Terraform is now tracking in its state file.

```
terraform -chdir=/home/ec2-user/tf-lab state list
```

`-chdir=` tells Terraform to switch to that directory before running, so this works from any folder you happen to be in. `state list` prints every resource Terraform knows about.

```
Expected output (yours will differ):
module.dev.aws_security_group.this
module.prod.aws_security_group.this
```

Check it worked: you should see exactly two lines, one for `module.dev` and one for `module.prod`.

---

### Step 16

On the server, as ec2-user: confirm that the live AWS resources exactly match your configuration (no drift).

Why this step: `terraform plan -detailed-exitcode` exits with code 0 if there are no changes needed, and code 2 if changes are needed. This is a common way to verify that what is deployed matches what is written.

```
terraform -chdir=/home/ec2-user/tf-lab plan -detailed-exitcode
```

`-detailed-exitcode` changes the exit code behavior: 0 means no changes, 1 means an error occurred, 2 means changes are needed. Seeing exit code 0 here means your deployed resources are a perfect match for your configuration files.

```
Expected output (yours will differ):
module.prod.aws_security_group.this: Refreshing state... [id=sg-02ba230ae10fb0f82]
module.dev.aws_security_group.this: Refreshing state... [id=sg-042239cafd7c1b3e4]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Check it worked: you should see the line `No changes. Your infrastructure matches the configuration.`

---

## Troubleshooting

**If you hit this - `terraform: command not found` after install:**

This means the shell's PATH does not yet include the folder where Terraform was installed. Start a new terminal session (log out and log back in) and try `terraform version` again.

**If you hit this - `aws` CLI commands return `command not found`:**

The AWS CLI is not required for this lab. Terraform communicates with AWS directly using the IAM role attached to your EC2 instance. The instance metadata service (reachable at `169.254.169.254`) provides temporary credentials automatically. You do not need to install or configure the AWS CLI.

**If you hit this - `Error: configuring Terraform AWS Provider: no valid credential sources`:**

This means your EC2 instance does not have an IAM role attached, or the role does not have permission to create security groups. Ask your instructor to verify the instance has the correct IAM role assigned.
