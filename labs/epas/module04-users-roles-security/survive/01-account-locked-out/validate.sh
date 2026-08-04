#!/bin/bash
# PASS when chaos_card_app's account_status is OPEN again (the student unlocked it).
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -Atc"

status=$($P "SELECT account_status FROM DBA_USERS WHERE username='CHAOS_CARD_APP';" 2>&1)

if [[ "$status" == "OPEN" ]]; then
    echo "PASS - chaos_card_app is OPEN; the account has been unlocked."
    exit 0
fi
echo "FAIL: chaos_card_app account_status is '$status' (want OPEN)."
echo "  Hint: a locked account is freed with ALTER USER ... ACCOUNT UNLOCK."
exit 1
