#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/08-secrets-exposed-in-logs
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
LAB=/tmp/secrets-chaos
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
mkdir -p "$LAB/ci-logs"
if [[ "$(psq postgres "select count(*) from pg_roles where rolname='dbadmin'")" == "0" ]]; then
  psq postgres "CREATE ROLE dbadmin LOGIN" >/dev/null
fi
psq postgres "ALTER ROLE dbadmin WITH PASSWORD 'SuperSecret123!'" >/dev/null
psq postgres "select md5(rolpassword) from pg_authid where rolname='dbadmin'" >"$STATE_DIR/leaked_verifier_md5"
cat >"$LAB/ci-logs/build-2026-04-19.log" <<'LOG'
[2026-04-19T10:00:00Z] Starting database CI pipeline
[2026-04-19T10:00:01Z] Checkout code: OK
[2026-04-19T10:00:15Z] Running migrations...
[2026-04-19T10:00:15Z] Connecting to postgresql://dbadmin:SuperSecret123!@prod-db.internal:5432/appdb
[2026-04-19T10:00:16Z] Applying V1__create_users.sql... OK
[2026-04-19T10:00:17Z] DEBUG AWS Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
[2026-04-19T10:00:23Z] Pipeline complete
LOG
cat >"$LAB/db-ci.yml" <<'YML'
name: Database CI
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      DATABASE_URL: postgresql://dbadmin:SuperSecret123!@prod-db.internal:5432/appdb
      AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    steps:
      - name: Debug connection
        run: echo "Connecting to $DATABASE_URL"
      - name: Debug AWS
        run: echo "AWS Key: $AWS_SECRET_ACCESS_KEY"
      - name: Run migrations
        run: psql "$DATABASE_URL" -f migrations.sql
YML
chmod 644 "$LAB/db-ci.yml" "$LAB/ci-logs/build-2026-04-19.log"
say "CI log lines containing credentials: $(grep -ciE 'SuperSecret123|wJalrXUtnFEMI' "$LAB/ci-logs/build-2026-04-19.log")"
say ""
say "ALERT: A security audit discovers that database credentials and AWS keys are visible in CI build logs."
say "The credentials are for a production database."
exit 0
