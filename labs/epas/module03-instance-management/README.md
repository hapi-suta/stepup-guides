# Module 03 - Instance Management

**Track:** EPAS (EDB Postgres Advanced Server 16)
**Topology:** `epas-single` (one server, the box you installed EPAS on in Module 02)
**Prerequisites:** Module 02 complete - EPAS 16 installed, initialized, and running.

## What you will be able to do

By the end of this module you can run an EPAS instance day to day the way a
production DBA does:

- Start, stop, restart, and reload the `edb-as-16` service, and know the
  difference between a reload and a restart (and why it matters).
- Connect to the database with both clients - `edb-psql` (the psql-style client)
  and `edbplus` (the Oracle SQL\*Plus-compatible client your Oracle muscle memory
  already knows).
- Find and edit the configuration files (`postgresql.conf`, `postgresql.auto.conf`,
  `pg_hba.conf`), change a parameter, and make it take effect the right way.
- Read the server log and confirm what the instance is actually doing.

## Oracle bridge

If you run Oracle today: the `edb-as-16` service is your `dbstart`/`dbshut` plus
the listener, rolled into one systemd unit. `edbplus` is EDB's `sqlplus`.
`postgresql.conf` is your `init.ora`/`spfile`, and `SHOW`/`ALTER SYSTEM` are your
`SHOW PARAMETER`/`ALTER SYSTEM`. The data directory (`PGDATA`) is the closest thing
to `ORACLE_BASE/oradata` for one instance.

## Structure

- `concepts/` - how an EPAS instance is put together and why the pieces exist.
- `build/` - hands-on: service control, the two clients, the config files.
- `use/` - exercises to make it stick.
- `survive/` - four things that break in production; you diagnose and fix them.

## Time

About 90 minutes for BUILD + USE. The SURVIVE scenarios are 15-30 minutes each.

## Next

Module 04 - Users, roles, profiles, RLS, and security.
