#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 04: Validate - Wraparound Emergency Resolved
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 04: Validation - Wraparound Emergency"

t8_validate_config || exit 1
check_aws_auth || exit 1
check_db_connectivity || exit 1

PASS_COUNT=0
FAIL_COUNT=0

if [[ -f "${SCRIPT_DIR}/.inject-state" ]]; then
  source "${SCRIPT_DIR}/.inject-state"
fi

# -----------------------------------------------------------------------
# Check 1: Wraparound table is cleaned up (autovacuum re-enabled)
# -----------------------------------------------------------------------
log_step "Check 1: autovacuum re-enabled on t8_high_churn_events"

TABLE_RELOPTIONS=$(run_sql "
  SELECT reloptions::text
  FROM pg_class
  WHERE relname = 't8_high_churn_events' AND relkind = 'r';" | tr -d ' ')

if [[ "${TABLE_RELOPTIONS}" != *"autovacuum_enabled=false"* ]]; then
  validate_check "autovacuum_enabled restored on t8_high_churn_events" "pass" \
    "reloptions: ${TABLE_RELOPTIONS:-none}"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "autovacuum_enabled still disabled on t8_high_churn_events" "fail" \
    "reloptions: ${TABLE_RELOPTIONS}"
  echo "  Fix: ALTER TABLE t8_high_churn_events RESET (autovacuum_enabled);"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 2: Dead tuple ratio is below 20% (VACUUM ran)
# -----------------------------------------------------------------------
log_step "Check 2: Dead tuple ratio reduced (VACUUM ran successfully)"

DEAD_PCT=$(run_sql "
  SELECT round(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2)
  FROM pg_stat_user_tables
  WHERE relname = 't8_high_churn_events';" | tr -d ' ')

if [[ -z "${DEAD_PCT}" ]]; then
  log_warn "Could not retrieve dead tuple ratio - table may have been dropped."
  PASS_COUNT=$((PASS_COUNT + 1))
elif (( $(echo "${DEAD_PCT} < 20" | bc -l) )); then
  validate_check "Dead tuple ratio below 20%: ${DEAD_PCT}%" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Dead tuple ratio is still high: ${DEAD_PCT}%" "fail" \
    "Expected < 20%. Run: VACUUM FREEZE VERBOSE t8_high_churn_events;"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 3: No tables in the database have autovacuum disabled
# -----------------------------------------------------------------------
log_step "Check 3: No tables have autovacuum explicitly disabled"

DISABLED_TABLES=$(run_sql "
  SELECT count(*)
  FROM pg_class
  WHERE reloptions::text LIKE '%autovacuum_enabled=false%'
  AND relkind = 'r';" | tr -d ' ')

if [[ "${DISABLED_TABLES}" == "0" ]]; then
  validate_check "No tables have autovacuum explicitly disabled" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Tables with autovacuum disabled still exist" "fail" \
    "Count: ${DISABLED_TABLES}"

  DISABLED_LIST=$(run_sql "
    SELECT relname FROM pg_class
    WHERE reloptions::text LIKE '%autovacuum_enabled=false%'
    AND relkind = 'r';")
  echo "  Tables: ${DISABLED_LIST}"
  echo "  Fix: ALTER TABLE [table] RESET (autovacuum_enabled);"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 4: autovacuum parameters are restored to healthy values
# -----------------------------------------------------------------------
log_step "Check 4: Autovacuum parameters restored to healthy values"

if [[ -n "${T8_PARAMETER_GROUP}" ]]; then
  COST_DELAY=$(get_parameter_value "autovacuum_vacuum_cost_delay")
  NAPTIME=$(get_parameter_value "autovacuum_naptime")

  COST_DELAY_OK=true
  NAPTIME_OK=true

  # cost_delay should be <= 20ms for normal operation
  if [[ "${COST_DELAY}" != "" && "${COST_DELAY}" != "PARAMETER-NOT-FOUND" ]]; then
    if [[ "${COST_DELAY}" -gt 20 ]]; then
      COST_DELAY_OK=false
    fi
  fi

  # naptime should be <= 60 seconds
  if [[ "${NAPTIME}" != "" && "${NAPTIME}" != "PARAMETER-NOT-FOUND" ]]; then
    if [[ "${NAPTIME}" -gt 60 ]]; then
      NAPTIME_OK=false
    fi
  fi

  if [[ "${COST_DELAY_OK}" == "true" && "${NAPTIME_OK}" == "true" ]]; then
    validate_check "Autovacuum parameters are healthy (cost_delay: ${COST_DELAY}ms, naptime: ${NAPTIME}s)" "pass"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    validate_check "Autovacuum parameters need restoration" "fail" \
      "cost_delay: ${COST_DELAY}ms (expected <=20), naptime: ${NAPTIME}s (expected <=60)"
    echo "  Restore via:"
    echo "  aws rds modify-db-parameter-group --db-parameter-group-name ${T8_PARAMETER_GROUP} \\"
    echo "    --parameters ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=20,ApplyMethod=immediate \\"
    echo "    ParameterName=autovacuum_naptime,ParameterValue=60,ApplyMethod=immediate \\"
    echo "    --region ${T8_REGION}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_warn "T8_PARAMETER_GROUP not set - skipping parameter check."
fi

# -----------------------------------------------------------------------
# Check 5: Wraparound monitoring query produces results
# -----------------------------------------------------------------------
log_step "Check 5: Wraparound monitoring query runs successfully"

XID_RESULT=$(run_sql "
  SELECT datname, age(datfrozenxid) AS xid_age
  FROM pg_database
  ORDER BY xid_age DESC
  LIMIT 1;" 2>/dev/null)

if [[ -n "${XID_RESULT}" ]]; then
  validate_check "Wraparound monitoring query functional" "pass" \
    "Result: ${XID_RESULT}"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Wraparound monitoring query failed" "fail"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  log_info "Cleaning up scenario artifacts..."
  run_sql "DROP TABLE IF EXISTS t8_high_churn_events;" 2>/dev/null || true
  rm -f "${SCRIPT_DIR}/.inject-state"
  log_info "Cleanup complete."
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "==========================================="
echo "VALIDATION SUMMARY"
echo "==========================================="
echo "Checks passed:  ${PASS_COUNT}"
echo "Checks failed:  ${FAIL_COUNT}"
echo ""

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  log_success "Scenario 04 RESOLVED: All checks pass."
  echo ""
  echo "What you demonstrated:"
  echo "  - Identified high dead tuple ratio and disabled autovacuum"
  echo "  - Re-enabled autovacuum on the affected table"
  echo "  - Ran VACUUM FREEZE to reclaim dead tuples"
  echo "  - Restored autovacuum parameters to healthy values"
  echo "  - Verified the wraparound monitoring query works"
else
  log_fail "Scenario 04 NOT FULLY RESOLVED: ${FAIL_COUNT} check(s) still failing."
fi
echo ""
