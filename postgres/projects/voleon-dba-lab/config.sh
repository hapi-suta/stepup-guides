#!/usr/bin/env bash
# =============================================================================
# CONFIG - Voleon DBA Interview Practice Lab
# =============================================================================
# Quantitative AI/ML finance firm. PostgreSQL on Ceph RBD, containers,
# Ansible automation, Redis caching, Prometheus/Grafana observability.
# =============================================================================

# ---- Nodes -----------------------------------------------------------------
# Public IPs (from terraform output)
PRIMARY_HOST="34.228.141.223"
REPLICA_HOST="3.88.2.229"
CONTAINER_HOST="54.90.166.10"
OPS_HOST="3.93.68.111"

# Private IPs
PRIMARY_PRIVATE="172.31.27.206"
REPLICA_PRIVATE="172.31.25.85"
CONTAINER_PRIVATE="172.31.16.195"
OPS_PRIVATE="172.31.30.35"

ALL_NODES=("$PRIMARY_HOST" "$REPLICA_HOST" "$CONTAINER_HOST" "$OPS_HOST")
PG_NODES=("$PRIMARY_HOST" "$REPLICA_HOST")

# ---- SSH -------------------------------------------------------------------
SSH_USER="ec2-user"
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"

# SSH helper functions
ssh_primary()   { ssh $SSH_OPTS ${SSH_USER}@${PRIMARY_HOST} "$@"; }
ssh_replica()   { ssh $SSH_OPTS ${SSH_USER}@${REPLICA_HOST} "$@"; }
ssh_container() { ssh $SSH_OPTS ${SSH_USER}@${CONTAINER_HOST} "$@"; }
ssh_ops()       { ssh $SSH_OPTS ${SSH_USER}@${OPS_HOST} "$@"; }

ssh_node() {
    local node="$1"; shift
    case "$node" in
        primary|pg-primary)     ssh $SSH_OPTS ${SSH_USER}@${PRIMARY_HOST} "$@" ;;
        replica|pg-replica)     ssh $SSH_OPTS ${SSH_USER}@${REPLICA_HOST} "$@" ;;
        container|pg-container) ssh $SSH_OPTS ${SSH_USER}@${CONTAINER_HOST} "$@" ;;
        ops|pg-ops)             ssh $SSH_OPTS ${SSH_USER}@${OPS_HOST} "$@" ;;
        *) echo "Unknown node: $node (use primary, replica, container, or ops)" && return 1 ;;
    esac
}

# ---- PostgreSQL ------------------------------------------------------------
PG_VERSION="17"
PG_PORT=5432
PG_USER="postgres"
PG_DB="quantdb"
PG_DATA="/var/lib/pgsql/17/data"
PG_CONF="/var/lib/pgsql/17/data"
PG_BIN="/usr/pgsql-17/bin"

# ---- PgBouncer -------------------------------------------------------------
PGBOUNCER_PORT=6432
PGBOUNCER_CONF="/etc/pgbouncer/pgbouncer.ini"

# ---- Redis -----------------------------------------------------------------
REDIS_PORT=6379
REDIS_DOCKER_PORT=6380

# ---- Docker PostgreSQL (on pg-container) -----------------------------------
DOCKER_PG_PORT=5433
DOCKER_MYSQL_PORT=3306

# ---- pgBackRest ------------------------------------------------------------
PGBACKREST_STANZA="voleon-lab"
PGBACKREST_REPO="/var/lib/pgbackrest"

# ---- Monitoring (on pg-ops) ------------------------------------------------
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
NODE_EXPORTER_PORT=9100
PG_EXPORTER_PORT=9187

# ---- Database Roles --------------------------------------------------------
ROLE_APP="quant_app"
ROLE_RESEARCH="quant_research"
ROLE_PIPELINE="quant_pipeline"
ROLE_READONLY="quant_readonly"
ROLE_REPLICATOR="replicator"

# ---- AWS -------------------------------------------------------------------
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="339276916173"
AWS_SG_ID="sg-029a684edd2cec982"
AWS_KEY_NAME="voleon-lab"
AWS_INSTANCE_IDS="i-03d20a24199d1e964 i-0b313e0c28c500f1f i-05db816887b16a67a i-0feac77811295369c"

# ---- Alerting (AWS SNS) ---------------------------------------------------
SNS_TOPIC_ARN=""      # Fill after SNS topic creation
SNS_REGION="us-east-1"

# ---- Runbook base URL -----------------------------------------------------
RUNBOOK_BASE_URL="https://github.com/hapi-suta/stepup-labs/blob/main/labs/postgres/voleon-dba-lab"

# ---- Chaos Results ---------------------------------------------------------
RESULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chaos/results"

# ---- Convenience -----------------------------------------------------------
psql_primary()  { psql -h "$PRIMARY_HOST" -U "$ROLE_APP" -d "$PG_DB" -p "$PG_PORT" "$@"; }
psql_bouncer()  { psql -h "$PRIMARY_HOST" -U "$ROLE_APP" -d "$PG_DB" -p "$PGBOUNCER_PORT" "$@"; }
psql_replica()  { psql -h "$REPLICA_HOST" -U "$ROLE_READONLY" -d "$PG_DB" -p "$PG_PORT" "$@"; }
psql_docker()   { psql -h "$CONTAINER_HOST" -U postgres -d postgres -p "$DOCKER_PG_PORT" "$@"; }
psql_admin()    { ssh_primary "sudo -u postgres $PG_BIN/psql -d $PG_DB" "$@"; }
mysql_docker()  { mysql -h "$CONTAINER_HOST" -u root -P "$DOCKER_MYSQL_PORT" "$@"; }
redis_primary() { redis-cli -h "$PRIMARY_HOST" -p "$REDIS_PORT" "$@"; }
redis_docker()  { redis-cli -h "$CONTAINER_HOST" -p "$REDIS_DOCKER_PORT" "$@"; }
