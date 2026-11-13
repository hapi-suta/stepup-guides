#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/01-exporter-crash
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
ENVF=/etc/postgres_exporter/postgres_exporter.env
if [[ ! -f /etc/systemd/system/postgres_exporter.service || ! -f "$ENVF" ]]; then
  say "PRECONDITION: finish Tutorial 2 (postgres_exporter service and env file) first"; exit 2
fi
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
if ! grep -qF 'wrong_user:wrong_password@localhost:9999' "$ENVF"; then
  cp -p "$ENVF" "$ENVF.bak"
  printf 'DATA_SOURCE_NAME=postgresql://wrong_user:wrong_password@localhost:9999/nonexistent?sslmode=disable\n' >"$ENVF"
fi
systemctl stop postgres_exporter >/dev/null 2>&1
systemctl reset-failed postgres_exporter >/dev/null 2>&1 || true
say "postgres_exporter: $(systemctl is-active postgres_exporter)"
say "metrics endpoint on :9187: $(curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:9187/metrics)"
say ""
say "ALERT: postgres_exporter is down. Prometheus shows the postgres target as DOWN."
say "No data in Grafana dashboards - metrics collection has stopped."
exit 0
