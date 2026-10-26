# Installing Terraform and Initializing an AWS Provider Project on CentOS Stream 9

**Objective:** Install Terraform from the official HashiCorp repository, create a project directory with a basic AWS provider configuration, and verify that Terraform can initialize and validate it.

**Estimated Time:** 20-30 minutes

**Prerequisites:**
- A CentOS Stream 9 server with internet access
- A user account with sudo privileges
- Basic familiarity with the terminal and the vi text editor

---

## Step 1 - Confirm your operating system

On the server, as your regular user:

```bash
cat /etc/os-release
```

This prints information about your Linux distribution. We are checking that we are on CentOS Stream 9 before choosing the right installation method.

**Expected output (yours will differ):**
```
NAME="CentOS Stream"
VERSION="9"
ID="centos"
ID_LIKE="rhel fedda"
VERSION_ID="9"
PLATFORM_ID="platform:el9"
PRETTY_NAME="CentOS Stream 9"
...
```

**Check it worked:** You should see `PRETTY_NAME="CentOS Stream 9"` in the output.

---

## Step 2 - Install yum-utils

Why this step: `yum-utils` provides the `yum-config-manager` command, which we need in the next step to add the HashiCorp software repository. It may already be installed, and that is fine.

On the server, as your regular user:

```bash
sudo yum install -y yum-utils
```

`sudo` runs the command as an administrator. `yum install` installs a package. `-y` answers "yes" automatically to any prompts so you do not have to confirm each one.

**Expected output (yours will differ):**
```
CentOS Stream 9 - BaseOS                        6.1 MB/s | 3.1 MB     00:00
CentOS Stream 9 - AppStream                      27 MB/s |  12 MB     00:00
Package yum-utils-4.3.0-27.el9.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
```

**Check it worked:** You should see `Complete!` at the end. If the package was already installed, the message `is already installed` is also fine.

---

## Step 3 - Add the HashiCorp software repository

Why this step: By default, CentOS does not know where to find Terraform. We need to tell it to look at HashiCorp's official repository. `yum-config-manager --add-repo` downloads a small configuration file that points yum to that location.

On the server, as your regular user:

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`--add-repo` downloads the repository definition file at the given web address and saves it in `/etc/yum.repos.d/` so yum will check it for packages from now on.

**Expected output (yours will differ):**
```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

**Check it worked:** You should see `Adding repo from:` followed by the URL.

---

## Step 4 - Confirm the repository file was saved

On the server, as your regular user:

```bash
cat /etc/yum.repos.d/hashicorp.repo
```

This prints the repository configuration file that was just created so you can confirm it looks correct.

**Expected output (yours will differ):**
```
[hashicorp]
name=Hashicorp Stable - $basearch
baseurl=https://rpm.releases.hashicorp.com/RHEL/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg

[hashicorp-test]
name=Hashicorp Test - $basearch
baseurl=https://rpm.releases.hashicorp.com/RHEL/$releasever/$basearch/test
enabled=0
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg
```

**Check it worked:** You should see `gpgcheck=1` and `gpgkey=https://rpm.releases.hashicorp.com/gpg`. This means packages will be verified against HashiCorp's official signing key before installation, which is a good security practice.

---

## Step 5 - Install Terraform

On the server, as your regular user:

```bash
sudo yum -y install terraform
```

`yum install terraform` searches the repositories we have configured (including the HashiCorp one we just added) and installs Terraform and any packages it depends on. `-y` answers yes to all prompts automatically.

**Expected output (yours will differ):**
```
Hashicorp Stable - x86_64                        30 MB/s | 1.9 MB     00:00
Last metadata expiration check: 0:00:01 ago on Fri 23 Oct 2026 03:17:51 AM UTC.
Dependencies resolved.
================================================================================
 Package               Arch        Version                 Repository      Size
================================================================================
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Transaction Summary
================================================================================
Install  9 Packages

Total download size: 45 M
Installed size: 166 M
...
```

**Check it worked:** You should see `terraform` listed under `Installing:` and `Complete!` at the very end of the output.

---

## Step 6 - Confirm Terraform is installed and check the version

On the server, as your regular user:

```bash
terraform version
```

This asks Terraform to print its own version number, which confirms the binary is installed correctly and is on your PATH (meaning your shell can find it).

**Expected output (yours will differ):**
```
Terraform v1.17.0
on linux_amd64
```

**Check it worked:** You should see a line starting with `Terraform v` followed by a version number.

---

## Step 7 - Create a project directory

Why this step: Terraform keeps all the files for one project together in a single directory. We will create a new directory specifically for this AWS project.

On the server, as your regular user:

```bash
mkdir -p ~/terraform-aws-project
```

`mkdir` creates a new directory. `-p` means "create any missing parent directories along the way and do not complain if the directory already exists." The `~` is a shortcut for your home directory.

**Expected output (yours will differ):**
```
(no output)
```

**Check it worked:** No error message means the directory was created successfully. A command that succeeds silently is normal for `mkdir`.

---

## Step 8 - Create the main Terraform configuration file

Why this step: Every Terraform project needs at least one configuration file (ending in `.tf`) that tells Terraform which cloud provider to use and how to connect to it. We will create `main.tf` with a minimal AWS provider block.

On the server, as your regular user, open vi to create the file:

```bash
vi ~/terraform-aws-project/main.tf
```

Inside vi, press `i` to enter insert mode, then type the following content exactly:

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.98"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}
```

Here is what each important part means:

- `terraform { required_providers { ... } }` - This block tells Terraform which external plugins (called "providers") to download. Without this, Terraform does not know about AWS at all.
- `source = "hashicorp/aws"` - This is the official address of the AWS provider in the Terraform registry.
- `version = "~> 5.98"` - This means "use version 5.98 or any newer version in the 5.x family, but not version 6 or higher." The `~>` symbol is called the pessimistic constraint operator.
- `required_version = ">= 1.0"` - This ensures anyone running this project has at least Terraform version 1.0 installed.
- `provider "aws" { region = "us-east-1" }` - This configures the AWS provider to operate in the US East (N. Virginia) region. You can change this to your preferred AWS region.

When you have finished typing, press `Esc` to leave insert mode, then type `:wq` and press `Enter` to save and quit.

**Expected output (yours will differ):**
```
(no output - vi closes and you are returned to the shell prompt)
```

**Check it worked:** You are returned to the terminal prompt without any error messages.

---

## Step 9 - Confirm the file was saved correctly

On the server, as your regular user:

```bash
cat ~/terraform-aws-project/main.tf
```

This prints the contents of the file you just created so you can check it matches what you typed.

**Expected output (yours will differ):**
```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.98"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}
```

**Check it worked:** The file contents should match exactly what you typed in Step 8, with no missing lines or typos.

---

## Step 10 - Change into the project directory

Why this step: Terraform commands must be run from inside the project directory. The next command (`terraform init`) looks for `.tf` files in the current directory, so we need to be in the right place first.

On the server, as your regular user:

```bash
cd ~/terraform-aws-project
```

`cd` means "change directory." This moves your current location in the terminal to your project folder.

**Expected output (yours will differ):**
```
(no output)
```

**Check it worked:** No error message means you are now inside the project directory. You can type `pwd` to confirm your location if you like.

---

## Step 11 - Initialize the Terraform project

Why this step: `terraform init` reads your `main.tf` file, sees that you need the AWS provider, and downloads it from the internet into a hidden `.terraform` folder inside your project directory. You must run this once before you can do anything else with a new project.

On the server, as your regular user (inside `~/terraform-aws-project`):

```bash
terraform init
```

This downloads all required provider plugins declared in your configuration and creates a lock file to record the exact versions used.

**Expected output (yours will differ):**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.98"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
...
```

**Check it worked:** You should see `Terraform has been successfully initialized!` near the end of the output.

---

## Step 12 - Confirm the provider plugin was downloaded

On the server, as your regular user (inside `~/terraform-aws-project`):

```bash
find ~/terraform-aws-project/.terraform -type f
```

`find` searches for files inside a directory. `-type f` means "only show files, not directories." This lets us confirm that the AWS provider binary was actually downloaded.

**Expected output (yours will differ):**
```
/home/ec2-user/terraform-aws-project/.terraform/providers/registry.terraform.io/hashicorp/aws/5.100.0/linux_amd64/LICENSE.txt
/home/ec2-user/terraform-aws-project/.terraform/providers/registry.terraform.io/hashicorp/aws/5.100.0/linux_amd64/terraform-provider-aws_v5.100.0_x5
```

**Check it worked:** You should see a path containing `hashicorp/aws` and a file named `terraform-provider-aws_...`. That file is the actual provider plugin binary Terraform will use.

---

## Step 13 - Validate the configuration

Why this step: `terraform validate` checks your `.tf` files for syntax errors and logical mistakes without connecting to AWS or making any changes. It is a quick safety check to run before doing anything real.

On the server, as your regular user (inside `~/terraform-aws-project`):

```bash
terraform validate
```

This reads all `.tf` files in the current directory and reports whether they are syntactically correct.

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

**Check it worked:** You should see `Success! The configuration is valid.`

---

## Troubleshooting

**If you hit a GPG key verification error during `yum install terraform`:**

This can happen if the HashiCorp GPG key has not been imported yet or if there is a temporary network issue. Try clearing the yum metadata cache and retrying:

```bash
sudo yum clean metadata
```

Then run the install command again (Step 5). If the problem persists, check that the `gpgkey=` line in `/etc/yum.repos.d/hashicorp.repo` is correct as shown in Step 4.

---

## Summary

You have completed the following:

1. Added the official HashiCorp yum repository to CentOS Stream 9.
2. Installed Terraform version 1.17.0.
3. Created a project directory and a `main.tf` configuration file that declares the AWS provider.
4. Run `terraform init` to download the AWS provider plugin.
5. Confirmed the configuration is valid with `terraform validate`.

Your next steps would be to configure AWS credentials on this server (using environment variables or the AWS CLI) and then begin writing resource blocks in `main.tf` to define infrastructure.
