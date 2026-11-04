#!/usr/bin/env bash
###############################################################################
# Scenario 11: Monitoring Incident
# validate.sh - Verify Prometheus config, alert rules, and node_exporter fixed
###############################################################################
# Pass criteria:
#   1. prometheus.yml has correct postgres_exporter port (9187, not 9999)
#   2. alert_rules.yml has no invalid chaos rules
#   3. node_exporter is running on pg-primary
#   4. All Prometheus targets are UP
#   5. Prometheus rules loaded without errors
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

PASS=0
FAIL=0
TOTAL=5

echo "==========================================="
echo " VALIDATION: Monitoring Incident"
echo "==========================================="
echo ""

# Helper function
check() {
  local description="$1"
  local result="$2"  # 0 = pass, non-zero = fail
  local detail="$3"

  if [ "$result" -eq 0 ]; then
    echo "  [PASS] ${description}"
    [ -n "$detail" ] && echo "         ${detail}"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] ${description}"
    [ -n "$detail" ] && echo "         ${detail}"
    FAIL=$((FAIL + 1))
  fi
}

# ---- Check 1: prometheus.yml has correct port (9187, not 9999) ----
echo "[1/5] Checking prometheus.yml on pg-ops (${OPS_HOST})..."

WRONG_PORT=$(ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} \
  "sudo grep -c ':9999' /opt/prometheus/prometheus.yml 2>/dev/null || echo '0'" 2>/dev/null)
WRONG_PORT=$(echo "${WRONG_PORT}" | tail -1 | tr -d '[:space:]')

if [ "${WRONG_PORT}" -eq 0 ] 2>/dev/null; then
  check "prometheus.yml has correct postgres_exporter port" 0 "No :9999 references found"
else
  check "prometheus.yml has correct postgres_exporter port" 1 "Found ${WRONG_PORT} occurrence(s) of :9999 - change to :9187 and reload Prometheus"
fi
echo ""

# ---- Check 2: alert_rules.yml has no invalid chaos rules ----
echo "[2/5] Checking alert_rules.yml on pg-ops (${OPS_HOST})..."

CHAOS_RULE=$(ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} \
  "sudo grep -c 'CHAOS: invalid rule' /opt/prometheus/alert_rules.yml 2>/dev/null || echo '0'" 2>/dev/null)
CHAOS_RULE=$(echo "${CHAOS_RULE}" | tail -1 | tr -d '[:space:]')

if [ "${CHAOS_RULE}" -eq 0 ] 2>/dev/null; then
  check "alert_rules.yml has no invalid chaos rules" 0 "No chaos rules found"
else
  check "alert_rules.yml has no invalid chaos rules" 1 "Found chaos-injected invalid rule - remove it and reload Prometheus"
fi
echo ""

# ---- Check 3: node_exporter is running on pg-primary ----
echo "[3/5] Checking node_exporter on pg-primary (${PRIMARY_HOST})..."

NODE_STATUS=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "systemctl is-active node_exporter 2>/dev/null" 2>/dev/null || true)
NODE_STATUS=$(echo "${NODE_STATUS}" | tail -1 | tr -d '[:space:]')
[ -z "${NODE_STATUS}" ] && NODE_STATUS="inactive"

if [ "${NODE_STATUS}" = "active" ]; then
  check "node_exporter is running on pg-primary" 0 "Service status: active"
else
  check "node_exporter is running on pg-primary" 1 "Service status: ${NODE_STATUS} - start with: sudo systemctl start node_exporter"
fi
echo ""

# ---- Check 4: All Prometheus targets are UP (parse on remote side) ----
echo "[4/5] Checking Prometheus targets on pg-ops (${OPS_HOST})..."

TARGET_SUMMARY=$(ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} 'bash -c "
  RAW=\$(curl -s --max-time 10 http://localhost:9090/api/v1/targets 2>/dev/null)
  if [ -z \"\$RAW\" ]; then echo \"ERROR 0 0\"; exit; fi
  UP=\$(echo \"\$RAW\" | grep -o \"\\\"health\\\":\\\"up\\\"\" | wc -l)
  DOWN=\$(echo \"\$RAW\" | grep -o \"\\\"health\\\":\\\"down\\\"\" | wc -l)
  echo \"OK \$UP \$DOWN\"
"' 2>/dev/null || echo "ERROR 0 0")

TARGET_STATUS=$(echo "${TARGET_SUMMARY}" | awk '{print $1}')
UP_T=$(echo "${TARGET_SUMMARY}" | awk '{print $2}')
DOWN_T=$(echo "${TARGET_SUMMARY}" | awk '{print $3}')
TOTAL_T=$((UP_T + DOWN_T))

if [ "${TARGET_STATUS}" = "OK" ] && [ "${DOWN_T}" -eq 0 ] && [ "${TOTAL_T}" -ge 7 ]; then
  check "All Prometheus targets are UP" 0 "${UP_T}/${TOTAL_T} targets healthy"
elif [ "${TARGET_STATUS}" = "OK" ]; then
  check "All Prometheus targets are UP" 1 "${UP_T}/${TOTAL_T} UP, ${DOWN_T} DOWN - fix scrape config and exporter(s)"
else
  check "All Prometheus targets are UP" 1 "Cannot reach Prometheus API - is Prometheus running?"
fi
echo ""

# ---- Check 5: Prometheus rules loaded successfully (parse on remote side) ----
echo "[5/5] Checking Prometheus rules on pg-ops (${OPS_HOST})..."

RULE_COUNT=$(ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} 'bash -c "
  RAW=\$(curl -s --max-time 10 http://localhost:9090/api/v1/rules 2>/dev/null)
  if [ -z \"\$RAW\" ]; then echo 0; exit; fi
  echo \"\$RAW\" | grep -o \"\\\"name\\\":\\\"[^\\\"]*\\\"\" | wc -l
"' 2>/dev/null || echo "0")
RULE_COUNT=$(echo "${RULE_COUNT}" | tail -1 | tr -d '[:space:]')

if [ "${RULE_COUNT}" -gt 0 ] 2>/dev/null; then
  check "Prometheus rules loaded without errors" 0 "${RULE_COUNT} rules loaded"
else
  check "Prometheus rules loaded without errors" 1 "No rules found - check alert_rules.yml syntax or if Prometheus is running"
fi
echo ""

# ---- Summary ----
echo "==========================================="
echo " RESULTS: ${PASS}/${TOTAL} checks passed"
echo "==========================================="
echo ""

if [ "${PASS}" -eq "${TOTAL}" ]; then
  echo " ALL CHECKS PASSED - Monitoring incident resolved!"
  echo ""
  exit 0
else
  echo " ${FAIL} check(s) failed - issues remain."
  echo " Review the failures above and re-run this script."
  echo ""
  exit 1
fi
