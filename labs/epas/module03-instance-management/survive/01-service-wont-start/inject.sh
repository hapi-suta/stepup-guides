#!/bin/bash
# Chaos: EPAS service will not start after a config change
# Target: epas-single
# Difficulty: junior
# Expected fix time: 15 minutes
#
# What we break: append an impossible value for a postmaster (restart-only)
# parameter to postgresql.conf, then bounce the service so it fails to come back.
# The student finds the database down and `systemctl start` failing. The clue is in
# the server log: "invalid value" / "could not map anonymous shared memory". The fix
# is to remove the bad line and restart. Idempotent - safe to run more than once.
set -u
CONF=/var/lib/edb/as16/data/postgresql.conf
MARK="# CHAOS-M03-S01 injected"

# Idempotent: only inject once.
if ! sudo grep -q "$MARK" "$CONF"; then
    echo "shared_buffers = 999TB   $MARK" | sudo tee -a "$CONF" >/dev/null
fi

# Bounce so the running server tries to load the bad value and fails.
sudo systemctl restart edb-as-16 >/dev/null 2>&1

echo "Chaos injected: the EPAS service is down and will not start."
echo "Your database on epas-single is unreachable. Diagnose and bring it back up."
