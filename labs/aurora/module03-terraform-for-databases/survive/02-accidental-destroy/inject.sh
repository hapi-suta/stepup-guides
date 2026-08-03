#!/bin/bash
# SURVIVE 02: Accidental Destroy - Injection Script
# This script creates a "production" environment and then destroys it,
# simulating an accidental terraform destroy.
#
# IDEMPOTENT: Safe to run multiple times.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive02-accidental-destroy"

echo "=== SURVIVE 02: Accidental Destroy ==="
echo "Setting up lab environment..."

# Clean up any previous run
rm -rf "$LAB_DIR"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"

# Create the Terraform configuration
cat > main.tf << 'EOF'
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environment" {
  type    = string
  default = "prod"
}

resource "local_file" "aurora_cluster" {
  content  = "cluster_id=prod-aurora\nengine=aurora-postgresql\nversion=16.4\nencrypted=true\nbackup_retention=35"
  filename = "${path.module}/aurora-cluster-${var.environment}.conf"
}

resource "local_file" "writer_instance" {
  content  = "instance_id=prod-aurora-writer\nclass=db.r6g.large\nrole=writer"
  filename = "${path.module}/writer-${var.environment}.conf"
}

resource "local_file" "reader_instance" {
  content  = "instance_id=prod-aurora-reader-1\nclass=db.r6g.large\nrole=reader"
  filename = "${path.module}/reader-${var.environment}.conf"
}

resource "local_file" "security_group" {
  content  = "sg_id=sg-0abc123def\nallow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-group-${var.environment}.conf"
}

resource "local_file" "parameter_group" {
  content  = "shared_preload_libraries=pg_stat_statements\nlog_connections=1\nlog_statement=ddl"
  filename = "${path.module}/parameter-group-${var.environment}.conf"
}

output "environment" {
  value = var.environment
}

output "resource_count" {
  value = "5 resources managed"
}
EOF

# Initialize and apply
echo ""
echo "Initializing Terraform..."
terraform init -input=false > /dev/null 2>&1

echo "Creating 'production' resources..."
terraform apply -auto-approve -input=false > /dev/null 2>&1

echo "Production environment created."
echo "Resources in state: $(terraform state list | wc -l | tr -d ' ')"
echo "Files on disk:"
ls -1 *-prod.conf 2>/dev/null || echo "  (none)"
echo ""

# === INJECT THE DISASTER ===
echo "=== INJECTING DISASTER ==="
echo "Simulating accidental terraform destroy..."
echo "(A colleague ran terraform destroy -auto-approve on production)"
echo ""

terraform destroy -auto-approve -input=false > /dev/null 2>&1

echo "DISASTER: All production resources have been destroyed!"
echo "The state file is empty (0 resources)."
echo "The .conf files have been deleted from disk."
echo ""
echo "Your mission:"
echo "  1. Recreate the destroyed resources"
echo "  2. Implement safeguards so this cannot happen again"
echo ""
echo "Lab directory: $LAB_DIR"
echo "Runbook: $(dirname "$0")/runbook.md"
echo ""
echo "=== DISASTER INJECTED ==="
