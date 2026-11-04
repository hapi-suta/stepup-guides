#!/usr/bin/env bash
# SUTA survive scenario: module11-repmgr-ha/06-repmgr-metadata-desync
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-repmgr-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

CONF=/etc/repmgr/16/repmgr.conf
[[ -x "$PGBIN/postgres" && -s "$CONF" ]] || { say "PRECONDITION: finish Tutorial 4 (repmgr.conf and primary register) first"; exit 2; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL did not start"; exit 1; }; }
if [[ -z "$(psq postgres "select 1 from pg_database where datname='repmgr'")" ]] \
   || [[ "$(psq repmgr "select coalesce(to_regclass('repmgr.nodes')::text,'')")" == "" ]]; then
  say "PRECONDITION: finish Tutorial 4 (the repmgr database and primary register) first"; exit 2
fi
if [[ "$(psq postgres 'select pg_is_in_recovery()')" != "f" ]]; then
  say "PRECONDITION: run this on the current primary (repmgr metadata is writable only there)"; exit 2
fi
NID=$(sed -n "s/^node_id=\([0-9][0-9]*\).*/\1/p" "$CONF" | head -1)
[[ -n "$NID" ]] || { say "node_id not found in $CONF"; exit 1; }

# mark this node as a standby in repmgr.nodes (once); the real role is untouched
cur=$(psq repmgr "select type from repmgr.nodes where node_id=$NID")
if [[ "$cur" == "primary" ]]; then
  printf '%s\n' "$cur" > "$STATE_DIR/type_before_node_$NID"
  psq repmgr "update repmgr.nodes set type='standby' where node_id=$NID" >/dev/null
fi
say "repmgr.nodes now lists: $(psq repmgr "select string_agg(node_name||'='||type, ', ' order by node_id) from repmgr.nodes")"
say ""
say "ALERT: High - repmgr shows incorrect topology, risking wrong failover decisions."
say "repmgr cluster show does not match what PostgreSQL reports."
exit 0
