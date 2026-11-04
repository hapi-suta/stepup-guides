#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/03-broken-pgdg-repo
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

REPO=/etc/yum.repos.d/pgdg-redhat-all.repo
[[ -f "$REPO" ]] || { say "PRECONDITION: finish Tutorial 0 (install PostgreSQL 16 from the PGDG repo) first"; exit 2; }
if ! grep -q '/pub/repos/BROKEN' "$REPO"; then
  grep -q '/pub/repos/yum' "$REPO" || { say "PRECONDITION: $REPO has no /pub/repos/yum baseurl to break"; exit 2; }
  cp -p "$REPO" "$REPO.suta-orig"
  cp -p "$REPO" "$REPO.chaos-bak"
  sed -i 's|/pub/repos/yum|/pub/repos/BROKEN|g' "$REPO"
fi
dnf clean all >/dev/null 2>&1
say "postgresql-16 service: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Package installation failing on the database server."
say "The team needs to install postgresql16-contrib but dnf reports"
say "'Failed to download metadata' errors."
say "PostgreSQL is still running - this is a packaging issue."
exit 0
