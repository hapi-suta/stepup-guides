#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/05-slow-query-flood
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. break: log every statement's duration (sighup, reload is enough)
psq postgres "ALTER SYSTEM SET log_min_duration_statement = 0"
psq postgres "SELECT pg_reload_conf()" >/dev/null
# 2. background load so the log really grows; it stops itself once the setting is no longer 0 (or after 4 hours)
cat > "$STATE_DIR/suta-flood.sh" <<'FLOOD'
#!/usr/bin/env bash
P=/usr/pgsql-16/bin/psql
while [ "$SECONDS" -lt 14400 ]; do
  v=$($P -p 5432 -d stepup_store -tAXqc "SHOW log_min_duration_statement" 2>/dev/null) || { sleep 5; continue; }
  [ "$v" = "0" ] || exit 0
  $P -p 5432 -d stepup_store -tAXqc "SELECT 1" >/dev/null 2>&1
  sleep 0.3
done
FLOOD
chmod 755 "$STATE_DIR/suta-flood.sh"
if ! pgrep -f "$STATE_DIR/suta-flood.sh" >/dev/null 2>&1; then
  nohup setsid sudo -u postgres bash "$STATE_DIR/suta-flood.sh" </dev/null >/dev/null 2>&1 &
fi
sleep 3
newest=$(ls -t "$PGLOG"/postgresql-* 2>/dev/null | head -1)
[[ -n "$newest" ]] && say "$(ls -lh "$newest")"
say ""
say "ALERT: Log files are growing at 500MB/hour."
say "log_min_duration_statement appears to be set to 0."
say "Disk alerts are firing. On-call cannot find real errors"
say "because the log is buried in noise."
exit 0
