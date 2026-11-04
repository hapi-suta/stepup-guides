#!/usr/bin/env bash
###############################################################################
# Scenario 09: Linux System Crisis
# inject.sh - /tmp exhaustion + aggressive swapping + network degradation
###############################################################################
# What breaks: Temp-heavy queries fail, PG response times degrade from
#              aggressive swapping, replication lag spikes from packet loss.
# Your job:    Clear /tmp, restore swappiness, remove iptables rule,
#              verify PG and replication are healthy.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

echo "==========================================="
echo " CHAOS INJECTION: Linux System Crisis"
echo "==========================================="
echo ""

# ---- 1. Fill /tmp to ~95% on pg-primary ----
echo "[1/3] Filling /tmp to ~95% on pg-primary (${PRIMARY_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} bash -s <<'REMOTE'
  # Create a 2GB file in /tmp to simulate temp space exhaustion
  # (We use a fixed size to avoid filling the root volume dangerously)
  FILL_MB=2048

  if [ -f /tmp/.chaos_tmpfill ]; then
    echo "  [SKIP] /tmp/.chaos_tmpfill already exists - idempotent skip"
  else
    dd if=/dev/zero of=/tmp/.chaos_tmpfill bs=1M count=${FILL_MB} status=none 2>/dev/null || true
    echo "  [DONE] Wrote ${FILL_MB} MB to /tmp/.chaos_tmpfill"
  fi
REMOTE

echo "  [OK] /tmp fill complete."
echo ""

# ---- 2. Set vm.swappiness to 100 on pg-primary ----
echo "[2/3] Setting vm.swappiness=100 on pg-primary (${PRIMARY_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} bash -s <<'REMOTE'
  CURRENT=$(cat /proc/sys/vm/swappiness)
  # Save original value for restore reference
  if [ ! -f /tmp/.chaos_swappiness_orig ]; then
    echo "${CURRENT}" > /tmp/.chaos_swappiness_orig
    echo "  [SAVED] Original swappiness=${CURRENT}"
  else
    echo "  [INFO] Original value already saved: $(cat /tmp/.chaos_swappiness_orig)"
  fi

  if [ "${CURRENT}" -eq 100 ]; then
    echo "  [SKIP] swappiness is already 100 - idempotent skip"
  else
    sudo sysctl -w vm.swappiness=100 >/dev/null
    echo "  [DONE] vm.swappiness set to 100 (was ${CURRENT})"
  fi
REMOTE

echo "  [OK] Swappiness change complete."
echo ""

# ---- 3. Drop 50% of packets between primary and replica ----
echo "[3/3] Adding iptables rule to drop 50% of packets to replica (${REPLICA_PRIVATE})..."

ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} bash -s <<REMOTE
  # Check if rule already exists
  if sudo iptables -C OUTPUT -d ${REPLICA_PRIVATE} -m statistic --mode random --probability 0.5 -j DROP 2>/dev/null; then
    echo "  [SKIP] iptables DROP rule already exists - idempotent skip"
  else
    sudo iptables -A OUTPUT -d ${REPLICA_PRIVATE} -m statistic --mode random --probability 0.5 -j DROP
    echo "  [DONE] 50% packet drop rule added for traffic to ${REPLICA_PRIVATE}"
  fi
REMOTE

echo "  [OK] Network degradation injected."
echo ""
echo "==========================================="
echo " CHAOS INJECTED SUCCESSFULLY"
echo "==========================================="
echo ""
echo " Injected on pg-primary (${PRIMARY_HOST}):"
echo "   1. /tmp filled to ~95% (/tmp/.chaos_tmpfill)"
echo "   2. vm.swappiness set to 100"
echo "   3. 50% packet drop to replica (${REPLICA_PRIVATE})"
echo ""
echo " Symptoms to expect:"
echo "   - Large sort/hash queries may fail (no temp space)"
echo "   - Increasing swap usage, degraded PG response times"
echo "   - Replication lag climbing, possible WAL sender timeouts"
echo ""
