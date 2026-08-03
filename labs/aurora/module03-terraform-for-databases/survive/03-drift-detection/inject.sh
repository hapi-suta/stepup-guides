#!/bin/bash
# SURVIVE 03: Drift Detection - Injection Script
# This script creates Terraform-managed resources, then modifies them
# outside of Terraform to simulate configuration drift.
#
# IDEMPOTENT: Safe to run multiple times.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive03-drift-detection"

echo "=== SURVIVE 03: Drift Detection ==="
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

resource "local_file" "security_group" {
  content  = "# Production Security Group\nallow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-group.conf"
}

resource "local_file" "cluster_params" {
  content  = "# Cluster Parameter Group\nshared_preload_libraries=pg_stat_statements\nlog_connections=1\nlog_disconnections=1"
  filename = "${path.module}/cluster-params.conf"
}

resource "local_file" "instance_params" {
  content  = "# Instance Parameter Group\nlog_statement=ddl\nlog_min_duration_statement=1000\nwork_mem=262144\nidle_in_transaction_session_timeout=300000"
  filename = "${path.module}/instance-params.conf"
}

resource "local_file" "aurora_config" {
  content  = "# Aurora Cluster Config\ncluster_id=prod-aurora\nengine_version=16.4\ninstance_class=db.r6g.large\nbackup_retention=35"
  filename = "${path.module}/aurora-config.conf"
}

output "managed_resources" {
  value = "4 resources under Terraform management"
}
EOF

# Initialize and apply
echo ""
echo "Initializing Terraform..."
terraform init -input=false > /dev/null 2>&1

echo "Creating resources..."
terraform apply -auto-approve -input=false > /dev/null 2>&1

echo "Resources created. Verifying state is clean..."
terraform plan -detailed-exitcode -input=false > /dev/null 2>&1
echo "State is in sync with configuration."
echo ""

# === INJECT THE DRIFT ===
echo "=== INJECTING DRIFT ==="
echo "Simulating manual changes made outside of Terraform..."
echo ""

# Drift 1: Someone added a security group rule via AWS Console
echo "Drift 1: Junior engineer added a permissive SG rule in AWS Console..."
echo "# Production Security Group
allow 10.0.0.0/8 port 5432
allow 172.16.0.0/12 port 5432
allow 0.0.0.0/0 port 5432" > security-group.conf

# Drift 2: Someone changed a parameter via AWS Console
echo "Drift 2: Developer changed log_statement to 'all' in AWS Console..."
echo "# Instance Parameter Group
log_statement=all
log_min_duration_statement=1000
work_mem=262144
idle_in_transaction_session_timeout=300000" > instance-params.conf

# Drift 3: Someone changed the backup retention
echo "Drift 3: Cost optimization team reduced backup retention..."
echo "# Aurora Cluster Config
cluster_id=prod-aurora
engine_version=16.4
instance_class=db.r6g.large
backup_retention=7" > aurora-config.conf

echo ""
echo "3 resources have been modified outside of Terraform:"
echo "  1. security-group.conf   - Added 0.0.0.0/0 rule (DANGEROUS)"
echo "  2. instance-params.conf  - Changed log_statement to 'all'"
echo "  3. aurora-config.conf    - Reduced backup retention from 35 to 7"
echo ""
echo "cluster-params.conf was NOT modified (no drift on this resource)."
echo ""
echo "Your mission:"
echo "  1. Detect all drift using terraform plan"
echo "  2. Decide which changes to keep and which to revert"
echo "  3. Reconcile state so terraform plan shows no changes"
echo ""
echo "Lab directory: $LAB_DIR"
echo "Runbook: $(dirname "$0")/runbook.md"
echo ""
echo "=== DRIFT INJECTED ==="
