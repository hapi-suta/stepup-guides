#!/usr/bin/env bash
# =============================================================================
# Scenario 04: Docker Container Crash
# validate.sh - Confirm the Docker PG container is running and healthy
# =============================================================================
# Pass criteria:
#   1. Container 'voleon-pg' is in state 'running'
#   2. Port 5433 is accepting PostgreSQL connections
#   3. A query executes successfully inside the container
#   4. Container has been running for at least 10 seconds (not in crash loop)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

DOCKER_CONTAINER_NAME="voleon-pg"

log_info "Validating Scenario 04: Docker Container Crash recovery"
echo ""

PASS=0
FAIL=0

check_pass() { log_success "$1"; (( PASS++ )) || true; }
check_fail() { log_error   "$1"; (( FAIL++ )) || true; }

# ---- Check 1: SSH into container host ---------------------------------------
log_info "Check 1: Container host ${CONTAINER_HOST} is reachable..."
if check_ssh "$CONTAINER_HOST"; then
    check_pass "Container host ${CONTAINER_HOST} is reachable via SSH"
else
    check_fail "Cannot SSH into container host ${CONTAINER_HOST}"
    exit 1
fi

# ---- Check 2: Container is in 'running' state --------------------------------
log_info "Check 2: Container '${DOCKER_CONTAINER_NAME}' is running..."
CONTAINER_STATUS=$(ssh_container \
    "docker inspect --format '{{.State.Status}}' ${DOCKER_CONTAINER_NAME} 2>/dev/null || echo 'notfound'")

if [[ "$CONTAINER_STATUS" == "running" ]]; then
    check_pass "Container '${DOCKER_CONTAINER_NAME}' is in state: running"
else
    check_fail "Container '${DOCKER_CONTAINER_NAME}' is in state: ${CONTAINER_STATUS}"
fi

# ---- Check 3: Container uptime is at least 10 seconds -----------------------
log_info "Check 3: Container has been running for at least 10 seconds..."
STARTED_AT=$(ssh_container \
    "docker inspect --format '{{.State.StartedAt}}' ${DOCKER_CONTAINER_NAME} 2>/dev/null || echo ''")

if [[ -n "$STARTED_AT" ]]; then
    # Get container uptime from the remote host (avoids macOS date parsing issues)
    UPTIME=$(ssh_container \
        "python3 -c \"from datetime import datetime,timezone; import sys; \
        s='${STARTED_AT}'.split('.')[0].replace('T',' '); \
        d=datetime.strptime(s,'%Y-%m-%d %H:%M:%S').replace(tzinfo=timezone.utc); \
        print(int((datetime.now(timezone.utc)-d).total_seconds()))\" 2>/dev/null || echo '0'"
    )
    UPTIME=$(echo "$UPTIME" | tr -d '[:space:]')

    if (( UPTIME >= 10 )); then
        check_pass "Container has been running for ${UPTIME}s (not in crash loop)"
    else
        check_fail "Container only started ${UPTIME}s ago - may be in a restart loop"
    fi
else
    log_warn "Could not determine container start time - skipping uptime check"
fi

# ---- Check 4: Port 5433 accepts PostgreSQL connections ----------------------
log_info "Check 4: PostgreSQL responding on ${CONTAINER_HOST}:${DOCKER_PG_PORT}..."
if check_pg "$CONTAINER_HOST" "$DOCKER_PG_PORT"; then
    check_pass "PostgreSQL is accepting connections on ${CONTAINER_HOST}:${DOCKER_PG_PORT}"
else
    check_fail "PostgreSQL is not responding on ${CONTAINER_HOST}:${DOCKER_PG_PORT}"
fi

# ---- Check 5: A query executes successfully ---------------------------------
log_info "Check 5: Query executes inside the container database..."
QUERY_RESULT=$(PGPASSWORD=docker_pg_2026 psql_docker -t -c "SELECT version();" 2>&1 || echo "FAILED")

if echo "$QUERY_RESULT" | grep -qi "postgresql"; then
    check_pass "Query executed successfully inside container (PostgreSQL is healthy)"
else
    check_fail "Query inside container failed: ${QUERY_RESULT}"
fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo -e "  Results: ${GREEN}PASS: ${PASS}${RESET}  ${RED}FAIL: ${FAIL}${RESET}"
echo ""

if (( FAIL == 0 )); then
    log_success "Scenario 04 PASSED - Docker container is running and healthy"
    exit 0
else
    log_error "Scenario 04 FAILED - ${FAIL} check(s) did not pass"
    exit 1
fi
