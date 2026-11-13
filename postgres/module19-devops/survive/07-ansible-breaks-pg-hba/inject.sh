#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/07-ansible-breaks-pg-hba
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
HBA="$PGDATA/pg_hba.conf"
[[ -f "$HBA" ]] || { say "pg_hba.conf not found at $HBA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
if ! grep -q 'suta-chaos-ansible' "$HBA"; then
  cp -p "$HBA" "$HBA.good"
  cat >"$HBA" <<'HBAEOF'
# pg_hba.conf - managed by Ansible (suta-chaos-ansible)
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
host    all             all             0.0.0.0/0               reject
host    all             all             ::0/0                   reject
HBAEOF
  chown postgres:postgres "$HBA"; chmod 600 "$HBA"
fi
systemctl reload postgresql-16 >/dev/null 2>&1 || psq postgres "select pg_reload_conf()" >/dev/null
sleep 2
out=$(sudo -u postgres env PGCONNECT_TIMEOUT=5 "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U postgres -d postgres -w -tAXqc "select 1" 2>&1 | head -1)
say "TCP test: $out"
say ""
say "ALERT: All applications report \"FATAL: pg_hba.conf rejects connection for host\" when trying to connect to PostgreSQL."
say "A recent Ansible playbook run deployed a broken pg_hba.conf."
exit 0
