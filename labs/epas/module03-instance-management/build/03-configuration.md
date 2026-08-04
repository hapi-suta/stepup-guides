# BUILD 03 - Configuration Files and Making Changes Take Effect

An EPAS instance reads its settings from a small set of files in the data directory.
Knowing which file to touch, and whether a change needs a reload or a full restart,
is the difference between a clean production change and an outage. This guide walks
both paths.

The configuration files live in the data directory, `/var/lib/edb/as16/data/`:

- **`postgresql.conf`** - the main settings file. You edit this by hand.
- **`postgresql.auto.conf`** - written by the `ALTER SYSTEM` SQL command. You do
  **not** edit this by hand.
- **`pg_hba.conf`** - who may connect and how (you changed this in BUILD 02).

> **Oracle bridge:** `postgresql.conf` is your `init.ora`. `ALTER SYSTEM` writing to
> `postgresql.auto.conf` is EPAS's `ALTER SYSTEM ... SCOPE=SPFILE` - a managed file
> you change through SQL, not a text editor.

## 1. See a parameter's current value

You will change `work_mem` (memory per sort/hash operation). First read its value.

On **epas-single**, as **enterprisedb** (switch in with `sudo -iu enterprisedb`, then):

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SHOW work_mem;"
```

Expected output (yours will differ):

```
 work_mem
----------
 8MB
```

## 2. Change it with ALTER SYSTEM

`ALTER SYSTEM` is the safe, SQL way to change a setting - it writes to
`postgresql.auto.conf` for you.

Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER SYSTEM SET work_mem = '16MB';"
```

Expected output (yours will differ):

```
ALTER SYSTEM
```

Nothing has changed yet - the setting is written to the file but the running server
has not re-read it.

## 3. Reload, and confirm it took effect

`work_mem` is a "reload" parameter, so a reload (not a restart) is enough.

Switch back to the ec2-user shell to run systemctl:

```bash
exit
```

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl reload edb-as-16
```

- No output on success.

Now check the value again. Back as **enterprisedb** on **epas-single** (`sudo -iu enterprisedb`, then):

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SHOW work_mem;"
```

Expected output (yours will differ):

```
 work_mem
----------
 16MB
```

The reload applied it with zero downtime - no connection was dropped.

## 4. A parameter that needs a full restart

Some settings can only change at startup. `shared_buffers` (the server's main memory
cache) is the classic one. Change it and watch what happens on a reload.

Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER SYSTEM SET shared_buffers = '256MB';"
```

Exit to ec2-user and reload:

```bash
exit
```

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl reload edb-as-16
```

The reload succeeds, but the change is **not** live. EPAS records that this
parameter is waiting for a restart. Check it - back as **enterprisedb**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SELECT name, pending_restart FROM pg_settings WHERE name IN ('shared_buffers','work_mem');"
```

Expected output (yours will differ):

```
     name       | pending_restart
----------------+-----------------
 shared_buffers | t
 work_mem       | f
```

`pending_restart = t` on `shared_buffers` is EPAS telling you: "I have your new value
but I cannot use it until you restart me." `work_mem` is `f` - it already applied on
the reload.

## 5. How to know which, BEFORE you change anything

You do not have to guess or find out the hard way. Every parameter carries a
`context` that tells you how it can change. Query it.

Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SELECT name, context FROM pg_settings WHERE name IN ('port','shared_buffers','max_connections','work_mem','log_min_duration_statement') ORDER BY context, name;"
```

Expected output (yours will differ):

```
          name           |  context
-------------------------+------------
 max_connections         | postmaster
 port                    | postmaster
 shared_buffers          | postmaster
 log_min_duration_statement | superuser
 work_mem                | user
```

Read the `context` column:

- **`postmaster`** - needs a full **restart** (`port`, `shared_buffers`,
  `max_connections`).
- **`sighup`**, **`superuser`**, **`user`** - takes effect on a **reload** (or even
  per-session). `work_mem` and `log_min_duration_statement` are here.

So the rule is: check `context` first. If it says `postmaster`, plan a restart window;
anything else, a reload is enough.

## 6. Apply the restart change and clean up

Because you changed a `postmaster` parameter, do the restart to apply it. On
**epas-single**, as **ec2-user**:

```bash
sudo systemctl restart edb-as-16
```

For the lab, put the values back to defaults so later modules start clean. As
**enterprisedb** on **epas-single**, run each reset on its own (ALTER SYSTEM cannot be
chained in one statement):

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER SYSTEM RESET work_mem;"
```

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER SYSTEM RESET shared_buffers;"
```

Exit to ec2-user and restart once more so both resets are fully live:

```bash
exit
```

```bash
sudo systemctl restart edb-as-16
```

## Checkpoint

You can now:

- [x] Name the three config files and which tool owns each
- [x] Change a parameter with `ALTER SYSTEM` and apply it with a reload
- [x] Recognize `pending_restart = t` and know it means a restart is required
- [x] Use the `pg_settings.context` column to tell reload-vs-restart in advance

Next: **USE - hands-on exercises**, then the **SURVIVE** scenarios where these break.
