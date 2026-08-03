#!/usr/bin/env bash
#
# SURVIVE scenario: docker-port-conflict
# validate.sh - exits 0 when port 8000 serves the student's own container.
#
# Passing criteria:
#   1. The offending 'port-hog' container is gone.
#   2. A container named 'my-app' is running and mapping host port 8000.
#   3. Port 8000 actually answers an HTTP request (status code returned).
#
# Run this on your lab server as ec2-user.

# Choose how to call docker (sudo fallback if not in the docker group).
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

fail() {
    echo "[validate] FAIL: $1"
    exit 1
}

# 1. The port-hog must be gone.
if ${DOCKER} ps --format '{{.Names}}' | grep -q '^port-hog$'; then
    fail "the 'port-hog' container is still running and holding port 8000. Remove it (runbook step 5)."
fi

# 2. my-app must be running and mapping port 8000.
if ! ${DOCKER} ps --format '{{.Names}}' | grep -q '^my-app$'; then
    fail "no running container named 'my-app'. Start it on port 8000 (runbook step 7)."
fi

if ! ${DOCKER} ps --filter name=my-app --format '{{.Ports}}' | grep -q '8000'; then
    fail "'my-app' is not mapping host port 8000. Re-run with -p 8000:8000 (runbook step 7)."
fi

# 3. Port 8000 must actually respond.
CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000 2>/dev/null)"
if [ -z "${CODE}" ] || [ "${CODE}" = "000" ]; then
    fail "nothing responds on http://localhost:8000. Check the container logs (docker logs my-app)."
fi

echo "[validate] PASS: 'my-app' is running and serving on port 8000 (HTTP ${CODE})"
exit 0
