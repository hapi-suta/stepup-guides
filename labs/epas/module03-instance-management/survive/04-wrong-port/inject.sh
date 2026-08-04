#!/bin/bash
# Chaos: the database is running but nobody can reach it on 5444
# Target: epas-single
# Difficulty: mid
# Expected fix time: 15 minutes
#
# What we break: append port = 5433 to postgresql.conf and restart, so EPAS comes up
# healthy but listening on the wrong port. Clients hard-coded to 5444 get "connection
# refused" even though the server is fine. The student must discover the real port,
# put it back to 5444, and restart. Idempotent.
set -u
CONF=/var/lib/edb/as16/data/postgresql.conf
MARK="# CHAOS-M03-S04 injected"

if ! sudo grep -q "$MARK" "$CONF"; then
    echo "port = 5433   $MARK" | sudo tee -a "$CONF" >/dev/null
    sudo systemctl restart edb-as-16 >/dev/null 2>&1
fi

echo "Chaos injected: applications report 'connection refused' on port 5444, but the"
echo "EPAS service shows as running. Find out where it is actually listening and fix it."
