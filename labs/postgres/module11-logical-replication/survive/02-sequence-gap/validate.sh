#!/usr/bin/env bash
# =============================================================================
# VALIDATE 02 - Sequence Gap recovery
# Checks: the sequence is caught up to at least max(id), and a fresh INSERT on
# the subscriber succeeds with a new id greater than max(id) (no duplicate key).
# =============================================================================
set -uo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCENARIO_DIR}/../config.sh"
# shellcheck source=/dev/null
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m11-02-state.env"
SEQ="${PUB_TABLE}_id_seq"
[[ -f "$STATE_FILE" ]] && { source "$STATE_FILE"; }

header "Validating: Sequence Gap Recovery"

MAXID=$(sub_psql "SELECT COALESCE(max(id),0) FROM $PUB_TABLE")
SEQVAL=$(sub_psql "SELECT last_value FROM $SEQ")

# 1. sequence has caught up to at least the table's max(id)
if [[ "${SEQVAL:-0}" -ge "${MAXID:-0}" ]]; then
  pass "sequence $SEQ ($SEQVAL) >= max(id) ($MAXID)"
else
  fail "sequence $SEQ ($SEQVAL) is still behind max(id) ($MAXID)"
fi

# 2. a fresh INSERT succeeds and gets a NEW id > max(id) (no duplicate-key error)
# CTE-wrap so only the id is returned (a bare INSERT ... RETURNING also prints
# the "INSERT 0 1" command tag on stdout, which would corrupt the captured id).
NEWID=$(sub_psql "WITH ins AS (INSERT INTO $PUB_TABLE (name, price) VALUES ('chaos-v02-$$', 9.99) RETURNING id) SELECT id FROM ins" 2>/dev/null || echo "ERR")
if [[ "$NEWID" =~ ^[0-9]+$ && "$NEWID" -gt "${MAXID:-0}" ]]; then
  pass "new INSERT succeeded with id=$NEWID (> $MAXID), no duplicate key"
else
  fail "new INSERT failed or reused an existing id (got '$NEWID')"
fi

# cleanup the probe row so the table is left clean
[[ "$NEWID" =~ ^[0-9]+$ ]] && sub_psql "DELETE FROM $PUB_TABLE WHERE id=$NEWID" >/dev/null 2>&1 || true

check_summary && rm -f "$STATE_FILE"
