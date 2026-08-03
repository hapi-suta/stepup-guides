#!/usr/bin/env bash
# SURVIVE 01 - Bad Parameter Change
# Inject: Set shared_buffers to an invalid value that will break the instance after reboot
#
# INSTRUCTOR USE ONLY - Do not show to students before they attempt the scenario

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

section "SURVIVE 01 - Injecting Bad Parameter Change"

info "Current shared_buffers value:"
get_param_value "shared_buffers"

info "Setting shared_buffers to an absurdly high value..."
# shared_buffers in kB - setting to 90% of a 32GB instance's RAM
# This simulates a student typing MB when they meant to type a formula
# On a small instance (db.t3.micro, 1 GB RAM), any large fixed value causes failure
set_param "shared_buffers" "7340032" "pending-reboot"

info "Verifying the bad value is saved..."
NEW_VALUE=$(get_param_value "shared_buffers")
info "shared_buffers set to: $NEW_VALUE kB"

warn "Rebooting the instance to apply the bad parameter..."
warn "The instance will fail to start after this reboot."
reboot_instance

info "Waiting 30 seconds for the instance to start rebooting..."
sleep 30

info "Checking instance status..."
STATUS=$(get_instance_status)
info "Current status: $STATUS"

echo ""
warn "=================================================================="
warn "INJECT COMPLETE"
warn "=================================================================="
warn "The instance has been rebooted with an invalid shared_buffers value."
warn "It will enter 'incompatible-parameters' status and stop accepting"
warn "connections."
warn ""
warn "Student scenario begins now."
warn "=================================================================="
