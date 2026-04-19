# Use 04: Security Audit

Perform a comprehensive security audit of your PostgreSQL deployment. Check roles, privileges, authentication, SSL, logging, and network exposure. Write an audit report at the end.

---

## Instructions

1. Run each check on your primary server
2. Record findings as PASS, WARNING, or FAIL
3. For any WARNING or FAIL, note the remediation
4. Write the audit report using the template at the end

---

## 1. Role and Privilege Audit

### 1.1 List all roles and their attributes

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolcanlogin, rolconnlimit, rolvaliduntil FROM pg_roles ORDER BY rolname;"
```

Record findings:

| Role | Superuser | Can Login | Connection Limit | Password Expires |
|------|-----------|-----------|-----------------|------------------|
| | | | | |

**Check**: Are there any unexpected superuser roles? Should any login roles have connection limits?

Finding: ____

### 1.2 Check for roles with no password expiry

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolcanlogin AND (rolvaliduntil IS NULL OR rolvaliduntil > now() + interval '1 year');"
```

Best practice: All service account passwords should expire and be rotated at least annually.

Finding: ____

### 1.3 List role memberships

```bash
/usr/pgsql-16/bin/psql -c "SELECT r.rolname AS role, m.rolname AS member FROM pg_auth_members am JOIN pg_roles r ON am.roleid = r.oid JOIN pg_roles m ON am.member = m.oid ORDER BY r.rolname, m.rolname;"
```

**Check**: Are there unexpected role memberships? Is any application role a member of a privileged group?

Finding: ____

### 1.4 Check for default privileges on public schema

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT nspname, nspacl FROM pg_namespace WHERE nspname = 'public';"
```

In PostgreSQL 15+, CREATE privilege on public is revoked by default. Verify this is still the case.

Finding: ____

### 1.5 List all database-level grants

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, datacl FROM pg_database WHERE datname NOT IN ('template0', 'template1');"
```

**Check**: Is `CONNECT` granted to `PUBLIC`? It should not be on production databases.

To revoke public connect:

```bash
/usr/pgsql-16/bin/psql -c "REVOKE CONNECT ON DATABASE appdb FROM PUBLIC;"
```

Finding: ____

### 1.6 Check schema-level grants

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT nspname, nspacl FROM pg_namespace WHERE nspname IN ('app', 'audit', 'public');"
```

**Check**: Does the `audit` schema have restricted access? Only the app_owner and postgres should have access.

Finding: ____

### 1.7 Check table-level grants

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname, tablename, tableowner, has_table_privilege('app_readwrite', schemaname || '.' || tablename, 'INSERT') AS can_insert, has_table_privilege('app_readonly', schemaname || '.' || tablename, 'INSERT') AS readonly_can_insert FROM pg_tables WHERE schemaname = 'app' ORDER BY tablename;"
```

**Check**: Can `app_readonly` INSERT into any table? It should not.

Finding: ____

```bash
exit
```

---

## 2. Authentication Audit

### 2.1 Review pg_hba.conf

```bash
su - postgres
```

```bash
cat /opt/pgsql/data/pg_hba.conf | grep -v '^#' | grep -v '^$'
```

Check for these red flags:
- [ ] No `trust` for remote connections
- [ ] No `md5` (should be `scram-sha-256`)
- [ ] No `0.0.0.0/0` without SSL requirement
- [ ] Replication restricted to known IPs or SSL
- [ ] A `hostnossl ... reject` catch-all rule exists

Finding: ____

### 2.2 Check password encryption method

```bash
/usr/pgsql-16/bin/psql -c "SHOW password_encryption;"
```

PASS: `scram-sha-256`
FAIL: `md5`

Finding: ____

### 2.3 Check for passwordless login roles

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname FROM pg_authid WHERE rolcanlogin AND rolpassword IS NULL;"
```

Any role listed can authenticate without a password (if pg_hba.conf allows trust or peer). Verify this is intentional.

Finding: ____

### 2.4 Check for roles with md5 passwords

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname FROM pg_authid WHERE rolpassword LIKE 'md5%';"
```

These roles still have md5-hashed passwords. They should be migrated to scram-sha-256 by resetting their passwords.

Finding: ____

```bash
exit
```

---

## 3. SSL and Encryption Audit

### 3.1 Check SSL is enabled

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW ssl;"
```

PASS: `on`
FAIL: `off`

Finding: ____

### 3.2 Check minimum SSL protocol version

```bash
/usr/pgsql-16/bin/psql -c "SHOW ssl_min_protocol_version;"
```

PASS: `TLSv1.2` or `TLSv1.3`
FAIL: `TLSv1` or `TLSv1.1` (deprecated, known vulnerabilities)

Finding: ____

### 3.3 Check SSL certificate expiry

```bash
openssl x509 -in /opt/pgsql/ssl/server.crt -noout -dates
```

Expected output (yours will differ):
```
notBefore=Apr 19 12:00:00 2026 GMT
notAfter=Apr 17 12:00:00 2036 GMT
```

**Check**: Does the certificate expire within the next 90 days? Set a calendar reminder.

Finding: ____

### 3.4 Verify active connections are using SSL

```bash
/usr/pgsql-16/bin/psql -c "SELECT usename, ssl, client_addr FROM pg_stat_ssl JOIN pg_stat_activity USING (pid) WHERE usename IS NOT NULL ORDER BY usename;"
```

**Check**: Are any remote connections showing `ssl = false`?

Finding: ____

### 3.5 Check backup encryption

```bash
pgbackrest --stanza=prod info | grep cipher
```

PASS: Shows `cipher: aes-256-cbc`
FAIL: No cipher line (backups unencrypted)

Finding: ____

```bash
exit
```

---

## 4. Logging Audit

### 4.1 Check log settings

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT name, setting FROM pg_settings WHERE name IN ('log_connections', 'log_disconnections', 'log_statement', 'log_min_duration_statement', 'log_checkpoints', 'log_lock_waits', 'log_temp_files', 'logging_collector') ORDER BY name;"
```

Expected for production:

| Setting | Expected | Actual | Status |
|---------|----------|--------|--------|
| log_connections | on | | |
| log_disconnections | on | | |
| log_statement | ddl | | |
| log_min_duration_statement | 1000 (1s) | | |
| log_checkpoints | on | | |
| log_lock_waits | on | | |
| log_temp_files | 0 (log all) | | |
| logging_collector | on | | |

Finding: ____

### 4.2 Check log file permissions

```bash
ls -la /opt/pgsql/log/
```

**Check**: Are log files readable only by postgres? Permissions should be `rw-------` (600).

Finding: ____

### 4.3 Check log rotation

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_rotation_age;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_rotation_size;"
```

PASS: `log_rotation_age = 1d` (daily rotation)
WARNING: No rotation configured (logs will grow indefinitely)

Finding: ____

```bash
exit
```

---

## 5. Network Exposure Audit

### 5.1 Check listen_addresses

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW listen_addresses;"
```

**Check**: Is it `*` (listens on all interfaces)? If so, verify the firewall restricts access. Ideally, list only the interfaces that need to accept connections.

Finding: ____

### 5.2 Check firewall rules

```bash
exit
```

```bash
firewall-cmd --list-all
```

**Check**: Is port 5432 open to the world? It should be restricted to application servers and standby servers.

Finding: ____

### 5.3 Check for exposed management ports

```bash
ss -tlnp | grep -E '(5432|6432|9090|9100|9187|3000)'
```

Record what is listening:

| Port | Service | Binding |
|------|---------|---------|
| 5432 | PostgreSQL | |
| 6432 | pgBouncer | |
| 9090 | Prometheus | |
| 9100 | node_exporter | |
| 9187 | postgres_exporter | |
| 3000 | Grafana | |

**Check**: Management ports (9090, 9100, 9187, 3000) should NOT be accessible from the public internet. They should be restricted to the monitoring network.

Finding: ____

---

## 6. Superuser Usage Audit

### 6.1 Check recent superuser activity

```bash
su - postgres
```

```bash
grep "user=postgres" /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | tail -20
```

**Check**: Is the postgres superuser being used for application queries? It should only be used for administration.

Finding: ____

### 6.2 Check for superuser-owned application objects

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname, tablename, tableowner FROM pg_tables WHERE schemaname = 'app' AND tableowner = 'postgres';"
```

**Check**: Application tables should be owned by `app_owner`, not `postgres`. If postgres owns them, permissions are harder to manage.

Finding: ____

```bash
exit
```

---

## 7. Audit Report Template

```
# PostgreSQL Security Audit Report

## Overview
- Date: [DATE]
- Auditor: [YOUR NAME]
- Database: [DATABASE NAME]
- Server: [HOSTNAME / IP]
- PostgreSQL version: [VERSION]

## Summary
- Total checks: 20
- PASS: ____
- WARNING: ____
- FAIL: ____

## Critical Findings (FAIL)

| # | Check | Finding | Risk | Remediation |
|---|-------|---------|------|-------------|
| | | | | |

## Warnings

| # | Check | Finding | Risk | Remediation |
|---|-------|---------|------|-------------|
| | | | | |

## Passed Checks

| # | Check |
|---|-------|
| | |

## Recommendations (Priority Order)
1. [Highest risk fix first]
2. [Second highest]
3. [Third]

## Next Audit Date
- [3 months from now]

## Sign-off
- Auditor: [YOUR NAME]
- Reviewed by: [REVIEWER NAME]
- Date: [DATE]
```
