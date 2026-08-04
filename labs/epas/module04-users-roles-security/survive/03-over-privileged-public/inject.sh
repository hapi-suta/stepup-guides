#!/bin/bash
# Chaos: a role reads a sensitive table it was never granted, via a PUBLIC grant
# Target: epas-single
# Difficulty: mid
# Expected fix time: 15 minutes
#
# What we break: create schema chaos_m04b with a sensitive table, then GRANT SELECT on
# it TO PUBLIC. Because PUBLIC is the implicit role every account belongs to, a role
# with no explicit grants (chaos_nobody) can now read it. The student finds the PUBLIC
# grant in the ACL (\dp) and revokes it, then grants explicitly only where needed.
# Idempotent: drops and recreates the schema/role each run.
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -q"

$P -c "DROP SCHEMA IF EXISTS chaos_m04b CASCADE;" >/dev/null 2>&1
$P -c "DROP ROLE IF EXISTS chaos_nobody;" >/dev/null 2>&1
$P -c "CREATE ROLE chaos_nobody LOGIN PASSWORD 'x';" >/dev/null 2>&1
$P -c "CREATE SCHEMA chaos_m04b;" >/dev/null 2>&1
$P -c "CREATE TABLE chaos_m04b.salaries (id int PRIMARY KEY, person text, salary numeric);" >/dev/null 2>&1
$P -c "INSERT INTO chaos_m04b.salaries VALUES (1,'alice',180000),(2,'bob',165000);" >/dev/null 2>&1
# The leak: schema + table readable by everyone via PUBLIC.
$P -c "GRANT USAGE ON SCHEMA chaos_m04b TO PUBLIC;" >/dev/null 2>&1
$P -c "GRANT SELECT ON chaos_m04b.salaries TO PUBLIC;" >/dev/null 2>&1

echo "Chaos injected: an audit found that 'chaos_nobody' - an account with no grants -"
echo "can read the sensitive table chaos_m04b.salaries. Find how it is reading data it"
echo "was never granted, and close the hole so chaos_nobody can no longer read it."
