# Scenario 10 - pg_hba.conf Blocks Connections

**Severity:** CRITICAL
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL is running but all connections fail.
Users report: FATAL: pg_hba.conf rejects connection
The security team updated authentication rules and now
nobody can connect to the database.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **pg_hba.conf and first-match-wins** - PostgreSQL reads `pg_hba.conf` from top to bottom for each connection attempt. The first rule that matches the connection's type, database, user, and address is used. If that rule says `reject`, the connection is denied immediately - PostgreSQL does not keep looking for a more permissive rule below it. This means rule ordering is everything. A broad `reject` rule at the top blocks all connections, regardless of what comes after.

- **reject vs deny** - In `pg_hba.conf`, the auth method `reject` unconditionally denies the connection and sends a clear error message to the client. There is no `deny` keyword - it is `reject`. The client sees `FATAL: pg_hba.conf rejects connection for host ...`. This is different from simply not having a matching rule, which produces `FATAL: no pg_hba.conf entry for host ...`.

- **Reload vs restart for HBA changes** - `pg_hba.conf` changes take effect with a reload - no restart needed. A reload sends SIGHUP to the postmaster, which re-reads all config files. Existing connections are NOT affected; only new connections use the updated rules. This means a bad HBA change does not kill active sessions, but it prevents new ones. Reload with `pg_ctl reload` or `kill -HUP <postmaster_pid>`.

- **Fixing HBA without SQL access** - If `pg_hba.conf` blocks all connections, you cannot run SQL commands to fix it. You must edit the file directly on disk as the `postgres` OS user. After editing, reload PostgreSQL using `pg_ctl reload` (run as postgres user) or `kill -HUP` on the postmaster PID. You do NOT need to restart - reload is sufficient and avoids downtime.

- **pg_hba_file_rules view** - PostgreSQL 15+ provides the `pg_hba_file_rules` system view, which shows the parsed rules from `pg_hba.conf` in order, including any errors. This is useful for auditing: `SELECT line_number, type, database, user_name, auth_method FROM pg_hba_file_rules;`. But you need a working connection to query it, so it is a post-fix verification tool in this scenario.

---

## Diagnostic Steps

### Step 1 - Attempt to connect

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 1;"
```

Expected output (yours will differ):

```
psql: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: FATAL:  pg_hba.conf rejects connection for host "[local]", user "postgres", database "labdb", no encryption
```

The error is very specific: `pg_hba.conf rejects connection`. This tells you a `reject` rule is matching before any permissive rule.

```bash
exit
```

### Step 2 - Confirm PostgreSQL is actually running

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

Expected output (yours will differ):

```
/var/run/postgresql:5432 - accepting connections
```

```bash
exit
```

`pg_isready` succeeds because it only checks if the postmaster is accepting TCP/socket connections at the protocol level. It does not perform HBA authentication. The server is healthy - just misconfigured for access.

### Step 3 - Inspect pg_hba.conf for the reject rule

Since you cannot connect via SQL, look at the file directly:

```bash
sudo cat /opt/pgsql/data/pg_hba.conf
```

Expected output (yours will differ):

```
# PostgreSQL Client Authentication Configuration File
# ...
# (comment lines)

# chaos injection - reject all local connections
local   all   all   reject

# original rules below
local   all   postgres                     peer
local   all   all                          peer
host    all   all   127.0.0.1/32           scram-sha-256
host    all   all   ::1/128                scram-sha-256
...
```

The problem is clear: `local all all reject` is the first non-comment rule. It matches every local connection before the `peer` rules below can be evaluated.

### Step 4 - Understand why this blocks everything

The reject rule matches:
- **Type:** `local` (Unix socket connections)
- **Database:** `all` (every database)
- **User:** `all` (every user)
- **Auth method:** `reject` (unconditional denial)

Since `psql` without `-h` connects via Unix socket (type `local`), it hits this rule first and gets rejected. The valid `peer` rule below never gets a chance to match.

---

## Resolution

### Step 1 - Edit pg_hba.conf to remove the reject rule

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Find and delete these lines:

```
# chaos injection - reject all local connections
local   all   all   reject
```

Remove both the comment line and the reject rule. Save and exit.

```bash
exit
```

### Step 2 - Verify the fix before reloading

```bash
sudo grep -n reject /opt/pgsql/data/pg_hba.conf
```

Expected output (yours will differ):

```
(no output)
```

No output means no `reject` rules remain. If you see any output, go back and remove the remaining reject lines.

### Step 3 - Reload PostgreSQL

You do not need a restart for HBA changes. A reload is sufficient and faster.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data reload
```

Expected output (yours will differ):

```
server signaled
```

```bash
exit
```

### Step 4 - Verify connections work

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 1;"
```

Expected output (yours will differ):

```
 ?column?
----------
        1
(1 row)
```

Connections are restored.

### Step 5 - Verify HBA rules are correct

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT line_number, type, database, user_name, auth_method FROM pg_hba_file_rules ORDER BY line_number;"
```

Expected output (yours will differ):

```
 line_number | type  | database | user_name |   auth_method
-------------+-------+----------+-----------+-----------------
          85 | local | {all}    | {postgres}| peer
          86 | local | {all}    | {all}     | peer
          88 | host  | {all}    | {all}     | scram-sha-256
          89 | host  | {all}    | {all}     | scram-sha-256
...
```

No `reject` rules appear. The rules are in the correct order.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- psql connects successfully to labdb
- No reject rule at top of pg_hba.conf
- pg_hba_file_rules shows no reject entries
- Connection to postgres database also works

---

## Interview Discussion Points

1. **Explain pg_hba.conf's first-match-wins behavior and why rule order matters.** - PostgreSQL scans `pg_hba.conf` from top to bottom for each connection. The first rule whose type, database, user, and address all match the incoming connection determines the outcome. If that rule's auth method is `reject`, the connection fails immediately - no further rules are checked. This is different from firewall rules that might have explicit allow/deny ordering. In pg_hba.conf, putting a broad `reject` or `trust` rule too early can override every specific rule below it. Always put narrow, specific rules first and broad rules last.

2. **How would you lock yourself out of PostgreSQL, and how would you recover?** - The easiest way: add `local all all reject` as the first rule and reload. Now all local connections fail. Recovery requires OS-level access: edit `pg_hba.conf` directly as the postgres user, then reload with `pg_ctl reload` or `kill -HUP <postmaster_pid>`. If you also blocked host connections, you cannot connect from anywhere. The recovery path is always through OS file access. This is why DBAs must have OS-level access to production servers - not just SQL access.

3. **What is the difference between pg_isready and an actual psql connection?** - `pg_isready` sends a startup packet and checks for a response at the protocol level. It does NOT perform authentication. It tells you the postmaster is listening and can accept connections. But a successful `pg_isready` does not mean `pg_hba.conf` will allow your connection. `psql` goes further: it completes the full authentication handshake, including HBA rule evaluation. Always test with both: `pg_isready` for "is the server alive?" and `psql` for "can users actually connect?"

4. **What changes require a reload vs a restart in PostgreSQL?** - `pg_hba.conf` changes need only a reload. Most `postgresql.conf` parameters also need only a reload. The exceptions requiring a restart: `shared_buffers`, `max_connections`, `port`, `listen_addresses`, `shared_preload_libraries`, `wal_level`, and a few others. Check `pg_settings.context`: `sighup` means reload, `postmaster` means restart, `user` means changeable per-session. The distinction matters because restarts cause downtime while reloads do not.

5. **How would you safely test pg_hba.conf changes in production?** - (1) Always back up `pg_hba.conf` before editing: `cp pg_hba.conf pg_hba.conf.bak`. (2) Edit the file but do NOT reload yet. (3) Use `SELECT * FROM pg_hba_file_rules;` (PG15+) to parse the new file and check for errors without activating it. (4) Keep a second terminal with an active psql session open - existing connections survive a reload, so if the new rules lock you out, you still have one session to fix things. (5) Then reload and immediately test with a new connection in a third terminal. If it fails, use your existing session to restore the backup and reload again.
