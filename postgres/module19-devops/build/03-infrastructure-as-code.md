# Module 19 - BUILD 03: Infrastructure as Code for PostgreSQL

## Overview

Infrastructure as Code (IaC) means managing servers, databases, and configurations through version-controlled files instead of manual clicks or SSH commands. This guide covers Terraform for provisioning PostgreSQL (RDS), Ansible for server configuration, and secrets management.

---

## Prerequisites

- CentOS Stream 9 server
- AWS account (for Terraform RDS examples)
- Basic understanding of YAML and HCL syntax
- SSH access to at least one PostgreSQL server (for Ansible)

---

## Part 1: Terraform for PostgreSQL (RDS Example)

Terraform is a tool by HashiCorp that lets you define cloud infrastructure in `.tf` files. You write what you want, and Terraform figures out how to create it.

### 1.1 Install Terraform

Add the HashiCorp repository. The `yum-config-manager` command adds a new package source.

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Install Terraform.

```bash
sudo dnf install -y terraform
```

Verify the install.

```bash
terraform version
```

Expected output (yours will differ):
```
Terraform v1.7.4
on linux_amd64
```

### 1.2 Create a Terraform Project

```bash
mkdir -p /opt/pgsql/terraform-rds
```

### 1.3 Define the AWS Provider

The provider block tells Terraform which cloud to talk to and how to authenticate.

```bash
vi /opt/pgsql/terraform-rds/provider.tf
```

```hcl
# provider.tf - Configure the AWS provider
terraform {
  required_version = ">= 1.5"

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
```

Line-by-line:
- `required_version` - Minimum Terraform version
- `required_providers` - Which cloud providers to download
- `~> 5.0` - Allow any 5.x version (but not 6.0)
- `region = var.aws_region` - Read the region from a variable (defined next)

### 1.4 Define Variables

Variables let you reuse the same Terraform code across environments.

```bash
vi /opt/pgsql/terraform-rds/variables.tf
```

```hcl
# variables.tf - Input variables for the RDS module

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the database"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}
```

The `sensitive = true` flag on `db_password` tells Terraform to never print this value in logs or output.

### 1.5 Define the RDS Instance

This is the main resource - an AWS RDS PostgreSQL instance.

```bash
vi /opt/pgsql/terraform-rds/main.tf
```

```hcl
# main.tf - RDS PostgreSQL instance and supporting resources

# Security group to control network access to the database
resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"

  # Allow PostgreSQL traffic from within the VPC
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "PostgreSQL access from VPC"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.environment}-rds-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Parameter group to customize PostgreSQL settings
resource "aws_db_parameter_group" "pg_params" {
  name   = "${var.environment}-pg16-params"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name        = "${var.environment}-pg16-params"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# The RDS PostgreSQL instance itself
resource "aws_db_instance" "postgresql" {
  identifier = "${var.environment}-postgresql"

  # Engine configuration
  engine         = "postgres"
  engine_version = "16.2"

  # Instance sizing
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network and security
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.pg_params.name

  # Backup configuration
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Storage encryption
  storage_encrypted = true

  # Deletion protection (remove for dev/test)
  deletion_protection = var.environment == "prod" ? true : false

  # Skip final snapshot in non-prod
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.environment}-final-snapshot" : null

  # Performance Insights
  performance_insights_enabled = true

  tags = {
    Name        = "${var.environment}-postgresql"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

Key settings explained:
- `storage_type = "gp3"` - General Purpose SSD v3, best price/performance for most workloads
- `backup_retention_period = 7` - Keep automated backups for 7 days
- `storage_encrypted = true` - Encrypt data at rest using AWS KMS
- `deletion_protection` - Uses a conditional: true in prod, false elsewhere
- `performance_insights_enabled` - Enables the Performance Insights dashboard

### 1.6 Define Outputs

Outputs display useful information after Terraform runs.

```bash
vi /opt/pgsql/terraform-rds/outputs.tf
```

```hcl
# outputs.tf - Values to display after apply

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.postgresql.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgresql.port
}

output "rds_db_name" {
  description = "Database name"
  value       = aws_db_instance.postgresql.db_name
}

output "connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${var.db_username}@${aws_db_instance.postgresql.endpoint}/${var.db_name}"
}
```

### 1.7 Create a terraform.tfvars File

This file provides values for your variables. Never commit this to Git if it contains secrets.

```bash
vi /opt/pgsql/terraform-rds/terraform.tfvars
```

```hcl
aws_region        = "us-east-1"
environment       = "dev"
db_name           = "appdb"
db_username       = "dbadmin"
db_instance_class = "db.t3.micro"
```

For the password, pass it via environment variable instead of putting it in a file.

```bash
export TF_VAR_db_password="YourSecurePasswordHere"
```

The `TF_VAR_` prefix tells Terraform to use this as the value for the `db_password` variable.

### 1.8 Create a .gitignore

Keep sensitive files out of version control.

```bash
vi /opt/pgsql/terraform-rds/.gitignore
```

```
# Terraform state files contain sensitive data
*.tfstate
*.tfstate.*

# Variable files may contain secrets
terraform.tfvars

# Terraform working directories
.terraform/
.terraform.lock.hcl

# Crash log
crash.log
```

### 1.9 Initialize and Plan

Initialize Terraform. This downloads the AWS provider plugin.

```bash
cd /opt/pgsql/terraform-rds
```

```bash
terraform init
```

Expected output (yours will differ):
```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.31.0...
- Installed hashicorp/aws v5.31.0 (signed by HashiCorp)
Terraform has been successfully initialized!
```

Run a plan to see what Terraform would create. The plan does not make any changes.

```bash
terraform plan
```

Expected output (yours will differ):
```
Terraform will perform the following actions:

  # aws_db_instance.postgresql will be created
  + resource "aws_db_instance" "postgresql" {
      + allocated_storage       = 20
      + engine                  = "postgres"
      + engine_version          = "16.2"
      + instance_class          = "db.t3.micro"
      ...
    }

  # aws_db_parameter_group.pg_params will be created
  ...

  # aws_security_group.rds_sg will be created
  ...

Plan: 3 to add, 0 to change, 0 to destroy.
```

To actually create the resources, you would run `terraform apply`. We skip that in this lab to avoid AWS charges.

---

## Part 2: Ansible for PostgreSQL Server Configuration

Ansible is a configuration management tool. You write "playbooks" that describe the desired state of your servers, and Ansible makes it happen.

### 2.1 Install Ansible

```bash
sudo dnf install -y ansible-core
```

Verify the install.

```bash
ansible --version
```

Expected output (yours will differ):
```
ansible [core 2.14.9]
  config file = /etc/ansible/ansible.cfg
  ...
  python version = 3.9.18
```

### 2.2 Create an Ansible Project

```bash
mkdir -p /opt/pgsql/ansible-pg/roles/postgresql/tasks
```

```bash
mkdir -p /opt/pgsql/ansible-pg/roles/postgresql/templates
```

```bash
mkdir -p /opt/pgsql/ansible-pg/roles/postgresql/handlers
```

```bash
mkdir -p /opt/pgsql/ansible-pg/inventory
```

### 2.3 Create the Inventory File

The inventory tells Ansible which servers to manage.

```bash
vi /opt/pgsql/ansible-pg/inventory/hosts.yml
```

```yaml
all:
  children:
    pg_primary:
      hosts:
        pg-primary:
          ansible_host: 10.0.1.10
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/pg-lab.pem
    pg_replicas:
      hosts:
        pg-replica-1:
          ansible_host: 10.0.1.11
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/pg-lab.pem
        pg-replica-2:
          ansible_host: 10.0.1.12
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/pg-lab.pem
  vars:
    pg_version: "16"
    pg_data_dir: "/opt/pgsql/data"
    pg_log_dir: "/opt/pgsql/log"
    pg_port: 5432
```

### 2.4 Create the postgresql.conf Template

Ansible uses Jinja2 templates. Variables inside `{{ }}` are replaced with actual values.

```bash
vi /opt/pgsql/ansible-pg/roles/postgresql/templates/postgresql.conf.j2
```

```ini
# postgresql.conf - Managed by Ansible
# DO NOT EDIT MANUALLY - changes will be overwritten

# Connection Settings
listen_addresses = '{{ pg_listen_addresses | default("*") }}'
port = {{ pg_port | default(5432) }}
max_connections = {{ pg_max_connections | default(200) }}

# Memory Settings
shared_buffers = '{{ pg_shared_buffers | default("256MB") }}'
effective_cache_size = '{{ pg_effective_cache_size | default("1GB") }}'
work_mem = '{{ pg_work_mem | default("4MB") }}'
maintenance_work_mem = '{{ pg_maintenance_work_mem | default("128MB") }}'

# WAL Settings
wal_level = '{{ pg_wal_level | default("replica") }}'
max_wal_senders = {{ pg_max_wal_senders | default(10) }}
max_replication_slots = {{ pg_max_replication_slots | default(10) }}
wal_keep_size = '{{ pg_wal_keep_size | default("1GB") }}'

# Checkpoint Settings
checkpoint_completion_target = {{ pg_checkpoint_completion_target | default(0.9) }}
min_wal_size = '{{ pg_min_wal_size | default("256MB") }}'
max_wal_size = '{{ pg_max_wal_size | default("1GB") }}'

# Logging
logging_collector = on
log_directory = '{{ pg_log_dir | default("/opt/pgsql/log") }}'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = {{ pg_log_min_duration | default(1000) }}
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_connections = on
log_disconnections = on
log_lock_waits = on
log_statement = 'ddl'

# Statistics
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all

# Data Directory
data_directory = '{{ pg_data_dir }}'
```

### 2.5 Create the pg_hba.conf Template

```bash
vi /opt/pgsql/ansible-pg/roles/postgresql/templates/pg_hba.conf.j2
```

```
# pg_hba.conf - Managed by Ansible
# DO NOT EDIT MANUALLY - changes will be overwritten

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256

# IPv4 remote connections
{% for entry in pg_hba_entries | default([]) %}
host    {{ entry.database }}    {{ entry.user }}    {{ entry.address }}    {{ entry.method | default('scram-sha-256') }}
{% endfor %}

# Replication connections
{% for host in groups['pg_replicas'] | default([]) %}
host    replication     replicator      {{ hostvars[host]['ansible_host'] }}/32    scram-sha-256
{% endfor %}
```

### 2.6 Create the Tasks

```bash
vi /opt/pgsql/ansible-pg/roles/postgresql/tasks/main.yml
```

```yaml
---
# roles/postgresql/tasks/main.yml - Configure PostgreSQL

- name: Ensure PostgreSQL data directory exists
  file:
    path: "{{ pg_data_dir }}"
    state: directory
    owner: postgres
    group: postgres
    mode: '0700'

- name: Ensure PostgreSQL log directory exists
  file:
    path: "{{ pg_log_dir }}"
    state: directory
    owner: postgres
    group: postgres
    mode: '0755'

- name: Deploy postgresql.conf
  template:
    src: postgresql.conf.j2
    dest: "{{ pg_data_dir }}/postgresql.conf"
    owner: postgres
    group: postgres
    mode: '0600'
    backup: yes
  notify: Reload PostgreSQL

- name: Deploy pg_hba.conf
  template:
    src: pg_hba.conf.j2
    dest: "{{ pg_data_dir }}/pg_hba.conf"
    owner: postgres
    group: postgres
    mode: '0600'
    backup: yes
  notify: Reload PostgreSQL

- name: Verify PostgreSQL configuration
  become: true
  become_user: postgres
  command: >
    /usr/pgsql-{{ pg_version }}/bin/pg_ctl
    -D {{ pg_data_dir }}
    -l /dev/null
    status
  register: pg_status
  changed_when: false
  failed_when: false

- name: Display PostgreSQL status
  debug:
    msg: "PostgreSQL is {{ 'running' if pg_status.rc == 0 else 'stopped' }}"
```

### 2.7 Create Handlers

Handlers run only when notified by a task that made a change.

```bash
vi /opt/pgsql/ansible-pg/roles/postgresql/handlers/main.yml
```

```yaml
---
# handlers/main.yml - PostgreSQL service handlers

- name: Reload PostgreSQL
  become: true
  become_user: postgres
  command: >
    /usr/pgsql-{{ pg_version }}/bin/pg_ctl
    -D {{ pg_data_dir }}
    reload
  listen: "Reload PostgreSQL"

- name: Restart PostgreSQL
  become: true
  become_user: postgres
  command: >
    /usr/pgsql-{{ pg_version }}/bin/pg_ctl
    -D {{ pg_data_dir }}
    -l {{ pg_log_dir }}/startup.log
    restart -m fast
  listen: "Restart PostgreSQL"
```

### 2.8 Create the Playbook

```bash
vi /opt/pgsql/ansible-pg/configure-postgresql.yml
```

```yaml
---
# configure-postgresql.yml - Apply PostgreSQL configuration to all servers

- name: Configure PostgreSQL servers
  hosts: all
  become: true
  vars:
    pg_shared_buffers: "512MB"
    pg_effective_cache_size: "2GB"
    pg_work_mem: "8MB"
    pg_maintenance_work_mem: "256MB"
    pg_max_connections: 200
    pg_log_min_duration: 500
    pg_hba_entries:
      - database: "all"
        user: "appuser"
        address: "10.0.0.0/16"
        method: "scram-sha-256"
      - database: "monitoring"
        user: "monitor"
        address: "10.0.0.0/16"
        method: "scram-sha-256"

  roles:
    - postgresql
```

### 2.9 Run the Playbook (Dry Run First)

Always do a dry run first with `--check`. This shows what Ansible would change without making any changes. The `--diff` flag shows the exact line-by-line differences.

```bash
cd /opt/pgsql/ansible-pg
```

```bash
ansible-playbook -i inventory/hosts.yml configure-postgresql.yml --check --diff
```

Expected output (yours will differ):
```
PLAY [Configure PostgreSQL servers] *******************

TASK [Gathering Facts] ********************************
ok: [pg-primary]
ok: [pg-replica-1]
ok: [pg-replica-2]

TASK [postgresql : Deploy postgresql.conf] ************
--- before: /opt/pgsql/data/postgresql.conf
+++ after: /opt/pgsql/data/postgresql.conf
@@ -5,7 +5,7 @@
-shared_buffers = '256MB'
+shared_buffers = '512MB'
changed: [pg-primary]
...
```

To apply for real, run without `--check`.

```bash
ansible-playbook -i inventory/hosts.yml configure-postgresql.yml --diff
```

---

## Part 3: Terraform State and the PostgreSQL Provider

### 3.1 Store Terraform State in PostgreSQL

By default, Terraform stores state in a local file. In a team, you need remote state. PostgreSQL can serve as a state backend.

```bash
vi /opt/pgsql/terraform-rds/backend.tf
```

```hcl
# backend.tf - Store Terraform state in PostgreSQL
# Uncomment this block after creating the state database

# terraform {
#   backend "pg" {
#     conn_str = "postgres://terraform@statedb.internal:5432/tfstate?sslmode=require"
#   }
# }
```

To use this, first create the state database.

Switch to postgres user.

```bash
sudo -iu postgres
```

```bash
psql -c "CREATE DATABASE tfstate OWNER terraform;"
```

Exit postgres user.

```bash
exit
```

Then uncomment the backend block and run `terraform init` to migrate state.

### 3.2 The PostgreSQL Terraform Provider

There is also a Terraform provider for managing PostgreSQL objects (databases, roles, extensions) directly.

```bash
vi /opt/pgsql/terraform-rds/pg-objects.tf
```

```hcl
# pg-objects.tf - Manage PostgreSQL objects with Terraform
# This provider connects to an existing PostgreSQL instance

terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }
}

provider "postgresql" {
  host     = aws_db_instance.postgresql.address
  port     = aws_db_instance.postgresql.port
  database = "postgres"
  username = var.db_username
  password = var.db_password
  sslmode  = "require"
}

# Create application database
resource "postgresql_database" "app" {
  name              = "app_production"
  owner             = postgresql_role.app_role.name
  template          = "template0"
  lc_collate        = "en_US.UTF-8"
  connection_limit  = 100
  allow_connections = true
}

# Create application role
resource "postgresql_role" "app_role" {
  name     = "app_service"
  login    = true
  password = var.app_db_password

  connection_limit = 50
}

# Create read-only role
resource "postgresql_role" "readonly_role" {
  name  = "app_readonly"
  login = true
  password = var.readonly_db_password
}

# Grant read-only access
resource "postgresql_grant" "readonly_tables" {
  database    = postgresql_database.app.name
  role        = postgresql_role.readonly_role.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}

# Enable extensions
resource "postgresql_extension" "pg_stat_statements" {
  name     = "pg_stat_statements"
  database = postgresql_database.app.name
}

resource "postgresql_extension" "pgcrypto" {
  name     = "pgcrypto"
  database = postgresql_database.app.name
}
```

---

## Part 4: Managing pg_hba.conf and postgresql.conf via IaC

### 4.1 Why IaC for Config Files?

Manual config changes lead to:
- **Configuration drift** - servers in the same cluster have different settings
- **Undocumented changes** - nobody knows who changed what or why
- **Failed rollbacks** - no easy way to revert to a known-good state

IaC solves all three: configs are versioned, reviewed, and applied consistently.

### 4.2 Ansible Variables Per Environment

Create environment-specific variable files.

```bash
mkdir -p /opt/pgsql/ansible-pg/group_vars
```

Development settings.

```bash
vi /opt/pgsql/ansible-pg/group_vars/dev.yml
```

```yaml
---
pg_shared_buffers: "256MB"
pg_effective_cache_size: "512MB"
pg_work_mem: "4MB"
pg_max_connections: 100
pg_log_min_duration: 0
```

Production settings.

```bash
vi /opt/pgsql/ansible-pg/group_vars/prod.yml
```

```yaml
---
pg_shared_buffers: "4GB"
pg_effective_cache_size: "12GB"
pg_work_mem: "16MB"
pg_max_connections: 500
pg_log_min_duration: 1000
```

### 4.3 Rolling Restart with Ansible

When postgresql.conf changes require a restart (not just a reload), do it one server at a time.

```bash
vi /opt/pgsql/ansible-pg/rolling-restart.yml
```

```yaml
---
# rolling-restart.yml - Restart PostgreSQL one server at a time

- name: Rolling restart of PostgreSQL replicas
  hosts: pg_replicas
  serial: 1
  become: true
  tasks:
    - name: Check replication lag before restart
      become_user: postgres
      command: >
        psql -tAc "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()
        THEN 0 ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) END;"
      register: lag_check

    - name: Fail if replication lag is too high
      fail:
        msg: "Replication lag is {{ lag_check.stdout }}s - too high to restart safely"
      when: lag_check.stdout | float > 30

    - name: Restart PostgreSQL
      become_user: postgres
      command: >
        /usr/pgsql-{{ pg_version }}/bin/pg_ctl
        -D {{ pg_data_dir }}
        -l {{ pg_log_dir }}/startup.log
        restart -m fast

    - name: Wait for PostgreSQL to accept connections
      wait_for:
        port: "{{ pg_port }}"
        delay: 5
        timeout: 60

    - name: Verify PostgreSQL is healthy
      become_user: postgres
      command: psql -tAc "SELECT 1;"
      register: health_check
      retries: 5
      delay: 5
      until: health_check.rc == 0

    - name: Wait for replication to catch up
      become_user: postgres
      command: >
        psql -tAc "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()
        THEN 0 ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) END;"
      register: post_lag
      retries: 12
      delay: 10
      until: post_lag.stdout | float < 5

- name: Restart PostgreSQL primary (after all replicas)
  hosts: pg_primary
  become: true
  tasks:
    - name: Restart PostgreSQL primary
      become_user: postgres
      command: >
        /usr/pgsql-{{ pg_version }}/bin/pg_ctl
        -D {{ pg_data_dir }}
        -l {{ pg_log_dir }}/startup.log
        restart -m fast

    - name: Wait for PostgreSQL to accept connections
      wait_for:
        port: "{{ pg_port }}"
        delay: 5
        timeout: 60

    - name: Verify PostgreSQL is healthy
      become_user: postgres
      command: psql -tAc "SELECT pg_is_in_recovery();"
      register: recovery_check

    - name: Confirm primary is not in recovery
      fail:
        msg: "Primary is in recovery mode - something went wrong"
      when: recovery_check.stdout | trim == 't'
```

Key concepts:
- `serial: 1` - Process one host at a time (not in parallel)
- Replication lag check before restart prevents restarting a lagging replica
- Health checks after restart confirm the server is back
- Primary restarts last, after all replicas are healthy

---

## Part 5: Secrets Management in IaC

### 5.1 The Problem

Database passwords, API keys, and certificates must be available to Terraform and Ansible but should never appear in:
- Git repositories
- CI/CD logs
- Terraform state files (in plaintext)
- Ansible playbook output

### 5.2 Ansible Vault

Ansible Vault encrypts sensitive variable files.

Create an encrypted file for database passwords.

```bash
ansible-vault create /opt/pgsql/ansible-pg/group_vars/vault.yml
```

This opens vi. Enter your secrets in YAML format:

```yaml
vault_db_password: "SuperSecretPassword123"
vault_replication_password: "ReplicaPass456"
vault_monitor_password: "MonitorPass789"
```

Save and exit. The file is now encrypted with AES-256.

View the encrypted file to confirm.

```bash
cat /opt/pgsql/ansible-pg/group_vars/vault.yml
```

Expected output (yours will differ):
```
$ANSIBLE_VAULT;1.1;AES256
38626433633839353934613130643064383865643833333063343736373939373237343366363538
...
```

Run playbooks with vault access.

```bash
ansible-playbook -i inventory/hosts.yml configure-postgresql.yml --ask-vault-pass
```

The `--ask-vault-pass` flag prompts you for the encryption password at runtime.

### 5.3 AWS Secrets Manager with Terraform

For Terraform, use AWS Secrets Manager instead of plaintext variables.

```bash
vi /opt/pgsql/terraform-rds/secrets.tf
```

```hcl
# secrets.tf - Read database password from AWS Secrets Manager

# Reference an existing secret
data "aws_secretsmanager_secret" "db_password" {
  name = "${var.environment}/postgresql/master-password"
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}

# Use the secret value in the RDS instance
# Replace the password line in main.tf with:
# password = data.aws_secretsmanager_secret_version.db_password.secret_string
```

### 5.4 Environment Variables

The simplest secrets approach - pass secrets via environment variables.

For Terraform:

```bash
export TF_VAR_db_password="YourSecurePassword"
```

For Ansible:

```bash
export PGPASSWORD="YourSecurePassword"
```

For CI/CD (GitHub Actions), use repository secrets:

```yaml
    env:
      DATABASE_URL: postgresql://postgres:${{ secrets.DB_PASSWORD }}@localhost:5432/testdb
```

### 5.5 Secrets Checklist

Before committing any IaC code, check:

- [ ] No passwords in `.tf` or `.yml` files
- [ ] `terraform.tfvars` is in `.gitignore`
- [ ] Ansible vault files are encrypted
- [ ] CI/CD uses repository secrets, not hardcoded values
- [ ] Terraform state is stored remotely with encryption
- [ ] No credentials in Terraform output blocks

---

## Key Takeaways

1. Terraform defines cloud infrastructure (RDS, security groups, parameter groups) as code
2. Ansible manages server configuration (postgresql.conf, pg_hba.conf) as code
3. Always run `terraform plan` and `ansible-playbook --check` before applying changes
4. Use parameter groups in Terraform, templates in Ansible for PostgreSQL settings
5. Rolling restarts with Ansible process one server at a time with health checks
6. Never store secrets in Git - use Ansible Vault, AWS Secrets Manager, or environment variables
7. Tag all cloud resources with `ManagedBy = "terraform"` to prevent manual drift
