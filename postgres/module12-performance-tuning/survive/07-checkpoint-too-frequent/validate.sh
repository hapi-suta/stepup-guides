#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/07-checkpoint-too-frequent
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-07
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
g() { psq postgres "select setting from pg_settings where name='$1'" 2>/dev/null; }
mw=$(g max_wal_size); cct=$(g checkpoint_completion_target); ct=$(g checkpoint_timeout)
if [[ -n "$mw" && "$mw" -ge 256 ]]; then ok "max_wal_size is at least 256MB (${mw}MB)"; else bad "max_wal_size is at least 256MB (got ${mw:-<none>}MB)"; fi
if [[ -n "$cct" ]] && awk -v v="$cct" 'BEGIN{exit !(v>=0.5)}'; then ok "checkpoint_completion_target is at least 0.5 ($cct)"; else bad "checkpoint_completion_target is at least 0.5 (got ${cct:-<none>})"; fi
if [[ -n "$ct" && "$ct" -ge 60 ]]; then ok "checkpoint_timeout is at least 60 seconds (${ct}s)"; else bad "checkpoint_timeout is at least 60 seconds (got ${ct:-<none>}s)"; fi
if grep -Eq "^(max_wal_size *= *'32MB'|checkpoint_completion_target *= *'0\.1'|checkpoint_timeout *= *'30s')" "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "postgresql.auto.conf has no aggressive checkpoint settings"; else ok "postgresql.auto.conf has no aggressive checkpoint settings"; fi
finish
