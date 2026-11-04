#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/08-effective-cache-size-wrong
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-08
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
ecs=$(psq stepup_store "select setting::bigint*8 from pg_settings where name='effective_cache_size'" 2>/dev/null)   # kB
mem=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
if [[ -n "$ecs" && "$ecs" -ge 131072 ]]; then ok "effective_cache_size is at least 128MB ($((ecs/1024))MB)"; else bad "effective_cache_size is at least 128MB (got ${ecs:-<none>}kB)"; fi
if [[ -n "$ecs" && -n "$mem" && "$ecs" -le "$mem" ]]; then ok "effective_cache_size does not exceed total RAM ($((mem/1024))MB)"; else bad "effective_cache_size does not exceed total RAM (got ${ecs:-<none>}kB vs ${mem:-<none>}kB)"; fi
finish
