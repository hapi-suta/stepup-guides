#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/01-ssl-certificate-expired
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
tcp_as() { PGCONNECT_TIMEOUT=5 PGPASSWORD="$2" "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U "$1" -d "${4:-stepup_store}" -v ON_ERROR_STOP=1 -tAXqc "$3" 2>/dev/null; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running (not accepting connections)"; fi
CRT="$PGDATA/server.crt"; KEY="$PGDATA/server.key"
check_eq "SSL is enabled in PostgreSQL" "on" "$(psq postgres 'SHOW ssl' 2>/dev/null)"
if openssl x509 -in "$CRT" -noout -checkend 86400 >/dev/null 2>&1; then ok "SSL certificate is not expired"; else bad "SSL certificate is not expired (server.crt missing or expiring within 24h)"; fi
if echo | timeout 10 openssl s_client -starttls postgres -connect "127.0.0.1:$PGPORT" 2>/dev/null | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then ok "server presents a valid certificate (reload picked it up)"; else bad "server presents a valid certificate (the running server still serves an expired or no certificate)"; fi
check_eq "server.crt has permissions 644" "644" "$(stat -c %a "$CRT" 2>/dev/null)"
check_eq "server.key has permissions 600" "600" "$(stat -c %a "$KEY" 2>/dev/null)"
check_eq "TCP SSL connection succeeds with sslmode=require" "t" "$(PGSSLMODE=require tcp_as app_user apppass123 "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")"
finish
