#!/usr/bin/env bash
###############################################################################
# Scenario 11: Monitoring Incident
# inject.sh - Broken Prometheus scrape config, stopped node_exporter,
#             and a corrupted alert rule file
###############################################################################
# What breaks: Grafana shows no postgres metrics, pg-primary node_exporter
#              target is DOWN, alert rules fail to evaluate.
# Your job:    Fix prometheus.yml port, start node_exporter, remove invalid
#              rule, reload Prometheus, verify all targets UP.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

echo "==========================================="
echo " CHAOS INJECTION: Monitoring Incident"
echo "==========================================="
echo ""

# ---- 1. Break Prometheus scrape config on pg-ops ----
echo "[1/3] Corrupting prometheus.yml on pg-ops (${OPS_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} bash -s <<'REMOTE'
  PROM_CONF="/opt/prometheus/prometheus.yml"

  if [ ! -f "${PROM_CONF}" ]; then
    echo "  [ERROR] prometheus.yml not found at ${PROM_CONF}"
    exit 1
  fi

  # Save original if not already backed up
  if [ ! -f "${PROM_CONF}.chaos_backup" ]; then
    sudo cp "${PROM_CONF}" "${PROM_CONF}.chaos_backup"
    echo "  [SAVED] Original prometheus.yml backed up to ${PROM_CONF}.chaos_backup"
  else
    echo "  [INFO] Backup already exists - using existing backup"
  fi

  # Check if already corrupted (9187 already changed to 9999)
  if sudo grep -q ":9999" "${PROM_CONF}"; then
    echo "  [SKIP] Wrong port 9999 already present - idempotent skip"
  else
    # Change postgres_exporter target port from 9187 to 9999
    sudo sed -i 's/:9187/:9999/g' "${PROM_CONF}"
    echo "  [DONE] Changed postgres_exporter target port from 9187 to 9999"
  fi
REMOTE

echo "  [OK] prometheus.yml corrupted."
echo ""

# ---- 2. Stop node_exporter on pg-primary ----
echo "[2/3] Stopping node_exporter on pg-primary (${PRIMARY_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} bash -s <<'REMOTE'
  # Record pre-chaos state and stop if currently running
  if sudo systemctl is-active --quiet node_exporter; then
    echo "  [INFO] node_exporter is running - stopping it now"
    sudo systemctl stop node_exporter
    echo "  [DONE] node_exporter stopped"
    # Leave a marker so validate.sh and runbook can verify it was running before chaos
    echo "was_running=true" | sudo tee /tmp/.chaos_node_exporter_state > /dev/null
  else
    echo "  [SKIP] node_exporter is already stopped - idempotent skip"
    if [ ! -f /tmp/.chaos_node_exporter_state ]; then
      echo "was_running=false" | sudo tee /tmp/.chaos_node_exporter_state > /dev/null
    fi
  fi
REMOTE

echo "  [OK] node_exporter stopped on pg-primary."
echo ""

# ---- 3. Corrupt an alert rule on pg-ops ----
echo "[3/3] Injecting invalid alert rule into alert_rules.yml on pg-ops (${OPS_HOST})..."

ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} bash -s <<'REMOTE'
  RULES_FILE="/opt/prometheus/alert_rules.yml"

  if [ ! -f "${RULES_FILE}" ]; then
    echo "  [ERROR] alert_rules.yml not found at ${RULES_FILE}"
    exit 1
  fi

  # Save original if not already backed up
  if [ ! -f "${RULES_FILE}.chaos_backup" ]; then
    sudo cp "${RULES_FILE}" "${RULES_FILE}.chaos_backup"
    echo "  [SAVED] Original alert_rules.yml backed up to ${RULES_FILE}.chaos_backup"
  else
    echo "  [INFO] Backup already exists - using existing backup"
  fi

  # Check if the invalid rule is already present
  if sudo grep -q "# CHAOS: invalid rule" "${RULES_FILE}"; then
    echo "  [SKIP] Invalid rule already present - idempotent skip"
  else
    # Append a syntactically invalid rule block - missing the required 'expr' field.
    # Prometheus will reject the entire rule group file when it encounters this.
    sudo tee -a "${RULES_FILE}" > /dev/null <<'INVALIDRULE'

  # CHAOS: invalid rule - missing required 'expr' field
  - alert: ChaosInvalidRule
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "This rule is intentionally broken for chaos testing"
INVALIDRULE
    echo "  [DONE] Appended syntactically invalid rule (missing expr field)"
  fi
REMOTE

echo "  [OK] Invalid alert rule injected into alert_rules.yml."
echo ""

# ---- Reload Prometheus to apply changes (expect failure or partial load) ----
echo "[...] Reloading Prometheus on pg-ops (${OPS_HOST}) to apply broken config..."

ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} bash -s <<'REMOTE'
  # Try the lifecycle API reload first (requires --web.enable-lifecycle on Prometheus)
  RELOAD_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    -X POST http://localhost:9090/-/reload 2>/dev/null || echo "000")

  if [ "${RELOAD_HTTP}" = "200" ]; then
    echo "  [INFO] Prometheus reload API returned 200 - config applied (errors may appear in UI)"
  elif [ "${RELOAD_HTTP}" = "000" ]; then
    echo "  [INFO] Prometheus lifecycle API not reachable - trying systemctl"
    sudo systemctl reload prometheus 2>/dev/null || \
      sudo systemctl restart prometheus 2>/dev/null || \
      echo "  [WARN] systemctl reload/restart also failed - Prometheus may be running stale config"
  else
    echo "  [INFO] Prometheus reload returned HTTP ${RELOAD_HTTP} - bad config likely rejected"
  fi
REMOTE

echo "  [OK] Prometheus reload attempted."
echo ""

echo "==========================================="
echo " CHAOS INJECTED SUCCESSFULLY"
echo "==========================================="
echo ""
echo " Injected issues:"
echo "   1. pg-ops: prometheus.yml has wrong postgres_exporter port (9999 instead of 9187)"
echo "      Original saved as /opt/prometheus/prometheus.yml.chaos_backup"
echo "   2. pg-primary: node_exporter service is stopped"
echo "      Pre-chaos state saved at /tmp/.chaos_node_exporter_state"
echo "   3. pg-ops: alert_rules.yml has an invalid rule (missing expr field)"
echo "      Original saved as /opt/prometheus/alert_rules.yml.chaos_backup"
echo ""
echo " Symptoms to expect:"
echo "   - Grafana shows no postgres metrics (postgres_exporter targets scraping wrong port)"
echo "   - Prometheus targets page shows pg-primary node_exporter as DOWN"
echo "   - Prometheus logs or /api/v1/rules shows rule evaluation errors"
echo "   - Alerts that depend on the corrupted rule group will not fire"
echo ""
