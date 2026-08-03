#!/usr/bin/env bash
# SURVIVE 01 - Validate recovery from bad parameter change

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

section "SURVIVE 01 - Validating Recovery"

# -------------------------------------------------------
# Check 1: Instance status is 'available'
# -------------------------------------------------------
info "Checking instance status..."
STATUS=$(get_instance_status)
if [[ "$STATUS" == "available" ]]; then
  success "Instance status is: available"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Instance status is: $STATUS (expected: available)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Parameter group is in-sync
# -------------------------------------------------------
info "Checking parameter group apply status..."
PG_STATUS=$(get_param_group_status)
if [[ "$PG_STATUS" == "in-sync" ]]; then
  success "Parameter group status: in-sync"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Parameter group status: $PG_STATUS (expected: in-sync)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: shared_buffers is no longer the bad value
# -------------------------------------------------------
info "Checking shared_buffers value..."
SB_VALUE=$(get_param_value "shared_buffers")
# The bad value was 7340032 - anything else is acceptable
if [[ "$SB_VALUE" != "7340032" ]]; then
  success "shared_buffers is no longer the invalid value (current: $SB_VALUE)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "shared_buffers is still set to 7340032 kB - the bad value has not been fixed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: Can connect to the database
# -------------------------------------------------------
info "Checking database connectivity..."
if [[ -z "${PGPASSWORD:-}" ]]; then
  warn "PGPASSWORD not set - skipping connectivity check"
  warn "Set PGPASSWORD and re-run to include this check"
else
  if check_connectivity; then
    success "Database accepts connections"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    fail "Cannot connect to the database"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # -------------------------------------------------------
  # Check 5: PostgreSQL reports the correct shared_buffers at runtime
  # -------------------------------------------------------
  info "Checking runtime shared_buffers value in PostgreSQL..."
  RUNTIME_SB=$(run_sql "SELECT setting::integer FROM pg_settings WHERE name = 'shared_buffers'")
  # A sane shared_buffers is less than 4GB (4194304 kB)
  if [[ -n "$RUNTIME_SB" && "$RUNTIME_SB" -lt 4194304 ]]; then
    success "Runtime shared_buffers is sane: ${RUNTIME_SB} kB"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    fail "Runtime shared_buffers is missing or too large: ${RUNTIME_SB}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

print_summary
