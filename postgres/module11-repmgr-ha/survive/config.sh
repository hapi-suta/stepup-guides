#!/usr/bin/env bash
# config.sh - Load student environment and export shared variables.
# Sourced by every inject/validate script.
set -uo pipefail

# ---------- locate student.env ----------
STUDENT_ENV=""
CANDIDATES=(
  "$(dirname "${BASH_SOURCE[0]}")/../student.env"
  "$(dirname "${BASH_SOURCE[0]}")/../../student.env"
  "$HOME/student.env"
  "/etc/stepup/student.env"
)

for path in "${CANDIDATES[@]}"; do
  if [[ -f "$path" ]]; then
    STUDENT_ENV="$path"
    break
  fi
done

if [[ -z "$STUDENT_ENV" ]]; then
  echo "FATAL: student.env not found. Checked:"
  printf '  %s\n' "${CANDIDATES[@]}"
  exit 1
fi

# shellcheck source=/dev/null
source "$STUDENT_ENV"

# ---------- validate required vars ----------
for var in NODE1 NODE2 NODE3 NODE4 SSH_USER SSH_KEY PG_VERSION PG_PORT PG_USER PG_DB; do
  if [[ -z "${!var:-}" ]]; then
    echo "FATAL: $var is not set in $STUDENT_ENV"
    exit 1
  fi
done

# ---------- derived exports ----------
export NODE1 NODE2 NODE3 NODE4
export SSH_USER SSH_KEY
export PG_VERSION PG_PORT PG_USER PG_DB
export SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $SSH_KEY"
export SURVIVE_DIR
SURVIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPMGR_CONF="/etc/repmgr/16/repmgr.conf"
export PG_DATA="/var/lib/pgsql/16/data"
export PG_BIN="/usr/pgsql-16/bin"
export PG_SERVICE="postgresql-16"
export REPMGRD_SERVICE="repmgr-16"
