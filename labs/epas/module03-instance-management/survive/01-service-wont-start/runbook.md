# Runbook: EPAS service will not start

## What is being tested

Your EPAS instance is down and `systemctl start edb-as-16` fails. This is the single
most common production page: someone changed a parameter and the server will not come
back. You need to find *which* parameter, from the evidence the server leaves behind -
not by guessing.

## Why this matters in production

A restart-only (`postmaster`) parameter with a bad value passes a reload silently but
kills the next restart. Weeks later the server reboots for patching and never comes
back, and the on-call DBA has minutes to find the cause. The log is the source of
truth - learn to go there first.

## Symptoms

- `sudo systemctl is-active edb-as-16` returns `failed` or `activating`.
- `sudo systemctl status edb-as-16` shows the unit failed to start.
- Applications cannot connect (connection refused on port 5444).

## Diagnostic hints (not the answer)

1. Confirm the state and read the unit's own message:
   `sudo systemctl status edb-as-16` - note it says the control process exited with an
   error, and points you at the logs.
2. The database's own reason is in its log, not journald. The log directory is inside
   the data directory: `/var/lib/edb/as16/data/log/`. Read the newest file and look at
   the last lines around the failed start.
3. The log will name the offending parameter and why it is unacceptable (an invalid or
   impossible value). Ask yourself: what changed recently in `postgresql.conf`?
4. Once you know the parameter, open `postgresql.conf`
   (`/var/lib/edb/as16/data/postgresql.conf`) and find the bad line.

## Recovery

1. Remove or correct the bad line in `postgresql.conf` (vi it as needed).
2. Start the service and confirm it is `active`.
3. Verify you can connect with `edb-psql -p 5444 -d edb`.

## What good looks like

`sudo systemctl is-active edb-as-16` prints `active`, and the injected line is no
longer in `postgresql.conf`. Run `validate.sh` to confirm.
