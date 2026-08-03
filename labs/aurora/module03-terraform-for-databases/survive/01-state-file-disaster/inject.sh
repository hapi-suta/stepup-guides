#!/bin/bash
# SURVIVE 01: State File Disaster - Injection Script
# This script corrupts or deletes the Terraform state file to simulate
# a real-world scenario where state is lost or corrupted.
#
# IDEMPOTENT: Safe to run multiple times. Creates the lab environment
# from scratch each time.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive01-state-disaster"

echo "=== SURVIVE 01: State File Disaster ==="
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

resource "local_file" "aurora_config" {
  content  = "cluster_id=prod-aurora\nengine=aurora-postgresql\nversion=16.4\nwriter_endpoint=prod-aurora.cluster-abc.rds.amazonaws.com"
  filename = "${path.module}/aurora-config.conf"
}

resource "local_file" "security_group" {
  content  = "allow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security-group.conf"
}

resource "local_file" "parameter_group" {
  content  = "shared_preload_libraries=pg_stat_statements\nlog_connections=1\nlog_statement=ddl"
  filename = "${path.module}/parameter-group.conf"
}

resource "local_file" "backup_policy" {
  content  = "retention=35\nschedule=daily\nwindow=02:00-03:00"
  filename = "${path.module}/backup-policy.conf"
}

output "resource_count" {
  value = "4 resources managed"
}
EOF

# Initialize and apply
echo ""
echo "Initializing Terraform..."
terraform init -input=false > /dev/null 2>&1

echo "Creating resources..."
terraform apply -auto-approve -input=false > /dev/null 2>&1

echo "Resources created. State file exists."
echo ""

# Verify state is good
RESOURCE_COUNT=$(terraform state list | wc -l | tr -d ' ')
echo "Resources in state: $RESOURCE_COUNT"
echo "Files on disk:"
ls -1 *.conf 2>/dev/null || echo "  (none)"
echo ""

# === INJECT THE DISASTER ===
echo "=== INJECTING DISASTER ==="
echo "Simulating state file corruption/deletion..."
echo ""

# Delete the state file (simulating loss)
rm -f terraform.tfstate
rm -f terraform.tfstate.backup

echo "State file has been DELETED."
echo "The .conf files still exist on disk, but Terraform has lost"
echo "all knowledge of them."
echo ""
echo "Your mission: Get Terraform state back in sync with reality."
echo ""
echo "Lab directory: $LAB_DIR"
echo "Runbook: $(dirname "$0")/runbook.md"
echo ""
echo "=== DISASTER INJECTED ==="
