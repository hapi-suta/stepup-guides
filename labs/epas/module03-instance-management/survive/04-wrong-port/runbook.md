# Runbook: running, but unreachable on 5444

## What is being tested

Applications report "connection refused" on port 5444, yet `systemctl` says the EPAS
service is `active`. A running server that nothing can reach is a classic trap. You
need to find *where* it is actually listening and put it back.

## Why this matters in production

EPAS's port (5444) is not PostgreSQL's (5432), and a well-meaning change - copying a
community-Postgres config, a fat-fingered edit - can move it. The service is healthy,
so monitoring that only checks "is the process up?" stays green while every application
is down. The lesson: "the service is running" and "clients can connect" are two
different checks.

## Symptoms

- `sudo systemctl is-active edb-as-16` says `active`.
- Clients on port 5444 get "connection refused".

## Diagnostic hints (not the answer)

1. Confirm the split: the service is up (`is-active`), but a connection on 5444 fails
   (`edb-psql -p 5444 -d edb`).
2. If it is up but not on 5444, then it is listening somewhere else. Ask the operating
   system what ports the database process holds:
   `sudo ss -tlnp | grep edb-postgres` (or just `sudo ss -tlnp`). Note the port it is
   actually on.
3. The server's startup log also announces its port. The newest file in
   `/var/lib/edb/as16/data/log/` will contain a line like "listening on ... port ...".
4. Now ask: what in `postgresql.conf` sets the port, and what changed?

## Recovery

1. In `/var/lib/edb/as16/data/postgresql.conf`, remove (or correct back to 5444) the
   line that set the wrong port.
2. Port is a `postmaster` parameter, so it needs a **restart**, not a reload:
   `sudo systemctl restart edb-as-16`.
3. Confirm with `sudo ss -tlnp | grep 5444` and `edb-psql -p 5444 -d edb`.

## What good looks like

EPAS is listening on 5444, a connection there works, and the injected line is gone.
Run `validate.sh` to confirm.
