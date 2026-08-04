# Runbook: a config change is "not working"

## What is being tested

Someone raised `work_mem` in `postgresql.conf`, but the database still behaves as if it
did not change. You need to know the difference between *editing a config file* and
*the running server actually using it* - and how to close that gap without an outage.

## Why this matters in production

This is the quiet mistake behind countless "I already changed that" arguments. Editing
`postgresql.conf` changes the file on disk; the running instance does not re-read it
until you tell it to. Miss this and you spend an afternoon convinced a setting is live
when it never took.

## Symptoms

- `postgresql.conf` clearly contains the new value.
- But `SHOW <parameter>;` in the database returns the old value.
- No error anywhere - it just "doesn't work."

## Diagnostic hints (not the answer)

1. Confirm the two views disagree. Read the value in the file:
   `sudo grep work_mem /var/lib/edb/as16/data/postgresql.conf`.
   Then read what the server actually uses:
   `SHOW work_mem;` from `edb-psql -p 5444 -d edb`.
2. They differ. Ask: what makes a running server pick up a changed file?
3. Recall from BUILD 03 the two ways a change takes effect - reload vs restart - and
   check this parameter's `context` in `pg_settings`. Is a reload enough here, or does
   it need a restart?

## Recovery

1. `work_mem` is not a `postmaster` parameter, so a **reload** applies it - no
   downtime: `sudo systemctl reload edb-as-16`.
2. Confirm with `SHOW work_mem;` - it should now read `128MB`.

## What good looks like

`SHOW work_mem;` returns `128MB`. Run `validate.sh` to confirm.
