#!/bin/bash
# PASS when chaos_nobody can NO LONGER read the table (the PUBLIC grant was revoked).
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -Atc"

out=$($P "SET ROLE chaos_nobody; SELECT count(*) FROM chaos_m04b.salaries;" 2>&1)

if echo "$out" | grep -qi "permission denied"; then
    echo "PASS - chaos_nobody is now denied; the PUBLIC grant has been removed."
    exit 0
fi
# SET ROLE prints a "SET" status line first; the count is the last line.
cnt=$(echo "$out" | tail -1)
if [[ "$cnt" =~ ^[0-9]+$ ]]; then
    echo "FAIL: chaos_nobody still read the table (got $cnt rows) - PUBLIC can still SELECT."
    echo "  Hint: REVOKE SELECT ON chaos_m04b.salaries FROM PUBLIC;"
    exit 1
fi
echo "FAIL: unexpected result: $out"
exit 1
