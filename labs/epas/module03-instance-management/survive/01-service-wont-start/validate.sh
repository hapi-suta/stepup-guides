#!/bin/bash
# Deterministic pass/fail for SURVIVE 01.
# PASS when: the EPAS service is active AND the bad line is gone from postgresql.conf.
set -u
CONF=/var/lib/edb/as16/data/postgresql.conf

active=$(sudo systemctl is-active edb-as-16 2>/dev/null)
# grep -c prints 0 (and exits 1) when there are no matches - capture the count, not
# the exit code; a trailing "|| echo 0" would append a second 0 and break the test.
still_bad=$(sudo grep -c "CHAOS-M03-S01 injected" "$CONF" 2>/dev/null)
still_bad=${still_bad:-0}

if [[ "$active" == "active" && "$still_bad" -eq 0 ]]; then
    echo "PASS - EPAS is running and the bad parameter is gone."
    exit 0
fi

echo "FAIL:"
[[ "$active" != "active" ]] && echo "  - edb-as-16 is '$active', not 'active' (the database is still down)."
[[ "$still_bad" -ne 0 ]] && echo "  - the injected line is still in postgresql.conf."
exit 1
