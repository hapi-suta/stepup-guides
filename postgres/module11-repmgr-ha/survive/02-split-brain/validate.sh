#!/usr/bin/env bash
# Scenario 02 - Validate: Confirm split-brain was prevented and cluster recovered.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-02-state.env"

header "Validate - Scenario 02: Split-Brain (Network Partition)"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. Network partition is resolved (iptables flushed on original primary)
IPTABLES_COUNT=$(remote_exec "$ORIGINAL_PRIMARY" \
  "sudo iptables -L OUTPUT -n 2>/dev/null | grep -c DROP || echo 0" 2>/dev/null | tr -d '[:space:]')
[[ -z "$IPTABLES_COUNT" ]] && IPTABLES_COUNT=999
check "iptables rules cleared on old primary (DROP rules: $IPTABLES_COUNT)" \
  test "$IPTABLES_COUNT" -eq 0

# 3. Exactly one primary exists across all data nodes
PRIMARY_COUNT=0
for node in "$NODE1" "$NODE2" "$NODE3"; do
  result=$(remote_exec "$node" \
    "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null) || continue
  if [[ "$result" == "f" ]]; then
    PRIMARY_COUNT=$((PRIMARY_COUNT + 1))
  fi
done
check "Exactly 1 primary exists (found: $PRIMARY_COUNT)" \
  test "$PRIMARY_COUNT" -eq 1

# 4. A primary is reachable
NEW_PRIMARY=$(get_primary)
check "A primary is reachable" test -n "$NEW_PRIMARY"

# 5. Writes succeed on the primary
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('split_brain_validate','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary" test -n "$WRITE_OK"

# 6. Original primary is now a standby
ORIG_RECOVERY=$(remote_exec "$ORIGINAL_PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "")
check "Original primary ($ORIGINAL_PRIMARY) is now standby (in_recovery: $ORIG_RECOVERY)" \
  test "$ORIG_RECOVERY" = "t"

# 7. At least 2 standbys streaming
STREAMING_COUNT=$(pg_exec "$NEW_PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 8. Data integrity - employee count >= 10000
ROW_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= 10000 rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge 10000

# 9. Cluster crosscheck - all nodes reachable
CROSSCHECK_FAILS=$(repmgr_exec "$NEW_PRIMARY" "cluster crosscheck" 2>/dev/null | grep -c 'x' || true)
CROSSCHECK_FAILS=${CROSSCHECK_FAILS:-0}
CROSSCHECK_FAILS=$(echo "$CROSSCHECK_FAILS" | tr -d '[:space:]')
check "Cluster crosscheck has no failures (x count: $CROSSCHECK_FAILS)" \
  test "$CROSSCHECK_FAILS" -eq 0

# 10. repmgrd running on all data nodes
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
