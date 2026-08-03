#!/usr/bin/env bash
# SURVIVE validate: the admin surface is locked down again.
#
# PASS conditions:
#   1. EVERY /admin/* route rejects an unauthenticated caller (401 or 403),
#      including the debug route (whether it was deleted or protected).
#   2. A real admin (bearer token) can still reach the admin API - we did not
#      break the feature, we secured it.
#   3. app.py has no route decorated without an auth dependency in the admin
#      namespace (static check that no unprotected admin route remains).
#
# Run as ec2-user after following runbook.md. Assumes the API is on :8000.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }
BASE="${BASE:-http://127.0.0.1:8000}"
ADMIN_TOKEN="${ADMIN_TOKEN:-token-admin}"

fail() { echo "FAIL: $1"; exit 1; }

# 1. The leaky debug route must NOT return data to an anonymous caller.
#    Acceptable outcomes: 401, 403, or 404 (route removed). A 200 with tokens
#    is a hard fail.
CODE=$(curl -s -o /tmp/dbg.out -w '%{http_code}' --max-time 5 "$BASE/admin/debug/users" || echo 000)
if [ "$CODE" = "200" ] && grep -q "api_token" /tmp/dbg.out 2>/dev/null; then
  fail "/admin/debug/users still leaks tokens to an anonymous caller (HTTP 200)"
fi
echo "OK: /admin/debug/users no longer leaks to anonymous (HTTP $CODE)"

# 2. The real admin API must still work for an authenticated admin.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
       -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE/admin/users" || echo 000)
[ "$CODE" = "200" ] || fail "authenticated admin cannot reach /admin/users (HTTP $CODE) - you broke the feature"
echo "OK: authenticated admin can still reach /admin/users"

# 3. Anonymous access to the real admin route must be rejected.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/admin/users" || echo 000)
case "$CODE" in
  401|403) echo "OK: /admin/users rejects anonymous (HTTP $CODE)";;
  *) fail "/admin/users did not reject anonymous access (HTTP $CODE)";;
esac

# 4. Static check: no admin route decorator without an auth dependency.
#    Every '@app.get("/admin' / '@app.post("/admin' line's function must take a
#    require_admin dependency within the next few lines.
if grep -nE '@app\.(get|post|put|delete)\("/admin' app.py >/dev/null; then
  BAD=$(awk '
    function flush() { if (pending && buf !~ /require_admin/) print "unprotected"; pending=0; n=0; buf="" }
    /@app\.(get|post|put|delete)\("\/admin/ { flush(); pending=1; buf=""; n=0; next }
    pending { buf=buf" "$0; if (++n>=3) flush() }
    END { flush() }
  ' app.py)
  [ -z "$BAD" ] || fail "an /admin route in app.py has no require_admin dependency"
  echo "OK: every /admin route in app.py requires admin"
fi

echo "PASS: admin surface locked down; admin API still works."
