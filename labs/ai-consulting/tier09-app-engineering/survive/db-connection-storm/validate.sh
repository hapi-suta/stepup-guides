#!/usr/bin/env bash
# SURVIVE validate: pooling is restored and the app survives a burst.
#
# PASS conditions:
#   1. db.py no longer contains the injected leak (no "_LEAKED" list).
#   2. /metrics shows the pool is initialized (pooling is back).
#   3. A burst of 40 concurrent /ask requests all return HTTP 200 - the app
#      does not fall over under load.
#   4. Open backend connections stay bounded (<= a small ceiling), proving the
#      leak is gone.
#
# Run as ec2-user after following runbook.md. API expected on :8000.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }
BASE="${BASE:-http://127.0.0.1:8000}"
ADMIN_TOKEN="${ADMIN_TOKEN:-token-admin}"

export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_NAME="${DB_NAME:-labdb}"
export DB_USER="${DB_USER:-labuser}"
export DB_PASSWORD="${DB_PASSWORD:-labpass}"

fail() { echo "FAIL: $1"; exit 1; }

# 1. The leak must be gone from db.py.
if grep -q "_LEAKED" db.py 2>/dev/null; then
  fail "db.py still contains the injected leak (_LEAKED) - pooling not restored"
fi
echo "OK: db.py no longer contains the connection leak"

# 2. The pool must be initialized.
METRICS="$(curl -s --max-time 5 "$BASE/metrics" || true)"
if ! echo "$METRICS" | grep -q '"initialized": *true'; then
  fail "/metrics does not show an initialized pool (got: ${METRICS:-<none>})"
fi
echo "OK: /metrics reports an initialized connection pool"

# 3. Fire a burst; every request must succeed.
echo "Firing 40 concurrent requests..."
CODES_FILE="$(mktemp)"
for _ in $(seq 1 40); do
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    -d '{"query":"backup"}' "$BASE/ask" >> "$CODES_FILE" &
done
wait 2>/dev/null || true
TOTAL=$(wc -l < "$CODES_FILE" | tr -d ' ')
OK200=$(grep -c '^200$' "$CODES_FILE" || true)
rm -f "$CODES_FILE"
[ "$OK200" = "$TOTAL" ] || fail "only $OK200/$TOTAL requests returned 200 under load - app still failing"
echo "OK: all $TOTAL concurrent requests returned 200"

# 4. Open backends must stay bounded.
OPEN=$(PGCONNECT_TIMEOUT=3 PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database()" 2>/dev/null || echo 999)
if [ "${OPEN:-999}" -le 15 ]; then
  echo "OK: open backend connections bounded ($OPEN)"
else
  fail "open backend connections high ($OPEN) - connections still leaking"
fi

echo "PASS: pooling restored; app survives the connection storm."
