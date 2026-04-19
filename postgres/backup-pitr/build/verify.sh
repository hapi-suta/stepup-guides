#!/usr/bin/env bash
# Automated verification that the backup-pitr build is complete.
# Run from the lab root: ./build/verify.sh
#
# Sources student.env for NODE1/NODE2 IPs. Exits 0 if all checks pass.

set -uo pipefail

# Find student.env - check lab root, then labs root
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/student.env" ]]; then
  source "$SCRIPT_DIR/student.env"
elif [[ -f "$SCRIPT_DIR/../../../student.env" ]]; then
  source "$SCRIPT_DIR/../../../student.env"
else
  echo "ERROR: No student.env found. Copy student.env.example and fill in your IPs." >&2
  exit 2
fi

[[ -z "${NODE1:-}" ]] && { echo "ERROR: NODE1 not set in student.env"; exit 2; }
[[ -z "${NODE2:-}" ]] && { echo "ERROR: NODE2 not set in student.env"; exit 2; }

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
[[ -n "${SSH_KEY:-}" ]] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
PG_USER="${PG_USER:-postgres}"
SSH_USER="${SSH_USER:-ec2-user}"

PASS=0
FAIL=0
WARN=0

check() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" == "0" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

warn() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" == "0" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "WARN: $label"
    WARN=$((WARN + 1))
  fi
}

echo "=============================================================="
echo "VERIFYING: backup-pitr build (CentOS Stream 9)"
echo "  Primary (NODE1): $NODE1"
echo "  Backup  (NODE2): $NODE2"
echo "=============================================================="

# ---------- Connectivity ----------

# 1. SSH reachability
ssh $SSH_OPTS "$SSH_USER@$NODE1" "echo ok" >/dev/null 2>&1
check "01 - SSH to primary ($NODE1)" "$?"

ssh $SSH_OPTS "$SSH_USER@$NODE2" "echo ok" >/dev/null 2>&1
check "02 - SSH to backup ($NODE2)" "$?"

# ---------- Custom mount points ----------

# 3. /opt/pgsql/data exists on NODE1
ssh $SSH_OPTS "$SSH_USER@$NODE1" "test -d /opt/pgsql/data" 2>/dev/null
check "03 - /opt/pgsql/data exists on primary" "$?"

# 4. /opt/pgsql/wal exists on NODE1
ssh $SSH_OPTS "$SSH_USER@$NODE1" "test -d /opt/pgsql/wal" 2>/dev/null
check "04 - /opt/pgsql/wal exists on primary" "$?"

# 5. /opt/pgsql/log exists on NODE1
ssh $SSH_OPTS "$SSH_USER@$NODE1" "test -d /opt/pgsql/log" 2>/dev/null
check "05 - /opt/pgsql/log exists on primary" "$?"

# 6. /opt/pgsql/backup exists on NODE2
ssh $SSH_OPTS "$SSH_USER@$NODE2" "test -d /opt/pgsql/backup" 2>/dev/null
check "06 - /opt/pgsql/backup exists on backup" "$?"

# ---------- PostgreSQL ----------

# 7. PostgreSQL 16 installed and running on NODE1
PG_VERSION=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SHOW server_version;'" 2>/dev/null | tr -d ' ')
[[ "$PG_VERSION" == 16* ]]
check "07 - PostgreSQL 16 running on primary (got: $PG_VERSION)" "$?"

# 8. PGDATA is /opt/pgsql/data
PGDATA_PATH=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SHOW data_directory;'" 2>/dev/null | tr -d ' ')
[[ "$PGDATA_PATH" == "/opt/pgsql/data" ]]
check "08 - PGDATA = /opt/pgsql/data (got: $PGDATA_PATH)" "$?"

# ---------- Sample databases ----------

# 9. labdb exists
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc \"SELECT 1 FROM pg_database WHERE datname='labdb';\"" 2>/dev/null | grep -q 1
check "09 - labdb database exists" "$?"

# 10. appdb exists
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc \"SELECT 1 FROM pg_database WHERE datname='appdb';\"" 2>/dev/null | grep -q 1
check "10 - appdb database exists" "$?"

# 11. blobdb exists
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc \"SELECT 1 FROM pg_database WHERE datname='blobdb';\"" 2>/dev/null | grep -q 1
check "11 - blobdb database exists" "$?"

# 12. labdb has 5GB pgbench data (33M rows in pgbench_accounts)
LABDB_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -tAc 'SELECT count(*) FROM pgbench_accounts;'" 2>/dev/null | tr -d ' ')
[[ "$LABDB_COUNT" -ge 33000000 ]] 2>/dev/null
check "12 - labdb has >= 33M pgbench_accounts rows (got: $LABDB_COUNT)" "$?"

# 13. labdb size is approximately 5GB
LABDB_SIZE_MB=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc \"SELECT pg_database_size('labdb') / 1024 / 1024;\"" 2>/dev/null | tr -d ' ')
[[ "$LABDB_SIZE_MB" -ge 4000 ]] 2>/dev/null
check "13 - labdb size >= 4GB (got: ${LABDB_SIZE_MB}MB)" "$?"

# ---------- WAL archiving ----------

# 14. archive_mode = on
ARCHIVE_MODE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SHOW archive_mode;'" 2>/dev/null | tr -d ' ')
[[ "$ARCHIVE_MODE" == "on" ]]
check "14 - archive_mode = on (got: $ARCHIVE_MODE)" "$?"

# 15. wal_level = replica (or logical)
WAL_LEVEL=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SHOW wal_level;'" 2>/dev/null | tr -d ' ')
[[ "$WAL_LEVEL" == "replica" || "$WAL_LEVEL" == "logical" ]]
check "15 - wal_level = replica or logical (got: $WAL_LEVEL)" "$?"

# 16. archive_command is configured (not empty, not disabled)
ARCHIVE_CMD=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SHOW archive_command;'" 2>/dev/null | tr -d ' ')
[[ -n "$ARCHIVE_CMD" && "$ARCHIVE_CMD" != "(disabled)" ]]
check "16 - archive_command is configured" "$?"

# 17. Check if archive_command uses pgbackrest
echo "$ARCHIVE_CMD" | grep -qi pgbackrest
check "17 - archive_command uses pgBackRest" "$?"

# ---------- pgBackRest ----------

# 18. pgBackRest installed on NODE1
PGBR_VER=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "pgbackrest version" 2>/dev/null)
[[ -n "$PGBR_VER" ]]
check "18 - pgBackRest installed on primary (got: $PGBR_VER)" "$?"

# 19. pgBackRest installed on NODE2
PGBR_VER2=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "pgbackrest version" 2>/dev/null)
[[ -n "$PGBR_VER2" ]]
check "19 - pgBackRest installed on backup (got: $PGBR_VER2)" "$?"

# 20. pgBackRest config exists on NODE1
ssh $SSH_OPTS "$SSH_USER@$NODE1" "test -f /etc/pgbackrest/pgbackrest.conf" 2>/dev/null
check "20 - pgBackRest config exists on primary" "$?"

# 21. pgBackRest config exists on NODE2
ssh $SSH_OPTS "$SSH_USER@$NODE2" "test -f /etc/pgbackrest/pgbackrest.conf" 2>/dev/null
check "21 - pgBackRest config exists on backup" "$?"

# 22. pgBackRest config has correct pg1-path
PGBR_PATH=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "grep pg1-path /etc/pgbackrest/pgbackrest.conf" 2>/dev/null | tr -d ' ')
echo "$PGBR_PATH" | grep -q "/opt/pgsql/data"
check "22 - pgBackRest pg1-path = /opt/pgsql/data" "$?"

# 23. Stanza is configured (check command succeeds)
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres pgbackrest --stanza=main check" >/dev/null 2>&1
check "23 - pgBackRest stanza 'main' check passes" "$?"

# 24. At least one pgBackRest backup exists
BACKUP_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres pgbackrest --stanza=main info --output=json 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); print(len(data[0].get(\"backup\",[])))'" 2>/dev/null | tr -d ' ')
[[ "$BACKUP_COUNT" -ge 1 ]] 2>/dev/null
check "24 - At least one pgBackRest backup exists (got: $BACKUP_COUNT)" "$?"

# 25. Check that a full backup exists
HAS_FULL=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres pgbackrest --stanza=main info --output=json 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); types=[b[\"type\"] for b in data[0].get(\"backup\",[])]; print(\"yes\" if \"full\" in types else \"no\")'" 2>/dev/null | tr -d ' ')
[[ "$HAS_FULL" == "yes" ]]
check "25 - At least one full backup exists" "$?"

# ---------- WAL archive health ----------

# 26. No archive failures
FAILED_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc 'SELECT failed_count FROM pg_stat_archiver;'" 2>/dev/null | tr -d ' ')
[[ "$FAILED_COUNT" == "0" ]] 2>/dev/null
warn "26 - No WAL archive failures (failed_count: $FAILED_COUNT)" "$?"

# 27. Recent WAL archived (within last 10 minutes)
RECENT_ARCHIVE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -u postgres /usr/pgsql-16/bin/psql -tAc \"SELECT CASE WHEN last_archived_time > now() - interval '10 minutes' THEN 'yes' ELSE 'no' END FROM pg_stat_archiver;\"" 2>/dev/null | tr -d ' ')
[[ "$RECENT_ARCHIVE" == "yes" ]]
warn "27 - WAL archived within last 10 minutes (got: $RECENT_ARCHIVE)" "$?"

echo ""
echo "=============================================================="
echo "SUMMARY: $PASS passed, $FAIL failed, $WARN warnings"
echo "=============================================================="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Fix the failing checks, then re-run this script."
  echo "Do not proceed to Phase 2 until all checks pass."
  exit 1
fi

if [[ $WARN -gt 0 ]]; then
  echo ""
  echo "Warnings are non-blocking but should be investigated."
fi

echo ""
echo "BUILD COMPLETE. Your backup infrastructure is ready."
echo "Proceed to the USE phase."
exit 0
