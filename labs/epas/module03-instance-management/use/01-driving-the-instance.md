# USE 01 - Driving the Instance

These exercises make the BUILD steps stick. Try each one yourself before you open the
solution. Every command runs on **epas-single**; the prompt reminds you which user.

---

## Exercise 1 - Is it up, and where does it live?

Without opening the full status page, answer three questions using one-line commands:
is the service active, is it set to start on boot, and what data directory is the
running server using?

<details>
<summary>Solution</summary>

As **ec2-user** on **epas-single**:

```bash
sudo systemctl is-active edb-as-16
sudo systemctl is-enabled edb-as-16
sudo systemctl show edb-as-16 -p Environment
```

`is-active` prints `active`; `is-enabled` prints `enabled`; the `Environment` line
shows `PGDATA=/var/lib/edb/as16/data`. (You could also read it off `systemctl status`,
but these are the surgical one-liners.)

</details>

---

## Exercise 2 - Change a setting the online way

The default `log_min_duration_statement` is `-1` (off), meaning slow queries are not
logged. Turn on logging of any statement that takes longer than 500 ms - and do it
**without** disconnecting anyone. Then confirm it is live.

<details>
<summary>Solution</summary>

`log_min_duration_statement` has context `superuser`, so a reload is enough - no
restart. As **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER SYSTEM SET log_min_duration_statement = '500ms';"
```

Exit to **ec2-user** and reload:

```bash
sudo systemctl reload edb-as-16
```

Confirm (back as **enterprisedb**):

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SHOW log_min_duration_statement;"
```

It reads `500ms`. Put it back with `ALTER SYSTEM RESET log_min_duration_statement;`
and reload when you are done.

</details>

---

## Exercise 3 - Would this need a restart?

A colleague wants to raise `max_connections` from 100 to 200 tonight and asks whether
they can do it live or need a maintenance window. Answer it *from the database*, not
from memory.

<details>
<summary>Solution</summary>

Check the parameter's context. As **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "SELECT name, context FROM pg_settings WHERE name = 'max_connections';"
```

`context` is `postmaster` - so it can only change at startup. Your colleague needs a
**restart**, i.e. a maintenance window. (Bonus: after they `ALTER SYSTEM SET
max_connections = 200` and reload, `pg_settings.pending_restart` for it will read `t`
until the restart happens.)

</details>

---

## Exercise 4 - Connect the Oracle way

Open `edbplus`, and from the `SQL>` prompt show the current user and the server
version, then exit - all in edbplus, not edb-psql.

<details>
<summary>Solution</summary>

As **enterprisedb** on **epas-single** (you set the password and the `scram-sha-256`
rule in BUILD 02):

```bash
/usr/edb/edbplus/edbplus.sh enterprisedb/LabPass2026@localhost:5444/edb
```

At the `SQL>` prompt:

```sql
SELECT USER FROM dual;
SELECT version();
EXIT;
```

`SELECT USER FROM dual;` returns `enterprisedb` - the Oracle-style way to ask "who am
I", working because EPAS provides `dual` and the `USER` pseudo-column.

</details>

---

## Checklist

- [ ] Report service state, boot state, and data dir with one-liners
- [ ] Make a live (reload-only) config change and verify it
- [ ] Decide reload-vs-restart from `pg_settings.context`
- [ ] Run a query from the `edbplus` `SQL>` prompt
