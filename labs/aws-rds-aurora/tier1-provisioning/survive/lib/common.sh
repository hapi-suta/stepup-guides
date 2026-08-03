#!/usr/bin/env bash
# survive/lib/common.sh
# Helper functions for AWS RDS survive scenarios.
# Source this file after config.sh.

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Check result and track pass/fail counts
# ---------------------------------------------------------------------------

_CHECK_PASS=0
_CHECK_FAIL=0

check() {
  local label="$1"
  local result="$2"   # "pass" or "fail"
  local detail="${3:-}"

  if [[ "$result" == "pass" ]]; then
    success "$label"
    (( _CHECK_PASS++ )) || true
  else
    fail "$label"
    if [[ -n "$detail" ]]; then
      echo "        Detail: $detail"
    fi
    (( _CHECK_FAIL++ )) || true
  fi
}

check_summary() {
  echo ""
  echo "================================"
  echo "  Results: ${_CHECK_PASS} passed, ${_CHECK_FAIL} failed"
  echo "================================"
  if [[ $_CHECK_FAIL -gt 0 ]]; then
    echo ""
    warn "Some checks failed. See details above."
    return 1
  else
    success "All checks passed."
    return 0
  fi
}

# ---------------------------------------------------------------------------
# AWS RDS helpers
# ---------------------------------------------------------------------------

# Get the status of an RDS instance
# Usage: rds_instance_status "instance-id"
# Returns: available | stopped | creating | modifying | ...
rds_instance_status() {
  local instance_id="$1"
  aws rds describe-db-instances \
    --db-instance-identifier "$instance_id" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text \
    2>/dev/null || echo "not-found"
}

# Wait for an RDS instance to reach a target status
# Usage: rds_wait_for_status "instance-id" "available" 600
rds_wait_for_status() {
  local instance_id="$1"
  local target_status="$2"
  local timeout_seconds="${3:-600}"
  local elapsed=0
  local interval=15

  info "Waiting for $instance_id to become $target_status (timeout: ${timeout_seconds}s)..."

  while true; do
    local current
    current=$(rds_instance_status "$instance_id")
    if [[ "$current" == "$target_status" ]]; then
      success "$instance_id is now $target_status"
      return 0
    fi

    if (( elapsed >= timeout_seconds )); then
      fail "Timeout waiting for $instance_id to be $target_status (current: $current)"
      return 1
    fi

    echo "  Status: $current. Waiting ${interval}s..."
    sleep "$interval"
    (( elapsed += interval )) || true
  done
}

# Check if an RDS instance is available
# Usage: rds_is_available "instance-id"
rds_is_available() {
  local instance_id="$1"
  local status
  status=$(rds_instance_status "$instance_id")
  [[ "$status" == "available" ]]
}

# Get the endpoint of an RDS instance
# Usage: rds_get_endpoint "instance-id"
rds_get_endpoint() {
  local instance_id="$1"
  aws rds describe-db-instances \
    --db-instance-identifier "$instance_id" \
    --query "DBInstances[0].Endpoint.Address" \
    --output text \
    2>/dev/null
}

# Get all inbound rules on port 5432 from a security group
# Usage: rds_get_sg_rules "sg-id"
rds_get_sg_rules() {
  local sg_id="$1"
  aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`]" \
    --output json \
    2>/dev/null
}

# Count inbound rules on port 5432 in a security group
# Usage: rds_count_sg_rules "sg-id"
rds_count_sg_rules() {
  local sg_id="$1"
  local rules
  rules=$(rds_get_sg_rules "$sg_id")
  echo "$rules" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data[0].get('IpRanges',[]))+len(data[0].get('UserIdGroupPairs',[])) if data else 0)" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# PostgreSQL connectivity helpers
# ---------------------------------------------------------------------------

# Test if PostgreSQL is reachable (TCP only, no auth)
# Usage: pg_port_open "hostname" "port" "timeout_seconds"
pg_port_open() {
  local host="$1"
  local port="${2:-5432}"
  local timeout="${3:-5}"
  nc -z -w "$timeout" "$host" "$port" 2>/dev/null
}

# Run a SQL query and return stdout
# Usage: rds_exec "SELECT 1"
# Requires: RDS_ENDPOINT, DB_USER, DB_NAME, PGPASSWORD all set
rds_exec() {
  local sql="$1"
  psql \
    -h "$RDS_ENDPOINT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t \
    -A \
    -c "$sql" \
    2>/dev/null
}

# Check if PostgreSQL accepts a connection and run a health check query
# Usage: pg_health_check
# Returns 0 if healthy, 1 if not
pg_health_check() {
  local result
  result=$(rds_exec "SELECT 'ok'" 2>/dev/null) || return 1
  [[ "$result" == "ok" ]]
}

# Resolve a hostname to its IP address
# Usage: dns_resolve "hostname"
dns_resolve() {
  local host="$1"
  dig +short "$host" 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Storage helpers
# ---------------------------------------------------------------------------

# Get free storage space in bytes for an RDS instance from CloudWatch
# Usage: rds_free_storage_bytes "instance-id"
rds_free_storage_bytes() {
  local instance_id="$1"
  aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions "Name=DBInstanceIdentifier,Value=$instance_id" \
    --start-time "$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
    --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --period 300 \
    --statistics Minimum \
    --query "Datapoints[0].Minimum" \
    --output text \
    2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# Scenario infrastructure helpers
# ---------------------------------------------------------------------------

# Save original SG rules before inject (for restore)
# Usage: save_sg_rules "sg-id" "/tmp/sg-backup.json"
save_sg_rules() {
  local sg_id="$1"
  local backup_file="$2"
  aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json > "$backup_file"
  info "Security group rules backed up to $backup_file"
}

# Remove ALL inbound rules from a security group
# Usage: revoke_all_sg_rules "sg-id"
revoke_all_sg_rules() {
  local sg_id="$1"
  local rules
  rules=$(aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json)

  if [[ "$rules" == "[]" || -z "$rules" ]]; then
    warn "No inbound rules found in $sg_id - nothing to revoke"
    return 0
  fi

  aws ec2 revoke-security-group-ingress \
    --group-id "$sg_id" \
    --ip-permissions "$rules"
  info "Revoked all inbound rules from $sg_id"
}

# Restore SG rules from a backup file
# Usage: restore_sg_rules "sg-id" "/tmp/sg-backup.json"
restore_sg_rules() {
  local sg_id="$1"
  local backup_file="$2"

  if [[ ! -f "$backup_file" ]]; then
    fail "Backup file not found: $backup_file"
    return 1
  fi

  aws ec2 authorize-security-group-ingress \
    --group-id "$sg_id" \
    --ip-permissions "$(cat "$backup_file")"
  info "Security group rules restored from $backup_file"
}
