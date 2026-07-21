#!/usr/bin/env bash
# DESC: Subscription stuck - replication slot missing on the publisher (data never arrives)
# =============================================================================
# SCENARIO 01 - Subscription Stuck in Initializing State
# Rebuilds the products_sub subscription WITHOUT a publisher replication slot
# (connect=false) and enables it. With no slot to stream from, the subscriber's
# products table stays empty and the subscription never reaches the 'r' (ready)
# state - it looks stuck. The candidate must diagnose the missing slot (runbook
# Cause B) and drop + recreate the subscription cleanly.
# =============================================================================
set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCENARIO_DIR}/../config.sh"
# shellcheck source=/dev/null
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m11-01-state.env"

header "Injecting Chaos: Subscription Stuck (missing replication slot)"

# ---------- connectivity ----------
step "Verifying connectivity to publisher and subscriber"
remote_exec "$PUB_HOST" "echo ok" >/dev/null 2>&1 || { error "cannot reach publisher $PUB_HOST"; exit 1; }
remote_exec "$SUB_HOST" "echo ok" >/dev/null 2>&1 || { error "cannot reach subscriber $SUB_HOST"; exit 1; }
info "connectivity confirmed"

# ---------- capture pre-injection state ----------
step "Capturing pre-injection state"
PUB_ROWS=$(pub_psql "SELECT count(*) FROM $PUB_TABLE")
info "publisher has $PUB_ROWS rows in $PUB_TABLE"
cat > "$STATE_FILE" <<EOF
INJECT_TIME=$(date -u +%FT%TZ)
PUB_ROWS=$PUB_ROWS
SUBSCRIPTION=$SUBSCRIPTION
PUBLICATION=$PUBLICATION
PUB_TABLE=$PUB_TABLE
EOF

# ---------- inject: recreate subscription with no slot ----------
step "Breaking replication (drop subscription, empty subscriber, recreate with no slot)"
sub_psql "ALTER SUBSCRIPTION $SUBSCRIPTION DISABLE" >/dev/null 2>&1 || true
sub_psql "ALTER SUBSCRIPTION $SUBSCRIPTION SET (slot_name=NONE)" >/dev/null 2>&1 || true
sub_psql "DROP SUBSCRIPTION IF EXISTS $SUBSCRIPTION" >/dev/null 2>&1 || true
pub_psql "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'" >/dev/null 2>&1 || true
sub_psql "TRUNCATE $PUB_TABLE" >/dev/null
sub_psql "CREATE SUBSCRIPTION $SUBSCRIPTION CONNECTION 'host=$PUB_HOST port=$PUB_PORT dbname=$DBNAME user=$REPL_USER password=$REPL_PASS' PUBLICATION $PUBLICATION WITH (connect=false, slot_name=$SUBSCRIPTION)" >/dev/null 2>&1
sub_psql "ALTER SUBSCRIPTION $SUBSCRIPTION ENABLE" >/dev/null

# ---------- wait for symptom ----------
step "Waiting for the symptom to manifest"
sleep 4
SUB_ROWS=$(sub_psql "SELECT count(*) FROM $PUB_TABLE")
SLOT=$(pub_psql "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'")

# ---------- alert ----------
send_alert "REPLICATION STALLED: subscriber has ${SUB_ROWS} of ${PUB_ROWS} rows in ${PUB_TABLE}; subscription '${SUBSCRIPTION}' is not advancing."
info "post-injection: subscriber_rows=$SUB_ROWS  publisher_slot_present=$SLOT (0 = missing)"
warn "The subscription is stuck. Work the runbook to restore replication."
