# Reusable Security Groups with Terraform Variables and for_each

**Objective:** Install Terraform and the AWS CLI on a CentOS Stream 9 server, write a three-file Terraform project, and use the `for_each` feature to create two AWS security groups from a single resource block.

**Estimated Time:** 45-60 minutes

**Prerequisites:**
- An EC2 instance running CentOS Stream 9 with an IAM role attached (so the server can talk to AWS without storing credentials)
- SSH access to the instance as `ec2-user`
- Basic comfort at a Linux command line (typing commands, pressing Enter)

---

## Part 1: Check What Is Already Installed

### Step 1: Check whether Terraform is already on the server

On the server, as ec2-user:

```bash
which terraform
```

This asks the shell to find a program called `terraform`. If it is not found, you will see a message saying so - that is fine, you will install it next.

Expected output (yours will differ):

```
/usr/bin/which: no terraform in (/home/ec2-user/.local/bin:/home/ec2-user/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin)
```

Check it worked: you should see a line beginning with `no terraform in` - this confirms Terraform is not yet installed and you need to continue to the next step.

---

### Step 2: Check whether the AWS CLI is already on the server

On the server, as ec2-user:

```bash
aws sts get-caller-identity
```

`aws sts get-caller-identity` asks AWS "who am I?" using your current credentials. This is a quick way to check that both the CLI and credentials are working.

Expected output (yours will differ):

```
bash: line 1: aws: command not found
```

Check it worked: you should see `command not found` - this tells you the AWS CLI is also missing and needs to be installed.

---

### Step 3: Confirm your operating system version

On the server, as ec2-user:

```bash
cat /etc/os-release
```

`cat` prints the contents of a file. `/etc/os-release` contains information about the Linux distribution you are running. You need to know this so you download the correct packages in the next steps.

Expected output (yours will differ):

```
NAME="CentOS Stream"
VERSION="9"
ID="centos"
...
PRETTY_NAME="CentOS Stream 9"
```

Check it worked: you should see `CentOS Stream` and `VERSION="9"` in the output, confirming this is CentOS Stream 9.

---

## Part 2: Install Required Tools

### Step 4: Install helper utilities

Why this step: `yum-utils` provides the `yum-config-manager` command you will use in the next step to add the HashiCorp repository. `unzip` and `curl` are general-purpose tools that many installers need.

On the server, as ec2-user:

```bash
sudo yum install -y yum-utils unzip curl
```

`sudo` runs the command as an administrator. `yum install` installs packages. `-y` automatically answers "yes" to any confirmation prompts so you do not have to type it. `yum-utils`, `unzip`, and `curl` are the package names to install.

Expected output (yours will differ):

```
Installed:
  unzip-6.0-59.el9.x86_64

Complete!
```

Check it worked: you should see `Complete!` at the end of the output.

---

### Step 5: Add the HashiCorp software repository

Why this step: CentOS does not know about Terraform by default. You need to tell it where to find HashiCorp packages by adding a new repository (a trusted list of software).

On the server, as ec2-user:

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`yum-config-manager` manages repository settings. `--add-repo` tells it to register a new repository using the URL that follows. HashiCorp publishes a ready-made repository file at this URL for Red Hat-family Linux systems.

Expected output (yours will differ):

```
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see `Adding repo from:` followed by the URL, confirming the repository was registered.

---

### Step 6: Install Terraform

On the server, as ec2-user:

```bash
sudo yum install -y terraform
```

Now that the HashiCorp repository is registered, `yum` can find and install Terraform. This also pulls in any other packages that Terraform depends on.

Expected output (yours will differ):

```
Installed:
  terraform-1.17.0-1.x86_64

Complete!
```

Check it worked: you should see `terraform-` followed by a version number in the `Installed:` section, and `Complete!` at the end.

---

### Step 7: Confirm Terraform installed correctly

On the server, as ec2-user:

```bash
terraform version
```

This asks Terraform to print its version number. If the command runs without an error, Terraform is installed and on your PATH (meaning the shell can find it).

Expected output (yours will differ):

```
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see `Terraform v` followed by a version number, with no error messages.

---

### Step 8: Check that this server has an IAM role attached

Why this step: Instead of storing AWS access keys on the server (which is a security risk), EC2 instances can be given an IAM role. Terraform will automatically use that role's temporary credentials. This step checks whether the role is present.

On the server, as ec2-user:

```bash
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

`curl` fetches a URL. `-s` means "silent" - it hides progress messages. The address `169.254.169.254` is a special internal AWS address that only works from inside an EC2 instance. It serves information about the instance, including its IAM role name.

Expected output (yours will differ):

```
suta-cb-spike-tf
```

Check it worked: you should see a role name printed on the screen. Any non-empty output means an IAM role is attached and Terraform will be able to authenticate to AWS automatically.

---

### Step 9: Install the AWS CLI

On the server, as ec2-user:

```bash
sudo yum install -y awscli
```

`awscli` is the package name for the AWS Command Line Interface on CentOS. Once installed, the `aws` command becomes available.

Expected output (yours will differ):

```
Complete!
```

Check it worked: you should see `Complete!` at the end.

---

### Step 10: Confirm the AWS CLI works and credentials are active

On the server, as ec2-user:

```bash
aws sts get-caller-identity
```

This asks AWS "who am I?" The CLI will automatically pick up the IAM role credentials from the instance metadata. A successful response proves both the CLI and the role are working.

Expected output (yours will differ):

```
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-02f9412f243a38117",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-02f9412f243a38117"
}
```

Check it worked: you should see a JSON block containing `"Account":` and `"Arn":` fields. Any response with these fields confirms authentication is working.

---

## Part 3: Create the Terraform Project Directory

### Step 11: Create the project folder

On the server, as ec2-user:

```bash
mkdir -p /home/ec2-user/tf-lab
```

`mkdir` creates a directory (folder). `-p` means "create any missing parent folders along the way and do not complain if the folder already exists." All your Terraform files will live in this folder.

Expected output (yours will differ):

```

```

Check it worked: no output and no error message means the directory was created successfully.

---

## Part 4: Write the Terraform Configuration Files

You will create three files. Together they form one Terraform project:

- `variables.tf` - defines the input data (the database names and port numbers)
- `main.tf` - defines the AWS provider and the security group resources
- `outputs.tf` - defines what information Terraform should print after it finishes

### Step 12: Create variables.tf

Why this step: Terraform lets you separate your data from your logic. This file declares a variable called `db_ports` which holds a map (a key-value list) of database engine names to port numbers. The resource in `main.tf` will loop over this map.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/variables.tf
```

This opens the vi text editor. Press `i` to enter Insert mode, then type the file contents exactly as shown below. When you are done, press `Escape`, then type `:wq` and press `Enter` to save and quit.

Type this content into the file:

```hcl
variable "db_ports" {
  description = "Map of database engine names to their default TCP port numbers"
  type        = map(number)
  default = {
    postgres = 5432
    mysql    = 3306
  }
}
```

What each line means:
- `variable "db_ports"` - declares a variable named `db_ports` that other files can reference as `var.db_ports`
- `description` - a human-readable note explaining what this variable is for
- `type = map(number)` - tells Terraform the value must be a map where the keys are text strings and the values are numbers
- `default` - the value Terraform uses if you do not provide your own; here it defines two entries: postgres on port 5432 and mysql on port 3306

Expected output (yours will differ):

```

```

Check it worked: no error message when you save means the file was written. You will verify the contents in a later step.

---

### Step 13: Create main.tf

Why this step: This is the main configuration file. It tells Terraform which cloud provider to use and defines the actual resource to create. The `for_each` argument is the key concept: instead of writing one resource block per database, you write one block and Terraform repeats it for every entry in the map.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/main.tf
```

Press `i` to enter Insert mode, then type the file contents below. Press `Escape`, then `:wq` and `Enter` to save.

Type this content into the file:

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

resource "aws_security_group" "db" {
  for_each = var.db_ports

  name_prefix = "db-${each.key}-"
  description = "Allow ${each.key} traffic on port ${each.value}"

  ingress {
    description = "Allow ${each.key} from internal network"
    from_port   = each.value
    to_port     = each.value
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

What each important section means:

- `terraform { required_providers ... }` - tells Terraform to download the official AWS plugin from HashiCorp; `~> 5.0` means "version 5.anything, but not version 6"
- `provider "aws" { region = "us-east-1" }` - tells the AWS plugin which AWS region to create resources in
- `default_tags` - any tag listed here is automatically added to every AWS resource this project creates; tags are labels that help you find and organize resources in the AWS console
- `resource "aws_security_group" "db"` - declares an AWS security group resource; `"db"` is just a local nickname Terraform uses internally
- `for_each = var.db_ports` - the key feature: Terraform will run through every entry in the `db_ports` map and create one security group for each entry
- `each.key` - inside a `for_each` block, this refers to the current map key (for example `postgres` or `mysql`)
- `each.value` - the current map value (for example `5432` or `3306`)
- `name_prefix` - instead of a fixed name, this gives the security group a name that starts with `db-postgres-` or `db-mysql-` and then a random suffix (AWS requires unique names)
- `ingress` block - defines traffic that is allowed IN; here it allows TCP connections on the database port, but only from IP addresses in the range `10.0.0.0/8` (a private internal network)
- `egress` block - defines traffic allowed OUT; `protocol = "-1"` means all protocols; `0.0.0.0/0` means any destination - this allows the security group to reach anywhere outbound
- `cidr_blocks = ["10.0.0.0/8"]` in ingress - a CIDR block is a notation for a range of IP addresses; `10.0.0.0/8` covers all addresses from 10.0.0.0 to 10.255.255.255, which are private internal addresses

Expected output (yours will differ):

```

```

Check it worked: no error message on save means the file was written correctly.

---

### Step 14: Create outputs.tf

Why this step: After Terraform creates your resources, it is useful to see the IDs of the things it made. This file tells Terraform to print the security group IDs at the end of `apply`.

On the server, as ec2-user:

```bash
vi /home/ec2-user/tf-lab/outputs.tf
```

Press `i` to enter Insert mode, type the content below, then press `Escape`, type `:wq`, and press `Enter`.

Type this content into the file:

```hcl
output "db_security_group_ids" {
  description = "Map of database engine names to their security group IDs"
  value       = { for k, sg in aws_security_group.db : k => sg.id }
}
```

What each line means:
- `output "db_security_group_ids"` - declares an output block with the name `db_security_group_ids`; this name is what you will see when Terraform prints results
- `description` - a note explaining what this output contains
- `value = { for k, sg in aws_security_group.db : k => sg.id }` - this is a `for` expression (a mini loop): for every security group that was created by the `for_each` in `main.tf`, collect its name (`k`) and its AWS-assigned ID (`sg.id`) into a map

Expected output (yours will differ):

```

```

Check it worked: no error on save means the file was written correctly.

---

### Step 15: Verify all three files look correct

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/main.tf
```

`cat` prints the file contents to the screen so you can visually confirm everything was saved correctly.

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
...
```

Check it worked: you should see the full content of `main.tf` with no strange characters or missing lines.

---

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/variables.tf
```

Expected output (yours will differ):

```
variable "db_ports" {
  description = "Map of database engine names to their default TCP port numbers"
  type        = map(number)
  default = {
    postgres = 5432
    mysql    = 3306
  }
}
```

Check it worked: you should see both `postgres = 5432` and `mysql = 3306` in the default block.

---

On the server, as ec2-user:

```bash
cat /home/ec2-user/tf-lab/outputs.tf
```

Expected output (yours will differ):

```
output "db_security_group_ids" {
  description = "Map of database engine names to their security group IDs"
  value       = { for k, sg in aws_security_group.db : k => sg.id }
}
```

Check it worked: you should see the `for` expression with `aws_security_group.db` in it.

---

## Part 5: Run Terraform

### Step 16: Move into the project directory

On the server, as ec2-user:

```bash
cd /home/ec2-user/tf-lab
```

`cd` means "change directory." All Terraform commands look for configuration files in the current directory, so you need to be inside the project folder before running them.

Expected output (yours will differ):

```

```

Check it worked: no error message means you are now inside the `tf-lab` folder. You can confirm by running `pwd` which should print `/home/ec2-user/tf-lab`.

---

### Step 17: Initialize the Terraform project

Why this step: Before Terraform can do anything, it needs to download the AWS plugin you specified in `main.tf`. `terraform init` reads your configuration, figures out which plugins are needed, and downloads them into a hidden folder called `.terraform`.

On the server, as ec2-user:

```bash
terraform init
```

This sets up the project. It downloads the `hashicorp/aws` provider plugin and creates a lock file (`.terraform.lock.hcl`) that records exactly which version was downloaded. You only need to run this once per project, or again if you change provider versions.

Expected output (yours will differ):

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!` near the end of the output.

---

### Step 18: Preview what Terraform will create

Why this step: `terraform plan` is a dry run. It shows you exactly what Terraform intends to do - without actually doing it. Always run plan before apply so there are no surprises.

On the server, as ec2-user:

```bash
terraform plan
```

Terraform reads your configuration files, compares them to what currently exists in AWS (nothing yet), and prints a list of resources it plans to create. Lines beginning with `+` mean "will be created."

Expected output (yours will differ):

```
Terraform will perform the following actions:

  # aws_security_group.db["mysql"] will be created
  + resource "aws_security_group" "db" {
      + description = "Allow mysql traffic on port 3306"
      ...
  # aws_security_group.db["postgres"] will be created
  + resource "aws_security_group" "db" {
      + description = "Allow postgres traffic on port 5432"
      ...
```

Check it worked: you should see two resources listed - one for `mysql` and one for `postgres` - both marked with `+` meaning they will be created.

---

### Step 19: Apply the configuration and create the resources

Why this step: `terraform apply` is the step that actually talks to AWS and creates the resources. The `-auto-approve` flag skips the manual confirmation prompt. In a learning environment this is fine, but on a real production system you would omit that flag and type `yes` when prompted so you have a chance to review before committing.

On the server, as ec2-user:

```bash
terraform apply -auto-approve
```

Terraform runs the same plan as before and then immediately executes it. It creates the two security groups in AWS and records what it created in a file called `terraform.tfstate` (the "state file"). The state file is how Terraform remembers what it has built.

Expected output (yours will differ):

```
Terraform will perform the following actions:
  # aws_security_group.db["mysql"] will be created
  ...
  # aws_security_group.db["postgres"] will be created
  ...
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

db_security_group_ids = {
  "mysql" = "sg-0184698820c79fbb7"
  "postgres" = "sg-0c63638f1b30b03ba"
}
```

Check it worked: you should see `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.` and then the `Outputs:` section showing both security group IDs starting with `sg-`.

---

## Part 6: Verify the Results

### Step 20: List the resources Terraform is tracking

On the server, as ec2-user:

```bash
terraform -chdir=/home/ec2-user/tf-lab state list
```

`terraform state list` prints all the resources that Terraform knows about (everything recorded in the state file). `-chdir=/home/ec2-user/tf-lab` tells Terraform to look in that folder for the state file, which is useful if you are not already in the project directory. Each line is a resource address in the format `type.name["key"]`.

Expected output (yours will differ):

```
aws_security_group.db["mysql"]
aws_security_group.db["postgres"]
```

Check it worked: you should see exactly two lines, one for `mysql` and one for `postgres`.

---

### Step 21: Confirm there is nothing left to change

Why this step: Running `plan` again after `apply` is a good sanity check. If everything was created correctly, Terraform should report that the real infrastructure matches the configuration and there is nothing to do.

On the server, as ec2-user:

```bash
terraform -chdir=/home/ec2-user/tf-lab plan -detailed-exitcode
```

`-detailed-exitcode` changes what exit code the command returns: `0` means no changes needed, `1` means an error, `2` means changes are needed. This is useful in scripts. Here you are using it to confirm the infrastructure is already in the desired state.

Expected output (yours will differ):

```
aws_security_group.db["mysql"]: Refreshing state... [id=sg-0184698820c79fbb7]
aws_security_group.db["postgres"]: Refreshing state... [id=sg-0c63638f1b30b03ba]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Check it worked: you should see `No changes. Your infrastructure matches the configuration.`

---

### Step 22: Print the output values

On the server, as ec2-user:

```bash
terraform -chdir=/home/ec2-user/tf-lab output
```

`terraform output` prints everything defined in `outputs.tf`. This is a quick way to retrieve information about resources Terraform has already created without having to dig through the state file manually.

Expected output (yours will differ):

```
db_security_group_ids = {
  "mysql" = "sg-0184698820c79fbb7"
  "postgres" = "sg-0c63638f1b30b03ba"
}
```

Check it worked: you should see a map with two entries, each containing a security group ID starting with `sg-`.

---

## Troubleshooting Notes

**If you hit this - Terraform command not found after install:**

If you run `terraform version` and still see `command not found`, your shell may have cached the old PATH. Fix it by starting a new shell session:

```bash
exec bash
```

Then try `terraform version` again.

---

**If you hit this - AWS CLI not found after install:**

Similarly, if `aws` is not found after installing `awscli`, start a fresh shell session:

```bash
exec bash
```

---

**If you hit this - GPG key or repository signature error during yum install:**

If `yum install terraform` fails with a message about a GPG key or signature verification, you may need to accept the HashiCorp GPG key. Re-run the install and type `y` when prompted to accept the key, or run:

```bash
sudo rpm --import https://rpm.releases.hashicorp.com/gpg
```

Then retry `sudo yum install -y terraform`.

---

**If you hit this - "No IAM role" or empty response from the metadata URL in Step 8:**

If `curl http://169.254.169.254/latest/meta-data/iam/security-credentials/` returns nothing or an error, the EC2 instance does not have an IAM role attached. You will need to attach one in the AWS console (EC2 > Actions > Security > Modify IAM Role) before Terraform can authenticate to AWS. Ask your instructor for help with this.
