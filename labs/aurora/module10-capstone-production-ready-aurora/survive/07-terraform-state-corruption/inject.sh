#!/usr/bin/env bash
# SURVIVE Scenario 07: Terraform State Corruption
# Injects: Corrupts the local Terraform state file by removing the Aurora
#          cluster resource, simulating a state file corruption.
# Idempotent: Creates a backup before corruption. Safe to run multiple times.
#
# Usage: bash inject.sh
# Requires: Terraform state file at ~/capstone-aurora/terraform/terraform.tfstate

set -euo pipefail

TERRAFORM_DIR="${TERRAFORM_DIR:-$HOME/capstone-aurora/terraform}"
STATE_FILE="$TERRAFORM_DIR/terraform.tfstate"

echo "============================================="
echo "  SURVIVE Scenario 07: Terraform State Corruption"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Verify state file exists
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: Terraform state file not found at $STATE_FILE"
  echo "Set TERRAFORM_DIR to the correct path."
  exit 1
fi

# Step 2: Create a backup (the student's safety net, but they need to find it)
BACKUP_FILE="$TERRAFORM_DIR/.terraform-state-backup-$(date +%Y%m%d%H%M%S).json"
cp "$STATE_FILE" "$BACKUP_FILE"
echo "State backup created (hidden): $BACKUP_FILE"
echo ""

# Step 3: Corrupt the state by removing Aurora cluster resources
echo "Corrupting Terraform state..."

# Use python3 to remove Aurora resources from state
python3 -c "
import json
import sys

with open('$STATE_FILE', 'r') as f:
    state = json.load(f)

# Remove Aurora cluster and instance resources from state
if 'resources' in state:
    original_count = len(state['resources'])
    state['resources'] = [
        r for r in state['resources']
        if not (r.get('type', '') in ['aws_rds_cluster', 'aws_rds_cluster_instance',
                'aws_rds_cluster_parameter_group', 'aws_db_parameter_group']
                or r.get('name', '') in ['aurora'])
    ]
    removed = original_count - len(state['resources'])
    print(f'  Removed {removed} Aurora resource(s) from state')

    # Increment the serial to make it look like a real change
    state['serial'] = state.get('serial', 0) + 1

with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"

echo ""
echo "State corruption complete."
echo ""

# Step 4: Show what terraform plan would do
echo "Running terraform plan to show the damage..."
cd "$TERRAFORM_DIR"
terraform plan -var-file=production.tfvars -no-color 2>&1 | head -30 || true

echo ""
echo "YOUR MISSION:"
echo "  1. Run 'terraform plan' and observe that Terraform wants to CREATE"
echo "     resources that already exist in AWS"
echo "  2. DO NOT run 'terraform apply' - it will try to create duplicate resources"
echo "     and fail (or worse, succeed with conflicts)"
echo "  3. Import the existing Aurora resources back into state using 'terraform import'"
echo "  4. Run 'terraform plan' again - it should show no changes"
echo "  5. Document the recovery procedure"
echo ""
echo "HINT: terraform import module.aurora.aws_rds_cluster.aurora devops-lab-cluster"
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
