#!/usr/bin/env bash
# SURVIVE 04 - Validate FDW connection recovery

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: Set PGPASSWORD environment variable before running validate.sh"
  exit 1
fi

section "SURVIVE 04 - Validating FDW Connection Recovery"

# -------------------------------------------------------
# Check 1: postgres_fdw extension is installed
# -------------------------------------------------------
info "Checking postgres_fdw extension..."
FDW_EXT=$(run_sql "SELECT installed_version FROM pg_available_extensions WHERE name = 'postgres_fdw'" 2>/dev/null | tr -d '[:space:]')
if [[ -n "$FDW_EXT" && "$FDW_EXT" != "NULL" ]]; then
  success "postgres_fdw is installed (version: $FDW_EXT)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "postgres_fdw is NOT installed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Foreign server exists
# -------------------------------------------------------
info "Checking foreign server exists..."
SERVER_EXISTS=$(run_sql "SELECT COUNT(*) FROM pg_foreign_server WHERE srvname = 'remote_data_server'" 2>/dev/null | tr -d '[:space:]')
if [[ "$SERVER_EXISTS" == "1" ]]; then
  success "Foreign server 'remote_data_server' exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Foreign server 'remote_data_server' does not exist"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Foreign server does NOT point to the bad host
# -------------------------------------------------------
info "Checking foreign server host is not the broken value..."
SRV_OPTIONS=$(run_sql "SELECT srvoptions::text FROM pg_foreign_server WHERE srvname = 'remote_data_server'" 2>/dev/null)
if echo "$SRV_OPTIONS" | grep -q "nonexistent-rds-endpoint.invalid"; then
  fail "Foreign server still points to the broken host: nonexistent-rds-endpoint.invalid..."
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  success "Foreign server host is no longer the broken value"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: User mapping exists
# -------------------------------------------------------
info "Checking user mapping exists..."
MAPPING_EXISTS=$(run_sql "
SELECT COUNT(*)
FROM pg_user_mappings
WHERE srvid = (SELECT oid FROM pg_foreign_server WHERE srvname = 'remote_data_server')
" 2>/dev/null | tr -d '[:space:]')
if [[ "$MAPPING_EXISTS" -ge 1 ]]; then
  success "User mapping exists for remote_data_server"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "No user mapping found for remote_data_server"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: Foreign table is accessible
# -------------------------------------------------------
info "Testing foreign table connectivity..."
FDW_COUNT=$(run_sql "SELECT COUNT(*) FROM remote_source.source_data" 2>/dev/null | tr -d '[:space:]')
if [[ "$FDW_COUNT" =~ ^[0-9]+$ && "$FDW_COUNT" -gt 0 ]]; then
  success "remote_source.source_data is accessible ($FDW_COUNT rows)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Cannot query remote_source.source_data (returned: $FDW_COUNT)"
  fail "The foreign server connection may still be broken"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: Can query and filter the foreign table
# -------------------------------------------------------
info "Testing foreign table filtering (push-down)..."
FILTERED=$(run_sql "SELECT COUNT(*) FROM remote_source.source_data WHERE value > 500" 2>/dev/null | tr -d '[:space:]')
if [[ "$FILTERED" =~ ^[0-9]+$ ]]; then
  success "Filtered query on remote_source.source_data works ($FILTERED rows matched)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Cannot run filtered query on remote_source.source_data"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 7: check_fdw_connectivity function (bonus)
# -------------------------------------------------------
info "Checking if check_fdw_connectivity() function was created..."
FUNC_EXISTS=$(run_sql "SELECT COUNT(*) FROM pg_proc WHERE proname = 'check_fdw_connectivity'" 2>/dev/null | tr -d '[:space:]')
if [[ "$FUNC_EXISTS" == "1" ]]; then
  success "Bonus: check_fdw_connectivity() function exists (good practice!)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  warn "Optional: check_fdw_connectivity() function not created (not required but recommended)"
fi

print_summary
