#!/bin/bash
# PASS when chaos_reader sees EXACTLY its own two rows (a correct RLS policy exists).
# Zero rows = still default-deny / no policy. Three rows = an over-broad USING(true).
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -Atc"

# Run the count in the chaos_reader role's context (SET ROLE drops superuser bypass).
# SET ROLE prints a "SET" status line first, so take the last line for the number.
seen=$($P "SET ROLE chaos_reader; SELECT count(*) FROM chaos_m04.orders;" 2>&1 | tail -1)
own=$($P "SELECT count(*) FROM chaos_m04.orders WHERE owner='chaos_reader';" 2>&1 | tail -1)

if [[ "$seen" == "$own" && "$seen" == "2" ]]; then
    echo "PASS - chaos_reader sees its own $seen rows and no others; the policy is correct."
    exit 0
fi
if [[ "$seen" == "0" ]]; then
    echo "FAIL: chaos_reader still sees 0 rows - RLS is enabled but no matching policy exists."
    echo "  Hint: CREATE POLICY ... ON chaos_m04.orders FOR SELECT USING (owner = current_user);"
    exit 1
fi
echo "FAIL: chaos_reader sees $seen rows (should see exactly its own 2)."
echo "  A policy of USING (true) leaks other owners' rows - scope it to owner = current_user."
exit 1
