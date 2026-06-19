# Build Guide 12: Terraform for Database Infrastructure Lifecycle

| | |
|---|---|
| **Time** | 75 minutes |
| **Server** | pg-ops (34.228.32.17) - Terraform installed, pg-primary (100.26.54.122), pg-replica (54.144.241.128) |
| **OS** | CentOS Stream 9 |
| **Terraform** | v1.15.6 |
| **Skill level** | Complete beginner |
| **Interview prep** | Lukasz Mucha - Senior DevOps Engineer, The Voleon Group |

## Why This Matters

At The Voleon Group, database infrastructure is not created by clicking buttons in the AWS console. Every EC2 instance, EBS volume, security group, and DNS record is defined in code - Terraform code. When Lukasz asks you about "infrastructure as code," he wants to know that you can read a Terraform plan, understand what it will change, and explain why state management matters for production databases.

This guide walks you through reading, planning, importing, and managing Terraform for PostgreSQL servers using your actual lab infrastructure.

## What You'll Learn

- Where the boundary is between Terraform (infrastructure) and Ansible (configuration)
- How to read existing Terraform code that creates database servers
- How to run `terraform init` and `terraform plan` safely
- How to import existing running servers into Terraform state
- How to create reusable Terraform modules for PostgreSQL servers
- How to manage Terraform state (list, show, move, taint)
- How to read and review a Terraform plan before approving it
- How Terraform and Ansible work together in a complete IaC workflow

## Prerequisites

- Completed BUILD-07 (Ansible) and BUILD-09 (Linux)
- SSH key at `~/.ssh/id_ed25519` with access to pg-ops
- PostgreSQL 17 running on pg-primary and pg-replica
- Terraform v1.15.6 installed on pg-ops (already done in lab setup)

---

## Section 1: Why Terraform for Database Infrastructure

### The Division of Labor

There are two layers to managing database servers:

1. **Infrastructure layer** - The physical (or virtual) resources: compute instances, storage volumes, network rules, DNS entries. This is what Terraform manages.
2. **Configuration layer** - What runs on those resources: PostgreSQL installation, postgresql.conf settings, pg_hba.conf rules, backup schedules. This is what Ansible manages.

The boundary is clean:

| Terraform creates... | Ansible configures... |
|---|---|
| EC2 instances | PostgreSQL installation |
| EBS volumes | postgresql.conf / pg_hba.conf |
| Security groups (firewall) | Database users and roles |
| Key pairs | Replication setup |
| DNS records | Backup schedules (pgBackRest) |
| IAM roles | Monitoring agents |

Think of it this way: Terraform builds the house (walls, roof, plumbing). Ansible furnishes it (furniture, appliances, paint).

### Why Not Just Use the AWS Console?

Three reasons that matter in production:

1. **Reproducibility** - If you need to rebuild the database cluster from scratch (disaster recovery, new datacenter), the Terraform code creates identical infrastructure every time.
2. **Audit trail** - The Terraform code is in git. You can see who changed what, when, and why. The AWS console has CloudTrail, but it is noisy and harder to review.
3. **State tracking** - Terraform knows what exists. It can tell you "these 4 instances, these 3 EBS volumes, this security group are the database cluster." Without it, you are manually tracking resources in a spreadsheet.

### The State File

Terraform keeps a **state file** (`terraform.tfstate`) that maps your code to real AWS resources. For example:

- Your code says `resource "aws_instance" "primary" {...}`
- The state file records: "that resource maps to instance `i-09ff260a00a39c041` in us-east-1"

This is critical because:

- Without state, Terraform would try to create a new instance every time you run `apply`
- With state, Terraform knows the instance already exists and only applies changes

For production, the state file should be stored in S3 (not on your laptop) with DynamoDB locking so two people cannot modify infrastructure at the same time. We will cover this in Section 5.

---

## Section 2: Read and Understand the Existing Terraform

Your lab was created with Terraform. The code lives in the project's `terraform/` directory. Let's copy it to pg-ops and walk through it.

### Step 2.1: Copy the Terraform Directory to pg-ops

On your **local machine**, as your local user:

```bash
scp -i ~/.ssh/id_ed25519 -r ~/Projects/practice/labs/labs/postgres/projects/voleon-dba-lab/terraform ec2-user@34.228.32.17:~/terraform-lab
```

`scp -r` copies a directory recursively over SSH. We copy to `~/terraform-lab` on pg-ops so we have a working copy to experiment with.

### Step 2.2: Verify Terraform Is Installed

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
terraform version
```

Expected output (yours will differ):

```
Terraform v1.15.6
on linux_amd64
```

### Step 2.3: Examine the Main Configuration

On **pg-ops**, as **ec2-user**:

```bash
cat ~/terraform-lab/main.tf
```

Let's break down what each block does:

**The terraform block** - Declares the minimum Terraform version and which providers (cloud APIs) we need:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

This means: "I need Terraform 1.5 or higher, and I need the AWS provider version 5.x." The `~>` means "any 5.x version but not 6.0."

**The provider block** - Tells Terraform which AWS region to use:

```hcl
provider "aws" {
  region = var.aws_region
}
```

`var.aws_region` references a variable defined in `variables.tf`. Terraform reads the value from there.

**The key pair resource** - Uploads your SSH public key to AWS:

```hcl
resource "aws_key_pair" "lab" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}
```

`file()` reads a file from disk. This uploads `~/.ssh/id_ed25519.pub` to AWS so EC2 instances can use it for SSH access.

**The security group resource** - Defines firewall rules for all lab nodes:

```hcl
resource "aws_security_group" "lab" {
  name        = "${var.lab_name}-sg"
  description = "Voleon DBA lab - PG, Redis, PgBouncer, Prometheus, Grafana, Docker, SSH"
  ...
}
```

Each `ingress` block opens a port range. For example, ports 5432-5433 for PostgreSQL (native and Docker). The `self = true` rule allows all traffic between instances in the same security group.

**The EC2 instance resource** - Creates the actual servers:

```hcl
resource "aws_instance" "node" {
  for_each = var.nodes
  ami           = var.ami_id
  instance_type = each.value.instance_type
  ...
}
```

`for_each = var.nodes` means Terraform creates one instance per entry in the `nodes` map variable. So four entries (primary, replica, container, ops) create four EC2 instances.

### Step 2.4: Examine the Variables

On **pg-ops**, as **ec2-user**:

```bash
cat ~/terraform-lab/variables.tf
```

The `nodes` variable is a map of objects. Each object has an `instance_type` and `hostname`. This is how Terraform knows to create four instances with different names:

```hcl
variable "nodes" {
  type = map(object({
    instance_type = string
    hostname      = string
  }))
  default = {
    primary = {
      instance_type = "t3.medium"
      hostname      = "pg-primary"
    }
    ...
  }
}
```

### Step 2.5: Examine the Outputs

On **pg-ops**, as **ec2-user**:

```bash
cat ~/terraform-lab/outputs.tf
```

Outputs are Terraform's way of exposing values after `apply`. For example, `node_ips` gives you the public IP of each instance. This is how we feed IPs into Ansible (covered in Section 7).

### Step 2.6: Initialize Terraform

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform init
```

Expected output (yours will differ):

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

`terraform init` downloads the AWS provider plugin. It does not create or modify any infrastructure. This is always safe to run.

### Step 2.7: Run Terraform Plan (Read-Only)

On **pg-ops**, as **ec2-user**:

```bash
terraform plan
```

Expected output (yours will differ):

```
aws_key_pair.lab: Refreshing state...
aws_security_group.lab: Refreshing state...
aws_instance.node["primary"]: Refreshing state...
aws_instance.node["replica"]: Refreshing state...
aws_instance.node["container"]: Refreshing state...
aws_instance.node["ops"]: Refreshing state...

Plan: 4 to add, 0 to change, 0 to destroy.
```

The plan output tells you exactly what Terraform wants to do. Because we have a fresh state file (no imported resources), Terraform thinks it needs to create everything from scratch. That is expected - we will fix this with `terraform import` in the next section.

Reading the plan line by line:

- `Refreshing state...` - Terraform checks what exists in AWS against what is in the state file
- `Plan: 4 to add` - Terraform wants to create 4 new instances (because it does not know about the existing ones yet)
- `0 to change` - No modifications to existing resources
- `0 to destroy` - Nothing will be deleted

**Never run `terraform apply` on a plan that shows unexpected destroys.** Always review the plan first.

---

## Section 3: Terraform Import - Bring Existing Resources Under Management

In the real world, you rarely build infrastructure from scratch. You inherit existing servers, and you need to bring them under Terraform management. This is exactly what `terraform import` does.

### Step 3.1: Get the Instance IDs

You need the AWS instance ID for each running server. These are in the project's config.sh file. The instance IDs for this lab are:

- `i-09ff260a00a39c041` (one of the lab instances)

On **pg-ops**, as **ec2-user**:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=voleon-lab-pg-primary" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text \
  --region us-east-1
```

Expected output (yours will differ):

```
i-09ff260a00a39c041
```

This command queries AWS for the instance tagged as `voleon-lab-pg-primary` and returns just the instance ID.

### Step 3.2: Import the Primary Instance

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform import 'aws_instance.node["primary"]' i-09ff260a00a39c041
```

Replace `i-09ff260a00a39c041` with the actual instance ID from Step 3.1.

Expected output (yours will differ):

```
aws_instance.node["primary"]: Importing from ID "i-09ff260a00a39c041"...
aws_instance.node["primary"]: Import prepared!
  Prepared aws_instance for import
aws_instance.node["primary"]: Refreshing state... [id=i-09ff260a00a39c041]

Import successful!

The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

What happened:
- Terraform read the real AWS instance details (AMI, instance type, security groups, tags, etc.)
- It stored all those details in the state file
- It mapped those details to `aws_instance.node["primary"]` in your code

### Step 3.3: Verify the Import

On **pg-ops**, as **ec2-user**:

```bash
terraform state list
```

Expected output (yours will differ):

```
aws_instance.node["primary"]
```

This shows all resources Terraform now knows about. Right now it is just the one instance we imported.

### Step 3.4: Inspect the Imported Resource

On **pg-ops**, as **ec2-user**:

```bash
terraform state show 'aws_instance.node["primary"]'
```

Expected output (yours will differ):

```
# aws_instance.node["primary"]:
resource "aws_instance" "node" {
    ami                          = "ami-0dd5887d49587d8e9"
    arn                          = "arn:aws:ec2:us-east-1:339276916173:instance/i-09ff260a00a39c041"
    associate_public_ip_address  = true
    availability_zone            = "us-east-1a"
    instance_state               = "running"
    instance_type                = "t3.medium"
    key_name                     = "voleon-lab"
    private_ip                   = "172.31.19.86"
    public_ip                    = "100.26.54.122"
    vpc_security_group_ids       = ["sg-029a684edd2cec982"]
    ...
}
```

This is the full real-world state of the instance. Notice it includes the private IP, public IP, security group - everything. This is the source of truth Terraform uses to detect drift.

### Step 3.5: Run Plan After Import

On **pg-ops**, as **ec2-user**:

```bash
terraform plan
```

Now the plan should show fewer resources to add (3 instead of 4) because Terraform knows the primary instance already exists. It may also show some differences between your code and the real instance - these are things your code defines differently from what is actually running.

### Why Import Matters

When you join a new company (like Voleon), the infrastructure already exists. You cannot recreate it from scratch. The workflow is:

1. Write Terraform code that describes the existing infrastructure
2. Use `terraform import` to link the code to real resources
3. Run `terraform plan` to see if there are differences
4. Adjust the code until `plan` shows no changes
5. Now you can safely manage the infrastructure with Terraform going forward

---

## Section 4: Terraform Modules - Reusable PostgreSQL Server

Modules let you define a "template" for a PostgreSQL server and reuse it. Instead of copying the same `aws_instance` block for every server, you define it once in a module and call it with different parameters.

### Step 4.1: Create the Module Directory

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/terraform-lab/modules/pg-server
```

### Step 4.2: Create the Module - main.tf

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/modules/pg-server/main.tf
```

Press `i` to enter insert mode and type:

```hcl
resource "aws_instance" "pg" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname ${var.hostname}
    echo "${var.hostname}" > /etc/hostname
  EOF

  tags = {
    Name = "${var.lab_name}-${var.hostname}"
    Lab  = var.lab_name
    Role = var.role
  }
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

This is the same instance definition from our main.tf, but now it uses module-level variables instead of hardcoded values. The module is a self-contained blueprint.

### Step 4.3: Create the Module - variables.tf

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/modules/pg-server/variables.tf
```

Press `i` to enter insert mode and type:

```hcl
variable "ami_id" {
  type        = string
  description = "AMI ID for the PostgreSQL server"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"
}

variable "key_name" {
  type        = string
  description = "AWS key pair name for SSH access"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID to attach"
}

variable "hostname" {
  type        = string
  description = "Hostname for the server (e.g., pg-primary)"
}

variable "lab_name" {
  type        = string
  description = "Lab name for tagging"
}

variable "role" {
  type        = string
  description = "Server role (primary, replica, container, ops)"
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root EBS volume size in GB"
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 4.4: Create the Module - outputs.tf

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/modules/pg-server/outputs.tf
```

Press `i` to enter insert mode and type:

```hcl
output "instance_id" {
  value       = aws_instance.pg.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = aws_instance.pg.public_ip
  description = "Public IP address"
}

output "private_ip" {
  value       = aws_instance.pg.private_ip
  description = "Private IP address"
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 4.5: Call the Module from Root main.tf

Now we can use the module to create a new server. Let's add a module call to the root main.tf. This is for demonstration - we will only run `plan`, not `apply`.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/main.tf
```

Press `G` to go to the end of the file, then press `o` to open a new line and enter insert mode. Add:

```hcl

# ---------------------------------------------------------------------------
# Example: Using the pg-server module to define a new analytics server
# ---------------------------------------------------------------------------
module "pg_analytics" {
  source = "./modules/pg-server"

  ami_id            = var.ami_id
  instance_type     = "t3.large"
  key_name          = aws_key_pair.lab.key_name
  security_group_id = aws_security_group.lab.id
  hostname          = "pg-analytics"
  lab_name          = var.lab_name
  role              = "analytics"
  root_volume_size  = 50
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 4.6: Initialize and Plan with the Module

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform init
```

You need to run `init` again because we added a new module. Terraform needs to register it.

Expected output (yours will differ):

```
Initializing modules...
- pg_analytics in modules/pg-server

Initializing provider plugins...

Terraform has been successfully initialized!
```

Now run the plan:

```bash
terraform plan
```

Expected output (yours will differ):

```
  # module.pg_analytics.aws_instance.pg will be created
  + resource "aws_instance" "pg" {
      + ami                          = "ami-0dd5887d49587d8e9"
      + instance_type                = "t3.large"
      + key_name                     = "voleon-lab"
      ...
      + tags = {
          + "Lab"  = "voleon-lab"
          + "Name" = "voleon-lab-pg-analytics"
          + "Role" = "analytics"
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

The `+` prefix means "this resource will be created." Terraform shows you every attribute of the new instance before creating it. This is your chance to review before approving.

**Do not run `terraform apply` here.** We are just demonstrating the module concept. In a real workflow, you would review the plan with your team, then apply.

---

## Section 5: Terraform State Management

State management is one of the most interview-relevant Terraform topics. Let's explore the commands you need to know.

### Step 5.1: List All Managed Resources

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform state list
```

Expected output (yours will differ):

```
aws_instance.node["primary"]
aws_key_pair.lab
aws_security_group.lab
```

This shows everything Terraform currently manages. If a resource is not in this list, Terraform does not know about it and will not touch it.

### Step 5.2: Show Resource Details

On **pg-ops**, as **ec2-user**:

```bash
terraform state show 'aws_instance.node["primary"]'
```

This prints every attribute of the resource as Terraform sees it. This is useful for debugging ("what security group is attached?", "what AMI is this running?").

### Step 5.3: Move a Resource (Rename Without Destroying)

Sometimes you need to rename a resource in your code. Without `state mv`, Terraform would destroy the old one and create a new one. With `state mv`, you just update the name in the state file.

On **pg-ops**, as **ec2-user**:

```bash
terraform state mv 'aws_instance.node["primary"]' 'aws_instance.node["pg-primary"]'
```

Expected output (yours will differ):

```
Move "aws_instance.node[\"primary\"]" to "aws_instance.node[\"pg-primary\"]"
Successfully moved 1 object(s).
```

This renamed the resource in state only. The EC2 instance was not touched. Now you would update your code to match the new name.

Let's move it back:

```bash
terraform state mv 'aws_instance.node["pg-primary"]' 'aws_instance.node["primary"]'
```

### Step 5.4: Replace a Resource (Taint/Untaint)

In older Terraform versions, `terraform taint` marked a resource for recreation. In modern Terraform (1.5+), use `terraform apply -replace`:

On **pg-ops**, as **ec2-user**:

```bash
terraform plan -replace='aws_instance.node["primary"]'
```

Expected output (yours will differ):

```
  # aws_instance.node["primary"] will be replaced, as requested
-/+ resource "aws_instance" "node" {
      ~ ami                          = "ami-0dd5887d49587d8e9" -> "ami-0dd5887d49587d8e9"
      ~ id                           = "i-09ff260a00a39c041" -> (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

The `-/+` means "destroy and recreate." The `~` means "this attribute will change." **Do not apply this** - it would destroy your primary database server. This is just to show you how the plan output looks.

### Step 5.5: Remote State with S3 Backend

In production, the state file should not live on your laptop or on pg-ops. It should be in S3 with DynamoDB locking. Here is what the configuration looks like (do not apply this - just read it):

```hcl
terraform {
  backend "s3" {
    bucket         = "voleon-terraform-state"
    key            = "database/pg-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

What each field does:

- `bucket` - The S3 bucket where the state file is stored
- `key` - The path inside the bucket (allows multiple state files in one bucket)
- `region` - Where the S3 bucket lives
- `dynamodb_table` - A DynamoDB table that prevents two people from running `terraform apply` at the same time (locking)
- `encrypt` - Encrypts the state file at rest (it contains sensitive data like instance IDs, IPs, security group rules)

Why this matters for databases:

- Two DBAs running `terraform apply` at the same time could create duplicate instances or corrupt state
- The state file contains your database server IPs and configuration - it should be encrypted
- S3 has versioning, so you can recover a previous state if something goes wrong

---

## Section 6: Terraform Plan Review Exercise

This is the most practical Terraform skill for a DBA interview. You will be shown a plan output and asked to explain what it does.

### Step 6.1: Generate a Plan That Adds an EBS Volume

Let's add an EBS volume to the configuration and review the plan output.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/main.tf
```

Press `G` to go to the end of the file, then press `o` to open a new line and enter insert mode. Add:

```hcl

# ---------------------------------------------------------------------------
# Additional EBS volume for WAL archive storage
# ---------------------------------------------------------------------------
resource "aws_ebs_volume" "wal_archive" {
  availability_zone = "us-east-1a"
  size              = 100
  type              = "gp3"
  iops              = 3000
  throughput        = 125

  tags = {
    Name = "${var.lab_name}-wal-archive"
    Lab  = var.lab_name
  }
}

resource "aws_volume_attachment" "wal_archive_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.wal_archive.id
  instance_id = aws_instance.node["primary"].id
}
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 6.2: Review the Plan Output

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform plan
```

Expected output (yours will differ):

```
  # aws_ebs_volume.wal_archive will be created
  + resource "aws_ebs_volume" "wal_archive" {
      + arn               = (known after apply)
      + availability_zone = "us-east-1a"
      + encrypted         = (known after apply)
      + iops              = 3000
      + size              = 100
      + throughput        = 125
      + type              = "gp3"
      + tags              = {
          + "Lab"  = "voleon-lab"
          + "Name" = "voleon-lab-wal-archive"
        }
    }

  # aws_volume_attachment.wal_archive_attach will be created
  + resource "aws_volume_attachment" "wal_archive_attach" {
      + device_name = "/dev/xvdf"
      + instance_id = "i-09ff260a00a39c041"
      + volume_id   = (known after apply)
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

### Step 6.3: How to Read a Terraform Plan

Here is what each symbol means:

| Symbol | Meaning | Risk Level |
|---|---|---|
| `+` | Resource will be **created** | Low - new thing, nothing existing is touched |
| `-` | Resource will be **destroyed** | HIGH - something will be deleted |
| `~` | Resource will be **modified in-place** | Medium - depends on what changes |
| `-/+` | Resource will be **destroyed and recreated** | HIGH - downtime for that resource |
| `<=` | Resource will be **read** (data source) | None - read-only |

**What to look for before approving a plan:**

1. **Unintended destroys** - If the plan shows `-` for an instance or volume you did not expect, STOP. Something is wrong.
2. **Security group changes** - Adding or removing ingress rules can break connectivity or expose ports.
3. **`(known after apply)`** - This is normal for attributes like IPs that AWS assigns at creation time.
4. **Force replacement (`-/+`)** - Changing certain attributes (like AMI or instance type) forces destruction and recreation. This means downtime.

### Step 6.4: Save and Apply a Plan File

In production, you save the plan to a file and apply that exact plan. This prevents surprise changes between `plan` and `apply`.

On **pg-ops**, as **ec2-user**:

```bash
terraform plan -out=plan.tfplan
```

This saves the plan to `plan.tfplan`. The file is binary - you cannot read it with `cat`. To review it again:

```bash
terraform show plan.tfplan
```

To apply the saved plan (do not run this in the lab - just understand the workflow):

```bash
# DO NOT RUN THIS - just showing the pattern
# terraform apply plan.tfplan
```

The key point: `terraform apply plan.tfplan` applies exactly what was in the plan, nothing more. If the infrastructure changed between `plan` and `apply`, Terraform will detect the mismatch and refuse.

---

## Section 7: Terraform + Ansible Integration

This is the complete Infrastructure as Code (IaC) lifecycle. Terraform creates the servers, Ansible configures them.

### Step 7.1: The Workflow

```
 terraform apply          terraform output -json        ansible-playbook
      |                          |                            |
      v                          v                            v
 Creates EC2 instances --> Outputs IPs as JSON --> Ansible uses IPs to
 EBS volumes                                      install PostgreSQL,
 Security groups                                   configure pg_hba.conf,
 DNS records                                       set up replication
```

### Step 7.2: Extract IPs from Terraform

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
terraform output -json node_ips
```

Expected output (yours will differ):

```json
{
  "primary": "100.26.54.122",
  "replica": "54.144.241.128",
  "container": "34.228.73.232",
  "ops": "34.228.32.17"
}
```

### Step 7.3: Feed Terraform Output into Ansible Inventory

You can write a script that reads Terraform output and generates an Ansible inventory. Here is the pattern:

On **pg-ops**, as **ec2-user**:

```bash
vi ~/terraform-lab/generate-inventory.sh
```

Press `i` to enter insert mode and type:

```bash
#!/bin/bash
# Generate Ansible inventory from Terraform output
cd ~/terraform-lab

PUBLIC_IPS=$(terraform output -json node_ips)
PRIVATE_IPS=$(terraform output -json node_private_ips)

PRIMARY_PRIVATE=$(echo "$PRIVATE_IPS" | python3 -c "import sys,json; print(json.load(sys.stdin)['primary'])")
REPLICA_PRIVATE=$(echo "$PRIVATE_IPS" | python3 -c "import sys,json; print(json.load(sys.stdin)['replica'])")
CONTAINER_PUBLIC=$(echo "$PUBLIC_IPS" | python3 -c "import sys,json; print(json.load(sys.stdin)['container'])")
OPS_PRIVATE=$(echo "$PRIVATE_IPS" | python3 -c "import sys,json; print(json.load(sys.stdin)['ops'])")

cat > ~/ansible/inventory/hosts-from-tf.yml <<INVENTORY
all:
  vars:
    ansible_user: ec2-user
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    pg_version: "17"
    pg_bin: "/usr/pgsql-17/bin"
    pg_data: "/var/lib/pgsql/17/data"
    pg_db: "quantdb"
  children:
    pg_primary:
      hosts:
        pg-primary:
          ansible_host: ${PRIMARY_PRIVATE}
          pg_role: primary
    pg_replica:
      hosts:
        pg-replica:
          ansible_host: ${REPLICA_PRIVATE}
          pg_role: replica
    pg_container:
      hosts:
        pg-container:
          ansible_host: ${CONTAINER_PUBLIC}
    pg_ops:
      hosts:
        pg-ops:
          ansible_host: ${OPS_PRIVATE}
    pg_servers:
      children:
        pg_primary:
        pg_replica:
    all_db:
      children:
        pg_servers:
        pg_container:
INVENTORY

echo "Inventory generated: ~/ansible/inventory/hosts-from-tf.yml"
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Make it executable:

```bash
chmod +x ~/terraform-lab/generate-inventory.sh
```

### Step 7.4: The Complete IaC Lifecycle

Here is the end-to-end workflow a DBA would follow at Voleon:

1. **Day 0 - Build Infrastructure**
   - Write Terraform code defining EC2 instances, EBS volumes, security groups
   - `terraform plan` - review what will be created
   - `terraform apply` - create the infrastructure
   - Run the inventory generator script to create Ansible inventory

2. **Day 0 - Configure Servers**
   - `ansible-playbook install-postgresql.yml` - install and configure PG
   - `ansible-playbook setup-replication.yml` - configure streaming replication
   - `ansible-playbook setup-monitoring.yml` - install Prometheus exporters

3. **Day N - Operational Changes**
   - Need more storage? - Terraform adds an EBS volume, then Ansible mounts and formats it
   - Need to change a PG setting? - Ansible runs the `update-pg-param.yml` playbook
   - Need a new server? - Terraform creates the instance, Ansible configures it

4. **Disaster Recovery**
   - The Terraform code can recreate all infrastructure in a new region
   - The Ansible playbooks can reconfigure everything from scratch
   - Combined, they give you a fully automated recovery path

---

## Summary - What to Tell the Interviewer

When Lukasz asks about Terraform:

- **State management** - "Terraform tracks real AWS resources in a state file. In production, we store it in S3 with DynamoDB locking so two people cannot modify infrastructure at the same time."
- **Plan before apply** - "I always run `terraform plan` first, save it to a file, and review it for unintended destroys or security group changes before applying."
- **Import vs. greenfield** - "When inheriting existing infrastructure, I use `terraform import` to bring resources under management without recreating them."
- **Modules** - "I use modules to create reusable templates. A pg-server module encapsulates instance creation, tagging, and volume configuration."
- **Terraform + Ansible boundary** - "Terraform creates the infrastructure (EC2, EBS, SG). Ansible configures what runs on it (PostgreSQL, pg_hba.conf, replication). Terraform outputs feed into Ansible inventory."

---

## Cleanup

If you added the EBS volume and module blocks to main.tf during the exercises, you can remove them to leave the code clean.

On **pg-ops**, as **ec2-user**:

```bash
cd ~/terraform-lab
```

```bash
vi main.tf
```

Delete the `module "pg_analytics"`, `aws_ebs_volume.wal_archive`, and `aws_volume_attachment.wal_archive_attach` blocks if you do not want them in the code.

The Terraform state and working directory on pg-ops are safe to leave in place - they do not affect the running infrastructure unless you run `terraform apply`.
