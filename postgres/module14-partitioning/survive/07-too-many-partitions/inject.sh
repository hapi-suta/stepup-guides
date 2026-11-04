#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/07-too-many-partitions
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
psqf() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and would not start"; exit 1; }; }
reload() { psq postgres "select pg_reload_conf()" >/dev/null; sleep 1; }
# seed: stepup_store database (idempotent)
if [[ "$(psq postgres "select count(*) from pg_database where datname='stepup_store'")" != "1" ]]; then
  sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" stepup_store && say "created database stepup_store"
fi
parts=$(psq stepup_store "select coalesce((select count(*) from pg_inherits where inhparent=to_regclass('chaos7_metrics')),0)")
if [[ "$parts" -lt 400 ]]; then
  psqf stepup_store <<'SQL'
DROP TABLE IF EXISTS chaos7_metrics CASCADE;
CREATE TABLE chaos7_metrics (metric_date DATE NOT NULL, metric_name VARCHAR(50), metric_value NUMERIC(12,3)) PARTITION BY RANGE (metric_date);
DO $$ DECLARE d date; BEGIN
  FOR d IN SELECT generate_series(DATE '2023-01-01', DATE '2023-01-01' + 499, interval '1 day')::date LOOP
    EXECUTE format('CREATE TABLE %I PARTITION OF chaos7_metrics FOR VALUES FROM (%L) TO (%L)', 'chaos7_metrics_' || to_char(d,'YYYY_MM_DD'), d, d + 1);
  END LOOP;
END $$;
INSERT INTO chaos7_metrics SELECT DATE '2023-01-01' + d, 'metric_' || m, (d * m) % 1000 FROM generate_series(0,499) d, generate_series(1,20) m;
ANALYZE chaos7_metrics;
SQL
else
  say "chaos7_metrics already has $parts partitions"
fi
psq stepup_store "select count(*) from chaos7_metrics" > "$STATE_DIR/rows"
say "partitions: $(psq stepup_store "select count(*) from pg_inherits where inhparent='chaos7_metrics'::regclass")"
say ""
say "ALERT: The metrics table has ~500 daily partitions."
say "Simple queries take 200-500ms just for planning."
say "Even queries that only touch one day spend most"
say "of their time in the planner, not executing."
say "The table was partitioned by day but should have"
say "been partitioned by month or quarter."
exit 0
