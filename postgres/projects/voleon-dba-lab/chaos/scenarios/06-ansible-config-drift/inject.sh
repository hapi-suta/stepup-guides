#!/usr/bin/env bash
# =============================================================================
# Scenario 06: Ansible Config Drift
# inject.sh - Push a broken pg_hba.conf that breaks replication
# =============================================================================
# What breaks: The replication CIDR in pg_hba.conf is changed to a wrong
#              subnet. On the next pg_hba reload, replication connections
#              from the replica are rejected. Streaming replication stops.
# Your job:    Detect config drift with Ansible, identify the bad entry,
#              restore the correct pg_hba.conf, reload, verify replication.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

PG_HBA="${PG_DATA}/pg_hba.conf"
BACKUP_SUFFIX=".chaos06_backup"

log_info "Scenario 06: Ansible Config Drift - Bad pg_hba.conf"
log_info "Target: ${PG_HBA} on ${PRIMARY_HOST}"
echo ""

# Confirm connectivity
log_info "Checking SSH and PostgreSQL connectivity..."
if ! check_ssh "$PRIMARY_HOST"; then
    log_error "Cannot SSH into primary (${PRIMARY_HOST})"
    exit 1
fi
if ! check_pg "$PRIMARY_HOST"; then
    log_error "PostgreSQL is not responding on ${PRIMARY_HOST}"
    exit 1
fi
log_success "Primary is reachable"

# Backup current pg_hba.conf before breaking it
log_info "Backing up current pg_hba.conf to ${PG_HBA}${BACKUP_SUFFIX}..."
ssh_primary "sudo cp ${PG_HBA} ${PG_HBA}${BACKUP_SUFFIX}"
log_success "Backup saved"

# Show current replication rule
log_info "Current replication entries in pg_hba.conf:"
ssh_primary "sudo grep -n 'replication' ${PG_HBA}" 2>/dev/null || log_warn "No replication entries found"
echo ""

# Inject bad pg_hba.conf:
# Change the replication line CIDR to a wrong subnet (10.99.0.0/16)
# that does not contain the replica's IP.
# Handles both 172.31.0.0/16 and 0.0.0.0/0 formats.
log_warn "Injecting bad pg_hba.conf - changing replication CIDR to wrong subnet..."
ssh_primary "sudo sed -i '/replication.*replicator/s|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}|10.99.0.0/16|' ${PG_HBA}"

# Also add a suspicious TRUST line for 0.0.0.0/0 to simulate a worse drift scenario
ssh_primary "echo 'host    all             all             0.0.0.0/0               trust    # DRIFT: added by unknown process' | sudo tee -a ${PG_HBA} > /dev/null"

# Reload PostgreSQL to apply the bad config
log_warn "Reloading PostgreSQL to apply the broken configuration..."
ssh_primary "sudo systemctl reload postgresql-${PG_VERSION}"
sleep 3

# Verify replication is now broken
log_info "Checking replication status after bad config reload..."
REPL_ACTIVE=$(ssh_primary "sudo -u postgres ${PG_BIN}/psql -t \
    -c \"SELECT COUNT(*) FROM pg_stat_replication WHERE state = 'streaming';\" \
    2>/dev/null | tr -d '[:space:]'" 2>/dev/null || echo "0")

echo ""
if [[ "$REPL_ACTIVE" == "0" ]]; then
    log_success "Replication is broken - replica cannot connect (injection successful)"
else
    log_warn "Replication still shows ${REPL_ACTIVE} streaming replica(s)."
    log_warn "The replica may still be using an existing connection."
    log_warn "It will break on next reconnect attempt."
fi

echo ""
echo "  pg_hba.conf on ${PRIMARY_HOST} has been corrupted:"
echo "    - Replication CIDR changed to 10.99.0.0/16 (wrong subnet)"
echo "    - Suspicious TRUST entry added for 0.0.0.0/0"
echo ""
echo "  Your tasks:"
echo "    1. Run Ansible to detect config drift:"
echo "       ansible-playbook -i inventory/hosts.ini playbooks/pg-config.yml --check"
echo "    2. Identify the bad entries in ${PG_HBA}"
echo "    3. Restore from backup: sudo cp ${PG_HBA}${BACKUP_SUFFIX} ${PG_HBA}"
echo "       OR manually fix the replication CIDR back to the correct subnet"
echo "    4. Remove the suspicious TRUST line"
echo "    5. Reload PostgreSQL: sudo systemctl reload postgresql-${PG_VERSION}"
echo "    6. Confirm replication is streaming again"
echo ""
echo "  When done: ./chaos.sh validate 06-ansible-config-drift"
