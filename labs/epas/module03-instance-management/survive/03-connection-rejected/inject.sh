#!/bin/bash
# Chaos: nobody can connect - pg_hba rejects local connections
# Target: epas-single
# Difficulty: mid
# Expected fix time: 15 minutes
#
# What we break: change the local (Unix-socket) rule in pg_hba.conf from 'peer' to
# 'reject' and reload, so even edb-psql on the box is refused. The server is UP - this
# is purely an authentication policy problem. The student fixes it by editing
# pg_hba.conf as root (no DB login needed) and reloading. Idempotent.
set -u
HBA=/var/lib/edb/as16/data/pg_hba.conf

# Only inject if the local rule is still 'peer'.
if sudo grep -qE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+peer' "$HBA"; then
    sudo cp "$HBA" "${HBA}.chaos-s03-bak"
    sudo sed -i -E '/^local[[:space:]]+all[[:space:]]+all[[:space:]]+peer/ s/peer/reject/' "$HBA"
    sudo systemctl reload edb-as-16 >/dev/null 2>&1
fi

echo "Chaos injected: connections are being refused even from the server itself."
echo "The database process is running. Find why logins are rejected and restore access."
