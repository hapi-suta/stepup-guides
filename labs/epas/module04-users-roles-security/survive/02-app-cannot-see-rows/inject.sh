#!/bin/bash
# Chaos: an app SELECT returns zero rows (no error) after RLS was enabled with no policy
# Target: epas-single
# Difficulty: mid
# Expected fix time: 15 minutes
#
# What we break: create schema chaos_m04 with a table whose rows are owned by
# 'chaos_reader' (2 rows) and 'other_user' (1 row), grant chaos_reader SELECT, then
# ENABLE ROW LEVEL SECURITY with NO policy. Row security with no matching policy is
# default-deny, so chaos_reader now sees zero rows even though SELECT is granted. The
# student must add a policy so chaos_reader sees its own two rows (and not the third).
# Idempotent: drops and recreates the schema/role each run.
set -u
P="sudo -u enterprisedb /usr/edb/as16/bin/edb-psql -p 5444 -d edb -X -q"

$P -c "DROP SCHEMA IF EXISTS chaos_m04 CASCADE;" >/dev/null 2>&1
$P -c "DROP ROLE IF EXISTS chaos_reader;" >/dev/null 2>&1
$P -c "CREATE ROLE chaos_reader LOGIN PASSWORD 'x';" >/dev/null 2>&1
$P -c "CREATE SCHEMA chaos_m04;" >/dev/null 2>&1
$P -c "CREATE TABLE chaos_m04.orders (id int PRIMARY KEY, owner text, amount numeric);" >/dev/null 2>&1
$P -c "INSERT INTO chaos_m04.orders VALUES (1,'chaos_reader',100),(2,'other_user',200),(3,'chaos_reader',300);" >/dev/null 2>&1
$P -c "GRANT USAGE ON SCHEMA chaos_m04 TO chaos_reader;" >/dev/null 2>&1
$P -c "GRANT SELECT ON chaos_m04.orders TO chaos_reader;" >/dev/null 2>&1
$P -c "ALTER TABLE chaos_m04.orders ENABLE ROW LEVEL SECURITY;" >/dev/null 2>&1

echo "Chaos injected: the reporting user 'chaos_reader' runs"
echo "  SELECT * FROM chaos_m04.orders;"
echo "and gets ZERO rows back - no error, just nothing - even though it has SELECT."
echo "As the DBA (enterprisedb) the same query shows all three rows. Restore the app's"
echo "access so chaos_reader sees ONLY its own two rows (owner = 'chaos_reader')."
