# Runbook 04 - Security Breach Response

**Severity:** Critical - Unauthorized superuser access, data exfiltration, audit disabled
**Time to resolve:** 20-30 minutes
**Skills tested:** Security (Module 07), roles/privileges (Module 06), pg_hba.conf (Module 06), logging (Module 10)

---

## Fix Path

### Step 1: Detect the unauthorized changes

Start by identifying what the attacker did. Even though audit logging was disabled, there are other traces.

```bash
su - postgres
```

#### Check for rogue roles

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication FROM pg_roles WHERE rolsuper = true ORDER BY rolname;"
```

Look for any superuser that should not exist. Expected superusers: `postgres`, `repmgr`. Anything else is suspicious.

#### Check for privilege escalation

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper FROM pg_roles WHERE rolname LIKE 'app_%';"
```

If any `app_*` role has `rolsuper = t`, it was escalated.

#### Check pg_hba.conf for trust rules

```bash
grep "trust" /opt/pgsql/data/pg_hba.conf
```

Any `host ... trust` line for remote connections is a backdoor.

#### Check for suspicious functions

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT proname, prosrc FROM pg_proc JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid WHERE nspname = 'app' AND prosrc LIKE '%RAISE LOG%';"
```

Functions that write data to logs are a common exfiltration technique.

#### Check the logs for exfiltrated data

```bash
grep "EXFIL" /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

If you see customer data in the log, the exfiltration already happened.

#### Check if audit logging is disabled

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_connections;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_statement;"
```

If `off` or `none`, the attacker disabled auditing to cover their tracks.

### Step 2: Revoke the rogue superuser

```bash
/usr/pgsql-16/bin/psql -c "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA app FROM backdoor_admin;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP ROLE IF EXISTS backdoor_admin;"
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname FROM pg_roles WHERE rolname = 'backdoor_admin';"
```

Expected: 0 rows.

### Step 3: Remove privilege escalation

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_readwrite WITH NOSUPERUSER;"
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper FROM pg_roles WHERE rolname = 'app_readwrite';"
```

Expected: `rolsuper = f`

### Step 4: Restore audit logging

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET log_connections = 'on';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET log_disconnections = 'on';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET log_statement = 'ddl';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET log_min_duration_statement = 1000;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_connections;"
```

Expected: `on`

### Step 5: Remove the exfiltration function

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DROP FUNCTION IF EXISTS app.exfil_data();"
```

### Step 6: Clean up pg_hba.conf

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Remove the line containing `backdoor_admin` and `trust`. Look for:

```
host all backdoor_admin 0.0.0.0/0 trust
```

Delete that line. Save and exit (`:wq`).

Reload:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

Verify no trust rules for remote connections:

```bash
grep "trust" /opt/pgsql/data/pg_hba.conf | grep -v "^#" | grep "host"
```

Expected: No output.

### Step 7: Rotate all credentials

The attacker had superuser access and may have read other passwords:

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_readwrite WITH PASSWORD 'AppRW_2026_rotated';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_readonly WITH PASSWORD 'AppRO_2026_rotated';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_owner WITH PASSWORD 'AppOwn_2026_rotated';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE replicator WITH PASSWORD 'Repl_2026_rotated';"
```

Update the pgBouncer userlist after rotating:

```bash
/usr/pgsql-16/bin/psql -t -A -c "SELECT '\"' || rolname || '\" \"' || rolpassword || '\"' FROM pg_authid WHERE rolcanlogin AND rolpassword IS NOT NULL;" > /etc/pgbouncer/userlist.txt
```

```bash
exit
```

Restart pgBouncer:

```bash
systemctl restart pgbouncer
```

### Step 8: Clean up exfiltrated data from logs

```bash
su - postgres
```

The log files contain customer data. In a real breach, you would preserve logs for forensics. For this lab, note the location:

```bash
grep -l "EXFIL" /opt/pgsql/log/*.log
```

In production: preserve a forensic copy, then redact the sensitive data from operational logs.

```bash
exit
```

---

## Revision Concepts

**Q: How would you detect this breach in production with logging disabled?**
A: Even with logging disabled, you can check: (1) `pg_roles` for unexpected roles, (2) `pg_hba.conf` for trust rules, (3) `pg_authid` for password hash changes, (4) `pg_stat_activity` for unexpected connections, (5) OS-level auth logs for SSH access. This is why defense-in-depth (multiple monitoring layers) matters.

**Q: Why rotate ALL passwords, not just the compromised ones?**
A: A superuser can read all password hashes from `pg_authid`. Even with scram-sha-256, the attacker could have captured the hashes for offline cracking. Rotating everything is the only safe response.

**Q: What is the most important thing to restore first?**
A: Audit logging. Without it, you cannot track what else the attacker does if they still have access through another vector. Restore visibility first, then close the gaps.
