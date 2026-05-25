#!/usr/bin/env bash
# Scenario 02 - Split-Brain: Network partition between primary and standbys.
# Simulate by blocking replication traffic with iptables on the primary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-02-state.env"

header "Scenario 02 - Split-Brain (Network Partition)"

# ---------- discover current primary ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
FIRST_STANDBY=$(echo "$STANDBYS" | head -1)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"

# ---------- capture pre-partition state ----------
step "Capturing pre-partition state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
STREAMING=$(pg_exec "$PRIMARY" "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'")

cat > "$STATE_FILE" <<EOF
SCENARIO="02-split-brain"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
FIRST_STANDBY="$FIRST_STANDBY"
PRE_PARTITION_TIMELINE="$TIMELINE"
PRE_PARTITION_STREAMING="$STREAMING"
EOF

info "State saved to $STATE_FILE"

# ---------- create network partition ----------
# Block PostgreSQL traffic from the primary to all standbys and witness.
# This simulates the primary becoming isolated.
step "Creating network partition - isolating primary ($PRIMARY)..."

# Ensure iptables is installed (CentOS 9 minimal may not have it)
remote_exec "$PRIMARY" "sudo dnf install -y iptables-nft >/dev/null 2>&1 || true"

# Get private IPs from /etc/hosts on the primary (nodes communicate via private network)
PRIVATE_IPS=$(remote_exec "$PRIMARY" "grep pg-repmgr /etc/hosts | awk '{print \$1}'" 2>/dev/null)
PRIMARY_PRIV=$(remote_exec "$PRIMARY" "hostname -I | awk '{print \$1}'" 2>/dev/null)

for priv_ip in $PRIVATE_IPS; do
  if [[ "$priv_ip" != "$PRIMARY_PRIV" ]]; then
    remote_exec "$PRIMARY" \
      "sudo iptables -A OUTPUT -d $priv_ip -p tcp --dport 5432 -j DROP" 2>/dev/null || true
    remote_exec "$PRIMARY" \
      "sudo iptables -A INPUT -s $priv_ip -p tcp --dport 5432 -j DROP" 2>/dev/null || true
  fi
done

success "Primary ($PRIMARY) is now network-isolated from other nodes"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Network partition detected!"
echo ""
echo "The primary ($PRIMARY) has been isolated from all other nodes."
echo "Standbys and witness CANNOT reach the primary."
echo "The primary CANNOT reach the standbys."
echo ""
echo "repmgrd on the standbys should detect this and:"
echo "  - Consult the witness for quorum"
echo "  - Promote a standby if quorum is met"
echo "  - The old (fenced) primary must be prevented from accepting writes"
echo ""
echo "Your tasks:"
echo "  1. Monitor repmgr logs for failover activity"
echo "  2. Verify split-brain was prevented (only ONE primary)"
echo "  3. Resolve the partition (remove iptables rules)"
echo "  4. Rejoin the old primary as a standby"
echo "  5. Run validate.sh"
echo ""
echo "To manually lift the partition (if needed):"
echo "  ssh ec2-user@$PRIMARY 'sudo iptables -F'"
echo "------------------------------------------------------------"
