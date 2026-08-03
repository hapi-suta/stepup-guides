#!/usr/bin/env bash
#
# SURVIVE scenario: docker-port-conflict
# inject.sh - starts a container that hogs port 8000.
#
# What this does (the "break"):
#   Starts a background container named 'port-hog' that binds host port 8000.
#   Later, when the student tries to run THEIR app (the container named
#   'my-app') on port 8000, Docker refuses because the port is already taken.
#
# The student's job: find what is using port 8000, free it, and run their own
# container on 8000 instead.
#
# Safe to run on CentOS Stream 9 as ec2-user (Docker installed, user in the
# 'docker' group per the BUILD module). Self-contained. Idempotent.

set -u

# Choose how to call docker (needs sudo if the user is not in the docker group).
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

echo "[inject] Setting up docker-port-conflict scenario"

# Clean any leftovers from a previous run.
${DOCKER} rm -f port-hog >/dev/null 2>&1 || true
${DOCKER} rm -f my-app   >/dev/null 2>&1 || true

# Start a tiny web server container that grabs host port 8000.
# python:3.12-slim is small and reliable; it serves the container filesystem.
${DOCKER} run -d --name port-hog -p 8000:8000 python:3.12-slim \
    python -m http.server 8000 >/dev/null 2>&1

sleep 2

if ${DOCKER} ps --format '{{.Names}}' | grep -q '^port-hog$'; then
    echo "[inject] DONE. A container 'port-hog' is now holding host port 8000."
else
    echo "[inject] WARNING: could not confirm 'port-hog' started. Check '${DOCKER} ps -a'."
fi

echo "[inject] Your job: find what is using port 8000, free it, and start your"
echo "[inject] own container named 'my-app' listening on host port 8000."
echo "[inject] See runbook.md. Then run: bash validate.sh"
