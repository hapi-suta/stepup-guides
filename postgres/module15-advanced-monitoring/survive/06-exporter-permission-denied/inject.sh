#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/06-exporter-permission-denied
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
if [[ ! -f /etc/systemd/system/postgres_exporter.service ]]; then
  say "PRECONDITION: finish Tutorial 2 (postgres_exporter and its postgres_exporter role) first"; exit 2
fi
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
if [[ "$(psq postgres "select count(*) from pg_roles where rolname='postgres_exporter'")" != "1" ]]; then
  say "PRECONDITION: finish Tutorial 2 (the postgres_exporter database role) first"; exit 2
fi
psq postgres "REVOKE pg_monitor FROM postgres_exporter" >/dev/null 2>&1
if [[ "$(psq stepup_store "select count(*) from pg_extension where extname='pg_stat_statements'" 2>/dev/null)" == "1" ]]; then
  psq stepup_store "REVOKE SELECT ON pg_stat_statements FROM postgres_exporter" >/dev/null 2>&1
fi
systemctl restart postgres_exporter >/dev/null 2>&1; sleep 3
say "postgres_exporter: $(systemctl is-active postgres_exporter)"
say "pg_up: $(curl -s -m 3 http://localhost:9187/metrics | awk '/^pg_up /{print $2}')"
say ""
say "ALERT: postgres_exporter is running (pg_up = 1) but many metrics return no data"
say "or permission errors. The exporter looks healthy but collects incomplete data."
exit 0
