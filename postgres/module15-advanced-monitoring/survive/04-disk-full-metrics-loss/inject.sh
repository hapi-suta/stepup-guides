#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/04-disk-full-metrics-loss
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
JUNK=/var/lib/prometheus/_junk_fill
if [[ ! -d /var/lib/prometheus ]] || ! systemctl cat prometheus >/dev/null 2>&1; then
  say "PRECONDITION: finish Tutorial 3 (Prometheus with /var/lib/prometheus) first"; exit 2
fi
if [[ ! -f "$JUNK" ]]; then
  avail_mb=$(df -Pm /var/lib/prometheus | awk 'NR==2{print $4}')
  size_mb=$(( avail_mb - 3072 ))      # never leave the root filesystem under 3 GB free
  (( size_mb > 2048 )) && size_mb=2048
  if (( size_mb < 64 )); then say "Not enough free space to inject safely (${avail_mb} MB free)"; exit 1; fi
  fallocate -l "${size_mb}M" "$JUNK" 2>/dev/null || dd if=/dev/zero of="$JUNK" bs=1M count="$size_mb" status=none
  chown prometheus:prometheus "$JUNK" 2>/dev/null || true
  say "$size_mb" >"$STATE_DIR/junk_mb"
fi
say "Filesystem usage:"
df -h /var/lib/prometheus
say ""
say "ALERT: Prometheus data directory is nearly full. Gaps in Grafana graphs."
say "Prometheus logs show TSDB write errors. Historical metrics are being lost."
exit 0
