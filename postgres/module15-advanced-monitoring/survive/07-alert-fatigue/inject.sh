#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/07-alert-fatigue
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
R=/etc/prometheus/rules/postgres.yml
if [[ ! -f "$R" ]] || ! systemctl cat prometheus >/dev/null 2>&1; then
  say "PRECONDITION: finish Tutorial 5 (Prometheus alerting rules in $R) first"; exit 2
fi
if ! grep -q 'suta-alert-fatigue' "$R"; then
  cp -p "$R" "$R.bak_scenario07"
  cat >"$R" <<'RULES'
# suta-alert-fatigue
groups:
  - name: postgres_alerts
    interval: 30s
    rules:
      - alert: PostgresExporterDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "postgres_exporter is down"
      - alert: PostgresHighConnectionCount
        expr: sum(pg_stat_activity_count{state!="idle"}) by (instance) > 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "High connection count"
          description: "More than 1 non-idle connection."
      - alert: PostgresLongRunningQuery
        expr: pg_stat_activity_max_tx_duration{state="active",datname!=""} > 0.001
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Long running query"
      - alert: PostgresLowCacheHitRatio
        expr: sum(rate(pg_stat_database_blks_hit[5m])) / (sum(rate(pg_stat_database_blks_hit[5m])) + sum(rate(pg_stat_database_blks_read[5m]))) < 0.9999
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Low cache hit ratio"
      - alert: PostgresDeadlocks
        expr: pg_stat_database_deadlocks >= 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Deadlocks detected"
      - alert: PostgresCheckpointWriteTimeTooHigh
        expr: pg_stat_bgwriter_checkpoint_write_time >= 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Checkpoint write time too high"
          description: "Any checkpoint write time is too high."
RULES
  chown --reference="$R.bak_scenario07" "$R" 2>/dev/null || true
fi
curl -s -m 5 -X POST http://localhost:9090/-/reload >/dev/null 2>&1 || systemctl reload prometheus >/dev/null 2>&1 || true
sleep 3
say "prometheus: $(systemctl is-active prometheus)"
say ""
say "ALERT: Prometheus /alerts page shows many FIRING alerts while the database appears healthy."
say "Monitoring is noisy and unreliable; real alerts will be ignored."
exit 0
