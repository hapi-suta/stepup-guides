#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/08-monitoring-query-overhead
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
D=/etc/postgres_exporter; Q=$D/queries.yaml
if [[ ! -d "$D" || ! -f /etc/systemd/system/postgres_exporter.service ]]; then
  say "PRECONDITION: finish Tutorial 2 (postgres_exporter and /etc/postgres_exporter) first"; exit 2
fi
if ! grep -q 'pg_expensive_monitoring_query' "$Q" 2>/dev/null; then
  if [[ -f "$Q" ]]; then cp -p "$Q" "$Q.bak_scenario08"; else printf '{}\n' >"$Q.bak_scenario08"; fi
  [[ -f "$Q" ]] && grep -qE '^\{\}[[:space:]]*$' "$Q" && : >"$Q"
  cat >>"$Q" <<'QUERY'

pg_expensive_monitoring_query:
  query: "SELECT count(*) AS total_rows FROM pg_stat_activity a CROSS JOIN (SELECT pg_sleep(2)) artificial_delay"
  metrics:
    - total_rows:
        usage: "GAUGE"
        description: "Expensive artificial monitoring metric"
QUERY
fi
chown root:postgres_exporter "$Q" 2>/dev/null; chmod 640 "$Q"
say "custom queries file: $Q ($(grep -c '^[a-z_]*:' "$Q") query definitions)"
say "scrape duration: $(curl -s -m 3 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds%7Bjob%3D%22postgres%22%7D' 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["result"][0]["value"][1])' 2>/dev/null)"
say ""
say "ALERT: Slow query alerts fire for a repeating query from the monitoring system itself."
say "Scrape duration is high - monitoring is hurting the database it observes."
exit 0
