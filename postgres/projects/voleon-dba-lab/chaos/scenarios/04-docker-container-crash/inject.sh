#!/usr/bin/env bash
# =============================================================================
# Scenario 04: Docker Container Crash
# inject.sh - Force-kill the voleon-pg Docker container
# =============================================================================
# What breaks: The PostgreSQL instance running in Docker on pg-container
#              (port 5433) stops accepting connections. Any application
#              relying on the container database loses connectivity.
# Your job:    Identify the crashed container, investigate why it stopped,
#              restart it, and verify the database is accessible again.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

DOCKER_CONTAINER_NAME="voleon-pg"

log_info "Scenario 04: Docker Container Crash"
log_info "Target: ${DOCKER_CONTAINER_NAME} on ${CONTAINER_HOST}"
echo ""

# Confirm we can reach the container host
log_info "Checking SSH connectivity to container host..."
if ! check_ssh "$CONTAINER_HOST"; then
    log_error "Cannot SSH into container host (${CONTAINER_HOST})"
    exit 1
fi
log_success "Container host is reachable"

# Confirm the container is currently running
log_info "Checking container status..."
CONTAINER_STATUS=$(ssh_container "docker inspect --format '{{.State.Status}}' ${DOCKER_CONTAINER_NAME} 2>/dev/null || echo 'notfound'")
log_info "Container status: ${CONTAINER_STATUS}"

if [[ "$CONTAINER_STATUS" == "notfound" ]]; then
    log_error "Container '${DOCKER_CONTAINER_NAME}' not found on ${CONTAINER_HOST}."
    log_error "Make sure you have completed BUILD-06 (Docker Databases) before running this scenario."
    exit 1
fi

if [[ "$CONTAINER_STATUS" != "running" ]]; then
    log_warn "Container is already in state '${CONTAINER_STATUS}'. Proceeding anyway."
fi

# Confirm the Docker PG port is currently responding
if check_pg "$CONTAINER_HOST" "$DOCKER_PG_PORT"; then
    log_success "Docker PostgreSQL is currently accepting connections on port ${DOCKER_PG_PORT}"
else
    log_warn "Docker PostgreSQL on port ${DOCKER_PG_PORT} is already not responding"
fi

echo ""
log_warn "Force-killing container '${DOCKER_CONTAINER_NAME}' with SIGKILL..."
ssh_container "docker kill ${DOCKER_CONTAINER_NAME}"

sleep 2

# Verify it actually stopped
NEW_STATUS=$(ssh_container "docker inspect --format '{{.State.Status}}' ${DOCKER_CONTAINER_NAME} 2>/dev/null || echo 'notfound'")
log_info "Container state after kill: ${NEW_STATUS}"

if [[ "$NEW_STATUS" == "running" ]]; then
    log_error "Container is still running after docker kill. This is unexpected."
    exit 1
fi

# Confirm port is no longer responding
if check_pg "$CONTAINER_HOST" "$DOCKER_PG_PORT" 2>/dev/null; then
    log_warn "Port ${DOCKER_PG_PORT} is still responding. Container may have a restart policy."
else
    log_success "Docker PostgreSQL on port ${DOCKER_PG_PORT} is no longer responding"
fi

echo ""
echo "  Container '${DOCKER_CONTAINER_NAME}' on ${CONTAINER_HOST} is DOWN."
echo "  Port ${DOCKER_PG_PORT} is no longer accepting PostgreSQL connections."
echo ""
echo "  Your tasks:"
echo "    1. SSH into ${CONTAINER_HOST}"
echo "    2. Check container state: docker ps -a"
echo "    3. Review container exit code and logs: docker logs ${DOCKER_CONTAINER_NAME}"
echo "    4. Restart the container: docker start ${DOCKER_CONTAINER_NAME}"
echo "    5. Verify PostgreSQL inside is accepting connections"
echo "       psql -h ${CONTAINER_HOST} -p ${DOCKER_PG_PORT} -U postgres -d postgres"
echo "    6. Check if data is intact after crash recovery"
echo ""
echo "  When done: ./chaos.sh validate 04-docker-container-crash"
