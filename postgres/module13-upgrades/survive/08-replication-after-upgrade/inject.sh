#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/08-replication-after-upgrade
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }

RDIR=/opt/pgsql/replica_status; RF=$RDIR/replica_info.conf
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running"; exit 1; }; fi
install -d -o postgres -g postgres -m 755 "$RDIR"
if [[ "$(psq postgres "select count(*) from pg_replication_slots where slot_name='chaos8_replica_slot'")" == "0" ]]; then
  psq postgres "select pg_create_physical_replication_slot('chaos8_replica_slot', true)" >/dev/null || exit 1
fi
if ! grep -qx "replica_pg_version=15" "$RF" 2>/dev/null; then
  cat > "$RF" <<'EOT'
# Replica Status File
# This file tracks the replica cluster state after primary upgrade.
replica_pg_version=15
primary_pg_version=16
replica_data_directory=/opt/pgsql/data15
replica_status=STOPPED
replica_last_lsn=0/5000000
upgrade_started=2026-04-18T10:00:00Z
upgrade_completed=
notes=Primary upgraded to PG16. Replica still on PG15. Streaming replication broken.
EOT
  chown postgres:postgres "$RF"
fi
psq postgres "select pg_drop_replication_slot(slot_name) from pg_replication_slots where slot_name <> 'chaos8_replica_slot' and not active and slot_type = 'physical' and slot_name = 'replica_slot'" >/dev/null 2>&1
say "Primary: PostgreSQL $(psq postgres 'show server_version') up; replication slots: $(psq postgres 'select count(*) from pg_replication_slots')"
say ""
say "ALERT: After upgrading the primary from PG15 to PG16,"
say "the replica is down and streaming replication is broken."
say "The replica status file shows it is still on PG15."
say "The replication slot on the primary is accumulating WAL."
say "You need to plan and execute the replica rebuild."
exit 0
