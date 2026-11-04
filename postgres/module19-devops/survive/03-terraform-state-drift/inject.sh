#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/03-terraform-state-drift
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
LAB=/tmp/tf-drift-lab
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
mkdir -p "$LAB"
cat >"$LAB/expected_params.txt" <<'PARAMS'
# Expected PostgreSQL parameters (from the IaC definition)
log_min_duration_statement = 1000
idle_in_transaction_session_timeout = 300000
log_connections = 1
log_disconnections = 1
PARAMS
if [[ ! -f "$STATE_DIR/before" ]]; then
  psq postgres "select name||'='||setting from pg_settings where name in ('log_min_duration_statement','idle_in_transaction_session_timeout') order by 1" >"$STATE_DIR/before" 2>/dev/null
fi
psq postgres "ALTER SYSTEM SET log_min_duration_statement = 5000" >/dev/null
psq postgres "ALTER SYSTEM SET idle_in_transaction_session_timeout = 0" >/dev/null
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
say "Current values:"
psq postgres "SELECT name||' = '||setting FROM pg_settings WHERE name IN ('log_min_duration_statement','idle_in_transaction_session_timeout') ORDER BY name"
say ""
say "ALERT: Monitoring alerts fire for slow query logging being effectively disabled."
say "PostgreSQL parameters differ from what is defined in the Terraform/IaC configuration."
exit 0
