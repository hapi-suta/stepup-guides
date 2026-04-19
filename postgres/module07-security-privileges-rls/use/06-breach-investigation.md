# Use 06 - Breach Investigation

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 25 minutes

---

## Objective

Given a set of log entries, trace unauthorized access attempts and identify the attack vector. You will practice reading PostgreSQL log output, querying pg_stat_activity, and using the audit_log table to reconstruct what happened.

---

## The Scenario

Your security monitoring system flagged unusual activity at 02:00 UTC. You have been paged. The following log fragments were captured before the investigation started. Your job is to trace the attack path and identify what was accessed.

---

## Simulated Log Fragment

```
2026-04-19 02:00:01 UTC [9910]: user=,db=,app=,client=10.0.1.45 LOG:  connection received
2026-04-19 02:00:01 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  connection authorized
2026-04-19 02:00:02 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  statement: SELECT * FROM pg_shadow;
2026-04-19 02:00:04 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  statement: CREATE ROLE backdoor WITH LOGIN SUPERUSER PASSWORD 'evil123';
2026-04-19 02:00:06 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  statement: SELECT tenant_id, COUNT(*) FROM orders GROUP BY tenant_id;
2026-04-19 02:00:08 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  statement: COPY orders TO '/tmp/orders_dump.csv' CSV HEADER;
2026-04-19 02:00:10 UTC [9910]: user=postgres,db=stepup_store,app=psql,client=10.0.1.45 LOG:  disconnection: session time: 0:00:09.123
```

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Answer these questions before querying the database

Read the log fragment above carefully and answer:

1. What client IP originated the attack?
2. Which database user did the attacker use?
3. What four actions did the attacker take?
4. What is the most dangerous single action, and why?

Write down your answers before continuing.

---

## Step 3 - Check if the backdoor role exists

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT rolname, rolsuper, rolcanlogin, rolpassword IS NOT NULL AS has_password
FROM pg_authid
WHERE rolname = 'backdoor';
```

Expected output if the attack scenario actually ran:

```
 rolname  | rolsuper | rolcanlogin | has_password
----------+----------+-------------+--------------
 backdoor | t        | t           | t
(1 row)
```

If this role exists, the attacker succeeded in creating a persistence mechanism.

---

## Step 4 - Immediately revoke the backdoor role if found

```sql
DROP ROLE IF EXISTS backdoor;
```

Expected output:

```
DROP ROLE
```

---

## Step 5 - Check for any other suspicious superuser roles created recently

```sql
SELECT rolname, rolsuper,
       (SELECT description FROM pg_description d WHERE d.objoid = r.oid) AS description
FROM pg_roles r
WHERE rolsuper = true
  AND rolname NOT IN ('postgres')
ORDER BY rolname;
```

This finds any superuser roles beyond the expected `postgres` account. Investigate every result.

---

## Step 6 - Simulate the investigation using the audit_log table

If the audit trigger from Build 05 was active, it captured the damage. Query the audit trail:

```sql
SELECT event_time, db_user, table_name, operation, client_addr
FROM audit_log
WHERE event_time > NOW() - INTERVAL '1 hour'
ORDER BY event_time ASC;
```

Expected output (yours will differ, showing recent activity in this lab):

```
         event_time         | db_user  | table_name | operation | client_addr
----------------------------+----------+------------+-----------+-------------
 2026-04-19 12:05:00+00     | postgres | orders     | INSERT    | 127.0.0.1
 2026-04-19 12:05:30+00     | postgres | orders     | UPDATE    | 127.0.0.1
```

---

## Step 7 - Check the actual PostgreSQL log on disk

```sql
\q
```

```bash
tail -50 /opt/pgsql/log/postgresql-*.log
```

Look for:
- Connection events from unusual IP addresses
- `CREATE ROLE` or `ALTER ROLE` statements with SUPERUSER
- `COPY ... TO` statements (data exfiltration)
- `SELECT * FROM pg_shadow` (password hash enumeration)

---

## Step 8 - Identify the attack vector from the log analysis

Based on the log fragment and your investigation, the attack path was:

1. **Access gained** - The attacker connected as `postgres` from IP `10.0.1.45`. This means either: the postgres password was compromised, pg_hba.conf had trust auth for that IP range, or the attacker had OS-level access to a client machine.

2. **Reconnaissance** - `SELECT * FROM pg_shadow` reads password hashes for all database roles. An attacker with this data can attempt offline password cracking.

3. **Persistence** - `CREATE ROLE backdoor WITH LOGIN SUPERUSER` creates a hidden admin account the attacker controls even if the postgres password is changed.

4. **Data exfiltration** - `COPY orders TO '/tmp/orders_dump.csv'` writes all order data to a file on the server. The attacker can then download it.

---

## Step 9 - Check pg_hba.conf for the attack vector

```bash
cat /opt/pgsql/data/pg_hba.conf
```

Look for:
- Any `trust` entries for TCP connections
- Overly broad CIDR ranges (like `0.0.0.0/0`)
- Any `host` (not `hostssl`) entries

If you find `host all all 0.0.0.0/0 trust`, that is the attack vector. The attacker connected over TCP as postgres without a password because trust auth was in place.

---

## Step 10 - Implement immediate remediation

If trust auth was the vector, connect locally and fix it:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Revoke any other suspicious grants:

```sql
SELECT grantee, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE grantee NOT IN ('postgres', 'pg_read_all_data', 'app_user', 'readonly_user', 'tenant_alpha', 'tenant_beta', 'analytics_team', 'dev_team', 'dba_ops', 'tenant_admin', 'tenant_user', 'tenant_readonly')
  AND table_schema = 'public';
```

Remove any unexpected grants found.

---

## Step 11 - Check for files written by the attacker

```sql
\q
```

```bash
exit
```

```bash
ls -la /tmp/*.csv 2>/dev/null
```

If an exfiltration file exists:

```bash
sudo wc -l /tmp/orders_dump.csv
```

Document the finding. In a real incident, preserve the file as evidence before removing it.

---

## Step 12 - Write up your incident findings

Answer these questions based on your investigation:

1. **What was the initial access vector?** (How did the attacker get in?)
2. **What data was accessed or exfiltrated?**
3. **What persistence mechanism was created?**
4. **What immediate remediation steps are required?**
5. **What controls should be added to prevent recurrence?**

---

## Remediation Checklist

After any confirmed breach, work through this checklist:

```
[ ] Revoke all backdoor roles created by the attacker
[ ] Reset the postgres password to a long random string
[ ] Audit pg_hba.conf and remove all trust entries for TCP
[ ] Review all roles with SUPERUSER or BYPASSRLS
[ ] Check audit_log for all statements made in the attack window
[ ] Identify what data was accessed (use audit_log + pg_stat_statements if available)
[ ] Remove any files written to disk by COPY ... TO
[ ] Restrict pg_hba.conf to known application IPs only
[ ] Enable hostssl for all TCP connections
[ ] Notify relevant stakeholders per your incident response plan
```

---

## Step 13 - Return to ec2-user

```bash
exit
```

---

## Validation Questions

1. Why is `SELECT * FROM pg_shadow` one of the first things an attacker does after gaining superuser access?
2. What is the difference between `COPY orders TO '/tmp/file.csv'` and `COPY orders TO STDOUT`? Which is more dangerous and why?
3. How would the audit_log trigger have helped in this investigation, and what would it NOT capture?
4. If an attacker creates a backdoor role with SUPERUSER, then the admin resets the postgres password, is the system still compromised? Why?
