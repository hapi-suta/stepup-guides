#!/bin/bash
# PASS when chaos_batch is OPEN again (the student set a fresh password).
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -Atc"

status=$($P "SELECT account_status FROM DBA_USERS WHERE username='CHAOS_BATCH';" 2>&1)

if [[ "$status" == "OPEN" ]]; then
    echo "PASS - chaos_batch is OPEN; the password has been reset and the account works."
    exit 0
fi
echo "FAIL: chaos_batch account_status is '$status' (want OPEN)."
echo "  Hint: an EXPIRED password is cleared by setting a new one: ALTER USER ... PASSWORD '...'."
exit 1
