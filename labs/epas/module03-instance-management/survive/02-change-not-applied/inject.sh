#!/bin/bash
# Chaos: a configuration change is "not working"
# Target: epas-single
# Difficulty: junior
# Expected fix time: 10 minutes
#
# What we break: write a new work_mem into postgresql.conf but do NOT reload, so the
# file says one thing and the running server still reports the old value. The student
# is told "I raised work_mem but SHOW still says 8MB" and must realize a file edit
# needs a reload to take effect. Idempotent.
set -u
CONF=/var/lib/edb/as16/data/postgresql.conf
MARK="# CHAOS-M03-S02 injected"

if ! sudo grep -q "$MARK" "$CONF"; then
    echo "work_mem = '128MB'   $MARK" | sudo tee -a "$CONF" >/dev/null
fi
# Deliberately do NOT reload - that is the whole point.

echo "Chaos injected: work_mem is set to 128MB in postgresql.conf, but a check shows"
echo "the server is still using the old value. Make the change actually take effect."
