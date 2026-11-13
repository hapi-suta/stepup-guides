#!/usr/bin/env bash
# DESC: Subscriber sequence not synced after logical replication (duplicate-key on insert)
# =============================================================================
# SCENARIO 02 - Sequences Not Synced After Logical Replication
# Logical replication copies row DATA but never sequence values. This resets the
# subscriber's products_id_seq back to 1 while the table already holds rows up to
# max(id), so the next INSERT on the (cut-over) subscriber fails with a duplicate
# key on products_pkey. The candidate must resync the sequence with setval().
# =============================================================================
set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCENARIO_DIR}/../config.sh"
# shellcheck source=/dev/null
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m11-02-state.env"
SEQ="${PUB_TABLE}_id_seq"

header "Injecting Chaos: Sequence Gap After Logical Replication"

# ---------- connectivity ----------
step "Verifying connectivity to subscriber"
remote_exec "$SUB_HOST" "echo ok" >/dev/null 2>&1 || { error "cannot reach subscriber $SUB_HOST"; exit 1; }

# ---------- capture state ----------
step "Capturing current data high-water mark on the subscriber"
MAXID=$(sub_psql "SELECT COALESCE(max(id),0) FROM $PUB_TABLE")
info "subscriber max(id) in $PUB_TABLE = $MAXID"
if [[ "${MAXID:-0}" -lt 1 ]]; then
  warn "subscriber $PUB_TABLE has no rows - run this scenario against a synced subscriber"
fi
cat > "$STATE_FILE" <<EOF
INJECT_TIME=$(date -u +%FT%TZ)
SEQ=$SEQ
MAXID=$MAXID
PUB_TABLE=$PUB_TABLE
EOF

# ---------- inject: rewind the sequence ----------
step "Rewinding $SEQ to 1 (simulating an unsynced sequence after cut-over)"
sub_psql "SELECT setval('$SEQ', 1, false)" >/dev/null

# ---------- confirm fault ----------
step "Confirming the fault"
SEQVAL=$(sub_psql "SELECT last_value FROM $SEQ")
send_alert "APPLICATION ERROR: INSERT into ${PUB_TABLE} failing with 'duplicate key value violates unique constraint \"${PUB_TABLE}_pkey\"' after cut-over."
info "subscriber $SEQ last_value=$SEQVAL, table max(id)=$MAXID -> the next INSERT will collide on id"
warn "The sequence is behind the data. Work the runbook to resync it."
