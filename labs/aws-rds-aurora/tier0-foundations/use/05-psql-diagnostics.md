# Exercise 05: psql Diagnostics

**Duration:** 20 minutes
**Objective:** Diagnose 6 common psql connection and permission errors from error message output alone, identify the root cause, and describe the correct resolution.
**Prerequisites:** Build guide 05 (Connecting with psql) complete

---

## Background

You are the on-call DBA at [COMPANY]. Your phone is buzzing. Six different developers have opened tickets in the last 20 minutes, all with variations of "I cannot connect to the database." Each ticket contains a copy-pasted error message and basic environment details.

Your job: read the error, identify the root cause, and tell them exactly what to fix. You do not have direct access to these servers right now - you need to diagnose from the error text alone.

Work through each scenario before reading the answer.

---

## How to Use This Exercise

For each scenario:
1. Read the error message carefully
2. State the root cause in one sentence
3. List 1-3 steps to resolve it

---

## Scenario 1: Connection Refused

**Developer ticket:** "I'm trying to connect to our new RDS instance but I keep getting this error. I used the same command I always use."

**Command used:**
```
psql -h 10.0.21.45 -U dbadmin -d appdb -p 5432
```

**Error output:**
```
psql: error: connection to server at "10.0.21.45", port 5432 failed:
Connection refused
        Is the server running on that host and accepting TCP/IP connections?
```

**Context:** This is a brand new RDS instance created 10 minutes ago. The AWS console shows the instance status as `creating`.

---

## Scenario 2: Authentication Failed

**Developer ticket:** "I've connected to this database before but now it's saying my password is wrong. I didn't change anything."

**Command used:**
```
psql -h mydb.abc123.us-east-1.rds.amazonaws.com -U appuser -d orders -p 5432
```

**Error output:**
```
psql: error: connection to server at "mydb.abc123.us-east-1.rds.amazonaws.com" (10.0.21.45), port 5432 failed:
FATAL:  password authentication failed for user "appuser"
```

**Context:** The developer is certain they are using the correct password. Another developer using the same credentials from a different machine also fails. The RDS master user (postgres) can still log in fine.

---

## Scenario 3: Permission Denied on Table

**Developer ticket:** "I can connect but I can't read the table I need. I've been using this database for weeks."

**Command used (after connecting):**
```sql
SELECT * FROM public.customer_orders LIMIT 10;
```

**Error output:**
```
ERROR:  permission denied for table customer_orders
```

**Context:** The developer connects as `reporting_user`. This worked last week. The table `customer_orders` was dropped and recreated yesterday by the schema migration team.

---

## Scenario 4: Database Does Not Exist

**Developer ticket:** "I can't connect to the staging database. It was working yesterday."

**Command used:**
```
psql -h staging.abc123.us-east-1.rds.amazonaws.com -U dbadmin -d staging_appdb
```

**Error output:**
```
psql: error: connection to server at "staging.abc123.us-east-1.rds.amazonaws.com" (10.0.22.10), port 5432 failed:
FATAL:  database "staging_appdb" does not exist
```

**Context:** The developer says "I definitely used this yesterday." Another developer on the team can connect fine using a different database name.

---

## Scenario 5: SSL Required

**Developer ticket:** "New RDS instance and I can't connect at all. Works fine on my old database."

**Command used:**
```
psql "host=newprod.abc123.us-east-1.rds.amazonaws.com user=dbadmin dbname=appdb sslmode=disable"
```

**Error output:**
```
psql: error: connection to server at "newprod.abc123.us-east-1.rds.amazonaws.com" (10.0.21.67), port 5432 failed:
FATAL:  no pg_hba.conf entry for host "10.0.21.67", user "dbadmin", database "appdb", SSL off
```

**Context:** The old database was on an older RDS instance. The new instance was created with a custom parameter group.

---

## Scenario 6: Role Does Not Exist

**Developer ticket:** "I'm getting a weird error that I've never seen before. I just got access to this account."

**Command used:**
```
psql -h devdb.abc123.us-east-1.rds.amazonaws.com -d appdb
```

**Error output:**
```
psql: error: connection to server at "devdb.abc123.us-east-1.rds.amazonaws.com" (10.0.21.90), port 5432 failed:
FATAL:  role "jsmith" does not exist
```

**Context:** This is the developer's first time connecting. Their local Mac username is `jsmith`. They are not sure what username they should be using.

---

## Answers

### Scenario 1: Connection Refused

**Root cause:** The RDS instance is still being created. It is not yet accepting connections.

**Explanation:** "Connection refused" at the TCP level means the server is not listening on that port. This is distinct from authentication errors, which happen after a connection is established. An instance in `creating` status has not yet started the PostgreSQL process. Depending on the instance class and storage size, RDS instance creation takes 5-15 minutes.

**Resolution:**
1. Wait for the instance status to change from `creating` to `available` in the AWS console or via `aws rds describe-db-instances`.
2. Once available, retry the connection.
3. If the instance shows `available` but connection is still refused, check the security group - the inbound rule for port 5432 may not allow the source IP. Also verify `Public Accessibility` is set correctly for the network path being used.

**Diagnostic tip:** "Connection refused" means TCP-level rejection. The network path reached the host, but nothing is listening on that port. Compare with a timeout (network unreachable / security group block), which produces a different error: `could not connect to server: Connection timed out`.

---

### Scenario 2: Authentication Failed

**Root cause:** The `appuser` role's password has been changed or the role's authentication method has been modified, but the application or developer is using the old password.

**Explanation:** The error `FATAL: password authentication failed for user "appuser"` means the connection reached the server and PostgreSQL recognized the user, but the password did not match. The fact that the master user (`postgres`) works fine confirms the instance is healthy and the network path is correct.

**Resolution:**
1. Log in as the RDS master user:
   ```
   psql -h mydb.abc123.us-east-1.rds.amazonaws.com -U postgres -d postgres
   ```
2. Reset the `appuser` password:
   ```sql
   ALTER USER appuser WITH PASSWORD 'new-secure-password';
   ```
3. Update the application configuration or AWS Secrets Manager entry with the new password.
4. Retry the connection.

**If Secrets Manager is in use:** The password rotation Lambda may have rotated the secret automatically. Check the current secret value in Secrets Manager and use that. The application should be retrieving credentials from Secrets Manager dynamically, not hardcoding them.

**Alternate root cause:** If `appuser` was recently deleted and recreated, the password is completely new. Check with whoever ran the migration or user management scripts recently.

---

### Scenario 3: Permission Denied on Table

**Root cause:** The `customer_orders` table was dropped and recreated yesterday. GRANTs on the old table do not carry over to the new table. The new table has no permissions granted to `reporting_user`.

**Explanation:** In PostgreSQL, permissions are attached to specific table objects. When a table is dropped and recreated (`DROP TABLE + CREATE TABLE` or a migration that recreates the table), it gets a new OID (object identifier). Any previous `GRANT` statements on the old table are gone. The new table starts with no grants except to the owner.

**Resolution:**

Log in as the database owner or a superuser and re-grant permissions:

```sql
-- Grant SELECT to the reporting user
GRANT SELECT ON public.customer_orders TO reporting_user;

-- If this table is in a schema where the user needs ongoing access:
GRANT USAGE ON SCHEMA public TO reporting_user;
```

**To prevent this in the future:** Use `DEFAULT PRIVILEGES` so new tables created by the schema owner automatically grant access:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
GRANT SELECT ON TABLES TO reporting_user;
```

This ensures that any future table created by `schema_owner` in the `public` schema will automatically be readable by `reporting_user` without a manual GRANT.

---

### Scenario 4: Database Does Not Exist

**Root cause:** The developer is using the wrong database name. The database `staging_appdb` does not exist on this instance.

**Explanation:** `FATAL: database "staging_appdb" does not exist` is a precise error - PostgreSQL accepted the credentials but cannot find a database with that name. This is almost always a typo, wrong environment, or a database that was renamed/dropped.

**Resolution:**

1. Connect to the default `postgres` database first to see what databases exist:
   ```
   psql -h staging.abc123.us-east-1.rds.amazonaws.com -U dbadmin -d postgres
   ```

2. List all databases:
   ```sql
   \l
   ```
   or
   ```sql
   SELECT datname FROM pg_database WHERE datistemplate = false;
   ```

3. Identify the correct database name and reconnect using the right `-d` value.

**Common causes:**
- The database was named `staging_app` (not `staging_appdb`)
- A migration renamed the database
- The developer is pointing at the wrong RDS endpoint (dev vs. staging)
- The database was never created on this specific instance

---

### Scenario 5: SSL Required

**Root cause:** The connection is being attempted with `sslmode=disable`, but the RDS instance requires SSL. The `pg_hba.conf` equivalent on this instance is configured to reject non-SSL connections.

**Explanation:** The error `no pg_hba.conf entry for host ... SSL off` means PostgreSQL found a `pg_hba.conf` rule for this user and database, but that rule requires SSL and the client connected without SSL. On RDS, this is controlled by the `rds.force_ssl` parameter in the parameter group. When `rds.force_ssl = 1`, all connections must use SSL.

**Resolution:**

Option 1 - Use SSL in the connection (recommended):
```
psql "host=newprod.abc123.us-east-1.rds.amazonaws.com user=dbadmin dbname=appdb sslmode=require"
```

Option 2 - Use SSL with certificate verification (most secure):
```
psql "host=newprod.abc123.us-east-1.rds.amazonaws.com user=dbadmin dbname=appdb sslmode=verify-full sslrootcert=/path/to/aws-rds-ca.pem"
```

Download the AWS RDS CA bundle from:
```
https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Option 3 - Disable the SSL requirement in the parameter group (not recommended for production):
- In the custom parameter group, set `rds.force_ssl = 0`
- Apply the parameter group change and reboot the instance

**Note:** `sslmode=disable` should never be used with production databases. The old instance the developer was comparing against likely had `rds.force_ssl = 0`. The new instance has the correct, more secure default.

---

### Scenario 6: Role Does Not Exist

**Root cause:** psql is defaulting to the local OS username (`jsmith`) when no `-U` flag is provided. The PostgreSQL role `jsmith` does not exist on the RDS instance.

**Explanation:** When you run `psql` without a `-U` flag, it defaults to using your operating system username as the PostgreSQL username. On a Mac, `whoami` returns `jsmith`, so psql tries to connect as PostgreSQL role `jsmith`. Unless someone explicitly created a `jsmith` role on the database, this fails with `role "jsmith" does not exist`.

**Resolution:**

Always specify the `-U` flag explicitly:
```
psql -h devdb.abc123.us-east-1.rds.amazonaws.com -U dbadmin -d appdb
```

Replace `dbadmin` with the actual username the developer has been provisioned with. Ask the DBA or check the welcome email / credentials documentation for the correct username.

**If the developer does need their own named role:**

A DBA with superuser access can create one:
```sql
CREATE ROLE jsmith WITH LOGIN PASSWORD 'secure-password';
GRANT CONNECT ON DATABASE appdb TO jsmith;
-- Add additional grants based on what they need
```

**Prevention:** Document the required connection parameters (host, port, username, database) in the team wiki or README. New developers should copy-paste the full connection string rather than constructing it from scratch.

---

## Bonus: Quick Diagnostic Decision Tree

When a developer reports "I can't connect," walk through this sequence:

```
1. Does the error say "Connection refused" or "timed out"?
   YES -> Instance not ready, not running, or security group/subnet blocking
   NO  -> Continue

2. Does the error say "password authentication failed"?
   YES -> Wrong password. Check Secrets Manager or reset the password.
   NO  -> Continue

3. Does the error say "role does not exist"?
   YES -> Wrong username (likely missing -U flag or role was never created)
   NO  -> Continue

4. Does the error say "database does not exist"?
   YES -> Wrong -d value. Connect to postgres DB and run \l to list databases.
   NO  -> Continue

5. Does the error say "SSL off" or reference pg_hba.conf?
   YES -> Add sslmode=require to the connection string
   NO  -> Continue

6. Does the error say "permission denied for table/schema"?
   YES -> Table was recreated without re-granting access. Run GRANT.
   NO  -> Escalate with full error text and connection details
```

---

## Summary of Key Takeaways

- "Connection refused" is a TCP error, not a PostgreSQL error. It means nothing is listening. Check instance status, security groups, and public accessibility before digging deeper.
- "Password authentication failed" means PostgreSQL recognized the user but rejected the password. The user exists; the credentials are wrong or were rotated.
- GRANT permissions do not survive a DROP TABLE + CREATE TABLE cycle. When migrations recreate tables, all grants must be reapplied. Use DEFAULT PRIVILEGES to handle this automatically.
- When `psql` is run without `-U`, it defaults to the OS username. Always specify `-U` explicitly when connecting to remote databases.
- `sslmode=disable` is never acceptable for databases holding real data. Always use at least `sslmode=require`.
- The root cause of "database does not exist" is almost always a typo or wrong endpoint. Connect to the `postgres` database first and run `\l` to see what actually exists.
- Train developers to always provide all connection parameters explicitly: `-h`, `-U`, `-d`, `-p`. Never rely on defaults for remote connections.
