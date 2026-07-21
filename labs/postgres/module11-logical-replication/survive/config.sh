#!/usr/bin/env bash
# config.sh - Load student environment + shared vars for the module11
# logical-replication SURVIVE scenarios. Sourced by every inject/validate script.
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
  [[ -f "$path" ]] && { STUDENT_ENV="$path"; break; }
done
if [[ -z "$STUDENT_ENV" ]]; then
  echo "FATAL: student.env not found. Checked:"; printf '  %s\n' "${CANDIDATES[@]}"; exit 1
fi
# shellcheck source=/dev/null
source "$STUDENT_ENV"

# ---------- required vars ----------
# NODE1 = publisher, NODE2 = subscriber (both from student.env).
for var in NODE1 NODE2 SSH_USER SSH_KEY; do
  [[ -z "${!var:-}" ]] && { echo "FATAL: $var is not set in $STUDENT_ENV"; exit 1; }
done

# ---------- derived / overridable exports ----------
export PUB_HOST="$NODE1" SUB_HOST="$NODE2"
export PUB_PORT="${PUB_PORT:-5432}" SUB_PORT="${SUB_PORT:-5432}"
export DBNAME="${DBNAME:-labdb}"
export PGBIN="${PGBIN:-/usr/pgsql-16/bin}"
export PUBLICATION="${PUBLICATION:-products_pub}"
export SUBSCRIPTION="${SUBSCRIPTION:-products_sub}"
export PUB_TABLE="${PUB_TABLE:-products}"
export REPL_USER="${REPL_USER:-replicator}"
export REPL_PASS="${REPL_PASS:-StrongPass123}"
export SSH_USER SSH_KEY
export SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=8 -i $SSH_KEY"
export SURVIVE_DIR
SURVIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
