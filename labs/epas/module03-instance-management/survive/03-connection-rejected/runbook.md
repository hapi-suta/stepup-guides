# Runbook: connections are being rejected

## What is being tested

The EPAS process is running, yet every connection - even `edb-psql` on the server
itself - is refused. This is not a "database is down" problem; it is an
**authentication policy** problem, and the fix is in `pg_hba.conf`, not the service.

## Why this matters in production

`pg_hba.conf` is the front door's lock. A single wrong line - a rule set to `reject`,
a method the client cannot satisfy, rules in the wrong order - locks everyone out while
the server sits there perfectly healthy. Knowing that a running server can still refuse
every login, and where that decision lives, saves you from needlessly bouncing (or
worse, rebuilding) a healthy instance.

## Symptoms

- `sudo systemctl is-active edb-as-16` says `active` - the server is up.
- `edb-psql -p 5444 -d edb` fails immediately with a message mentioning `pg_hba.conf`
  and "no pg_hba.conf entry" or "connection rejected".

## Diagnostic hints (not the answer)

1. First prove the server is actually up (`is-active`, and `sudo ss -tlnp | grep 5444`
   shows it listening). If it is up but refusing you, the problem is authentication,
   not the service.
2. Read the exact client error - it will point you straight at `pg_hba.conf`.
3. Open `/var/lib/edb/as16/data/pg_hba.conf`. The rules are read top to bottom; the
   first match wins. Look at the `local` line (Unix socket connections) - what METHOD
   is it set to? A healthy lab uses `peer` for local.
4. You do not need a database connection to fix this - you edit the file as root and
   reload.

## Recovery

1. In `pg_hba.conf`, set the local rule's method back to `peer`:
   `local   all   all   peer`.
2. `pg_hba.conf` is picked up on a reload: `sudo systemctl reload edb-as-16`.
3. Confirm `edb-psql -p 5444 -d edb` connects again.

## What good looks like

A local `edb-psql` connection succeeds. Run `validate.sh` to confirm.
