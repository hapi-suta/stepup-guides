#!/bin/bash
# PASS when EPAS is listening on 5444 again AND a connection on 5444 works AND the
# injected port line is gone.
set -u
CONF=/var/lib/edb/as16/data/postgresql.conf

listening=$(sudo ss -tlnp 2>/dev/null | grep -c ':5444 ')
still_bad=$(sudo grep -c "CHAOS-M03-S04 injected" "$CONF" 2>/dev/null); still_bad=${still_bad:-0}
conn=$(sudo -u enterprisedb /usr/edb/as16/bin/psql -p 5444 -d edb -Atc "SELECT 'ok';" 2>/dev/null)

if [[ "$listening" -ge 1 && "$conn" == "ok" && "$still_bad" -eq 0 ]]; then
    echo "PASS - EPAS is listening on 5444 and reachable, and the bad port line is gone."
    exit 0
fi
echo "FAIL:"
[[ "$listening" -lt 1 ]] && echo "  - nothing is listening on port 5444."
[[ "$conn" != "ok" ]]   && echo "  - a connection on 5444 does not work."
[[ "$still_bad" -ne 0 ]] && echo "  - the injected 'port = 5433' line is still in postgresql.conf."
exit 1
