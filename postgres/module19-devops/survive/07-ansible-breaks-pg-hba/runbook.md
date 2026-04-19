# SURVIVE 07: Ansible Breaks pg_hba.conf - Runbook

## Symptom

All applications report "FATAL: pg_hba.conf rejects connection for host" when trying to connect to PostgreSQL. A recent Ansible playbook run deployed a broken pg_hba.conf.

---

## Step 1: Verify the Problem

Try a TCP connection. The `-h 127.0.0.1` flag forces a TCP connection instead of a local socket.

```bash
sudo -iu postgres
```

```bash
psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT 1;"
```

Expected error:
```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "127.0.0.1", user "postgres", database "postgres", no encryption
```

This confirms TCP connections are blocked.

---

## Step 2: Connect via Local Socket

Local socket connections (peer authentication) should still work because the broken pg_hba.conf still has a `local` entry.

```bash
psql -c "SELECT 1;"
```

Expected output:
```
 ?column?
----------
        1
(1 row)
```

If this works, you can fix the problem.

---

## Step 3: Check the Current pg_hba.conf

Look at the loaded rules.

```bash
psql -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules ORDER BY line_number;"
```

Expected output (yours will differ):
```
 line_number | type  | database | user_name |  address  | auth_method
-------------+-------+----------+-----------+-----------+-------------
           5 | local | {all}    | {postgres}|           | peer
           8 | host  | {all}    | {all}     | 0.0.0.0/0 | reject
           9 | host  | {all}    | {all}     | ::0/0     | reject
```

The problem is clear: all host connections are set to `reject`.

---

## Step 4: Check for the Backup

Ansible usually creates backups when deploying config files (if `backup: yes` is set).

```bash
ls -la /opt/pgsql/data/pg_hba.conf*
```

If there is a `.good` backup, restore it.

```bash
cp /opt/pgsql/data/pg_hba.conf.good /opt/pgsql/data/pg_hba.conf
```

If no backup exists, write a correct pg_hba.conf. Exit psql first.

```bash
\q
```

Open the file with vi.

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Replace the contents with:

```
# pg_hba.conf - Fixed
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 localhost
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 localhost
host    all             all             ::1/128                 scram-sha-256

# Application connections from private network
host    all             all             10.0.0.0/8              scram-sha-256
```

Save and exit.

---

## Step 5: Validate the Config File

Before reloading, check that the file has no syntax errors.

```bash
psql -c "SELECT pg_reload_conf();"
```

Check for any errors in the config.

```bash
psql -c "SELECT line_number, error FROM pg_hba_file_rules WHERE error IS NOT NULL;"
```

Expected output:
```
 line_number | error
-------------+-------
(0 rows)
```

Zero rows means no syntax errors.

---

## Step 6: Verify Remote Connections Work

Test a TCP connection.

```bash
psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT 1;"
```

Expected output:
```
 ?column?
----------
        1
(1 row)
```

Exit the postgres user.

```bash
exit
```

---

## Prevention

1. **Always validate pg_hba.conf before reloading** - Use `pg_hba_file_rules` to check for errors
2. **Ansible backup** - Always use `backup: yes` on config file templates
3. **Test with --check first** - Run `ansible-playbook --check --diff` before applying
4. **Never use `reject` as a catch-all** - Use specific deny rules only for specific hosts
5. **Keep a local peer entry** - Always maintain `local all postgres peer` as the first rule so you can recover via local socket
6. **Canary connection test** - Add an Ansible task that tests a TCP connection after deploying pg_hba.conf, and rolls back if it fails

---

## Discussion Points

- Why does `local` still work when `host` is broken? Because `local` uses Unix domain sockets (no TCP/IP) and has its own pg_hba.conf rules
- What if the `local` line was also removed? You would need to stop PostgreSQL, edit pg_hba.conf, and restart. Or use `pg_ctl reload` which does not need a database connection
- How can Ansible prevent this? Add a post-deploy task that tests TCP connectivity and rolls back pg_hba.conf if the test fails
