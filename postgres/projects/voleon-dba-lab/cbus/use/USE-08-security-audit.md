# USE Exercise 08: Security Compliance Audit

| | |
|---|---|
| **Time** | 50 minutes |
| **Server** | pg-primary (3.90.199.62), pg-replica (3.91.32.84), pg-ops (54.209.143.137) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice

- Checking password encryption settings and authentication methods
- Reviewing pg_hba.conf for correct authentication configuration
- Auditing role privileges and confirming least privilege is in place
- Verifying that application roles cannot perform destructive operations
- Identifying superuser accounts and confirming only `postgres` holds that privilege
- Reviewing pg_stat_statements for unusual query patterns
- Checking active connections by role
- Verifying SSL is configured and enforced
- Checking audit logging configuration
- Reviewing replication security entries in pg_hba.conf
- Auditing PgBouncer authentication settings

---

## Why Security Audits Matter

Quantitative trading firms like Voleon handle proprietary trading strategies, market positions, and financial data that is extremely sensitive. A database security audit verifies that:

- No role has more access than it needs (principle of least privilege)
- Passwords are stored and transmitted using strong cryptography (SCRAM-SHA-256, not MD5)
- Connections require SSL so credentials and data cannot be intercepted on the network
- Audit logging captures enough information to investigate incidents
- Replication channels use authenticated connections, not open trust entries

This exercise walks you through each check systematically. In a real audit you would document findings, assign severity ratings, and produce a remediation plan.

---

## Exercise 1: Check Password Encryption Setting

SSH into pg-primary. On **pg-primary**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

Switch to the postgres user. On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

Connect to the database. On **pg-primary**, as **postgres**:

```bash
psql -d quantdb
```

Check what algorithm PostgreSQL uses when storing new passwords. On **pg-primary**, as **postgres**, inside psql:

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

If the output says `md5`, that is a finding. MD5 password hashes are weak and can be cracked. SCRAM-SHA-256 is the modern standard required for compliance. To fix it you would run `ALTER SYSTEM SET password_encryption = 'scram-sha-256';` followed by `SELECT pg_reload_conf();` and then reset each role's password to regenerate the hash.

---

## Exercise 2: Verify Role Password Hashes

Check which roles have passwords set. On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT
    rolname,
    rolpassword IS NOT NULL AS has_password,
    LEFT(rolpassword, 7) AS hash_prefix
FROM pg_authid
ORDER BY rolname;
```

Expected output (yours will differ):

```
      rolname      | has_password | hash_prefix
-------------------+--------------+-------------
 pg_monitor        | f            |
 pgbouncer         | t            | SCRAM-SH
 postgres          | t            | SCRAM-SH
 quant_app         | t            | SCRAM-SH
 quant_pipeline    | t            | SCRAM-SH
 quant_readonly    | t            | SCRAM-SH
 quant_research    | t            | SCRAM-SH
 replicator        | t            | SCRAM-SH
(8 rows)
```

The `hash_prefix` column shows the first 7 characters of the stored hash. SCRAM-SHA-256 hashes start with `SCRAM-SH`. MD5 hashes start with `md5`. Any role showing `md5` in the prefix column needs its password reset.

`pg_monitor` has no password because it is a built-in PostgreSQL role, not a login role - it is used for granting monitoring access and does not authenticate directly.

---

## Exercise 3: Review pg_hba.conf

pg_hba.conf controls which clients can connect, from where, to which databases, and using which authentication method. It is the front door to your database.

Exit psql first. On **pg-primary**, as **postgres**, inside psql:

```sql
\q
```

Exit to ec2-user. On **pg-primary**, as **postgres**:

```bash
exit
```

Read the pg_hba.conf file. On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres grep -v "^#" /var/lib/pgsql/17/data/pg_hba.conf | grep -v "^$"
```

Expected output (yours will differ):

```
local   all             postgres                                peer
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    quantdb         quant_app       10.0.0.0/8              scram-sha-256
host    quantdb         quant_research  10.0.0.0/8              scram-sha-256
host    quantdb         quant_pipeline  10.0.0.0/8              scram-sha-256
host    quantdb         quant_readonly  0.0.0.0/0               scram-sha-256
host    replication     replicator      10.0.0.0/8              scram-sha-256
```

Audit each line against these rules:
- No `trust` entries should exist for network connections. `trust` means no password is required.
- No `md5` entries should exist. All entries should say `scram-sha-256`.
- Application roles should be restricted to internal IP ranges (`10.0.0.0/8`), not `0.0.0.0/0`.
- `quant_readonly` at `0.0.0.0/0` is a potential finding - it allows connections from any IP. Document whether this is intentional for read-only API access or should be restricted.
- The replication entry should be restricted to known replica IPs, not a broad CIDR range.

---

## Exercise 4: Audit Role Privileges

Switch to postgres and connect to psql. On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb
```

List all roles with their attributes. On **pg-primary**, as **postgres**, inside psql:

```sql
\du+
```

Expected output (yours will differ):

```
                          List of roles
    Role name    |          Attributes           | Member of
-----------------+-------------------------------+-----------
 pgbouncer       |                               | {}
 postgres        | Superuser, Create role, ...   | {}
 quant_app       |                               | {}
 quant_pipeline  |                               | {}
 quant_readonly  |                               | {}
 quant_research  |                               | {}
 replicator      | Replication                   | {}
```

Key checks:
- Only `postgres` should have `Superuser` in the Attributes column. Any other role with Superuser is a critical finding.
- `replicator` should have only `Replication` - no create-role or create-db privileges.
- Application roles (`quant_app`, `quant_research`, `quant_pipeline`, `quant_readonly`) should have empty attributes. If any of them has `Create role` or `Bypass RLS`, that is a finding.

Check whether any non-postgres role has superuser. On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT rolname FROM pg_roles WHERE rolsuper = true;
```

Expected output:

```
 rolname
----------
 postgres
(1 row)
```

If more than one role appears here, that is a high-severity finding.

---

## Exercise 5: Test Least Privilege - quant_app Cannot Delete

You will verify that the `quant_app` role cannot delete from `quant.market_data`. You need the quant_app password for this test. Check your lab credentials or use the password set during BUILD exercises.

Exit psql and the postgres user. On **pg-primary**, as **postgres**, inside psql:

```sql
\q
```

On **pg-primary**, as **postgres**:

```bash
exit
```

Attempt a DELETE as quant_app. On **pg-primary**, as **ec2-user**:

```bash
psql -h 127.0.0.1 -U quant_app -d quantdb \
  -c "DELETE FROM quant.market_data WHERE market_data_id = 1;"
```

Expected output:

```
ERROR:  permission denied for table market_data
```

This confirms the DELETE privilege has not been granted to `quant_app`. If you see `DELETE 1` instead of the error, that is a finding - `quant_app` has more access than it should.

---

## Exercise 6: Test Least Privilege - quant_research Cannot Insert or Update

On **pg-primary**, as **ec2-user**:

```bash
psql -h 127.0.0.1 -U quant_research -d quantdb \
  -c "INSERT INTO quant.instruments (symbol, asset_class) VALUES ('TEST', 'equity');"
```

Expected output:

```
ERROR:  permission denied for table instruments
```

Test UPDATE as well. On **pg-primary**, as **ec2-user**:

```bash
psql -h 127.0.0.1 -U quant_research -d quantdb \
  -c "UPDATE quant.instruments SET active = false WHERE symbol = 'AAPL';"
```

Expected output:

```
ERROR:  permission denied for table instruments
```

Both should fail. `quant_research` is a read-only research role. Researchers can read the data but cannot modify it.

---

## Exercise 7: Check pg_stat_statements for Suspicious Queries

`pg_stat_statements` records all query patterns that have been executed. You can use it to spot unusual activity - for example, a role running queries it should not be running, or queries that scan large amounts of data.

Switch to postgres user. On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

Connect to psql. On **pg-primary**, as **postgres**:

```bash
psql -d quantdb
```

Check that pg_stat_statements is enabled. On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT count(*) FROM pg_stat_statements;
```

If you get `ERROR: relation "pg_stat_statements" does not exist`, the extension is not installed. That is a finding - you cannot audit query history without it.

Show the top 10 queries by total execution time, with the role that ran them. On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT
    rolname,
    LEFT(query, 80) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms
FROM pg_stat_statements
JOIN pg_roles ON pg_roles.oid = pg_stat_statements.userid
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
    rolname    |                     query_preview                      | calls | total_ms | mean_ms
---------------+--------------------------------------------------------+-------+----------+---------
 quant_app     | SELECT * FROM quant.market_data WHERE instrument_id... |  4823 |  9821.33 |    2.04
 quant_pipeline| INSERT INTO quant.market_data (instrument_id, trade_d  |   312 |  5420.11 |   17.37
 quant_research| SELECT asset_class, count(*) FROM quant.instruments    |    44 |   128.44 |    2.92
...
```

Look for:
- Any role running DDL (`CREATE TABLE`, `DROP TABLE`, `ALTER TABLE`) - application roles should not do this.
- Any role running queries on tables they should not have access to.
- Unexpectedly high call counts that could indicate a runaway query loop.

---

## Exercise 8: Check Connection Counts by Role

Seeing who is connected right now and how many connections each role is holding is part of an active security posture.

On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT
    usename,
    application_name,
    client_addr,
    state,
    count(*) AS connection_count
FROM pg_stat_activity
WHERE usename IS NOT NULL
GROUP BY usename, application_name, client_addr, state
ORDER BY connection_count DESC;
```

Expected output (yours will differ):

```
    usename    | application_name |  client_addr  | state  | connection_count
---------------+------------------+---------------+--------+------------------
 quant_app     | pgbouncer        | 10.0.1.50     | idle   |               10
 quant_research| psql             | 10.0.2.31     | active |                1
 pgbouncer     | pgbouncer        | 127.0.0.1     | idle   |                1
 replicator    |                  | 10.0.1.84     | idle   |                1
(4 rows)
```

Look for:
- Unknown `client_addr` values that you do not recognize as internal IPs.
- Roles showing connections from `0.0.0.0` or external IPs when they should only connect internally.
- Connections in `idle in transaction` state that have been sitting for a long time (indicates a transaction was opened but never committed or rolled back).

Check for long-running idle-in-transaction connections. On **pg-primary**, as **postgres**, inside psql:

```sql
SELECT
    usename,
    client_addr,
    state,
    now() - state_change AS idle_duration,
    LEFT(query, 60) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;
```

Any connection idle in transaction for more than a few minutes should be investigated and potentially terminated.

---

## Exercise 9: Verify SSL Configuration

On **pg-primary**, as **postgres**, inside psql:

```sql
SHOW ssl;
```

Expected output:

```
 ssl
-----
 on
(1 row)
```

If `ssl` is `off`, that is a critical finding. All connections would be sending credentials and data in plaintext.

Check the SSL certificate file. On **pg-primary**, as **postgres**, inside psql:

```sql
SHOW ssl_cert_file;
SHOW ssl_key_file;
SHOW ssl_ca_file;
```

Verify that the certificate files actually exist on disk. Exit psql first. On **pg-primary**, as **postgres**, inside psql:

```sql
\q
```

On **pg-primary**, as **postgres**:

```bash
ls -lh $(psql -d quantdb -t -c "SHOW ssl_cert_file;" | tr -d ' \n')
```

If the certificate file is missing or the path is empty, SSL is misconfigured.

Exit to ec2-user. On **pg-primary**, as **postgres**:

```bash
exit
```

---

## Exercise 10: Check Audit Logging Configuration

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb
```

Check what statements are being logged. On **pg-primary**, as **postgres**, inside psql:

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

Possible values and their meanings:
- `none` - nothing is logged. This is a finding for a compliance environment.
- `ddl` - only DDL statements like CREATE, DROP, ALTER are logged. Minimum acceptable for audit.
- `mod` - DDL plus INSERT, UPDATE, DELETE, TRUNCATE. Better.
- `all` - every statement. Verbose but provides complete audit trail.

For Voleon's compliance requirements, `ddl` captures schema changes. `mod` would capture data modification for higher assurance. Discuss with your team which level is appropriate based on your data classification.

Check the slow query log threshold. On **pg-primary**, as **postgres**, inside psql:

```sql
SHOW log_min_duration_statement;
```

Expected output (yours will differ):

```
 log_min_duration_statement
----------------------------
 1000
(1 row)
```

A value of `1000` means queries taking longer than 1 second are logged. A value of `-1` means slow query logging is disabled (finding). A value of `0` means every query is logged (may be too verbose in production).

Check whether connection attempts are logged. On **pg-primary**, as **postgres**, inside psql:

```sql
SHOW log_connections;
SHOW log_disconnections;
```

Both should be `on` for a compliance-grade audit trail. If either is `off`, failed connection attempts cannot be tracked.

---

## Exercise 11: Review Replication Security

Still inside psql on pg-primary. Check the replication-specific pg_hba.conf entries.

On **pg-primary**, as **postgres**, inside psql:

```sql
\q
```

On **pg-primary**, as **postgres**:

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres grep "replication" /var/lib/pgsql/17/data/pg_hba.conf
```

Expected output (yours will differ):

```
host    replication     replicator      10.0.1.84/32            scram-sha-256
```

Audit this line:
- The auth method must be `scram-sha-256`, not `trust` or `md5`.
- The CIDR should be the specific replica IP (`/32`), not a broad range. Using `0.0.0.0/0` here would allow any machine on the internet to attempt a replication connection.
- The role must be `replicator` (or equivalent), not `postgres`. Using the `postgres` superuser for replication gives the replication channel superuser-level access, which is excessive.

Verify the replicator role has the replication attribute and nothing more. On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "\du replicator"
```

Expected output (yours will differ):

```
            List of roles
  Role name  |  Attributes   | Member of
-------------+---------------+-----------
 replicator  | Replication   | {}
```

`Replication` only. No superuser, no create role.

Exit to ec2-user. On **pg-primary**, as **postgres**:

```bash
exit
```

---

## Exercise 12: PgBouncer Security Audit

PgBouncer sits in front of PostgreSQL and pools connections. Its security configuration is part of the overall database security posture.

SSH into pg-ops. Open a second terminal or exit pg-primary first.

On **pg-ops**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

Find the PgBouncer configuration file. On **pg-ops**, as **ec2-user**:

```bash
sudo find /etc -name "pgbouncer.ini" 2>/dev/null
```

Read the authentication settings. On **pg-ops**, as **ec2-user**:

```bash
sudo grep -E "auth_type|auth_file|server_tls|client_tls" /etc/pgbouncer/pgbouncer.ini
```

Expected output (yours will differ):

```
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
client_tls_sslmode = require
server_tls_sslmode = require
```

Key checks:
- `auth_type` must be `scram-sha-256`, not `md5` or `trust`.
- `client_tls_sslmode = require` means clients must use SSL to connect to PgBouncer.
- `server_tls_sslmode = require` means PgBouncer must use SSL when connecting to PostgreSQL.
- If either TLS setting is `disable` or `allow`, connections may travel in plaintext.

Check the userlist.txt permissions. On **pg-ops**, as **ec2-user**:

```bash
sudo ls -l /etc/pgbouncer/userlist.txt
```

Expected output (yours will differ):

```
-rw------- 1 pgbouncer pgbouncer 284 Jun 12 10:00 /etc/pgbouncer/userlist.txt
```

The file permissions must be `600` (owner read/write only). If the file is readable by other users (`644` or `655`), that is a finding. The userlist.txt contains hashed credentials, but broader permissions increase the attack surface.

Check the actual content format. On **pg-ops**, as **ec2-user**:

```bash
sudo head -3 /etc/pgbouncer/userlist.txt
```

Expected output (yours will differ):

```
"quant_app" "SCRAM-SHA-256$4096:..."
"quant_research" "SCRAM-SHA-256$4096:..."
"pgbouncer" "SCRAM-SHA-256$4096:..."
```

Each line should show `SCRAM-SHA-256$` as the hash prefix. If any line shows `md5` as the prefix, regenerate that password hash.

---

## Exercise 13: Produce an Audit Summary

Compile your findings into a simple table. Based on what you observed, fill in this template in your notes:

```
FINDING                              STATUS      SEVERITY
password_encryption = scram-sha-256  PASS/FAIL   CRITICAL
No md5 role hashes                   PASS/FAIL   HIGH
No trust entries in pg_hba.conf      PASS/FAIL   CRITICAL
Only postgres has superuser          PASS/FAIL   CRITICAL
quant_app cannot DELETE              PASS/FAIL   HIGH
quant_research cannot INSERT/UPDATE  PASS/FAIL   HIGH
SSL enabled                          PASS/FAIL   CRITICAL
log_statement captures DDL           PASS/FAIL   MEDIUM
log_connections = on                 PASS/FAIL   MEDIUM
Replication uses scram-sha-256       PASS/FAIL   HIGH
Replication CIDR is /32              PASS/FAIL   MEDIUM
replicator has no superuser          PASS/FAIL   HIGH
PgBouncer auth_type = scram-sha-256  PASS/FAIL   HIGH
userlist.txt permissions = 600       PASS/FAIL   MEDIUM
PgBouncer enforces TLS               PASS/FAIL   HIGH
```

Any FAIL at CRITICAL severity requires immediate remediation. FAIL at HIGH severity requires a remediation plan within the sprint. FAIL at MEDIUM severity should be tracked and scheduled.

---

## Summary

In this exercise you:
- Verified SCRAM-SHA-256 is the active password encryption algorithm
- Confirmed all role password hashes use SCRAM-SHA-256, not MD5
- Reviewed pg_hba.conf for trust entries, md5 entries, and overly broad CIDR ranges
- Used `\du+` to audit role attributes and confirm only postgres has superuser
- Tested that `quant_app` and `quant_research` cannot perform operations outside their intended scope
- Reviewed pg_stat_statements for unusual query patterns and high-volume activity
- Checked active connections by role and flagged idle-in-transaction risks
- Confirmed SSL is enabled and certificate files exist
- Reviewed audit logging settings for DDL, slow queries, and connection events
- Audited the replication pg_hba.conf entry for authentication method and CIDR restriction
- Audited PgBouncer's auth_type, TLS settings, and userlist.txt file permissions
- Compiled findings into a prioritized audit summary

Security audits are not one-time events. In a production environment, run these checks on a scheduled basis and compare results against your previous audit to detect regression.
