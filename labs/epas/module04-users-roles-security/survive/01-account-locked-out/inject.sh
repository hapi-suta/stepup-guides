#!/bin/bash
# Chaos: an application account is locked out and even the correct password is refused
# Target: epas-single
# Difficulty: easy
# Expected fix time: 10 minutes
#
# What we break: create a profile with FAILED_LOGIN_ATTEMPTS 3, attach it to user
# chaos_card_app, then trip the lockout with three bad-password TCP logins. The account
# ends up LOCKED(TIMED). The student diagnoses via DBA_USERS.account_status and unlocks
# with ALTER USER ... ACCOUNT UNLOCK. Idempotent: recreates the user each run.
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -q"

$P -c "DROP USER IF EXISTS chaos_card_app;" >/dev/null 2>&1
$P -c "DROP PROFILE IF EXISTS chaos_lock_prof;" >/dev/null 2>&1
$P -c "CREATE PROFILE chaos_lock_prof LIMIT FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;" >/dev/null 2>&1
$P -c "CREATE USER chaos_card_app WITH LOGIN PASSWORD 'GoodPass_2026' PROFILE chaos_lock_prof;" >/dev/null 2>&1

# Trip the lockout with 3 bad-password TCP logins.
for i in 1 2 3; do
    sudo -u enterprisedb bash -c "PGPASSWORD='wrong_$i' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U chaos_card_app -d edb -c 'SELECT 1'" >/dev/null 2>&1
done

echo "Chaos injected: the application user 'chaos_card_app' can no longer log in,"
echo "even though the app team insists the password 'GoodPass_2026' is unchanged."
echo "Find out why and restore the account's access."
