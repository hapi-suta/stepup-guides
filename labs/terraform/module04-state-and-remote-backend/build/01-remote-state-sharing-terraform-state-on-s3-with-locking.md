# Remote State: Sharing Terraform State on S3 with Locking

**Objective:** Install Terraform and the AWS CLI on a CentOS server, use Terraform to create an S3 bucket with versioning and encryption, and then move Terraform's state file from your local disk into that S3 bucket so your whole team can share it.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- A CentOS Stream 9 server (x86_64) with sudo access, logged in as ec2-user
- An AWS IAM role or credentials attached to the server that allows S3 and SSM actions
- Basic familiarity with the Linux command line (changing directories, running commands)

---

## Background: The Two-Phase Approach

Terraform stores a record of everything it has created in a file called **state**. By default that file lives on your local disk (`terraform.tfstate`), which means no one else on your team can see it and it can be lost if the server is deleted. The goal of this lab is to move that state into an S3 bucket so it is safe and shared.

There is a chicken-and-egg problem: you cannot tell Terraform to store state in an S3 bucket that does not exist yet. So you will work in two phases:

- **Phase A (Steps 1-21):** Let Terraform store state locally while you create the S3 bucket.
- **Phase B (Steps 22-34):** Tell Terraform to use that S3 bucket for state and migrate the local state up to S3.

---

## Phase A: Install the Tools and Create the S3 Bucket

### Step 1: Check whether Terraform is already installed

On the server, as ec2-user:

```bash
which terraform
```

The `which` command searches your PATH for an executable named `terraform`. If it finds nothing it prints nothing.

```
Expected output (yours will differ):

```

Check it worked: no output means Terraform is not installed yet, which is exactly what you expect at this point.

---

### Step 2: Check the operating system and CPU architecture

On the server, as ec2-user:

```bash
cat /etc/os-release
```

This prints the distribution name and version so you know which package manager and repository to use.

```
Expected output (yours will differ):
NAME="CentOS Stream"
VERSION="9"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="9"
```

Check it worked: you should see `CentOS Stream` and `VERSION="9"`.

---

### Step 3: Confirm the CPU architecture

On the server, as ec2-user:

```bash
uname -m
```

`uname -m` prints the machine hardware name. You need to know whether the CPU is 64-bit (`x86_64`) because the packages you will download are architecture-specific.

```
Expected output (yours will differ):
x86_64
```

Check it worked: you should see `x86_64`.

---

### Step 4: Install the yum-utils package

Why this step: CentOS uses a tool called `yum-config-manager` (part of `yum-utils`) to add third-party software repositories. You need it to add HashiCorp's repository in the next step.

On the server, as ec2-user:

```bash
sudo yum install -y yum-utils
```

`yum install` downloads and installs a package. `-y` automatically answers "yes" to all prompts so the command does not wait for you.

```
Expected output (yours will differ):
Dependencies resolved.
Nothing to do.
Complete!
```

Check it worked: you should see `Complete!` at the end.

---

### Step 5: Add the HashiCorp software repository

Why this step: CentOS does not include Terraform in its default package list. You need to tell `yum` about HashiCorp's own package server so it can find and install Terraform.

On the server, as ec2-user:

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`--add-repo` downloads the repository definition file from the URL and saves it on your system. From now on `yum` knows about HashiCorp packages.

```
Expected output (yours will differ):
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see the line beginning with `Adding repo from:`.

---

### Step 6: Install Terraform

Why this step: You pin the exact version (`1.10.5`) to ensure the lab steps match what you have installed. Picking a specific version is a good habit so your team all uses the same one.

On the server, as ec2-user:

```bash
sudo yum install -y terraform-1.10.5
```

`terraform-1.10.5` is the exact package name. `yum` looks it up in the HashiCorp repository you just added and installs it.

```
Expected output (yours will differ):
  terraform-1.10.5-1.x86_64

Complete!
```

Check it worked: you should see `terraform-1.10.5-1.x86_64` listed and `Complete!` at the end.

---

### Step 7: Verify Terraform is working

On the server, as ec2-user:

```bash
terraform version
```

This prints the installed version so you can confirm the installation succeeded.

```
Expected output (yours will differ):
Terraform v1.10.5
on linux_amd64
```

Check it worked: you should see `Terraform v1.10.5`.

Note: you may see a message saying a newer version is available. That is just a notification and does not affect this lab.

---

### Step 8: Check whether the AWS CLI is already installed

On the server, as ec2-user:

```bash
find /usr /opt /home -name "aws" -type f
```

This searches common installation directories for a file named `aws`. If it finds nothing, the AWS CLI is not installed.

```
Expected output (yours will differ):

```

Check it worked: no output means the AWS CLI is not installed yet, which is expected.

---

### Step 9: Download the AWS CLI installer

Why this step: The AWS CLI is not in the CentOS package repositories, so you download the official zip file directly from Amazon.

On the server, as ec2-user:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

`curl` downloads a file from a URL. `-o /tmp/awscliv2.zip` saves it to `/tmp` with that filename instead of printing it to the screen.

```
Expected output (yours will differ):
100 70.9M  100 70.9M    0     0   412M      0 --:--:-- --:--:-- --:--:--  412M
```

Check it worked: you should see `100` in the first column, meaning 100% of the file was downloaded.

---

### Step 10: Install the unzip utility

Why this step: The AWS CLI is packaged as a zip file and `unzip` is not installed on this server by default. You need it before you can extract the installer.

On the server, as ec2-user:

```bash
sudo yum install -y unzip
```

This installs the `unzip` command-line tool.

```
Expected output (yours will differ):
unzip-6.0-59.el9.x86_64

Complete!
```

Check it worked: you should see `unzip-6.0-...` listed and `Complete!`.

---

### Step 11: Extract the AWS CLI installer

On the server, as ec2-user:

```bash
cd /tmp
```

Change into the `/tmp` directory so that the next command extracts the files there.

```
Expected output (yours will differ):

```

Check it worked: no error means the directory change succeeded.

---

On the server, as ec2-user (still in /tmp):

```bash
unzip -q awscliv2.zip
```

`unzip` extracts the zip file. `-q` means quiet - it suppresses the long list of extracted filenames.

```
Expected output (yours will differ):

```

Check it worked: no error message means the zip extracted cleanly.

---

### Step 12: Run the AWS CLI installer

On the server, as ec2-user:

```bash
sudo /tmp/aws/install
```

This runs the official AWS installer script, which copies the `aws` binary to `/usr/local/bin` so it is available system-wide.

```
Expected output (yours will differ):
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see `You can now run: /usr/local/bin/aws --version`.

---

### Step 13: Verify the AWS CLI version

On the server, as ec2-user:

```bash
aws --version
```

Prints the installed AWS CLI version to confirm it is working.

```
Expected output (yours will differ):
aws-cli/2.38.5 Python/3.14.8 Linux/5.14.0-759.el9.x86_64 exe/x86_64.centos.9
```

Check it worked: you should see `aws-cli/2.x.x` at the start of the line.

---

### Step 14: Confirm AWS credentials are working

Why this step: The server must have an AWS IAM role or credentials configured so that Terraform can create real AWS resources. This command asks AWS "who am I?" and returns your account number.

On the server, as ec2-user:

```bash
aws sts get-caller-identity --query Account --output text
```

`sts get-caller-identity` asks the AWS Security Token Service for the identity of whoever is making this call. `--query Account` filters the response down to just the account number. `--output text` prints it as plain text instead of JSON. **Write down this number - you will need it to name your S3 bucket.**

```
Expected output (yours will differ):
339276916173
```

Check it worked: you should see a 12-digit AWS account number.

---

### Step 15: Create the project directory

On the server, as ec2-user:

```bash
mkdir -p /home/ec2-user/tf-lab
```

`mkdir` creates a new directory. `-p` means "create any missing parent directories and do not error if it already exists."

```
Expected output (yours will differ):

```

Check it worked: no error means the directory was created.

---

### Step 16: Create the Terraform versions file

Why this step: Every Terraform project needs a file that declares which version of the AWS provider plugin to download. This file also configures the AWS region. You are creating it **without** a backend block on purpose - the S3 bucket does not exist yet.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/versions.tf
```

Open vi and type the following content exactly. Press `i` to enter insert mode, type the content, then press `Esc` followed by `:wq` and Enter to save and quit.

```hcl
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
```

What each important part means:
- `required_providers` - tells Terraform which plugin to download and from where. `hashicorp/aws` is the official AWS plugin published by HashiCorp.
- `version = "~> 5.0"` - use any version that starts with 5 (for example 5.1, 5.99) but never version 6. The `~>` symbol means "this version or higher patch releases, but not the next major version."
- `provider "aws"` - configures the AWS plugin. `region = "us-east-1"` means all resources will be created in the US East (N. Virginia) region unless you say otherwise.
- `default_tags` - automatically applies the tag `Project = "suta-cb-spike"` to every AWS resource Terraform creates. Tags help you identify and manage costs for resources.

```
Expected output (yours will differ):

```

Check it worked: vi closes without an error message and you are back at the shell prompt.

---

### Step 17: Verify the versions file was saved correctly

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/versions.tf
```

`cat` prints the contents of a file to the screen so you can confirm what was saved.

```
Expected output (yours will differ):
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
}
```

Check it worked: the file contents match what you typed in the previous step.

---

### Step 18: Create the main Terraform configuration file

Why this step: This file describes the actual AWS resources you want to create. You are creating three things: an S3 bucket (which will later hold your state), versioning on that bucket (so old state files are recoverable), and encryption on that bucket. You are also creating a small demo S3 object so there is something interesting in the state file besides the bucket itself.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/main.tf
```

Press `i` to enter insert mode and type the following. Replace `YOUR_ACCOUNT_ID` with the 12-digit number you wrote down in Step 14.

```hcl
resource "aws_s3_bucket" "state" {
  bucket = "tfstate-YOUR_ACCOUNT_ID-suta"

  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "demo" {
  bucket       = aws_s3_bucket.state.id
  key          = "demo/hello.txt"
  content      = "hello-from-suta-remote-state-lab"
  content_type = "text/plain"
}
```

What each important part means:
- `resource "aws_s3_bucket" "state"` - creates an S3 bucket. The name must be globally unique across all AWS accounts, which is why your account ID is part of it.
- `force_destroy = true` - allows Terraform to delete the bucket even if it still has files in it. **Only use this in a lab environment.** In production you want the bucket to be protected from accidental deletion.
- `aws_s3_bucket_versioning` - turns on versioning so every change to the state file is saved as a new version. If state gets corrupted you can restore a previous version.
- `aws_s3_bucket_server_side_encryption_configuration` - turns on AES-256 encryption so the state file is encrypted at rest inside S3.
- `aws_s3_object "demo"` - creates a small text file inside the bucket. This gives the state file something to track besides the bucket itself.
- `aws_s3_bucket.state.id` - a reference to the bucket resource above. Terraform reads this as "use the ID (bucket name) of the bucket resource named `state`." This creates a dependency so Terraform creates the bucket before trying to configure it.

Press `Esc` then type `:wq` and press Enter to save and quit.

```
Expected output (yours will differ):

```

Check it worked: vi closes without an error message.

---

### Step 19: Verify the main file was saved correctly

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/main.tf
```

```
Expected output (yours will differ):
resource "aws_s3_bucket" "state" {
  bucket = "tfstate-YOUR_ACCOUNT_ID-suta"
  force_destroy = true
}
...
```

Check it worked: the file contents match what you typed.

---

### Step 20: Move into the project directory

On the server, as ec2-user:

```bash
cd /home/ec2-user/tf-lab
```

All Terraform commands must be run from the directory that contains your `.tf` files.

```
Expected output (yours will differ):

```

Check it worked: no error means the directory change succeeded.

---

### Step 21: Initialize Terraform

Why this step: Before Terraform can do anything it needs to download the AWS provider plugin you declared in `versions.tf`. This only needs to be done once per project (or when you add new providers).

On the server, as ec2-user (in /home/ec2-user/tf-lab):

```bash
terraform init
```

Terraform reads your `.tf` files, finds the `hashicorp/aws` provider, downloads it into a hidden `.terraform` folder, and creates a lock file to record the exact version downloaded.

```
Expected output (yours will differ):
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!`.

---

### Step 22: Apply the Terraform configuration

Why this step: This is the command that actually creates the AWS resources. Terraform will show you a plan of what it is about to do and then create the resources.

On the server, as ec2-user (in /home/ec2-user/tf-lab):

```bash
terraform apply -auto-approve
```

`apply` tells Terraform to create the resources described in your `.tf` files. `-auto-approve` skips the interactive "do you want to do this?" prompt. You would normally leave this flag out and review the plan before typing `yes`.

```
Expected output (yours will differ):
aws_s3_bucket.state: Creating...
aws_s3_bucket_versioning.state: Creating...
aws_s3_bucket_server_side_encryption_configuration.state: Creating...
aws_s3_object.demo: Creating...

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

Check it worked: you should see `Apply complete!` and `4 added`.

**If you hit this - first apply fails with an access error:**
If you see an error like `AccessDenied` or `AuthorizationError`, the IAM role on the server does not have permission to create S3 buckets or SSM parameters. Check with your instructor that the correct IAM role is attached to the instance. The engineer encountered an `AccessDenied` error on SSM parameters specifically, which is why the demo resource was changed from an SSM parameter to an S3 object (S3 permissions were available).

---

### Step 23: Confirm the S3 bucket exists in AWS

On the server, as ec2-user:

```bash
aws s3 ls
```

Lists all S3 buckets in your AWS account.

```
Expected output (yours will differ):
2026-10-26 13:49:01 tfstate-339276916173-suta
```

Check it worked: you should see your bucket name (`tfstate-YOUR_ACCOUNT_ID-suta`) in the list.

---

### Step 24: Inspect the local state file

Why this step: Before you migrate state to S3, take a look at what the local state file contains. This helps you understand what you are about to move.

On the server, as ec2-user:

```bash
ls -la /home/ec2-user/tf-lab/terraform.tfstate
```

`ls -la` lists the file with its size and permissions. `-l` gives the long format and `-a` includes hidden files.

```
Expected output (yours will differ):
-rw-r--r--. 1 ec2-user ec2-user 6262 Oct 26 13:50 /home/ec2-user/tf-lab/terraform.tfstate
```

Check it worked: you should see a file with a size greater than zero (6262 bytes in this example), confirming state was written locally.

---

## Phase B: Migrate State to S3

Now the S3 bucket exists. You will update `versions.tf` to add a `backend "s3"` block, then run `terraform init -migrate-state` to copy the local state up to S3.

---

### Step 25: Update versions.tf to add the S3 backend block

Why this step: A backend block tells Terraform where to store state. You are adding it now that the bucket exists. Note that the backend block **cannot** use variables or references - the bucket name must be typed as a plain string.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/versions.tf
```

Press `i` to enter insert mode. Replace the entire file contents with the following. Replace `YOUR_ACCOUNT_ID` with your 12-digit AWS account number.

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-YOUR_ACCOUNT_ID-suta"
    key          = "global/s3/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

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
```

What each important part of the backend block means:
- `backend "s3"` - tells Terraform to use S3 as its state storage. This replaces the default local file storage.
- `bucket` - the name of the S3 bucket where state will be stored. Must already exist.
- `key` - the path inside the bucket where the state file will be saved. Think of it like a folder path. `global/s3/terraform.tfstate` is a common convention for the bucket that manages itself.
- `region` - the AWS region where the bucket lives. Must match the region you created the bucket in.
- `encrypt = true` - tells Terraform to request server-side encryption when writing the state file.
- `use_lockfile = true` - a Terraform 1.10+ feature. When you run `apply`, Terraform writes a tiny lock file to S3 next to the state file. If two people try to run `apply` at the same time, the second one sees the lock and waits instead of overwriting. No separate DynamoDB table is needed - the lock lives in S3 itself.

Press `Esc` then type `:wq` and Enter to save and quit.

```
Expected output (yours will differ):

```

Check it worked: vi closes without an error message.

---

### Step 26: Verify the updated versions file

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/versions.tf
```

```
Expected output (yours will differ):
terraform {
  backend "s3" {
    bucket       = "tfstate-YOUR_ACCOUNT_ID-suta"
    key          = "global/s3/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
  ...
}
```

Check it worked: you should see the `backend "s3"` block near the top of the file.

---

### Step 27: Re-initialize Terraform and migrate state

Why this step: Whenever you change the backend configuration, you must run `terraform init` again so Terraform can connect to the new backend. The `-migrate-state` flag tells it to copy the existing local state up to S3 instead of starting fresh.

On the server, as ec2-user (in /home/ec2-user/tf-lab):

```bash
terraform init -migrate-state
```

Terraform will detect that you had local state and ask if you want to copy it to S3. Type `yes` and press Enter when prompted.

```
Expected output (yours will differ):
Initializing the backend...
Do you want to copy existing state to the new backend?
  ...
  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

Check it worked: you should see `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!`.

---

### Step 28: Verify the state list still works

Why this step: After migration, Terraform should be reading state from S3. Running `state list` confirms Terraform can connect to S3 and still sees all four resources.

On the server, as ec2-user:

```bash
terraform -chdir=/home/ec2-user/tf-lab state list
```

`state list` prints every resource that Terraform is tracking. `-chdir=/home/ec2-user/tf-lab` tells Terraform to look for configuration files in that directory rather than the current directory.

```
Expected output (yours will differ):
aws_s3_bucket.state
aws_s3_bucket_server_side_encryption_configuration.state
aws_s3_bucket_versioning.state
aws_s3_object.demo
```

Check it worked: you should see all four resource names listed.

---

### Step 29: Confirm the state file is now in S3

On the server, as ec2-user:

```bash
aws s3api list-objects-v2 --bucket tfstate-YOUR_ACCOUNT_ID-suta --query "Contents[].Key" --output text
```

`s3api list-objects-v2` lists every object (file) stored in an S3 bucket. `--bucket` specifies which bucket. `--query "Contents[].Key"` filters the output to show only the file paths. `--output text` prints them as plain text. Replace `YOUR_ACCOUNT_ID` with your account number.

```
Expected output (yours will differ):
demo/hello.txt	global/s3/terraform.tfstate
```

Check it worked: you should see `global/s3/terraform.tfstate` in the output, which is the state file you just migrated.

---

### Step 30: Download and inspect the remote state file

Why this step: This step proves that the state file in S3 contains real content and is not empty. You are downloading a copy to `/tmp` just for inspection - you are not changing anything.

On the server, as ec2-user:

```bash
aws s3api get-object --bucket tfstate-YOUR_ACCOUNT_ID-suta --key global/s3/terraform.tfstate /tmp/check-state.json
```

`s3api get-object` downloads an object from S3. `--bucket` and `--key` identify which file to download. The last argument (`/tmp/check-state.json`) is where to save it locally. Replace `YOUR_ACCOUNT_ID` with your account number.

```
Expected output (yours will differ):
{
    "AcceptRanges": "bytes",
    "LastModified": "2026-10-26T13:50:31+00:00",
    "ContentLength": 6262,
    "ServerSideEncryption": "AES256",
    ...
}
```

Check it worked: you should see `"ServerSideEncryption": "AES256"`, confirming the file is encrypted, and a `ContentLength` greater than zero.

---

### Step 31: Inspect the state file contents

On the server, as ec2-user:

```bash
python3 -m json.tool /tmp/check-state.json
```

`python3 -m json.tool` is a built-in Python tool that pretty-prints a JSON file with indentation so it is easier to read.

```
Expected output (yours will differ):
{
    "version": 4,
    "terraform_version": "1.10.5",
    "serial": 1,
    "resources": [
        ...
    ]
}
```

Check it worked: you should see a `resources` section containing your four resources.

---

### Step 32: Confirm the local state file is now empty

Why this step: After a successful migration, Terraform empties the local `terraform.tfstate` file. This confirms state has truly moved to S3 and the local file is no longer the source of truth.

On the server, as ec2-user:

```bash
wc -c /home/ec2-user/tf-lab/terraform.tfstate
```

`wc -c` counts the number of bytes (characters) in a file.

```
Expected output (yours will differ):
0 /home/ec2-user/tf-lab/terraform.tfstate
```

Check it worked: you should see `0` before the filename, confirming the local state file is empty.

---

### Step 33: Check the backup file

On the server, as ec2-user:

```bash
wc -c /home/ec2-user/tf-lab/terraform.tfstate.backup
```

When Terraform migrates state it saves a backup of the old local state file as `terraform.tfstate.backup`. This is your safety net.

```
Expected output (yours will differ):
6262 /home/ec2-user/tf-lab/terraform.tfstate.backup
```

Check it worked: you should see a non-zero byte count, confirming the backup was saved.

---

### Step 34: Run a final plan to confirm everything is consistent

Why this step: A clean `terraform plan` with "No changes" is the gold standard confirmation that your remote state matches the real infrastructure in AWS. If Terraform detects a difference it would show proposed changes here.

On the server, as ec2-user (in /home/ec2-user/tf-lab):

```bash
terraform plan
```

Terraform reads your `.tf` files, reads the current state from S3, and compares both against the real AWS resources. It then prints what it would do.

```
Expected output (yours will differ):
aws_s3_bucket.state: Refreshing state... [id=tfstate-339276916173-suta]
aws_s3_bucket_server_side_encryption_configuration.state: Refreshing state...
aws_s3_bucket_versioning.state: Refreshing state...
aws_s3_object.demo: Refreshing state... [id=demo/hello.txt]

No changes. Your infrastructure matches the configuration.
```

Check it worked: you should see `No changes. Your infrastructure matches the configuration.` This confirms that remote state is working correctly and Terraform is reading from S3.

---

## Summary

You have completed the lab. Here is what you built and why each piece matters:

| What you did | Why it matters |
|---|---|
| Installed Terraform 1.10.5 and AWS CLI v2 on CentOS 9 | Your server can now manage AWS infrastructure |
| Created an S3 bucket with versioning and AES-256 encryption | State files are protected from accidental deletion and are encrypted at rest |
| Migrated Terraform state from a local file to S3 | Any team member can now run Terraform from any machine and see the same state |
| Enabled native S3 locking with `use_lockfile = true` | Two people cannot accidentally overwrite each other's state at the same time |
| Confirmed the local state file is empty (0 bytes) | Proves S3 is now the single source of truth |
