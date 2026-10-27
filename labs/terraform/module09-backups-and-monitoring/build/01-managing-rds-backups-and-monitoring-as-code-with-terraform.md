# Managing RDS Backups and Monitoring as Code with Terraform

**Objective:** Use Terraform to create an AWS RDS PostgreSQL database with a 7-day backup policy and a CloudWatch alarm that fires when free storage drops below 2 GiB.

**Estimated Time:** 60-90 minutes

**Prerequisites:**
- An AWS EC2 instance running CentOS Stream 9 (or Amazon Linux 2023)
- An IAM role attached to the instance with permissions for RDS, CloudWatch, EC2 (VPC/subnets), and IAM
- SSH access to the instance as `ec2-user`
- Basic comfort with the Linux command line and the `vi` text editor

---

## Part 1 - Install Terraform

Terraform is a tool that lets you describe AWS infrastructure in text files and then create it with a single command. Think of it as a recipe that AWS follows to build things for you.

**Step 1 - Check whether Terraform is already installed**

On the server, as ec2-user:

```
which terraform
```

This checks every directory in your PATH for a program called `terraform` and prints its location if found.

```
Expected output (yours will differ):
/usr/bin/which: no terraform in (/home/ec2-user/.local/bin:/home/ec2-user/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin)
```

Check it worked: if you see "no terraform", it is not installed and you need the next steps. If you see a path like `/usr/bin/terraform`, skip ahead to Step 5.

---

**Step 2 - Install the yum-utils package**

Why this step: `yum-utils` provides the `yum-config-manager` command you need in Step 3 to add the HashiCorp software repository.

On the server, as ec2-user:

```
sudo yum install -y yum-utils
```

`sudo` runs the command as root (administrator). `yum install` installs a package. `-y` automatically answers "yes" to any prompts.

```
Expected output (yours will differ):
Package yum-utils-4.3.0-27.el9.noarch is already installed.
...
Complete!
```

Check it worked: you should see the word `Complete!` at the end of the output.

---

**Step 3 - Add the HashiCorp software repository**

Why this step: By default, yum does not know where to find Terraform. This step tells it to look in HashiCorp's official repository.

On the server, as ec2-user:

```
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

`yum-config-manager --add-repo` downloads a repository definition file from the URL and saves it so yum can find packages from HashiCorp.

```
Expected output (yours will differ):
Adding repo from: https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Check it worked: you should see `Adding repo from:` followed by the HashiCorp URL.

---

**Step 4 - Install Terraform**

On the server, as ec2-user:

```
sudo yum -y install terraform
```

This downloads and installs the Terraform package from the HashiCorp repository you just added. `-y` skips confirmation prompts.

```
Expected output (yours will differ):
Installing:
 terraform             x86_64      1.17.0-1                hashicorp       37 M
...
Complete!
```

Check it worked: you should see `terraform` listed under `Installing:` and the word `Complete!` at the end.

---

**Step 5 - Confirm Terraform is working**

On the server, as ec2-user:

```
terraform version
```

Prints the installed version of Terraform.

```
Expected output (yours will differ):
Terraform v1.17.0
on linux_amd64
```

Check it worked: you should see a version number starting with `Terraform v`.

---

## Part 2 - Install the AWS CLI

The AWS CLI (Command Line Interface) is a tool that lets you talk to AWS services from the terminal. Terraform uses the same AWS credentials, so getting the CLI working also confirms Terraform can reach AWS.

**Step 6 - Download the AWS CLI installer**

On the server, as ec2-user:

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
```

`curl` downloads a file from a URL. `-o /tmp/awscliv2.zip` saves it to the `/tmp` folder with that filename.

```
Expected output (yours will differ):
100 70.9M  100 70.9M    0     0   389M      0 --:--:-- --:--:-- --:--:--  387M
```

Check it worked: you should see `100` in the first column, meaning the download reached 100%.

---

**If you hit this - unzip not found**

If you try to unzip the file and see:

```
bash: line 1: unzip: command not found
```

Install unzip first with:

```
sudo yum install -y unzip
```

You should see `Complete!` before continuing.

---

**Step 7 - Move into the /tmp directory**

On the server, as ec2-user:

```
cd /tmp
```

Changes your current working directory to `/tmp` where the downloaded zip file is stored.

```
Expected output (yours will differ):
(no output - a blank prompt means it worked)
```

Check it worked: your prompt should now show `/tmp` or simply return to a prompt with no error.

---

**Step 8 - Unzip the AWS CLI installer**

On the server, as ec2-user:

```
unzip -q awscliv2.zip
```

Unpacks the zip file. `-q` means quiet - it suppresses the long list of file names so the output is clean.

```
Expected output (yours will differ):
(no output - silence is success)
```

Check it worked: no error message means the extraction succeeded. You can confirm by running `ls /tmp/aws` and looking for a folder named `aws`.

---

**Step 9 - Run the AWS CLI installer**

On the server, as ec2-user:

```
sudo ./aws/install
```

Runs the installer script that was inside the zip. `./` means "in the current directory". `sudo` is needed because the installer writes files to `/usr/local/bin` which requires administrator access.

```
Expected output (yours will differ):
You can now run: /usr/local/bin/aws --version
```

Check it worked: you should see the line `You can now run: /usr/local/bin/aws --version`.

---

**Step 10 - Confirm the AWS CLI is working**

On the server, as ec2-user:

```
aws --version
```

Prints the installed version of the AWS CLI.

```
Expected output (yours will differ):
aws-cli/2.38.5 Python/3.12.9 Linux/...
```

Check it worked: you should see `aws-cli/` followed by a version number.

---

**Step 11 - Confirm AWS credentials are available via the instance role**

Why this step: The EC2 instance has an IAM role attached to it. The AWS CLI automatically uses that role - you do not need to run `aws configure` or paste any keys. This step confirms the role is working.

On the server, as ec2-user:

```
aws sts get-caller-identity
```

Asks AWS "who am I?" and returns the account number and the role being used. `sts` stands for Security Token Service.

```
Expected output (yours will differ):
{
    "UserId": "AROAU57T24XGRYRUIJGPZ:i-082b3745a7a48481d",
    "Account": "339276916173",
    "Arn": "arn:aws:sts::339276916173:assumed-role/suta-cb-spike-tf/i-082b3745a7a48481d"
}
```

Check it worked: you should see an `"Arn"` value containing `assumed-role` which means the instance role is active and working.

---

## Part 3 - Create the Terraform Project Directory

**Step 12 - Create the working directory**

On the server, as ec2-user:

```
mkdir -p /home/ec2-user/tf-lab
```

Creates a folder called `tf-lab` in your home directory. `-p` means "create any missing parent folders too" and does not fail if the folder already exists.

```
Expected output (yours will differ):
(no output - silence is success)
```

Check it worked: no error message means the folder was created.

---

## Part 4 - Write the Terraform Configuration Files

A Terraform project is made up of `.tf` text files. You will create three:

- `variables.tf` - declares the database password as an input
- `outputs.tf` - declares what information Terraform should print after it finishes
- `main.tf` - the main file that describes all the AWS resources to create

---

**Step 13 - Create variables.tf**

Why this step: Terraform needs to know about the database password before it can use it. Declaring it as a variable here, with `sensitive = true`, means Terraform will never print the password in its output.

On the server, as ec2-user, change into the project directory:

```
cd /home/ec2-user/tf-lab
```

```
Expected output (yours will differ):
(no output - silence is success)
```

Check it worked: no error means you are now in the tf-lab directory.

---

**Step 14 - Open variables.tf in vi**

On the server, as ec2-user:

```
vi variables.tf
```

Opens the `vi` text editor to create a new file called `variables.tf`.

```
Expected output (yours will differ):
(vi opens a blank screen)
```

Check it worked: you should see a mostly blank screen with `~` characters down the left side and `variables.tf` in the title area at the bottom.

---

**Step 15 - Enter insert mode and type the file contents**

Press `i` to enter insert mode (you will see `-- INSERT --` at the bottom of the screen), then type the following exactly:

```
variable "db_password" {
  description = "Master password for the RDS instance. Choose a strong password."
  type        = string
  sensitive   = true
}
```

What each line means:
- `variable "db_password"` - declares a variable named `db_password` that you will supply when running Terraform
- `type = string` - the value must be plain text
- `sensitive = true` - tells Terraform to hide this value in all output and logs

When you have finished typing, press `Esc` to leave insert mode, then type `:wq` and press `Enter` to save and quit.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: you are back at the shell prompt with no error message.

---

**Step 16 - Create outputs.tf**

On the server, as ec2-user:

```
vi outputs.tf
```

Opens vi to create the outputs file.

```
Expected output (yours will differ):
(vi opens a blank screen)
```

Check it worked: vi opens without error.

---

**Step 17 - Enter the outputs.tf contents**

Press `i` to enter insert mode, then type the following:

```
output "db_instance_id" {
  description = "The identifier of the RDS instance"
  value       = aws_db_instance.appdb.id
}

output "db_instance_endpoint" {
  description = "The connection endpoint of the RDS instance"
  value       = aws_db_instance.appdb.endpoint
}

output "db_instance_status" {
  description = "The status of the RDS instance"
  value       = aws_db_instance.appdb.status
}

output "cloudwatch_alarm_name" {
  description = "Name of the FreeStorageSpace CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.rds_low_storage.alarm_name
}

output "backup_retention_period" {
  description = "Backup retention period in days"
  value       = aws_db_instance.appdb.backup_retention_period
}
```

What each block does: each `output` block names a piece of information (`value`) that Terraform will print once it has finished creating your resources. For example `aws_db_instance.appdb.endpoint` means "the endpoint attribute of the resource named `appdb`".

Press `Esc`, then type `:wq` and press `Enter`.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: you are back at the shell prompt with no error.

---

**Step 18 - Create main.tf**

This is the most important file. It defines every AWS resource Terraform will create. You will open it in vi and enter it in sections so you understand each part.

On the server, as ec2-user:

```
vi main.tf
```

```
Expected output (yours will differ):
(vi opens a blank screen)
```

Check it worked: vi opens without error.

---

**Step 19 - Enter the main.tf contents**

Press `i` to enter insert mode, then type the entire block below. Take your time - every line matters.

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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "appdb" {
  name_prefix = "appdb-"
  subnet_ids  = data.aws_subnets.default.ids
  description = "Subnet group for appdb RDS instance (all default-VPC subnets)"
}

resource "aws_db_instance" "appdb" {
  identifier_prefix = "appdb-"
  db_name           = "appdb"
  username          = "dbadmin"
  password          = var.db_password

  engine         = "postgres"
  engine_version = "16.3"

  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_subnet_group_name = aws_db_subnet_group.appdb.name
  publicly_accessible  = false

  deletion_protection = false
  apply_immediately   = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  copy_tags_to_snapshot   = true

  maintenance_window = "sun:04:30-sun:05:30"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  skip_final_snapshot = true
}

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "rds-appdb-low-free-storage"
  alarm_description   = "Fires when RDS free storage drops below 2 GiB. Add an SNS action in production."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 2147483648
  evaluation_periods  = 3
  period              = 300

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.appdb.id
  }

  alarm_actions = []
  ok_actions    = []

  treat_missing_data = "notBreaching"
}
```

What the key settings mean:

- `required_providers` - locks the AWS plugin to version 5.x so the code behaves the same for everyone
- `default_tags` - adds a `Project` tag to every resource automatically
- `data "aws_vpc" "default"` - looks up your account's default VPC so you do not need to hard-code an ID
- `aws_db_subnet_group` - RDS requires a subnet group that spans at least two availability zones; this creates one using all subnets in the default VPC
- `backup_retention_period = 7` - keeps automated daily backups for 7 days (the AWS default is only 1 day)
- `backup_window = "03:00-04:00"` - the daily backup runs between 3 AM and 4 AM UTC
- `maintenance_window = "sun:04:30-sun:05:30"` - patches are applied Sunday morning, after the backup window finishes, so they never overlap
- `copy_tags_to_snapshot = true` - every backup snapshot inherits the Project tag
- `enabled_cloudwatch_logs_exports` - streams the PostgreSQL query log and upgrade log to CloudWatch automatically
- `skip_final_snapshot = true` - for this lab only, allows `terraform destroy` to work without taking a final backup; in production set this to `false`
- `threshold = 2147483648` - the alarm fires when free space falls below 2 GiB (2,147,483,648 bytes). RDS measures free space in bytes
- `evaluation_periods = 3` and `period = 300` - the alarm only fires if free space is below the threshold for 3 checks in a row, each 5 minutes apart (15 minutes total), to avoid false alarms from momentary dips
- `alarm_actions = []` - no notification is sent for this lab; in production you would add an SNS topic ARN here to page your team

Press `Esc`, then type `:wq` and press `Enter`.

```
Expected output (yours will differ):
(returns to the shell prompt)
```

Check it worked: you are back at the shell prompt with no error.

---

**Step 20 - Confirm all three files exist**

On the server, as ec2-user:

```
ls -la /home/ec2-user/tf-lab/
```

Lists all files in the project directory. `-l` shows details (size, date). `-a` includes hidden files.

```
Expected output (yours will differ):
total 16
drwxr-xr-x. 2 ec2-user ec2-user   59 Oct 25 21:21 .
drwx------. 6 ec2-user ec2-user  120 Oct 25 21:20 ..
-rw-r--r--. 1 ec2-user ec2-user 5544 Oct 25 21:21 main.tf
-rw-r--r--. 1 ec2-user ec2-user  714 Oct 25 21:21 outputs.tf
-rw-r--r--. 1 ec2-user ec2-user  276 Oct 25 21:20 variables.tf
```

Check it worked: you should see all three files - `main.tf`, `outputs.tf`, and `variables.tf` - listed with non-zero sizes.

---

## Part 5 - Initialize Terraform

**Step 21 - Run terraform init**

Why this step: Before Terraform can do anything, it must download the AWS plugin (called a "provider") that teaches it how to talk to AWS. `terraform init` reads your `main.tf`, sees that you need `hashicorp/aws`, and downloads it into a hidden `.terraform` folder.

On the server, as ec2-user:

```
terraform init
```

Downloads the AWS provider plugin and sets up the project. You only need to run this once per project (or when you add new providers).

```
Expected output (yours will differ):
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
```

Check it worked: you should see `Terraform has been successfully initialized!`.

---

## Part 6 - Preview and Apply the Configuration

**Step 22 - Run terraform plan**

Why this step: `terraform plan` is a dry run. It shows you exactly what Terraform will create, change, or delete - without actually doing anything. Always review the plan before applying.

You need to supply the database password here. Choose your own strong password (at least 8 characters, mixing uppercase letters, lowercase letters, numbers, and symbols). Replace `YOUR_DB_PASSWORD` in the command below with your chosen password.

On the server, as ec2-user:

```
terraform plan -var="db_password=YOUR_DB_PASSWORD"
```

`-var="db_password=..."` passes your password to the variable you declared in `variables.tf`. Because the variable is marked `sensitive = true`, Terraform will not print the value in its output.

```
Expected output (yours will differ):
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 1s [id=vpc-09a1c840cf0697b9a]
data.aws_subnets.default: Reading...
data.aws_subnets.default: Read complete after 0s [id=us-east-1]

Terraform will perform the following actions:

  # aws_cloudwatch_metric_alarm.rds_low_storage will be created
  + resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
      ...
  }

  # aws_db_instance.appdb will be created
  + resource "aws_db_instance" "appdb" {
      ...
  }
...
Plan: 3 to add, 0 to change, 0 to destroy.
```

Check it worked: the last line should say `Plan: 3 to add, 0 to change, 0 to destroy` - three resources being created (the DB instance, the subnet group, and the CloudWatch alarm).

---

**Step 23 - Apply the configuration**

Why this step: This is the step that actually creates the resources in AWS. RDS instances take several minutes to become available - be patient.

Use the same password you chose in the previous step. Replace `YOUR_DB_PASSWORD` with it.

On the server, as ec2-user:

```
terraform apply -auto-approve -var="db_password=YOUR_DB_PASSWORD"
```

`apply` creates the resources. `-auto-approve` skips the interactive "yes/no" confirmation prompt (safe because you already reviewed the plan). `-var` passes the password.

```
Expected output (yours will differ):
data.aws_vpc.default: Reading...
...
aws_db_subnet_group.appdb: Creating...
aws_db_subnet_group.appdb: Creation complete after 2s
aws_db_instance.appdb: Creating...
aws_db_instance.appdb: Still creating... [10s elapsed]
...
aws_cloudwatch_metric_alarm.rds_low_storage: Creating...
aws_cloudwatch_metric_alarm.rds_low_storage: Creation complete after 1s
aws_db_instance.appdb: Still creating... [4m10s elapsed]
aws_db_instance.appdb: Creation complete after ...

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

Check it worked: you should see `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

---

## Part 7 - Verify Everything Was Created Correctly

**Step 24 - List all resources in Terraform state**

On the server, as ec2-user:

```
terraform state list
```

Shows every resource that Terraform is now managing. "State" is Terraform's record of what it created.

```
Expected output (yours will differ):
data.aws_subnets.default
data.aws_vpc.default
aws_cloudwatch_metric_alarm.rds_low_storage
aws_db_instance.appdb
aws_db_subnet_group.appdb
```

Check it worked: you should see all five entries including `aws_db_instance.appdb` and `aws_cloudwatch_metric_alarm.rds_low_storage`.

---

**Step 25 - Print the Terraform outputs**

On the server, as ec2-user:

```
terraform output
```

Prints the values declared in `outputs.tf` - instance ID, endpoint, status, alarm name, and backup retention period.

```
Expected output (yours will differ):
backup_retention_period = 7
cloudwatch_alarm_name = "rds-appdb-low-free-storage"
db_instance_endpoint = "appdb-20261025212211673400000002.cyn0wsqma5in.us-east-1.rds.amazonaws.com:5432"
db_instance_id = "db-F3XMIJDBIJGGKENZM4MPM6FTKQ"
db_instance_status = "available"
```

Check it worked: `db_instance_status` should show `"available"` and `backup_retention_period` should show `7`.

---

**Step 26 - Verify the backup settings directly in AWS**

Why this step: Terraform said it worked, but it is good practice to confirm the settings are really in AWS and not just in Terraform's local state file.

On the server, as ec2-user:

```
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[DBInstanceIdentifier,DBInstanceStatus,BackupRetentionPeriod,PreferredBackupWindow,PreferredMaintenanceWindow]" --output text
```

`describe-db-instances` fetches details about your RDS instances from AWS directly. The `--query` argument filters the response down to just the fields that matter for this lab:
- `DBInstanceIdentifier` - the name of the instance
- `DBInstanceStatus` - whether it is available
- `BackupRetentionPeriod` - how many days backups are kept
- `PreferredBackupWindow` - when daily backups run
- `PreferredMaintenanceWindow` - when patches are applied

`--output text` prints results as plain columns rather than JSON.

```
Expected output (yours will differ):
appdb-20261025212211673400000002	available	7	03:00-04:00	sun:04:30-sun:05:30
```

Check it worked: the third column should be `7` (retention days), the fourth column `03:00-04:00` (backup window), and the fifth column `sun:04:30-sun:05:30` (maintenance window).

---

**Step 27 - Verify the CloudWatch alarm exists**

On the server, as ec2-user:

```
aws cloudwatch describe-alarms --region us-east-1 --alarm-names "rds-appdb-low-free-storage" --query "MetricAlarms[0].{AlarmName:AlarmName,MetricName:MetricName,Threshold:Threshold,EvaluationPeriods:EvaluationPeriods,Period:Period}" --output json
```

`describe-alarms` fetches your CloudWatch alarms from AWS. `--alarm-names` filters to only the alarm you created. The `--query` argument pulls out the most important fields. `--output json` prints the result as formatted JSON.

```
Expected output (yours will differ):
{
    "AlarmName": "rds-appdb-low-free-storage",
    "MetricName": "FreeStorageSpace",
    "Threshold": 2147483648.0,
    "EvaluationPeriods": 3,
    "Period": 300
}
```

Check it worked: `"Threshold"` should be `2147483648.0` (2 GiB in bytes) and `"EvaluationPeriods"` should be `3`.

---

**Step 28 - Verify CloudWatch log exports are enabled**

On the server, as ec2-user:

```
aws rds describe-db-instances --region us-east-1 --query "DBInstances[?starts_with(DBInstanceIdentifier,'appdb-')].[EnabledCloudwatchLogsExports]" --output json
```

Checks which log types are being streamed to CloudWatch Logs.

```
Expected output (yours will differ):
[
    [
        [
            "postgresql",
            "upgrade"
        ]
    ]
]
```

Check it worked: you should see both `"postgresql"` and `"upgrade"` in the list.

---

## Summary

You have successfully:

1. Installed Terraform and the AWS CLI on a CentOS server
2. Written three Terraform configuration files that describe an RDS PostgreSQL instance with explicit backup settings and a CloudWatch alarm
3. Used `terraform init` to download the AWS provider
4. Used `terraform plan` to preview the changes safely
5. Used `terraform apply` to create the resources in AWS
6. Verified every key setting directly in AWS using the CLI

The most important lesson here is that backup and monitoring settings are now in version-controlled text files rather than being clicked once in the console and forgotten. Anyone on your team can read `main.tf` and immediately see the retention policy, backup window, maintenance window, and alarm threshold.

**Important note for production use:** Before using this configuration for a real database, change `skip_final_snapshot = true` to `skip_final_snapshot = false` and add a `final_snapshot_identifier` value. Also add an SNS topic ARN to `alarm_actions` in the CloudWatch alarm so your team is notified automatically when storage runs low.
