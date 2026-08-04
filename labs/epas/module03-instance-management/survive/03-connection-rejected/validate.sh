#!/bin/bash
# PASS when a local edb-psql connection succeeds again (the reject rule is gone).
set -u
out=$(sudo -u enterprisedb /usr/edb/as16/bin/psql -p 5444 -d edb -Atc "SELECT 'ok';" 2>&1)

if [[ "$out" == "ok" ]]; then
    echo "PASS - local connections work again."
    exit 0
fi
echo "FAIL: a local connection still fails:"
echo "  $out"
exit 1
