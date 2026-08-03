# Use 03 - SSL Enforcement

**Time:** 20 minutes
**Prerequisite:** Build 03 (SSL/TLS Connections)

---

## Scenario

Your security team ran a scan and found that some connections to your [COMPANY] production RDS instance are not using SSL. This is a compliance violation.

Your tasks:
1. Find which connections are not using SSL
2. Determine why (misconfigured app? developer tool? legacy script?)
3. Fix the issue on the server side (enforce SSL)
4. Verify all connections now use SSL
5. Document which applications needed updating

---

## Setup

Connect to your RDS instance as master user:

```bash
psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=require"
```

Create a second test user for simulating the problem:

```sql
CREATE ROLE legacy_app WITH LOGIN PASSWORD 'LegacyPass1!';
GRANT CONNECT ON DATABASE postgres TO legacy_app;
```

---

## Task 1 - Simulate Unencrypted Connections

Open several terminal windows and connect without SSL to simulate what the security team found.

**Terminal 2 (unencrypted connection):**

```bash
psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=legacy_app sslmode=disable"
```

If this fails (SSL already enforced), note that and skip to Task 3.

If it succeeds, leave this connection open.

---

## Task 2 - Find Unencrypted Connections

In your master user session, run:

```sql
SELECT
    sa.pid,
    sa.usename,
    sa.client_addr,
    sa.application_name,
    sa.state,
    ss.ssl,
    ss.version AS ssl_version,
    ss.cipher
FROM pg_stat_activity sa
LEFT JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend'
  AND sa.usename IS NOT NULL
ORDER BY ss.ssl, sa.usename;
```

Expected output (yours will differ):

```
  pid  │  usename   │ client_addr  │ application_name │ state │ ssl │ ssl_version │ cipher
───────┼────────────┼──────────────┼──────────────────┼───────┼─────┼─────────────┼───────────
 12340 │ legacy_app │ 203.0.113.5  │ psql             │ idle  │ f   │             │
 12345 │ postgres   │ 203.0.113.5  │ psql             │ active│ t   │ TLSv1.3     │ TLS_AES...
```

Write down:
- Which users are connecting without SSL
- What their `client_addr` is
- What `application_name` they are using

---

## Task 3 - Check If rds.force_ssl Is Already Set

```sql
SHOW rds.force_ssl;
```

Expected output if not enforced:

```
 rds.force_ssl
───────────────
 off
```

Expected output if already enforced:

```
 rds.force_ssl
───────────────
 on
```

---

## Task 4 - Create or Find Your Parameter Group

Check what parameter group your instance uses:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DBParameterGroups' \
  --output table \
  --region [REGION]
```

If it is using the default parameter group (the name will be `default.postgres15` or similar), you cannot edit it. Create a custom one:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name ssl-enforced-params \
  --db-parameter-group-family postgres16 \
  --description "SSL enforced parameter group" \
  --region [REGION]
```

---

## Task 5 - Enable rds.force_ssl

Set the parameter:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name ssl-enforced-params \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region [REGION]
```

Assign the parameter group to your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --db-parameter-group-name ssl-enforced-params \
  --apply-immediately \
  --region [REGION]
```

Reboot:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [REGION]
```

Wait for it to come back up:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [REGION]
```

---

## Task 6 - Verify SSL Is Now Enforced

Try to connect without SSL:

```bash
psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=legacy_app sslmode=disable"
```

Expected output:

```
psql: error: connection to server at "..." failed:
FATAL:  no pg_hba.conf entry for host "...", user "legacy_app", database "postgres", SSL off
```

Good - rejected.

Now connect with SSL:

```bash
psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=legacy_app sslmode=require"
```

Expected output:

```
psql (16.6)
SSL connection (protocol: TLSv1.3, ...)
Type "help" for help.

postgres=>
```

---

## Task 7 - Find All Non-SSL Connections in a Running System

After re-enabling connections, this query shows you the current SSL status of all sessions. In a healthy system enforcing SSL, every row should show `ssl = t`:

```sql
SELECT
    COUNT(*) FILTER (WHERE ss.ssl = TRUE) AS ssl_connections,
    COUNT(*) FILTER (WHERE ss.ssl = FALSE) AS non_ssl_connections,
    COUNT(*) AS total_connections
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend';
```

Expected output in a correctly configured system:

```
 ssl_connections │ non_ssl_connections │ total_connections
─────────────────┼─────────────────────┼───────────────────
               3 │                   0 │                 3
```

`non_ssl_connections` should be 0.

---

## Task 8 - Write the Remediation Report

Write a brief report covering:

1. How many connections were found without SSL before enforcement
2. What parameter was changed and what value it was set to
3. Confirmation that all connections now use SSL
4. Recommendation: should applications use `sslmode=require` or `sslmode=verify-full`? Why?

---

## Stretch Challenge

The `pg_stat_ssl` view also shows client certificate information. Some high-security environments require clients to present their own certificate (mutual TLS / mTLS).

Research: how would you configure RDS to require client certificates?

Hint: look at the `ssl_cert_file` and `ssl_ca_file` parameters, and the `clientcert` option in pg_hba.conf (not configurable directly on RDS - you would need `rds.custom_dns_resolution` and other workarounds).

This is an advanced topic. Understanding why it is hard on RDS is the goal.

---

## Clean Up

```sql
DROP ROLE legacy_app;
```
