#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 03: Application Bug Causing Connection Storm
#
# What this script does:
#   1. Reduces max_connections to a low value (50) to simulate a misconfigured
#      or under-provisioned database relative to connection demand.
#   2. Opens many idle-in-transaction connections to fill up the connection slots.
#   3. Leaves the database unable to accept new connections.
#
# After injection, the database will report "too many clients already" to any
# new connection attempt. Your task is to diagnose and restore service.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 03: Connection Storm Injection"
print_survive_warning "Application Bug - Connection Storm"

t8_validate_config || exit 1
check_prerequisites || exit 1
check_aws_auth || exit 1
check_db_connectivity || {
  log_error "Cannot connect to database. Set T8_DB_HOST and verify connectivity."
  exit 1
}

record_start

# -----------------------------------------------------------------------
# Step 1: Save current max_connections
# -----------------------------------------------------------------------
log_step "Step 1: Saving current max_connections setting..."

CURRENT_MAX_CONN=$(run_sql "SHOW max_connections;" | tr -d ' ')
log_info "Current max_connections: ${CURRENT_MAX_CONN}"

CURRENT_PARAM_VALUE=$(get_parameter_value "max_connections" 2>/dev/null || echo "FORMULA")
log_info "Parameter group max_connections: ${CURRENT_PARAM_VALUE}"

# -----------------------------------------------------------------------
# Step 2: Reduce max_connections to create the storm condition
# -----------------------------------------------------------------------
log_step "Step 2: Reducing max_connections to 50 (requires restart)..."

if [[ -n "${T8_PARAMETER_GROUP}" ]]; then
  aws rds modify-db-parameter-group \
    --db-parameter-group-name "${T8_PARAMETER_GROUP}" \
    --parameters ParameterName=max_connections,ParameterValue=50,ApplyMethod=pending-reboot \
    --region "${T8_REGION}"

  log_info "max_connections set to 50 (pending reboot)."
  log_warn "Rebooting instance to apply the change..."

  aws rds reboot-db-instance \
    --db-instance-identifier "${T8_INSTANCE_ID}" \
    --region "${T8_REGION}"

  log_info "Waiting for instance to become available after reboot..."
  wait_for_instance_available "${T8_INSTANCE_ID}" 300
else
  log_warn "T8_PARAMETER_GROUP not set. Skipping max_connections reduction."
  log_warn "The connection flood below will still run."
fi

# -----------------------------------------------------------------------
# Step 3: Open many long-lived idle-in-transaction connections
# -----------------------------------------------------------------------
log_step "Step 3: Opening idle-in-transaction connections to flood connection slots..."

# Open background psql processes that start a transaction but do not commit
CONN_PIDS=()
for i in $(seq 1 40); do
  psql \
    --host="${T8_DB_HOST}" \
    --port="${T8_DB_PORT}" \
    --username="${T8_DB_USER}" \
    --dbname="${T8_DB_NAME}" \
    --command="BEGIN; SELECT pg_sleep(300);" \
    --no-psqlrc \
    --quiet &>/dev/null &
  CONN_PIDS+=($!)
done

log_info "Opened ${#CONN_PIDS[@]} idle-in-transaction connections."
sleep 5

# Verify the connections are visible
IDLE_IN_TX=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction';" | tr -d ' ')
log_info "Idle-in-transaction connections visible in pg_stat_activity: ${IDLE_IN_TX}"

TOTAL_CONN=$(run_sql "SELECT count(*) FROM pg_stat_activity;" | tr -d ' ')
log_info "Total connections: ${TOTAL_CONN}"

# -----------------------------------------------------------------------
# Step 4: Describe the scenario
# -----------------------------------------------------------------------
echo ""
log_warn "========================================================"
log_warn "INJECTION COMPLETE"
log_warn "========================================================"
echo ""
echo "What has been injected:"
echo "  1. max_connections reduced to 50 (pending reboot applied)"
echo "  2. 40 idle-in-transaction connections opened (holding slots)"
echo "  3. Remaining available connections: approximately $((50 - TOTAL_CONN))"
echo ""
echo "Your scenario:"
echo "  It is 3:15 AM. PagerDuty fires:"
echo "  'CRITICAL: DatabaseConnections at 100% of max_connections'"
echo "  'Application errors: FATAL: sorry, too many clients already'"
echo "  'Error rate: 85% of API requests failing'"
echo ""
echo "  The last deployment was 2 hours ago."
echo "  You have one reserved connection slot (superuser)."
echo ""
echo "  Your tasks:"
echo "    a. Confirm the root cause (connection exhaustion vs something else)"
echo "    b. Restore service without restarting the database (application cannot tolerate a restart)"
echo "    c. Identify how this happened (deployment? config change?)"
echo "    d. Implement a fix that prevents recurrence"
echo ""
echo "Hint: You have superuser access. Use it carefully."
echo ""

# Save state
cat > "${SCRIPT_DIR}/.inject-state" << EOF
INJECT_TIME=$(date +%s)
ORIGINAL_MAX_CONN=${CURRENT_MAX_CONN}
CONN_PIDS=(${CONN_PIDS[*]})
EOF

log_info "Inject state saved. Background connection processes are running."
log_warn "Run validate.sh to clean up when done."
