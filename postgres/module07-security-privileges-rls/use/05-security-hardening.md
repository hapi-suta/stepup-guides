# Use 05 - Security Hardening

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 25 minutes

---

## Objective

Apply CIS PostgreSQL Benchmark recommendations to harden the stepup_store database. You will disable trust authentication, set password encryption, limit superusers, lock down the public schema, and verify each change.

---

## CIS Benchmark Items We Cover

| Item | Setting | Risk if skipped |
|------|---------|----------------|
| CIS 3.1 | Disable trust auth for TCP | Any OS user can connect as any DB user |
| CIS 3.2 | Use scram-sha-256 password encryption | MD5 hashes are crackable offline |
| CIS 4.1 | Minimize superuser accounts | Superusers bypass all controls |
| CIS 4.2 | Revoke CREATE on public schema | Any user can plant malicious functions |
| CIS 4.3 | Set password_encryption = scram-sha-256 | New passwords use weak hashing by default |
| CIS 6.2 | Ensure SSL is required | Credentials sent in plaintext |

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Audit current superusers

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT rolname FROM pg_roles WHERE rolsuper = true;
```

Expected output (yours will differ):

```
 rolname
----------
 postgres
(1 row)
```

If any unexpected role appears here, investigate immediately. Only `postgres` should be a superuser in this lab.

---

## Step 3 - Check current password encryption setting

```sql
SHOW password_encryption;
```

Expected output:

```
 password_encryption
---------------------
 scram-sha-256
(1 row)
```

If it shows `md5`, change it:

```sql
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
```

```sql
SELECT pg_reload_conf();
```

---

## Step 4 - Reset passwords for all roles to use scram-sha-256 encryption

After changing `password_encryption`, existing passwords are still stored with the old algorithm until they are reset. Reset each application role password:

```sql
ALTER ROLE app_user PASSWORD 'apppass123';
```

```sql
ALTER ROLE readonly_user PASSWORD 'readpass123';
```

```sql
ALTER ROLE tenant_alpha PASSWORD 'alphapass123';
```

```sql
ALTER ROLE tenant_beta PASSWORD 'betapass123';
```

Expected output for each:

```
ALTER ROLE
```

---

## Step 5 - Verify passwords are now scram-sha-256 encoded

```sql
SELECT rolname, rolpassword
FROM pg_authid
WHERE rolname IN ('app_user', 'readonly_user', 'tenant_alpha')
  AND rolname NOT LIKE 'pg_%';
```

Expected output (yours will differ):

```
    rolname    |                     rolpassword
---------------+------------------------------------------------------
 app_user      | SCRAM-SHA-256$4096:...
 readonly_user | SCRAM-SHA-256$4096:...
 tenant_alpha  | SCRAM-SHA-256$4096:...
```

Each password entry should start with `SCRAM-SHA-256$`. If any still shows `md5...`, reset that password again after verifying `password_encryption = 'scram-sha-256'`.

---

## Step 6 - Exit psql and update pg_hba.conf for scram-sha-256

```sql
\q
```

```bash
exit
```

```bash
sudo vi /opt/pgsql/data/pg_hba.conf
```

Change any `md5` auth method entries to `scram-sha-256`. Also change any `trust` entries for TCP connections to `scram-sha-256`. The local Unix socket entry can stay as `trust` for operational convenience in this lab, but in production it should also use `scram-sha-256` or `peer`.

Before:

```
host    all             all             0.0.0.0/0               trust
```

After:

```
hostssl all             all             0.0.0.0/0               scram-sha-256
```

Save and exit with `:wq`.

---

## Step 7 - Reload pg_hba.conf

```bash
sudo systemctl reload postgresql-16
```

---

## Step 8 - Verify trust auth is no longer allowed for TCP

Try connecting without a password over TCP:

```bash
/usr/pgsql-16/bin/psql "host=127.0.0.1 port=5432 dbname=stepup_store user=app_user"
```

Expected output:

```
Password for user app_user:
```

psql prompts for a password because trust is no longer in pg_hba.conf for TCP connections. Press Ctrl+C to cancel.

---

## Step 9 - Revoke CREATE on the public schema from PUBLIC

This is one of the most important CIS benchmark items. By default, any authenticated user can create objects in the public schema, including functions that shadow system functions.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Expected output:

```
REVOKE
```

---

## Step 10 - Verify the revoke

```sql
SELECT nspacl FROM pg_namespace WHERE nspname = 'public';
```

Expected output (yours will differ):

```
           nspacl
-----------------------------
 {postgres=UC/postgres,=U/postgres}
```

The `=UC/postgres` (CREATE for PUBLIC) should now be gone. Only `=U/postgres` (USAGE for PUBLIC) remains, meaning all users can still use the public schema but cannot create objects in it.

---

## Step 11 - Revoke CONNECT on the database from PUBLIC (optional hardening)

By default, every role can connect to every database. In a multi-database cluster, you may want to restrict this:

```sql
REVOKE CONNECT ON DATABASE stepup_store FROM PUBLIC;
```

```sql
GRANT CONNECT ON DATABASE stepup_store TO app_user, readonly_user, tenant_alpha, tenant_beta;
```

Expected output for each:

```
REVOKE
GRANT
```

---

## Step 12 - Check for roles with login but no password

```sql
SELECT rolname
FROM pg_authid
WHERE rolcanlogin = true
  AND rolpassword IS NULL
  AND rolname NOT LIKE 'pg_%';
```

Roles that can log in but have no password rely on other authentication methods (peer, cert) or trust. If you find unexpected results here, investigate.

Expected output:

```
 rolname
---------
(0 rows)
```

All login roles in this lab should have passwords set.

---

## Step 13 - Set password expiry (optional)

For compliance environments, set password expiry on application roles:

```sql
ALTER ROLE app_user VALID UNTIL '2027-01-01';
```

Expected output:

```
ALTER ROLE
```

---

## Step 14 - Verify the full hardened state

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin, rolbypassrls,
       CASE WHEN rolpassword LIKE 'SCRAM-SHA-256%' THEN 'scram' ELSE 'other/none' END AS pw_type
FROM pg_authid
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;
```

Review this output. Every login role should have `pw_type = 'scram'`. Only `postgres` should have `rolsuper = t`.

---

## Step 15 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Validation Questions

Answer these before moving to the next exercise:

1. Why is `trust` authentication in pg_hba.conf acceptable on the local Unix socket for operational work but not for TCP connections?
2. What is the attack vector enabled by CREATE on the public schema for all users?
3. After revoking CONNECT from PUBLIC on a database, what happens to roles that are already connected?
4. How do you rotate a password for a role without downtime for applications currently connected?
