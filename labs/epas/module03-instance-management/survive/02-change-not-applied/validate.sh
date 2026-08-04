#!/bin/bash
# PASS when the running server's work_mem actually equals the value set in the file
# (128MB) - i.e. the student reloaded so the change took effect.
set -u
live=$(sudo -u enterprisedb /usr/edb/as16/bin/psql -p 5444 -d edb -Atc "SHOW work_mem;" 2>/dev/null)

if [[ "$live" == "128MB" ]]; then
    echo "PASS - work_mem is live at 128MB; the change was reloaded and applied."
    exit 0
fi
echo "FAIL: the running server reports work_mem = '${live:-unknown}', not 128MB."
echo "      The value in postgresql.conf has not been made live yet."
exit 1
