# Module 10 - Build Guide 02: Terraform Foundation (VPC, Security Groups, IAM)

**Objective:** Build the networking and security foundation for your Aurora stack using Terraform. Create a VPC with public and private subnets, NAT gateways, security groups, IAM roles, and KMS keys.
**Time:** 50 minutes
**Level:** Senior / Staff
**Prerequisites:** Terraform >= 1.5 installed. AWS CLI configured. Architecture Decision Document from Build 01 completed.

---

## 1. Project Structure

Set up the Terraform project with a clean module structure.

**On your local workstation:**

```bash
mkdir -p ~/capstone-aurora/terraform
```

```bash
cd ~/capstone-aurora/terraform
```

```bash
mkdir -p modules/vpc modules/security modules/iam
```

This creates three modules:
- `vpc` - VPC, subnets, route tables, NAT gateways, VPC endpoints
- `security` - Security groups, KMS keys
- `iam` - IAM roles for RDS monitoring, Secrets Manager access

Verify the structure:

```bash
ls -la ~/capstone-aurora/terraform/modules/
```

Expected output (yours will differ):
```
drwxr-xr-x  vpc
drwxr-xr-x  security
drwxr-xr-x  iam
```

---

## 2. Provider Configuration

Create the root Terraform configuration.

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/versions.tf
```

Add this content:

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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "devops-lab"
      ManagedBy   = "terraform"
    }
  }
}
```

The `default_tags` block automatically applies these tags to every resource Terraform creates. This satisfies the tagging requirement from the Production Readiness Checklist without repeating tags on every resource.

---

## 3. Root Variables

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/variables.tf
```

Add this content:

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "devops-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_cidr" {
  description = "CIDR block allowed to SSH to bastion host"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

The `admin_cidr` variable has no default - Terraform will prompt for it. This prevents hardcoding your IP address.

---

## 4. VPC Module

### 4.1 VPC Module Variables

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/vpc/variables.tf
```

Add this content:

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}
```

### 4.2 VPC Module Main

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/vpc/main.tf
```

Add this content:

```hcl
# ------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ------------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ------------------------------------------------------------------
# Public Subnets (for NAT Gateways and Bastion)
# ------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ------------------------------------------------------------------
# Private Application Subnets
# ------------------------------------------------------------------
resource "aws_subnet" "private_app" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-app-${var.availability_zones[count.index]}"
    Tier = "private-app"
  }
}

# ------------------------------------------------------------------
# Private Database Subnets
# ------------------------------------------------------------------
resource "aws_subnet" "private_db" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 21)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-db-${var.availability_zones[count.index]}"
    Tier = "private-db"
  }
}

# ------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index + 1}"
  }
}

# ------------------------------------------------------------------
# NAT Gateways (one per public subnet for HA)
# ------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ------------------------------------------------------------------
# Route Tables
# ------------------------------------------------------------------

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app route tables (one per AZ, routing through AZ-local NAT)
resource "aws_route_table" "private_app" {
  count = 2

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-app-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private_app" {
  count = 2

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# Private DB route table (NO internet route - fully isolated)
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count = 3

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# ------------------------------------------------------------------
# DB Subnet Group
# ------------------------------------------------------------------
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ------------------------------------------------------------------
# VPC Endpoints (for isolated DB subnets)
# ------------------------------------------------------------------

# S3 Gateway Endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  route_table_ids = [aws_route_table.private_db.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# Secrets Manager Interface Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

# CloudWatch Monitoring Interface Endpoint
resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.monitoring"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-monitoring-endpoint"
  }
}

# CloudWatch Logs Interface Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-logs-endpoint"
  }
}

data "aws_region" "current" {}
```

The `cidrsubnet` function calculates subnet CIDRs automatically. `cidrsubnet("10.0.0.0/16", 8, 1)` produces `10.0.1.0/24`. The second argument (8) adds 8 bits to the prefix (16+8=24). The third argument is the subnet number.

### 4.3 VPC Module Outputs

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/vpc/outputs.tf
```

Add this content:

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets"
  value       = aws_subnet.private_db[*].id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.aurora.name
}
```

---

## 5. Security Module

### 5.1 Security Module Variables

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/security/variables.tf
```

Add this content:

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security groups"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block for admin SSH access"
  type        = string
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks of private app subnets"
  type        = list(string)
  default     = []
}
```

### 5.2 Security Module Main

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/security/main.tf
```

Add this content:

```hcl
# ------------------------------------------------------------------
# Security Group: Bastion Host
# ------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-bastion-"
  description = "Allow SSH from admin CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------
# Security Group: Application Servers
# ------------------------------------------------------------------
resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-app-"
  description = "Allow HTTPS inbound, all outbound"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------
# Security Group: Aurora Cluster
# ------------------------------------------------------------------
resource "aws_security_group" "aurora" {
  name_prefix = "${var.project_name}-aurora-"
  description = "Allow PostgreSQL from app and bastion security groups only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-aurora-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Separate ingress rules to avoid circular dependencies
resource "aws_vpc_security_group_ingress_rule" "aurora_from_app" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from app servers"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_bastion" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from bastion"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

# ------------------------------------------------------------------
# KMS Key for Aurora Encryption
# ------------------------------------------------------------------
resource "aws_kms_key" "aurora" {
  description             = "CMK for Aurora storage encryption - ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = true

  tags = {
    Name = "${var.project_name}-aurora-cmk"
  }
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.project_name}-aurora-cmk"
  target_key_id = aws_kms_key.aurora.key_id
}
```

Key design decisions in this security module:

- The Aurora security group uses `name_prefix` with `create_before_destroy`. This avoids the "security group is in use" error during replacement.
- Aurora ingress rules reference security groups (not CIDRs). This means only resources in the `app` or `bastion` security groups can connect - no IP-based access.
- The KMS key has `multi_region = true` so you can replicate it to the DR region for cross-region snapshot restores.
- Key rotation is enabled (annual automatic rotation).

### 5.3 Security Module Outputs

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/security/outputs.tf
```

Add this content:

```hcl
output "bastion_sg_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
}

output "app_sg_id" {
  description = "Security group ID for application servers"
  value       = aws_security_group.app.id
}

output "aurora_sg_id" {
  description = "Security group ID for Aurora cluster"
  value       = aws_security_group.aurora.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for Aurora encryption"
  value       = aws_kms_key.aurora.arn
}

output "kms_key_id" {
  description = "ID of the KMS key for Aurora encryption"
  value       = aws_kms_key.aurora.key_id
}
```

---

## 6. IAM Module

### 6.1 IAM Module Variables

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/iam/variables.tf
```

Add this content:

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}
```

### 6.2 IAM Module Main

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/iam/main.tf
```

Add this content:

```hcl
# ------------------------------------------------------------------
# IAM Role: RDS Enhanced Monitoring
# ------------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ------------------------------------------------------------------
# IAM Role: RDS Secrets Manager Access
# ------------------------------------------------------------------
resource "aws_iam_role" "rds_secrets" {
  name = "${var.project_name}-rds-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rds-secrets-role"
  }
}

resource "aws_iam_role_policy" "rds_secrets" {
  name = "${var.project_name}-rds-secrets-policy"
  role = aws_iam_role.rds_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:rds!*"
      }
    ]
  })
}

# ------------------------------------------------------------------
# IAM Role: GitHub Actions (for CI/CD pipeline)
# ------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

resource "aws_iam_role_policy" "github_actions_rds" {
  name = "${var.project_name}-github-actions-rds-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds-db:connect"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:rds!*"
      }
    ]
  })
}
```

The GitHub Actions IAM role uses OIDC federation - no long-lived AWS credentials stored in GitHub secrets. The role can only be assumed by GitHub Actions runners.

### 6.3 IAM Module Outputs

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/modules/iam/outputs.tf
```

Add this content:

```hcl
output "rds_monitoring_role_arn" {
  description = "ARN of the RDS Enhanced Monitoring role"
  value       = aws_iam_role.rds_monitoring.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions role"
  value       = aws_iam_role.github_actions.arn
}
```

---

## 7. Root Module - Wire It Together

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/main.tf
```

Add this content:

```hcl
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  admin_cidr   = var.admin_cidr
}

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
}
```

Create the outputs file:

```bash
vi ~/capstone-aurora/terraform/outputs.tf
```

Add this content:

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "db_subnet_group_name" {
  description = "DB subnet group name for Aurora"
  value       = module.vpc.db_subnet_group_name
}

output "aurora_sg_id" {
  description = "Security group ID for Aurora"
  value       = module.security.aurora_sg_id
}

output "kms_key_arn" {
  description = "KMS key ARN for Aurora encryption"
  value       = module.security.kms_key_arn
}

output "rds_monitoring_role_arn" {
  description = "IAM role ARN for Enhanced Monitoring"
  value       = module.iam.rds_monitoring_role_arn
}
```

---

## 8. Create the tfvars File

**On your local workstation:**

```bash
vi ~/capstone-aurora/terraform/production.tfvars
```

Add this content (replace the admin CIDR with your IP):

```hcl
aws_region         = "us-east-1"
environment        = "production"
project_name       = "devops-lab"
vpc_cidr           = "10.0.0.0/16"
admin_cidr         = "YOUR.IP.ADDRESS/32"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

Replace `YOUR.IP.ADDRESS` with your actual IP. Find it with:

```bash
curl -s https://checkip.amazonaws.com
```

Expected output (yours will differ):
```
203.0.113.42
```

---

## 9. Initialize and Plan

**On your local workstation:**

```bash
cd ~/capstone-aurora/terraform
```

```bash
terraform init
```

`terraform init` downloads the AWS provider plugin and initializes the backend. You should see "Terraform has been successfully initialized!"

Expected output (yours will differ):
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.82.0...
Terraform has been successfully initialized!
```

Now run the plan:

```bash
terraform plan -var-file=production.tfvars -out=foundation.plan
```

`-var-file` loads variables from the file you created. `-out` saves the plan to a file so `apply` uses the exact same plan.

Review the plan output carefully. You should see approximately 25-30 resources to create:
- 1 VPC
- 1 Internet Gateway
- 2 Public subnets
- 2 Private app subnets
- 3 Private DB subnets
- 2 NAT gateways + 2 EIPs
- Route tables and associations
- 3 Security groups
- 1 DB subnet group
- 4 VPC endpoints
- 1 KMS key + alias
- 3 IAM roles + policies

---

## 10. Apply the Foundation

**On your local workstation:**

```bash
terraform apply foundation.plan
```

This creates all the networking, security, and IAM resources. NAT gateway creation takes 1-2 minutes.

Expected output (yours will differ):
```
Apply complete! Resources: 28 added, 0 changed, 0 destroyed.

Outputs:

aurora_sg_id = "sg-0abc123def456789"
db_subnet_group_name = "devops-lab-db-subnet-group"
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/abc-def-123"
rds_monitoring_role_arn = "arn:aws:iam::123456789012:role/devops-lab-rds-monitoring-role"
vpc_id = "vpc-0abc123def456789"
```

---

## 11. Verify the Foundation

Run these verification commands to confirm everything was created correctly.

**On your local workstation:**

Verify the VPC exists:

```bash
aws ec2 describe-vpcs \
  --filters Name=tag:Name,Values=devops-lab-vpc \
  --query 'Vpcs[0].[VpcId,CidrBlock,State]' \
  --output table
```

Expected output (yours will differ):
```
---------------------------------------------
|             DescribeVpcs                  |
+---------------------+-----------+---------+
|  vpc-0abc123def456  | 10.0.0.0/16 | available |
+---------------------+-----------+---------+
```

Verify DB subnets are in private route tables (no internet gateway):

```bash
aws ec2 describe-route-tables \
  --filters Name=tag:Name,Values=devops-lab-private-db-rt \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,NatGatewayId]' \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------
|          DescribeRouteTables               |
+--------------+--------+-------------------+
|  10.0.0.0/16 | local  |  None             |
+--------------+--------+-------------------+
```

The only route should be `local`. No `igw-*` or `nat-*` entries - the DB subnets are fully isolated.

Verify the KMS key exists and has rotation enabled:

```bash
aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.[KeyId,KeyState,MultiRegion]' \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------
|               DescribeKey                      |
+------------------+-----------+-----------------+
|  abc-def-123-456 | Enabled   | True            |
+------------------+-----------+-----------------+
```

---

## Summary

You have built the networking and security foundation for your production Aurora stack:

- **VPC** with public, private-app, and private-db subnets across 3 AZs
- **NAT Gateways** (2) for HA outbound from app subnets
- **DB subnets** with no internet route (fully isolated)
- **Security groups** with least-privilege rules (Aurora only accepts from app and bastion SGs)
- **KMS key** (multi-region, rotation enabled) for storage encryption
- **IAM roles** for Enhanced Monitoring, Secrets Manager, and GitHub Actions CI/CD
- **VPC endpoints** so isolated DB subnets can reach AWS services

The foundation is ready. Build Guide 03 will add the Aurora cluster on top of this infrastructure.

**Next:** [Build 03 - Terraform Aurora](./03-terraform-aurora.md)
