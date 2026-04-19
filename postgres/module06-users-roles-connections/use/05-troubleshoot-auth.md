# Exercise 05 - Troubleshoot Authentication Failures

**Module:** 06 - Users, Roles & Connections
**Time:** 20 minutes

---

## Scenario

Someone on your team edited pg_hba.conf and now the application cannot connect. You will be given a series of broken configurations to diagnose. For each one, identify the problem and explain the fix.

---

## Setup

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Diagnostic Toolkit

Before looking at each scenario, memorize these commands. You will use them for every authentication problem.

**Check service status:**

```bash
sudo systemctl status postgresql-16
```

**View pg_hba.conf:**

```bash
sudo cat /opt/pgsql/data/pg_hba.conf
```

**Check what rules PostgreSQL parsed:**

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT line_number, type, database, user_name, address, auth_method, error FROM pg_hba_file_rules ORDER BY line_number;"
```

```bash
exit
```

**Check the PostgreSQL log:**

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

---

## Scenario A - The wrong user is connecting

**Symptom:** app_user cannot connect. Error: "password authentication failed."

**Broken hba rule:**

```
host    all    readonly_user    0.0.0.0/0    scram-sha-256
```

**Question:** The app connects as app_user, but this rule only matches readonly_user. What happens when app_user connects?

**Answer:** The rule does not match app_user. PostgreSQL continues scanning down the file. If no other rule matches app_user from the source IP, the connection is rejected with "no pg_hba.conf entry for host."

**Fix:** Change the rule to match `app_user` or use `all` to match any user.

---

## Scenario B - Trust on a TCP connection (security policy violation)

**Symptom:** Audit team flagged that app_user can connect without a password from any IP.

**Broken hba rule:**

```
host    all    app_user    0.0.0.0/0    trust
```

**Question:** How is this a security problem even if the server is in a private network?

**Answer:** `trust` means no password is checked. Anyone who can reach port 5432 can connect as app_user. A network misconfiguration, a compromised internal host, or a port scan finding the port open is enough for an attacker to gain access.

**Fix:** Change `trust` to `scram-sha-256`.

---

## Scenario C - Order matters

**Symptom:** app_user connects successfully but the audit log shows it is using `trust` instead of `scram-sha-256`.

**Broken hba content (in order):**

```
host    all    all    0.0.0.0/0    trust
host    all    app_user    0.0.0.0/0    scram-sha-256
```

**Question:** Why does app_user use `trust` even though there is a scram-sha-256 rule for it below?

**Answer:** PostgreSQL uses the FIRST matching rule. The first rule matches all users from all addresses with trust. The app_user-specific scram-sha-256 rule is never reached.

**Fix:** Move the more specific rule ABOVE the more general rule.

**Correct order:**

```
host    all    app_user    0.0.0.0/0    scram-sha-256
host    all    all         0.0.0.0/0    trust
```

---

## Scenario D - Wrong connection type for peer auth

**Symptom:** Connection attempt from 127.0.0.1 fails with: "FATAL: Ident authentication failed for user postgres."

**Broken hba rule:**

```
host    all    postgres    127.0.0.1/32    peer
```

**Question:** Why does peer auth fail for a TCP connection?

**Answer:** `peer` authentication only works for Unix socket connections (TYPE = `local`). It works by asking the OS what user owns the connecting process. TCP connections do not have this OS-level process association.

**Fix:** Change `peer` to `scram-sha-256` for host-type connections, or change `host` to `local` if only local socket connections are needed.

---

## Scenario E - CIDR mismatch

**Symptom:** App server at 10.0.1.50 cannot connect. Error: "no pg_hba.conf entry for host 10.0.1.50."

**Current hba rule:**

```
host    all    app_user    10.0.0.0/24    scram-sha-256
```

**Question:** The rule looks like it allows the app server. Why does it fail?

**Answer:** The rule covers 10.0.0.0 - 10.0.0.255. The app server at 10.0.1.50 is in the 10.0.1.x subnet, which is NOT covered by /24. The CIDR needs to be expanded.

**Fix:** Change to `10.0.0.0/16` to cover both subnets, or add a second rule for `10.0.1.0/24`.

---

## Practice Task - Fix a real pg_hba.conf

Back up the current file:

```bash
sudo cp /opt/pgsql/data/pg_hba.conf /opt/pgsql/data/pg_hba.conf.exercise-backup
```

Edit pg_hba.conf and introduce one of the bugs above:

```bash
sudo vi /opt/pgsql/data/pg_hba.conf
```

Swap the order of a general rule and a specific rule so the general one comes first.

Reload:

```bash
sudo systemctl reload postgresql-16
```

Observe the connection behavior. Then fix it and reload again.

Restore from backup when done:

```bash
sudo cp /opt/pgsql/data/pg_hba.conf.exercise-backup /opt/pgsql/data/pg_hba.conf
```

```bash
sudo systemctl reload postgresql-16
```

---

## Review Questions

1. What does "FATAL: no pg_hba.conf entry for host" mean, and how is it different from "FATAL: password authentication failed"?
2. If you add a new rule to pg_hba.conf, do you need to restart or reload PostgreSQL?
3. How can you check that pg_hba.conf parsed without errors without restarting the server?
