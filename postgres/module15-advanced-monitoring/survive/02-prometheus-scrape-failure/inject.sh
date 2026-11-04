#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/02-prometheus-scrape-failure
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PY=/etc/prometheus/prometheus.yml
if [[ ! -f "$PY" ]] || ! grep -q "job_name: *'postgres'" "$PY" || ! systemctl cat prometheus >/dev/null 2>&1; then
  say "PRECONDITION: finish Tutorial 3 (Prometheus with the postgres scrape job) first"; exit 2
fi
if ! awk '/job_name/{j=($0 ~ /postgres/)} j && /localhost:9999/{f=1} END{exit !f}' "$PY"; then
  cp -p "$PY" "$PY.bak"
  awk '/job_name/{j=($0 ~ /'"'"'postgres'"'"'/)} j{sub(/localhost:9187/,"localhost:9999")} {print}' "$PY.bak" >"$PY.new" \
    && cat "$PY.new" >"$PY" && rm -f "$PY.new"
fi
curl -s -m 5 -X POST http://localhost:9090/-/reload >/dev/null 2>&1 || systemctl reload prometheus >/dev/null 2>&1 || true
sleep 3
say "prometheus: $(systemctl is-active prometheus)"
say "postgres_exporter: $(systemctl is-active postgres_exporter 2>/dev/null)"
say ""
say "ALERT: Grafana dashboards show \"No data\". Prometheus targets page shows postgres DOWN."
say "Monitoring is blind to all PostgreSQL metrics."
exit 0
