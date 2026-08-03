# BUILD 04: Ansible + Terraform - Provision Then Configure

**Module 06: Ansible for Database Configuration**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to combine Terraform (provisions infrastructure) with Ansible (configures software) to create a fully automated pipeline from bare cloud account to running PostgreSQL HA cluster.

---

## The Handoff: Terraform Provisions, Ansible Configures

Each tool excels at a different layer:

| Layer | Tool | What It Does |
|-------|------|-------------|
| Infrastructure | Terraform | Creates EC2 instances, VPCs, security groups, DNS |
| Configuration | Ansible | Installs PostgreSQL, deploys configs, manages users |

**DBA Analogy:** Think of building a database server:
- Terraform = the datacenter team that racks the server, plugs in network cables, assigns an IP
- Ansible = the DBA team that installs PostgreSQL, tunes the config, creates databases

They are complementary. Terraform creates the servers. Ansible configures them. The handoff point is the server IP addresses.

---

## Step 1: Project Structure

```bash
mkdir -p ~/dba-labs/terraform-ansible
cd ~/dba-labs/terraform-ansible
mkdir -p terraform ansible/{templates,group_vars,roles}
```

The project has two directories:
- `terraform/` - infrastructure code
- `ansible/` - configuration code

---

## Step 2: Terraform - Provision EC2 Instances

This Terraform configuration creates two EC2 instances for a primary + standby PostgreSQL pair.

```bash
vi terraform/main.tf
```

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
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "ami_id" {
  description = "CentOS Stream 9 AMI"
  type        = string
}

# Security group for PostgreSQL
resource "aws_security_group" "pg_sg" {
  name        = "postgresql-ha-sg"
  description = "Security group for PostgreSQL HA cluster"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Patroni REST API
  ingress {
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # etcd
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # PgBouncer
  ingress {
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal traffic
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  tags = {
    Name    = "postgresql-ha-sg"
    Project = "dba-automation"
  }
}

# Primary instance
resource "aws_instance" "pg_primary" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.pg_sg.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name    = "pg-primary"
    Role    = "primary"
    Project = "dba-automation"
  }
}

# Standby instance
resource "aws_instance" "pg_standby" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.pg_sg.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name    = "pg-standby"
    Role    = "standby"
    Project = "dba-automation"
  }
}
```

---

## Step 3: Terraform Outputs

Outputs are how Terraform passes information to Ansible. The most critical output is the IP addresses of the created instances.

```bash
vi terraform/outputs.tf
```

```hcl
# Outputs: these values are passed to Ansible

output "primary_public_ip" {
  value       = aws_instance.pg_primary.public_ip
  description = "Public IP of the primary PostgreSQL server"
}

output "primary_private_ip" {
  value       = aws_instance.pg_primary.private_ip
  description = "Private IP of the primary PostgreSQL server"
}

output "standby_public_ip" {
  value       = aws_instance.pg_standby.public_ip
  description = "Public IP of the standby PostgreSQL server"
}

output "standby_private_ip" {
  value       = aws_instance.pg_standby.private_ip
  description = "Private IP of the standby PostgreSQL server"
}

output "security_group_id" {
  value       = aws_security_group.pg_sg.id
  description = "Security group ID for the cluster"
}
```

After `terraform apply`, you can retrieve these values:

```bash
cd ~/dba-labs/terraform-ansible/terraform
terraform output -json
```

Expected output (yours will differ):
```json
{
  "primary_public_ip": {
    "value": "54.210.123.45"
  },
  "primary_private_ip": {
    "value": "10.0.1.20"
  },
  "standby_public_ip": {
    "value": "54.210.123.46"
  },
  "standby_private_ip": {
    "value": "10.0.1.21"
  }
}
```

---

## Step 4: Generate Ansible Inventory from Terraform Output

The bridge between Terraform and Ansible is the inventory file. You can generate it automatically from Terraform outputs.

```bash
vi terraform/generate-inventory.sh
```

```bash
#!/bin/bash
# Generate Ansible inventory from Terraform outputs

set -euo pipefail

cd "$(dirname "$0")"

PRIMARY_IP=$(terraform output -raw primary_public_ip)
PRIMARY_PRIVATE=$(terraform output -raw primary_private_ip)
STANDBY_IP=$(terraform output -raw standby_public_ip)
STANDBY_PRIVATE=$(terraform output -raw standby_private_ip)

cat > ../ansible/inventory.ini <<EOF
# Auto-generated from Terraform outputs
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[primary]
pg-primary ansible_host=${PRIMARY_IP} private_ip=${PRIMARY_PRIVATE}

[standbys]
pg-standby ansible_host=${STANDBY_IP} private_ip=${STANDBY_PRIVATE}

[postgresql:children]
primary
standbys

[all:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/your-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

echo "Inventory generated: ../ansible/inventory.ini"
echo "Primary: ${PRIMARY_IP} (${PRIMARY_PRIVATE})"
echo "Standby: ${STANDBY_IP} (${STANDBY_PRIVATE})"
```

```bash
chmod +x terraform/generate-inventory.sh
```

---

## Step 5: AWS Dynamic Inventory Plugin

For larger clusters, manually generating inventory is impractical. Ansible's AWS EC2 dynamic inventory plugin discovers servers automatically based on tags.

```bash
vi ansible/aws_ec2.yml
```

```yaml
# Ansible dynamic inventory plugin for AWS EC2
plugin: amazon.aws.aws_ec2

# AWS region to scan
regions:
  - us-east-1

# Filter instances by tags
filters:
  tag:Project: dba-automation
  instance-state-name: running

# Group instances by their tags
keyed_groups:
  - key: tags.Role
    prefix: role
    separator: "_"
  - key: tags.Name
    prefix: name
    separator: "_"

# Use public IP for SSH connection
hostnames:
  - public-ip-address

# Compose additional variables from instance metadata
compose:
  ansible_host: public_ip_address
  private_ip: private_ip_address
  instance_type: instance_type
  ansible_user: "'ec2-user'"
```

Install the AWS collection:

```bash
ansible-galaxy collection install amazon.aws
pip3 install boto3 botocore
```

Test the dynamic inventory:

```bash
ansible-inventory -i ansible/aws_ec2.yml --graph
```

Expected output (yours will differ):
```
@all:
  |--@role_primary:
  |  |--54.210.123.45
  |--@role_standby:
  |  |--54.210.123.46
  |--@ungrouped:
```

Now you can target servers by their tag-based groups:

```bash
ansible role_primary -i ansible/aws_ec2.yml -m ping
ansible role_standby -i ansible/aws_ec2.yml -m ping
```

---

## Step 6: The Complete Workflow

Here is the full end-to-end pipeline:

### Phase 1: Provision with Terraform

```bash
cd ~/dba-labs/terraform-ansible/terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="key_name=your-key" -var="ami_id=ami-xxxx"

# Apply (create the servers)
terraform apply -var="key_name=your-key" -var="ami_id=ami-xxxx" -auto-approve

# Generate Ansible inventory from outputs
./generate-inventory.sh
```

### Phase 2: Configure with Ansible

```bash
cd ~/dba-labs/terraform-ansible/ansible

# Verify connectivity
ansible all -i inventory.ini -m ping

# Install and configure PostgreSQL
ansible-playbook -i inventory.ini playbook-install-pg.yml

# Configure as primary + standby
ansible-playbook -i inventory.ini playbook-configure-replication.yml

# Verify the setup
ansible-playbook -i inventory.ini playbook-health-check.yml
```

### Phase 3: Verify

```bash
# SSH to primary and check replication
ssh -i ~/.ssh/your-key.pem ec2-user@$(terraform -chdir=terraform output -raw primary_public_ip)
```

---

## Step 7: Tags for Organization

Tags in both Terraform and Ansible help organize and filter resources:

### Terraform Tags

```hcl
tags = {
  Name        = "pg-primary"
  Role        = "primary"
  Project     = "dba-automation"
  Environment = "production"
  ManagedBy   = "terraform"
}
```

### Ansible Tags on Tasks

```yaml
tasks:
  - name: Install PostgreSQL
    dnf:
      name: postgresql16-server
      state: present
    tags: [install]

  - name: Configure postgresql.conf
    template:
      src: postgresql.conf.j2
      dest: "{{ pg_data_dir }}/postgresql.conf"
    tags: [configure]

  - name: Create databases
    postgresql_db:
      name: myapp
    tags: [databases]
```

Run specific tagged tasks:

```bash
# Only run configuration tasks
ansible-playbook -i inventory.ini playbook.yml --tags configure

# Skip installation tasks
ansible-playbook -i inventory.ini playbook.yml --skip-tags install
```

---

## Step 8: CI/CD Integration - GitHub Actions

Automate the entire Terraform + Ansible workflow in a GitHub Actions pipeline:

```bash
vi .github/workflows/deploy-ha-cluster.yml
```

```yaml
name: Deploy HA PostgreSQL Cluster

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'
      - 'ansible/**'
  workflow_dispatch:           # Manual trigger

env:
  AWS_REGION: us-east-1
  TF_VAR_key_name: ${{ secrets.AWS_KEY_NAME }}
  TF_VAR_ami_id: ${{ secrets.CENTOS_AMI_ID }}

jobs:
  terraform:
    name: Provision Infrastructure
    runs-on: ubuntu-latest
    outputs:
      primary_ip: ${{ steps.tf-output.outputs.primary_ip }}
      standby_ip: ${{ steps.tf-output.outputs.standby_ip }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Plan
        working-directory: terraform
        run: terraform plan -out=tfplan

      - name: Terraform Apply
        working-directory: terraform
        run: terraform apply -auto-approve tfplan

      - name: Get Terraform outputs
        id: tf-output
        working-directory: terraform
        run: |
          echo "primary_ip=$(terraform output -raw primary_public_ip)" >> "$GITHUB_OUTPUT"
          echo "standby_ip=$(terraform output -raw standby_public_ip)" >> "$GITHUB_OUTPUT"

  ansible:
    name: Configure PostgreSQL
    needs: terraform
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible
        run: pip3 install ansible boto3

      - name: Install Ansible collections
        run: ansible-galaxy collection install community.postgresql

      - name: Write SSH key
        run: |
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > /tmp/deploy-key.pem
          chmod 600 /tmp/deploy-key.pem

      - name: Generate inventory
        run: |
          cat > ansible/inventory.ini <<EOF
          [primary]
          pg-primary ansible_host=${{ needs.terraform.outputs.primary_ip }}

          [standbys]
          pg-standby ansible_host=${{ needs.terraform.outputs.standby_ip }}

          [postgresql:children]
          primary
          standbys

          [all:vars]
          ansible_user=ec2-user
          ansible_ssh_private_key_file=/tmp/deploy-key.pem
          ansible_ssh_common_args='-o StrictHostKeyChecking=no'
          EOF

      - name: Wait for SSH
        run: |
          for ip in ${{ needs.terraform.outputs.primary_ip }} ${{ needs.terraform.outputs.standby_ip }}; do
            until ssh -o StrictHostKeyChecking=no -i /tmp/deploy-key.pem ec2-user@$ip "echo ready" 2>/dev/null; do
              echo "Waiting for SSH on $ip..."
              sleep 10
            done
          done

      - name: Run Ansible playbook
        working-directory: ansible
        run: |
          ansible-playbook -i inventory.ini playbook-install-pg.yml
          ansible-playbook -i inventory.ini playbook-configure-replication.yml

      - name: Verify deployment
        working-directory: ansible
        run: ansible-playbook -i inventory.ini playbook-health-check.yml
```

---

## Step 9: Practical - Provision and Configure

This is the hands-on exercise. If you have an AWS account, follow these steps:

### Prerequisites
- AWS CLI configured (`aws configure`)
- An SSH key pair created in AWS
- A CentOS Stream 9 AMI ID for your region

### Run the Pipeline

```bash
cd ~/dba-labs/terraform-ansible

# Phase 1: Provision
cd terraform
terraform init
terraform plan -var="key_name=YOUR_KEY" -var="ami_id=YOUR_AMI"
terraform apply -var="key_name=YOUR_KEY" -var="ami_id=YOUR_AMI"
./generate-inventory.sh

# Phase 2: Configure
cd ../ansible
ansible all -i inventory.ini -m ping
ansible-playbook -i inventory.ini playbook-install-pg.yml

# Phase 3: Verify
ansible-playbook -i inventory.ini playbook-health-check.yml

# Cleanup (when done)
cd ../terraform
terraform destroy -var="key_name=YOUR_KEY" -var="ami_id=YOUR_AMI"
```

---

## Step 10: Terraform State and Ansible - Best Practices

### Do Not Mix Concerns

- Terraform manages infrastructure lifecycle (create, update, destroy)
- Ansible manages software configuration (install, configure, restart)
- Do not use Terraform `provisioner` blocks for configuration - use Ansible instead
- Do not use Ansible to create cloud resources - use Terraform instead

### State Management

| Concern | Tool | Storage |
|---------|------|---------|
| Infrastructure state | Terraform | S3 backend (remote state) |
| Configuration state | Ansible | Idempotent (no state file needed) |
| Secrets | Ansible Vault | Encrypted in Git |
| Cloud secrets | AWS Secrets Manager | Referenced by both tools |

### The Golden Rule

**Terraform answers: "What servers exist?"**
**Ansible answers: "What software runs on them?"**

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Terraform + Ansible handoff | Terraform provisions, Ansible configures - each excels at its layer |
| Terraform outputs | Pass IP addresses from Terraform to Ansible |
| Generated inventory | Script converts Terraform outputs into Ansible inventory format |
| Dynamic inventory | AWS EC2 plugin discovers servers by tags - no manual inventory needed |
| Tags | Organize resources for both Terraform filtering and Ansible targeting |
| Complete workflow | terraform apply -> generate inventory -> ansible-playbook |
| CI/CD integration | GitHub Actions runs Terraform then Ansible in sequence |
| Job outputs | GitHub Actions passes data between jobs via outputs |
| Best practices | Do not mix concerns - Terraform for infra, Ansible for config |

---

**Next:** Module 06 exercises will test your ability to write complete Ansible playbooks for PostgreSQL management.
