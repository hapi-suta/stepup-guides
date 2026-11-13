#!/usr/bin/env bash
# =============================================================================
# Scenario 01: Primary Failover
# inject.sh - Stop PostgreSQL on the primary node
# =============================================================================
# What breaks: All writes fail. PgBouncer connections start erroring.
#              The replica is healthy but read-only.
# Your job:    Promote the replica, redirect PgBouncer, verify writes work.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

log_info "Scenario 01: Primary Failover"
log_info "Target: ${PRIMARY_HOST} (pg-primary)"
echo ""

# Confirm we can reach the primary before breaking it
log_info "Checking SSH connectivity to primary..."
if ! check_ssh "$PRIMARY_HOST"; then
    log_error "Cannot SSH into primary (${PRIMARY_HOST}). Is the lab up?"
    exit 1
fi
log_success "Primary is reachable via SSH"

# Confirm PostgreSQL is currently running
log_info "Confirming PostgreSQL is currently UP on primary..."
if ! check_pg "$PRIMARY_HOST"; then
    log_warn "PostgreSQL on primary is already DOWN. Was it stopped earlier?"
    log_warn "Proceeding anyway - validate.sh will still score your recovery."
    exit 0
fi
log_success "PostgreSQL is running on primary - proceeding with injection"

echo ""
log_warn "Stopping postgresql-17 on ${PRIMARY_HOST}..."

ssh_primary "sudo systemctl stop postgresql-17"

# Allow a moment for the service to fully stop
sleep 3

# Verify it actually stopped
if check_pg "$PRIMARY_HOST" 2>/dev/null; then
    log_error "PostgreSQL is still responding on primary after stop. Injection may have failed."
    exit 1
fi

echo ""
log_success "PostgreSQL is DOWN on ${PRIMARY_HOST}"
echo ""
echo "  The primary (${PRIMARY_HOST}) is no longer accepting connections."
echo "  PgBouncer on port ${PGBOUNCER_PORT} will start returning errors."
echo "  The replica (${REPLICA_HOST}) is healthy but read-only."
echo ""
echo "  Your tasks:"
echo "    1. Confirm the primary is truly down (not just slow)"
echo "    2. Check the replica is healthy"
echo "    3. Promote the replica using pg_promote() or pg_ctl promote"
echo "    4. Update PgBouncer to point to the new primary"
echo "    5. Verify writes succeed through PgBouncer"
echo ""
echo "  Runbook: cbus/survive/01-primary-failover/runbook.md"
echo ""
echo "  When done: ./chaos.sh validate 01-primary-failover"
