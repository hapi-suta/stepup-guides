# Build 05 - Audit Logging

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- How to configure PostgreSQL logging for security-relevant events
- How to set log_statement, log_connections, and log_disconnections
- How to create an audit trigger that records changes to sensitive tables
- How to install and configure pgAudit if available
- How to read the audit trail from the audit_log table

---

> **Concept: PostgreSQL Logging vs Auditing**
> PostgreSQL has built-in logging (controlled by `postgresql.conf`) which writes server events to log files. This is useful for operational monitoring but not designed for security auditing. Audit logging requires: recording who did what, on which object, at what time, and what the values were. PostgreSQL's `log_statement = 'ddl'` captures DDL commands in the log file, but not DML (INSERT, UPDATE, DELETE). For full DML auditing, you need either the pgAudit extension or a trigger-based approach. Trigger-based auditing stores the audit trail in a database table, which is queryable but can be bypassed by a superuser who disables triggers.

---

> **Concept: pgAudit**
> pgAudit is an open-source PostgreSQL extension that integrates with the standard logging infrastructure to provide detailed, object-level audit logging. It captures session-level events (every statement executed) or object-level events (statements touching specific tables). The output goes to the PostgreSQL log file in a structured format. pgAudit must be loaded via `shared_preload_libraries` and requires a server restart. On some systems it must be installed from the PGDG repository.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Configure log_statement, log_connections, log_disconnections

```bash
sudo vi /opt/pgsql/data/postgresql.conf
```

Find and update these settings. If a line is commented out (starts with `#`), remove the `#` and update the value:

```
log_statement = 'ddl'
log_connections = on
log_disconnections = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

- `log_statement = 'ddl'` - logs all DDL (CREATE, ALTER, DROP). Use `'mod'` for DDL + DML. Use `'all'` for every statement (avoid in production - see Scenario 07).
- `log_connections = on` - logs each new connection with user and database name.
- `log_disconnections = on` - logs each disconnection with session duration.
- `log_line_prefix` - adds user, database, application name, and client IP to every log line for traceability.

Save and exit with `:wq`.

---

## Step 3 - Reload PostgreSQL to apply logging changes

Logging parameters are SIGHUP-compatible - no restart needed:

```bash
sudo systemctl reload postgresql-16
```

---

## Step 4 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

---

## Step 5 - Connect to PostgreSQL and test logging

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Run a DDL statement to trigger log_statement = 'ddl':

```sql
CREATE TABLE audit_test_table (id SERIAL PRIMARY KEY, note TEXT);
```

Expected output:

```
CREATE TABLE
```

---

## Step 6 - Check the log file for the DDL statement

```sql
\q
```

```bash
tail -20 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
2026-04-19 12:00:01 UTC [1234]: [1-1] user=postgres,db=stepup_store,app=psql,client= LOG:  connection received: host=[local]
2026-04-19 12:00:01 UTC [1234]: [2-1] user=postgres,db=stepup_store,app=psql,client= LOG:  connection authorized: user=postgres database=stepup_store
2026-04-19 12:00:15 UTC [1234]: [3-1] user=postgres,db=stepup_store,app=psql,client= LOG:  statement: CREATE TABLE audit_test_table (id SERIAL PRIMARY KEY, note TEXT);
```

The log shows who (user=postgres), from where (client), on which database (db=stepup_store), and what statement was executed.

---

## Step 7 - Connect back to psql

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 8 - Create an audit_log table

```sql
CREATE TABLE IF NOT EXISTS public.audit_log (
    id           BIGSERIAL PRIMARY KEY,
    event_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    db_user      TEXT NOT NULL,
    client_addr  INET,
    table_schema TEXT NOT NULL,
    table_name   TEXT NOT NULL,
    operation    TEXT NOT NULL,
    row_before   JSONB,
    row_after    JSONB
);
```

This table stores a structured record of every change made to tables we attach the audit trigger to.

Expected output:

```
CREATE TABLE
```

---

## Step 9 - Create the audit trigger function

```sql
CREATE OR REPLACE FUNCTION public.audit_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.audit_log (
        db_user,
        client_addr,
        table_schema,
        table_name,
        operation,
        row_before,
        row_after
    ) VALUES (
        current_user,
        inet_client_addr(),
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;
```

The function uses trigger-provided variables:
- `TG_TABLE_SCHEMA` - schema of the table that triggered the event
- `TG_TABLE_NAME` - name of the table
- `TG_OP` - operation type: INSERT, UPDATE, DELETE
- `OLD` - the row before the change (NULL for INSERT)
- `NEW` - the row after the change (NULL for DELETE)
- `SECURITY DEFINER` - the function runs as its owner (postgres), so it can always write to audit_log even if the triggering user cannot

Expected output:

```
CREATE FUNCTION
```

---

## Step 10 - Attach the audit trigger to the orders table

```sql
CREATE TRIGGER orders_audit_trigger
AFTER INSERT OR UPDATE OR DELETE
ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.audit_trigger_fn();
```

`AFTER` triggers fire after the row change is complete. `FOR EACH ROW` fires once per affected row (not once per statement).

Expected output:

```
CREATE TRIGGER
```

---

## Step 11 - Test the audit trigger with an INSERT

```sql
INSERT INTO orders (customer_id, status, total_amount, tenant_id)
VALUES (99, 'pending', 150.00, 'tenant_alpha');
```

Expected output:

```
INSERT 0 1
```

---

## Step 12 - Test the audit trigger with an UPDATE

```sql
UPDATE orders SET status = 'paid' WHERE customer_id = 99;
```

Expected output:

```
UPDATE 1
```

---

## Step 13 - View the audit trail

```sql
SELECT event_time, db_user, table_name, operation, row_before, row_after
FROM audit_log
ORDER BY event_time DESC
LIMIT 5;
```

Expected output (yours will differ):

```
         event_time         | db_user  | table_name | operation |      row_before      |      row_after
----------------------------+----------+------------+-----------+---------------------+--------------------
 2026-04-19 12:05:00+00     | postgres | orders     | UPDATE    | {"id":11,"status":"pending",...} | {"id":11,"status":"paid",...}
 2026-04-19 12:04:00+00     | postgres | orders     | INSERT    |                     | {"id":11,"status":"pending",...}
```

The audit log shows the exact before and after state of each row, who made the change, and when.

---

## Step 14 - Check if pgAudit is available

```sql
SELECT * FROM pg_available_extensions WHERE name = 'pgaudit';
```

Expected output (yours will differ):

```
  name   | default_version | installed_version |        comment
---------+-----------------+-------------------+------------------------
 pgaudit | 16              |                   | provides auditing functionality
```

If `installed_version` is null, pgAudit is not yet installed. If the extension is not in the list at all, it needs to be installed from the PGDG repository.

---

## Step 15 - Install pgAudit if available

Exit psql:

```sql
\q
```

```bash
exit
```

Install the package:

```bash
sudo dnf install -y pgaudit_16
```

Expected output (yours will differ):

```
...
Installed:
  pgaudit_16-1.7.0-1.rhel9.x86_64
...
```

If the package is not found, add the PGDG repository first:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

---

## Step 16 - Configure pgAudit in postgresql.conf

```bash
sudo vi /opt/pgsql/data/postgresql.conf
```

Add or update:

```
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'ddl, write'
```

- `shared_preload_libraries` loads pgAudit at server start (requires restart)
- `pgaudit.log = 'ddl, write'` audits all DDL and all write (INSERT, UPDATE, DELETE, TRUNCATE) statements

Save and exit with `:wq`.

---

## Step 17 - Restart PostgreSQL to load pgAudit

```bash
sudo systemctl restart postgresql-16
```

---

## Step 18 - Enable pgAudit extension in the database

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

Expected output:

```
CREATE EXTENSION
```

---

## Step 19 - Run a test write and check pgAudit output

```sql
INSERT INTO orders (customer_id, status, total_amount, tenant_id)
VALUES (100, 'pending', 200.00, 'tenant_beta');
```

Exit psql and check the log:

```sql
\q
```

```bash
tail -10 /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
2026-04-19 12:10:00 UTC [1234]: [1-1] user=postgres,db=stepup_store,... LOG:  AUDIT: SESSION,1,1,WRITE,INSERT,TABLE,public.orders,"INSERT INTO orders ...",<none>
```

pgAudit log entries are prefixed with `AUDIT:` and include the audit type, statement type, object type, object name, and the full statement text.

---

## Step 20 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Summary

| Method | What it captures | Where logs go | Bypass risk |
|--------|-----------------|---------------|-------------|
| log_statement = 'ddl' | DDL only | Log file | Log rotation |
| log_statement = 'mod' | DDL + write DML | Log file | Log rotation |
| log_statement = 'all' | Everything (avoid in prod) | Log file | Log rotation, passwords exposed |
| Trigger-based audit | INSERT/UPDATE/DELETE row data | audit_log table | Superuser can disable trigger |
| pgAudit | Session or object-level, configurable | Log file | Log rotation |

---

## Interview Discussion Points

1. **Why is log_statement = 'all' dangerous in production?** - It logs every SQL statement including CREATE USER with PASSWORD and any query that contains sensitive data in WHERE clauses or VALUES. Passwords can appear in plaintext in log files. Log files are often shipped to centralized log aggregators where many people have access. Additionally, logging every statement under high load generates enormous log volume, consuming disk space and I/O that competes with the database itself.

2. **What is the difference between trigger-based auditing and pgAudit?** - Trigger-based auditing captures the before and after state of individual rows and stores them in a database table. This gives you queryable, structured audit data with full row context. However, a superuser can disable a trigger temporarily to make unlogged changes. pgAudit hooks into the PostgreSQL executor and writes to the server log file. It is harder to bypass and captures the statement text, but does not capture row-level before/after values by default. For compliance requirements, combining both approaches is common.

3. **Can a user cover their tracks by deleting rows from audit_log?** - If the user has DELETE on the audit_log table, yes. To prevent this, the audit function should run as SECURITY DEFINER (owned by a privileged role), and the audit_log table should have no DELETE or UPDATE privilege granted to any application role. The audit table owner should be a dedicated role that no application user can assume. You can also use partitioning with automatic archiving to move old audit records to read-only storage.

4. **What does SECURITY DEFINER mean on a function?** - A SECURITY DEFINER function runs with the privileges of the function owner, not the privileges of the caller. This is what allows the audit trigger function (owned by postgres) to insert into audit_log even if the user who triggered the event does not have INSERT on audit_log. It is the correct pattern for audit functions. The risk is privilege escalation - if a SECURITY DEFINER function is written poorly or can be manipulated, the caller may gain the owner's privileges. Always validate inputs in SECURITY DEFINER functions.

5. **How would you implement an immutable audit log?** - Several techniques: First, use a separate PostgreSQL role as the audit writer with INSERT-only on audit_log and no UPDATE or DELETE. Second, use a WORM (Write Once Read Many) storage tier - export audit logs to S3 with Object Lock, or use a dedicated audit database with restricted access. Third, use PostgreSQL's logical replication to stream changes to a separate audit system that application roles cannot touch. Fourth, for high compliance needs, use pgAudit combined with a log management system that has immutable storage.
