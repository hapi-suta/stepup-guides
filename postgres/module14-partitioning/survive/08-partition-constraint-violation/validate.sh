#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/08-partition-constraint-violation
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-08
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

# run SQL inside BEGIN..ROLLBACK (nothing persists); prints output and errors
try_sql() { printf 'BEGIN;\n%s\nROLLBACK;\n' "$2" | sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq 2>&1; }
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
ins() { printf "INSERT INTO chaos8_invoices (invoice_date, customer_name, amount) VALUES ('%s', 'Validate Probe', 1.00) RETURNING tableoid::regclass::text;" "$1"; }
out=$(try_sql stepup_store "$(ins 2024-04-15)")
if [[ -n "$out" && "$out" != *ERROR* && "$out" != *default* ]]; then ok "April 2024 insert lands in a Q2 partition ($out)"; else bad "April 2024 insert lands in a Q2 partition (got: $(head -1 <<<"${out:-nothing}"))"; fi
out=$(try_sql stepup_store "$(ins 2024-11-20)")
if [[ -n "$out" && "$out" != *ERROR* && "$out" != *default* ]]; then ok "November 2024 insert lands in a Q4 partition ($out)"; else bad "November 2024 insert lands in a Q4 partition (got: $(head -1 <<<"${out:-nothing}"))"; fi
check_eq "default partition exists" "1" "$(psq stepup_store "select count(*) from pg_inherits i join pg_class c on c.oid=i.inhrelid where i.inhparent=to_regclass('chaos8_invoices') and pg_get_expr(c.relpartbound,c.oid)='DEFAULT'" 2>/dev/null)"
finish
