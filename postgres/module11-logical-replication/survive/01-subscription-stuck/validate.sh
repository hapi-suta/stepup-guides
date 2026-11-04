#!/usr/bin/env bash
# =============================================================================
# VALIDATE 01 - Subscription Stuck recovery
# Checks: subscription enabled, publisher slot present, every subscribed table
# in 'r' (ready), row counts match, and a fresh publisher change replicates.
# =============================================================================
set -uo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCENARIO_DIR}/../config.sh"
# shellcheck source=/dev/null
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m11-01-state.env"
[[ -f "$STATE_FILE" ]] && { source "$STATE_FILE"; }

header "Validating: Subscription Stuck Recovery"

# 1. subscription enabled
check_eq "subscription '$SUBSCRIPTION' is enabled" "t" \
  "$(sub_psql "SELECT subenabled FROM pg_subscription WHERE subname='$SUBSCRIPTION'")"

# 2. publisher replication slot exists again
check_eq "publisher replication slot '$SUBSCRIPTION' exists" "1" \
  "$(pub_psql "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'")"

# 3. no subscribed table left in a non-ready state
check_eq "all subscribed tables are in 'r' (ready) state" "0" \
  "$(sub_psql "SELECT count(*) FROM pg_subscription_rel WHERE srsubstate <> 'r'")"

# 4. row counts match between publisher and subscriber
check_eq "subscriber row count matches publisher" \
  "$(pub_psql "SELECT count(*) FROM $PUB_TABLE")" \
  "$(sub_psql "SELECT count(*) FROM $PUB_TABLE")"

# 5. live change: a new publisher row must replicate to the subscriber
MARK="chaos-v01-$$"
pub_psql "INSERT INTO $PUB_TABLE (name, price) VALUES ('$MARK', 1.23)" >/dev/null
sleep 3
check_eq "a new publisher row replicates to the subscriber" "1" \
  "$(sub_psql "SELECT count(*) FROM $PUB_TABLE WHERE name='$MARK'")"
# cleanup the probe row
pub_psql "DELETE FROM $PUB_TABLE WHERE name='$MARK'" >/dev/null 2>&1 || true
sleep 1

check_summary && rm -f "$STATE_FILE"
