#!/bin/bash
# Chaos: an account's password has expired and logins are refused
# Target: epas-single
# Difficulty: easy
# Expected fix time: 10 minutes
#
# What we break: create user chaos_batch and expire its password with
# ALTER USER ... PASSWORD EXPIRE. account_status becomes EXPIRED and a login with the
# (otherwise correct) password is told it must change the password first. The student
# distinguishes this from a lockout via DBA_USERS.account_status and resolves it by
# setting a new password (which returns the account to OPEN). Idempotent.
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -q"

$P -c "DROP USER IF EXISTS chaos_batch;" >/dev/null 2>&1
$P -c "CREATE USER chaos_batch WITH LOGIN PASSWORD 'GoodPass_2026';" >/dev/null 2>&1
$P -c "ALTER USER chaos_batch PASSWORD EXPIRE;" >/dev/null 2>&1

echo "Chaos injected: the batch account 'chaos_batch' can no longer log in. This is NOT"
echo "a bad-password lockout - the password itself has reached the end of its life."
echo "Diagnose it from the account state and restore the account to working order."
