#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/05-prometheus-scrape-fails
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
U=/etc/systemd/system/postgres_exporter.service
if ! grep -q 'Environment="DATA_SOURCE_NAME=' "$U" 2>/dev/null; then
  say "PRECONDITION: finish Tutorial 5 (observability stack: postgres_exporter service with an inline DATA_SOURCE_NAME) first"; exit 2
fi
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
if ! grep -q 'WRONG_PASSWORD@.*nonexistent_db' "$U"; then
  cp -p "$U" "$STATE_DIR/postgres_exporter.service.before"
  sed -i -E 's|^(Environment="DATA_SOURCE_NAME=postgresql://[^:]+:)[^@]*(@[^/]+/)[^?"]*|\1WRONG_PASSWORD\2nonexistent_db|' "$U"
fi
systemctl daemon-reload
systemctl restart postgres_exporter >/dev/null 2>&1
sleep 3
say "postgres_exporter: $(systemctl is-active postgres_exporter)"
say "pg_up: $(curl -s -m 3 http://localhost:9187/metrics | awk '/^pg_up /{print $2}')"
say ""
say "ALERT: Grafana dashboards show \"No data\" for all PostgreSQL panels."
say "The Prometheus target page shows the postgresql job as DOWN."
exit 0
