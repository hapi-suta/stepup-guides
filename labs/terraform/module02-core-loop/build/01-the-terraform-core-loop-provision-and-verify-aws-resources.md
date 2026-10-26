# The Terraform Core Loop: Provision and Verify AWS Resources

**Objective:** Install Terraform, write a configuration file, and use it to create an S3 bucket and a security group in AWS.

**Estimated Time:** 45-60 minutes

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 (or RHEL 9) with SSH access as `ec2-user`
- An IAM role attached to the instance that has permissions to create S3 buckets and security groups (no manual AWS credentials are needed if the role is in place)

---

## Background: How Authentication Works Here

You do not need to run `aws configure` or type any credentials. The EC2 instance has an IAM role attached to it. Terraform automatically contacts the instance's metadata service (a special internal address at `169.254.169.254`) to retrieve temporary credentials. You will confirm this in Step 7.

---

## Part 1: Install Terraform

Terraform is not installed by default on CentOS. You need to add HashiCorp's official package repository first, then install from it.

### Step 1: Install yum-utils

Why this step: `yum-utils` provides the `yum-config-manager` command, which is the clean way to add a new software repository.

On the server, as ec2-user:

```
sudo yum install -y yum-utils
```

`sudo` runs the command as root. `-y` answers "yes" automatically to any prompts so you do not have to confirm.

Expected output (yours will differ):

```
Package yum-utils-4.3.0-27.el9.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
```

Check it worked: you should see the word `Complete!` at the end of the output. If the package was already present (as above), that is fine - it is still there and ready.

---

### Step 2: Add the HashiCorp package repository

Why this step: By default, CentOS does not know where to find Terraform. This command teaches your system to look at HashiCorp's official repository.

On the server, as ec2-user:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`--add-repo` takes a URL pointing to a repository definition file and saves it so `yum` can find HashiCorp packages from now on.

Expected output (yours will differ):

```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line `Adding repo from:` followed by the HashiCorp URL.

---

### Step 3: Install Terraform

On the server, as ec2-user:

```
sudo yum -y install terraform
```

`yum install terraform` downloads and installs Terraform and any packages it depends on. `-y` confirms all prompts automatically.

Expected output (yours will differ):

```
Hashicorp Stable - x86_64                        31 MB/s | 1.9 MB     00:00
...
Installing:
 terraform             x86_64      1.17.0-1                hashicorp   37 M
...
Complete!
```

Check it worked: you should see `terraform` listed under `Installing:` and the word `Complete!` at the end.

---

### Step 4: Confirm Terraform is installed

On the server, as ec2-user:

```
terraform version
```

This prints the installed version of Terraform.

Expected output (yours will differ):

```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a line beginning with `Terraform v` followed by a version number.

---

## Part 2: Confirm AWS Credentials Are Available

### Step 5: Check the IAM role attached to this instance

Why this step: Before writing any Terraform code, confirm that the instance can reach AWS. The metadata service at `169.254.169.254` is a special internal-only address that EC2 instances use to learn about themselves, including their IAM role credentials.

On the server, as ec2-user:

```
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

`curl` fetches a URL. `-s` means "silent" (no progress bars). This URL returns the name of the IAM role attached to the instance.

Expected output (yours will differ):

```
suta-cb-spike-tf
```

Check it worked: you should see a role name printed. Any non-empty name confirms that an IAM role is attached and Terraform will be able to authenticate to AWS automatically.

---

## Part 3: Create the Project Directory

### Step 6: Make a working directory for this lab

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

`mkdir` creates a directory. `-p` means "create any missing parent directories and do not complain if the directory already exists".

Expected output (yours will differ):

```

```

Check it worked: there is no output, which is normal. A Unix command that succeeds silently is working correctly.

---

## Part 4: Write the Terraform Configuration File

You will now create the file `main.tf` inside your working directory. This is the file that tells Terraform what AWS resources to build. You will create it one section at a time so you understand what each part does.

### Step 7: Open a new file called main.tf in vi

On the server, as ec2-user:

```
vi /home/ec2-user/tf-lab/main.tf
```

This opens the vi text editor with a new, empty file. To start typing, press `i` (for "insert mode"). When you are done entering all the text in the steps below, press `Esc` to leave insert mode, then type `:wq` and press `Enter` to save and quit.

Expected output (yours will differ):

```
~
~
~
"/home/ec2-user/tf-lab/main.tf" [New File]
```

Check it worked: you should see a mostly empty screen with tilde characters (`~`) on the left, indicating an empty file.

---

### Step 8: Type the terraform block

Why this step: This block tells Terraform which external plugins (called "providers") it needs to download. Here you are telling it to use the official AWS provider, version 5.x.

In vi, type the following exactly:

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- `required_providers` - lists the plugins this configuration needs.
- `source = "hashicorp/aws"` - tells Terraform to download the AWS plugin from HashiCorp's public registry.
- `version = "~> 5.0"` - means "any version 5.x, but not version 6 or higher". The `~>` symbol means "compatible with".

---

### Step 9: Type the provider block

Why this step: The provider block configures the AWS plugin you declared above. It sets the AWS region and a default tag that will be stamped on every resource Terraform creates.

In vi, continuing in the same file, type:

```
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "suta-cb-spike"
    }
  }
}
```

- `region = "us-east-1"` - all resources will be created in the US East (N. Virginia) region.
- `default_tags` - any tag listed here is automatically applied to every AWS resource this configuration creates. This saves you from repeating the same tag on every resource block.

---

### Step 10: Type the S3 bucket resource block

Why this step: This block defines an S3 bucket that will be used to store database backups.

In vi, continuing in the same file, type:

```
resource "aws_s3_bucket" "db_backups" {
  bucket_prefix = "dba-backups-"
}
```

- `resource "aws_s3_bucket"` - tells Terraform you want an S3 bucket.
- `"db_backups"` - this is just a local name you give this resource inside your Terraform code so you can refer to it elsewhere. It does not affect the real bucket name.
- `bucket_prefix = "dba-backups-"` - instead of you choosing a name, AWS will start with `dba-backups-` and add random characters to guarantee the name is globally unique. S3 bucket names must be unique across all AWS accounts worldwide, so letting AWS generate the suffix is safer than picking one yourself.

---

### Step 11: Type the security group resource block

Why this step: This block defines a firewall rule (called a security group in AWS) that will later allow a PostgreSQL database to receive connections from your internal network.

In vi, continuing in the same file, type:

```
resource "aws_security_group" "db_sg" {
  name_prefix = "db-sg-"
  description = "Allow inbound PostgreSQL traffic from internal network"

  ingress {
    description = "PostgreSQL from internal network"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

- `aws_security_group` - creates an AWS firewall rule set.
- `"db_sg"` - the local name for this resource in your Terraform code.
- `name_prefix = "db-sg-"` - like `bucket_prefix` above, AWS appends random characters to make the name unique.
- `ingress` block - defines inbound traffic that is allowed:
  - `from_port = 5432` and `to_port = 5432` - PostgreSQL listens on port 5432. Allowing from and to the same port means only that port is opened.
  - `protocol = "tcp"` - PostgreSQL uses TCP.
  - `cidr_blocks = ["10.0.0.0/8"]` - only allow connections from IP addresses starting with `10.`, which is the private network range. This keeps the database off the public internet.
- `egress` block - defines outbound traffic. `protocol = "-1"` means all protocols. `0` to `0` for ports also means all ports. This allows the database to make any outbound connection (needed for updates, responses, etc.).

Now press `Esc`, then type `:wq` and press `Enter` to save the file and exit vi.

Expected output (yours will differ):

```
"/home/ec2-user/tf-lab/main.tf" 45L, 1009C written
```

Check it worked: vi tells you the file name, number of lines, and number of characters written.

---

### Step 12: Confirm the file was saved correctly

On the server, as ec2-user:

```
cat /home/ec2-user/tf-lab/main.tf
```

`cat` prints the contents of a file to the screen.

Expected output (yours will differ):

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
...
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Check it worked: you should see all three blocks - `terraform`, `provider "aws"`, `resource "aws_s3_bucket"`, and `resource "aws_security_group"` - in the output. If any block is missing, re-open the file with `vi /home/ec2-user/tf-lab/main.tf` and add what is missing.

---

## Part 5: Initialise Terraform

### Step 13: Move into the project directory

On the server, as ec2-user:

```
cd /home/ec2-user/tf-lab
```

`cd` (change directory) moves you into your project folder. All Terraform commands must be run from the directory containing `main.tf`.

Expected output (yours will differ):

```

```

Check it worked: no output is expected. Run `pwd` if you want to confirm you are in the right place - it should print `/home/ec2-user/tf-lab`.

---

### Step 14: Initialise the Terraform working directory

Why this step: Before you can do anything else, Terraform needs to download the AWS provider plugin you declared in the `terraform` block. This step does that download and sets up a hidden `.terraform` folder in your project directory.

On the server, as ec2-user (inside /home/ec2-user/tf-lab):

```
terraform init
```

This reads your `main.tf`, finds the `required_providers` block, downloads the AWS provider plugin from the internet, and creates a lock file recording exactly which version was downloaded.

Expected output (yours will differ):

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Check it worked: you should see the line `Terraform has been successfully initialized!` at the bottom of the output.

---

## Part 6: Preview the Changes

### Step 15: Run a plan to see what Terraform will create

Why this step: `terraform plan` is a dry run. It shows you exactly what Terraform intends to create, change, or destroy - without actually doing anything yet. Always review the plan before applying.

On the server, as ec2-user (inside /home/ec2-user/tf-lab):

```
terraform plan
```

Terraform reads your configuration, compares it to the current real state of AWS (nothing exists yet), and lists everything it will create. A `+` next to a resource means it will be created.

Expected output (yours will differ):

```
Terraform used the selected providers to generate the following execution plan.
...
  # aws_s3_bucket.db_backups will be created
  + resource "aws_s3_bucket" "db_backups" {
      + bucket_prefix = "dba-backups-"
      ...
    }

  # aws_security_group.db_sg will be created
  + resource "aws_security_group" "db_sg" {
      ...
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

Check it worked: you should see `Plan: 2 to add, 0 to change, 0 to destroy.` at the bottom. The `2 to add` means the S3 bucket and security group will be created.

---

## Part 7: Apply the Configuration

### Step 16: Create the real AWS resources

Why this step: `terraform apply` actually sends the instructions to AWS and creates the resources. This will create real cloud resources.

On the server, as ec2-user (inside /home/ec2-user/tf-lab):

```
terraform apply -auto-approve
```

`apply` sends your configuration to AWS and creates the resources. `-auto-approve` skips the manual confirmation prompt. In a real production environment you would leave out `-auto-approve` and review the plan one more time before typing `yes`.

Expected output (yours will differ):

```
...
aws_security_group.db_sg: Creating...
aws_s3_bucket.db_backups: Creating...
aws_s3_bucket.db_backups: Creation complete after 1s [id=dba-backups-20261023043342827800000002]
aws_security_group.db_sg: Creation complete after 2s [id=sg-08d2ea383de1e0d4e]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Check it worked: you should see `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.` You will also see the real AWS IDs for your new resources (for example `id=dba-backups-...` and `id=sg-...`).

---

## Part 8: Verify What Was Created

### Step 17: List the resources Terraform is tracking

Why this step: Terraform keeps a local record called "state" of every resource it has created. Listing the state confirms that both resources were created and are being tracked.

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab state list
```

- `-chdir=/home/ec2-user/tf-lab` - tells Terraform to look in that directory for its configuration and state files. This means you can run the command from any directory. It is equivalent to `cd`-ing into the folder first.
- `state list` - prints the name of every resource Terraform currently manages.

Expected output (yours will differ):

```
aws_s3_bucket.db_backups
aws_security_group.db_sg
```

Check it worked: you should see exactly two lines - `aws_s3_bucket.db_backups` and `aws_security_group.db_sg`.

---

### Step 18: Confirm the real infrastructure matches the configuration

Why this step: This is a final check. Terraform compares your `main.tf` against what actually exists in AWS and reports whether anything has drifted (changed outside of Terraform) since you applied.

On the server, as ec2-user:

```
terraform -chdir=/home/ec2-user/tf-lab plan -detailed-exitcode
```

- `-detailed-exitcode` changes what exit code the command returns: `0` means no changes needed, `1` means an error, `2` means changes are needed. Here we expect `0`.
- The overall effect is: Terraform checks AWS, and if your resources exist and match your config exactly, it says so clearly.

Expected output (yours will differ):

```
aws_security_group.db_sg: Refreshing state... [id=sg-08d2ea383de1e0d4e]
aws_s3_bucket.db_backups: Refreshing state... [id=dba-backups-20261023043342827800000002]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Check it worked: you should see the line `No changes. Your infrastructure matches the configuration.` This confirms that both resources exist in AWS exactly as described in your `main.tf`.

---

## Troubleshooting Notes

**If you hit this - terraform: command not found after installation**

If you type `terraform version` and still see `command not found`, your shell session may not have refreshed its list of available programs. Fix it by running:

```
hash -r
```

Then try `terraform version` again. `hash -r` clears the shell's internal cache of command locations so it finds the newly installed binary.

---

**If you hit this - aws: command not found**

You may notice that the AWS CLI (`aws`) is not installed on this server. That is fine for this lab. Terraform does not need the AWS CLI. Terraform communicates with AWS directly using its own built-in code. The IAM role attached to the EC2 instance (confirmed in Step 5) provides the credentials for both Terraform and the AWS CLI if you ever install it later.

---

**If you hit this - terraform init fails with a GPG or signature error**

This means the package repository's signing key could not be verified. Run the following to clear the yum cache and try again:

```
sudo yum clean all
```

Then re-run `terraform init`. If the problem persists, check that the HashiCorp repo was added correctly by running `sudo yum repolist` and confirming you see a `hashicorp` entry in the list.

---

## Summary

You have completed the following:

1. Installed Terraform from HashiCorp's official package repository.
2. Confirmed that the EC2 instance's IAM role provides AWS credentials automatically.
3. Written a Terraform configuration (`main.tf`) that declares two AWS resources - an S3 bucket and a security group.
4. Used `terraform init` to download the AWS provider plugin.
5. Used `terraform plan` to preview the changes safely before making them.
6. Used `terraform apply` to create the real AWS resources.
7. Verified that the resources exist and match the configuration with `terraform state list` and a final `terraform plan`.
