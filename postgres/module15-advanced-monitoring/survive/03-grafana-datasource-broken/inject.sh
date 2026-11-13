#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/03-grafana-datasource-broken
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
G="curl -s -m 5 -u admin:admin"
if ! systemctl is-active --quiet grafana-server; then
  say "PRECONDITION: finish Tutorial 4 (Grafana with the Prometheus data source) first"; exit 2
fi
J=$($G http://localhost:3000/api/datasources 2>/dev/null)
ID=$(printf '%s' "$J" | python3 -c 'import sys,json
try:
  print(next(str(d["id"]) for d in json.load(sys.stdin) if d.get("type")=="prometheus"))
except Exception:
  pass' 2>/dev/null)
[[ -n "$ID" ]] || { say "PRECONDITION: finish Tutorial 4 (Grafana Prometheus data source, admin login) first"; exit 2; }
URL=$(printf '%s' "$J" | python3 -c 'import sys,json
print(next(d["url"] for d in json.load(sys.stdin) if d.get("type")=="prometheus"))')
if [[ "$URL" != "http://localhost:9999" ]]; then
  say "$URL" >"$STATE_DIR/orig_url"
  $G -X PUT -H 'Content-Type: application/json' \
    -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9999","access":"proxy","isDefault":true}' \
    "http://localhost:3000/api/datasources/$ID" >/dev/null
fi
say "grafana-server: $(systemctl is-active grafana-server)"
say "prometheus health: $(curl -s -m 3 http://localhost:9090/-/healthy 2>/dev/null)"
say ""
say "ALERT: All Grafana dashboard panels show \"No data\" or \"datasource not connected\"."
say "Visualization is down but monitoring data collection continues."
exit 0
