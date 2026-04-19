# Scenario 02 - pg_hba.conf Misconfigured

**Severity:** HIGH
**Expected Recovery Time:** 4-6 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: All TCP connections to PostgreSQL are being rejected.
The Pulse dashboard shows AUTH FAILED.
Internal monitoring shows 0 successful TCP connections.
```

---

## Key Concepts for Revision

- **reject method** - When pg_hba.conf specifies `reject` as the method, PostgreSQL immediately rejects the connection with an error and stops evaluating rules. This is different from having no matching rule (which gives "no pg_hba.conf entry"). `reject` is used intentionally to block specific users or addresses while allowing others.

- **pg_hba.conf reload vs restart** - pg_hba.conf changes take effect on reload (SIGHUP). You do not need to restart PostgreSQL. Existing connections are unaffected by the reload. Use `sudo systemctl reload postgresql-16` or `SELECT pg_reload_conf();` from inside psql.

- **Diagnostic path when TCP is blocked** - If TCP connections are blocked, use the Unix socket to diagnose. Connect as the postgres OS user via `sudo -iu postgres` then `psql -p 5432`. From there, you can query `pg_hba_file_rules` to see what the server parsed, or edit the file and reload.

- **pg_hba_file_rules view** - This system view shows the parsed contents of pg_hba.conf. It is much easier to read than the raw file and also shows any parse errors in the `error` column.

---

## Diagnostic Steps

### Step 1 - Confirm the problem

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "127.0.0.1", user "app_user", database "stepup_store", no encryption
```

The error message "pg_hba.conf rejects" confirms this is a `reject` rule, not a missing rule or wrong password.

### Step 2 - Connect via Unix socket to investigate

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Check what rules are active

```sql
SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules
ORDER BY line_number;
```

Expected output (yours will differ):

```
 line_number | type  | database | user_name | address   | auth_method
-------------+-------+----------+-----------+-----------+-------------
           4 | local | {all}    | {all}     |           | trust
           7 | host  | {all}    | {all}     | 127.0.0.1 | reject
           8 | host  | {all}    | {all}     | ::1       | reject
           9 | host  | {all}    | {all}     | 0.0.0.0   | reject
```

The problem is obvious: all TCP connection rules use `reject`.

---

## Resolution

### Step 1 - Back up and edit pg_hba.conf

```bash
cp /opt/pgsql/data/pg_hba.conf /opt/pgsql/data/pg_hba.conf.broken
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Change `reject` to `scram-sha-256` for the TCP connection rules:

```
# TYPE  DATABASE  USER  ADDRESS         METHOD

# local socket
local   all       all                   trust

# TCP connections - fixed
host    all       all   127.0.0.1/32    scram-sha-256
host    all       all   ::1/128         scram-sha-256
host    all       all   0.0.0.0/0       scram-sha-256

local   replication all                 trust
host    replication all 127.0.0.1/32   scram-sha-256
```

Save and exit vi with `:wq`.

### Step 2 - Reload PostgreSQL

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data reload
```

Expected output:

```
server signaled
```

### Step 3 - Verify the rules took effect

```sql
SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules
ORDER BY line_number;
```

Confirm auth_method is now `scram-sha-256` for TCP rules, not `reject`.

### Step 4 - Exit and test TCP connection

```bash
\q
```

```bash
exit
```

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT current_user;"
```

Enter `apppass123` when prompted.

Expected output:

```
 current_user
--------------
 app_user
(1 row)
```

### Step 5 - Verify the Pulse dashboard recovers

Open your browser and go to `http://NODE1:8080`. The dashboard should show green status.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user can connect via TCP
- pg_hba.conf has no reject rules for TCP connections
- pg_hba_file_rules shows scram-sha-256 for host connections

---

## Interview Discussion Points

1. **What is the difference between `reject` and having no matching rule in pg_hba.conf?** - Both result in the connection being rejected, but the error messages are different. `reject` gives "pg_hba.conf rejects connection." No matching rule gives "no pg_hba.conf entry for host." The `reject` method is intentional - you use it to explicitly block specific users or addresses BEFORE a more general allow rule can match them.

2. **How do you test a pg_hba.conf change safely while keeping a connection open?** - Keep your current psql session open. Edit pg_hba.conf in a separate shell and run `SELECT pg_reload_conf();` from inside your existing session. The reload does not affect your open connection. Then open a new psql connection to test the new rules. If the new rules are wrong, you still have the old session to fix them.

3. **What does the `error` column in pg_hba_file_rules show?** - If pg_hba.conf has a syntax error in a rule, the parsed row in pg_hba_file_rules will have a non-NULL value in the `error` column describing the parse problem. The rule with the error is ignored. This is useful for spotting typos in authentication method names or CIDR notation.

4. **When would you legitimately use `reject` in pg_hba.conf?** - Common use cases: blocking a specific user from a specific host ("allow app_user from the app subnet, but reject app_user from all other addresses"), blocking replication connections from untrusted sources, or creating an explicit deny rule above a catch-all allow rule to prevent specific access patterns.

5. **Can you have multiple pg_hba.conf files?** - Yes, via `include` and `include_dir` directives. `include '/path/to/file'` inserts the rules from that file at that position. `include_dir '/path/to/dir'` includes all `*.conf` files from the directory in filename-sorted order. This is useful for modular configurations - a base hba.conf that includes team-specific or environment-specific overrides.
