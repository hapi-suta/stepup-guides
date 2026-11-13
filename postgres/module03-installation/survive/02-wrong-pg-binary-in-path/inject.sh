#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/02-wrong-pg-binary-in-path
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/psql" ]] || { say "postgresql-16 client is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
HOME_PG=$(getent passwd postgres | cut -d: -f6); PROF="$HOME_PG/.bash_profile"
# 1. a decoy psql that looks for a server on port 5555 (the "source build"), 2. put its directory first in postgres's PATH
mkdir -p /opt/pg-src/bin
cat > /opt/pg-src/bin/psql <<'WRAP'
#!/usr/bin/env bash
# decoy psql from a long-gone source build: defaults to port 5555, later flags still override
exec /usr/pgsql-16/bin/psql -h /tmp -p 5555 "$@"
WRAP
chmod 755 /opt/pg-src/bin/psql
if ! grep -q '/opt/pg-src/bin' "$PROF" 2>/dev/null; then
  [[ -f "$PROF" ]] && cp -p "$PROF" "$PROF.suta-orig"
  touch "$PROF"
  printf '\n# .bash_profile - modified\nexport PATH=/opt/pg-src/bin:$PATH\n' >> "$PROF"
  chown postgres:postgres "$PROF"
fi
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL appears to be unreachable."
say "A developer reports 'psql: connection refused' when logging in as the"
say "postgres user and running psql. The DBA team confirms PG16 service is active."
exit 0
