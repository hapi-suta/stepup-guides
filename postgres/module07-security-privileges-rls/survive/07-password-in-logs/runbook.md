# Scenario 07 - Password in Logs

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Security audit found plaintext passwords in
PostgreSQL log files. A CREATE ROLE statement with
PASSWORD in cleartext was logged. The log files are
readable by the ops team and backed up to S3.
Immediate remediation required.
```

---

## Key Concepts for Revision

- **log_statement = 'all' logs every SQL statement** - This includes CREATE ROLE and ALTER ROLE statements that contain plaintext passwords. The password appears in cleartext in the log file. This is a common source of credential leaks.

- **log_statement levels** - `none` logs nothing, `ddl` logs DDL statements (CREATE, ALTER, DROP), `mod` logs DDL plus data-modifying statements (INSERT, UPDATE, DELETE), `all` logs every statement. For security, `ddl` is recommended in production - it captures schema changes without logging passwords from DML or SELECT queries.

- **PostgreSQL 16 introduced log_destination filtering** - But the primary defense is to never put plaintext passwords in SQL statements. Use `\password` in psql (which sends the hash) or use `CREATE ROLE ... PASSWORD NULL` and set the password separately with an encrypted method.

- **Exposed passwords must be changed immediately** - Even if you delete the log file, it may exist in backups, log aggregation systems, or monitoring tools. Treat the password as compromised and change it immediately.

---

## Diagnostic Steps

### Step 1 - Check the current log_statement setting

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 all
(1 row)
```

Every SQL statement is being logged, including ones containing passwords.

### Step 2 - Find the password in the logs

```sql
\q
```

```bash
grep -i "password" /opt/pgsql/log/postgresql-*.log | tail -5
```

Expected output (yours will differ):

```
2026-04-19 10:00:00.000 UTC [12345] LOG:  statement: ...PASSWORD 'SuperSecret_Prod_2026!'...
2026-04-19 10:00:00.000 UTC [12345] LOG:  statement: ...PASSWORD 'BatchW0rk3r_Secret!'...
```

Plaintext passwords are visible in the log file. Anyone with read access to these files can see the credentials.

### Step 3 - Check which roles were affected

```bash
/usr/pgsql-16/bin/psql -p 5432 -d postgres
```

```sql
SELECT rolname, rolcanlogin
FROM pg_roles
WHERE rolname IN ('api_service', 'batch_worker');
```

Expected output:

```
   rolname    | rolcanlogin
--------------+-------------
 api_service  | t
 batch_worker | t
(2 rows)
```

Both roles exist and can log in. Their passwords are compromised.

---

## Resolution

### Step 1 - Change the compromised passwords immediately

```sql
ALTER ROLE api_service PASSWORD 'NewApiService_2026_Rotated!';
```

Expected output:

```
ALTER ROLE
```

```sql
ALTER ROLE batch_worker PASSWORD 'NewBatchWorker_2026_Rotated!';
```

Expected output:

```
ALTER ROLE
```

### Step 2 - Change log_statement to a safer level

```sql
ALTER SYSTEM SET log_statement = 'ddl';
```

Expected output:

```
ALTER SYSTEM
```

The `ddl` level logs schema changes (CREATE, ALTER, DROP) but not data queries. This is the recommended production setting. It still logs ALTER ROLE DDL, but the password in the ALTER ROLE output is masked in PostgreSQL 16 when using `log_statement = 'ddl'` and `log_min_duration_statement`.

### Step 3 - Reload the configuration

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 4 - Verify the new setting

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 ddl
(1 row)
```

### Step 5 - Clean the compromised log entries

```sql
\q
```

Find the log files that contain the password and remove the offending lines. First, identify which files are affected.

```bash
grep -l "SuperSecret_Prod_2026\|BatchW0rk3r_Secret" /opt/pgsql/log/postgresql-*.log
```

For each file found, remove lines containing the old passwords.

```bash
sed -i '/SuperSecret_Prod_2026/d' /opt/pgsql/log/postgresql-*.log
```

```bash
sed -i '/BatchW0rk3r_Secret/d' /opt/pgsql/log/postgresql-*.log
```

### Step 6 - Verify passwords are gone from logs

```bash
grep -c "SuperSecret_Prod_2026\|BatchW0rk3r_Secret" /opt/pgsql/log/postgresql-*.log
```

The `-c` flag prints a count of matching lines instead of the lines themselves. If the passwords have been cleaned, the count will be 0 for each file.

Expected output:

```
/opt/pgsql/log/postgresql-Sat.log:0
```

If you see any count greater than 0, repeat the sed cleanup for that file.

### Step 7 - Exit

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
- log_statement is not set to 'all'
- No old plaintext passwords in recent log files
- Compromised roles have been re-passworded

---

## Interview Discussion Points

1. **Why is log_statement = 'all' dangerous in production?** - It logs every SQL statement including those containing plaintext passwords, API keys, and sensitive data in INSERT/UPDATE values. Log files are often less protected than the database itself - they get shipped to log aggregators, backed up to object storage, and accessed by ops teams who may not have database credentials. A single `CREATE ROLE ... PASSWORD 'secret'` statement exposes the credential to anyone with log access.

2. **What is the safest way to set a password for a PostgreSQL role?** - Use psql's `\password` command, which prompts interactively and sends the hashed password over the wire. The plaintext password never appears in a SQL statement, so it cannot be logged. Alternatively, hash the password client-side and pass the hash: `ALTER ROLE foo PASSWORD 'SCRAM-SHA-256$...'`. Never put a plaintext password in a CREATE ROLE or ALTER ROLE statement in production.

3. **What log_statement level do you recommend for production and why?** - `ddl` is the best balance. It captures schema changes (important for auditing and troubleshooting) without logging data queries (which may contain sensitive values). If you need query-level logging for performance analysis, use `log_min_duration_statement` to log only slow queries, or use `pg_stat_statements` which captures query patterns without actual parameter values.

4. **After finding passwords in logs, what steps beyond changing the password are needed?** - (a) Rotate the password immediately. (b) Clean log files on the server. (c) Check if logs were shipped to external systems (S3 backups, ELK, Splunk, CloudWatch) and clean those too. (d) Review access logs for the log files to see if anyone accessed them. (e) Notify the security team per your incident response policy. (f) Update your deployment scripts to prevent future occurrences.

5. **What is the pgaudit extension and how does it help?** - pgaudit provides detailed session and object audit logging. Unlike `log_statement`, pgaudit can be configured to log specific operations on specific objects without logging everything. It also integrates with structured logging and can redact sensitive values. For compliance-heavy environments, pgaudit provides the audit trail without the security risk of logging all statements.
