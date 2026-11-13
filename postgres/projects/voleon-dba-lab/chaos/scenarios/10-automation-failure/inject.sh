#!/usr/bin/env bash
###############################################################################
# Scenario 10: Automation Failure
# inject.sh - Broken Ansible inventory + bad pg_hba.conf blocks replication
###############################################################################
# What breaks: Ansible cannot reach pg-primary (wrong IP in inventory).
#              Replication is broken (pg_hba.conf rejects replicator).
# Your job:    Fix the Ansible inventory, fix pg_hba.conf, reload PG,
#              verify replication and Ansible connectivity.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

echo "==========================================="
echo " CHAOS INJECTION: Automation Failure"
echo "==========================================="
echo ""

# ---- 1. Break the Ansible inventory on pg-ops ----
echo "[1/2] Corrupting Ansible inventory on pg-ops (${OPS_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} bash -s <<'REMOTE'
  INVENTORY="$HOME/ansible/inventory/hosts.yml"

  if [ ! -f "${INVENTORY}" ]; then
    echo "  [ERROR] Inventory file not found at ${INVENTORY}"
    exit 1
  fi

  # Save original if not already saved
  if [ ! -f "${INVENTORY}.chaos_backup" ]; then
    cp "${INVENTORY}" "${INVENTORY}.chaos_backup"
    echo "  [SAVED] Original inventory backed up to ${INVENTORY}.chaos_backup"
  else
    echo "  [INFO] Backup already exists - using existing backup"
  fi

  # Replace pg-primary's IP with a wrong IP (10.99.99.99)
  if grep -q "10.99.99.99" "${INVENTORY}"; then
    echo "  [SKIP] Inventory already has wrong IP - idempotent skip"
  else
    sed -i 's/ansible_host: 172\.31\.19\.86/ansible_host: 10.99.99.99/' "${INVENTORY}"
    echo "  [DONE] Changed pg-primary ansible_host to 10.99.99.99"
  fi
REMOTE

echo "  [OK] Ansible inventory corrupted."
echo ""

# ---- 2. Push bad pg_hba.conf that blocks replication ----
echo "[2/2] Injecting bad pg_hba.conf rule on pg-primary (${PRIMARY_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} bash -s <<REMOTE
  PG_HBA="/var/lib/pgsql/17/data/pg_hba.conf"

  # Save original if not already saved
  if [ ! -f "\${PG_HBA}.chaos_backup" ]; then
    sudo cp "\${PG_HBA}" "\${PG_HBA}.chaos_backup"
    sudo chown postgres:postgres "\${PG_HBA}.chaos_backup"
    echo "  [SAVED] Original pg_hba.conf backed up"
  else
    echo "  [INFO] Backup already exists - using existing backup"
  fi

  # Add a reject rule for the replicator user from the replica IP
  # Place it BEFORE any existing replication allow rules
  if sudo grep -q "# CHAOS: block replication" "\${PG_HBA}"; then
    echo "  [SKIP] Reject rule already present - idempotent skip"
  else
    # Insert the reject rule right after the TYPE header line
    sudo sed -i '/^# TYPE/a\# CHAOS: block replication\nhost    replication     replicator      ${REPLICA_PRIVATE}/32       reject' "\${PG_HBA}"
    echo "  [DONE] Added reject rule for replicator from ${REPLICA_PRIVATE}"
  fi

  # Reload PG to apply the new pg_hba.conf
  sudo systemctl reload postgresql-17
  echo "  [DONE] PostgreSQL reloaded with bad pg_hba.conf"
REMOTE

echo "  [OK] Bad pg_hba.conf applied."
echo ""

# ---- Wait briefly for replication to break ----
echo "[...] Waiting 10 seconds for replication to disconnect..."
sleep 10

echo ""
echo "==========================================="
echo " CHAOS INJECTED SUCCESSFULLY"
echo "==========================================="
echo ""
echo " Injected issues:"
echo "   1. pg-ops: Ansible inventory has wrong IP for pg-primary (10.99.99.99)"
echo "      Original saved as ~/ansible/inventory/hosts.yml.chaos_backup"
echo "   2. pg-primary: pg_hba.conf rejects replication from replica (${REPLICA_PRIVATE})"
echo "      Original saved as pg_hba.conf.chaos_backup"
echo ""
echo " Symptoms to expect:"
echo "   - Ansible cannot reach pg-primary (connection timeout)"
echo "   - Replication lag climbing, then replica disconnects"
echo "   - pg_stat_replication on primary shows no active replicas"
echo ""
