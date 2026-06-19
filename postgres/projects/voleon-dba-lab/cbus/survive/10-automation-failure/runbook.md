# Runbook: Automation Failure

## Scenario Overview

Two simultaneous issues are breaking your automation and replication:

1. **Ansible cannot reach pg-primary** - The inventory file on pg-ops has a wrong IP address for pg-primary. Any playbook targeting pg-primary will timeout with "UNREACHABLE."
2. **Replication is broken** - A bad `pg_hba.conf` rule on pg-primary is rejecting the replicator connection from pg-replica. The standby has disconnected and is falling behind.

These two issues simulate a common real-world problem: someone made manual changes to automation config files and database access rules, and now both your tooling and your replication are broken.

---

## Phase 1: Triage - What Are You Seeing?

Before diving into fixes, confirm the symptoms. A production alert scenario might look like:

- Ansible playbooks fail with "UNREACHABLE" for pg-primary
- Grafana shows replication lag climbing from seconds to minutes
- The replica's PostgreSQL logs show "FATAL: no pg_hba.conf entry for replication connection"
- `pg_stat_replication` on the primary shows zero rows

**Your first step should be to confirm both issues are real.**

### Confirm Issue 1: Ansible Cannot Reach pg-primary

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

```bash
ansible pg_primary -i inventory/hosts.yml -m ping
```

Expected output (yours will differ):

```
pg-primary | UNREACHABLE! => {
    "changed": false,
    "msg": "Failed to connect to the host via ssh: ssh: connect to host 10.99.99.99 port 22: Connection timed out",
    "unreachable": true
}
```

Notice the IP in the error message - it is `10.99.99.99`, not the real IP `172.31.19.86`. This tells you the inventory file has the wrong IP.

### Confirm Issue 2: Replication Is Down

SSH into pg-primary directly (using the real IP, not through Ansible). On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
 client_addr | state | sent_lsn | replay_lsn
-------------+-------+----------+------------
(0 rows)
```

Zero rows means no replica is connected. Replication is broken.

Check the PostgreSQL log for details:

```bash
tail -30 /var/lib/pgsql/17/data/log/postgresql-*.log | grep -i "replication\|FATAL\|reject"
```

Expected output (yours will differ):

```
FATAL:  pg_hba.conf rejects connection for host "172.31.22.69", user "replicator", database "replication", SSL encryption
```

This confirms the pg_hba.conf is blocking the replica.

```bash
exit
```

Now you know both issues. Time to fix them.

---

## Phase 2: Diagnose Each Issue

### Issue 1: Wrong IP in Ansible Inventory

On **pg-ops**, as **ec2-user**:

Look at the inventory file:

```bash
cat ~/ansible/inventory/hosts.yml
```

Expected output (yours will differ):

```yaml
    pg_primary:
      hosts:
        pg-primary:
          ansible_host: 10.99.99.99
          pg_role: primary
```

The `ansible_host` for pg-primary is `10.99.99.99` instead of `172.31.19.86`. This is why Ansible cannot connect.

Check if there is a backup:

```bash
ls -la ~/ansible/inventory/hosts.yml*
```

Expected output (yours will differ):

```
-rw-r--r-- 1 ec2-user ec2-user  612 Jun 18 14:30 hosts.yml
-rw-r--r-- 1 ec2-user ec2-user  615 Jun 18 14:29 hosts.yml.chaos_backup
```

Good - there is a `.chaos_backup` file. This is the original before the change.

### Issue 2: Bad pg_hba.conf Rule

On **pg-primary**, as **ec2-user** (SSH using the real IP):

```bash
sudo -u postgres grep -n "reject\|CHAOS\|replicat" /var/lib/pgsql/17/data/pg_hba.conf
```

Expected output (yours will differ):

```
5:# CHAOS: block replication
6:host    replication     replicator      172.31.22.69/32       reject
...
15:host    replication     replicator      172.31.22.69/32       scram-sha-256
```

The problem is clear: line 6 has a `reject` rule that comes before line 15's `allow` rule. PostgreSQL reads pg_hba.conf top to bottom and uses the first matching rule. The `reject` rule matches first, so the replica is denied.

Check if there is a backup:

```bash
ls -la /var/lib/pgsql/17/data/pg_hba.conf*
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 4830 Jun 18 14:30 pg_hba.conf
-rw------- 1 postgres postgres 4750 Jun 18 14:29 pg_hba.conf.chaos_backup
```

Good - there is a backup here too.

---

## Phase 3: Fix Both Issues

### Fix 1: Restore the Ansible Inventory

On **pg-ops**, as **ec2-user**:

```bash
cp ~/ansible/inventory/hosts.yml.chaos_backup ~/ansible/inventory/hosts.yml
```

`cp` copies the backup file over the corrupted file. This restores the original inventory with the correct IP address.

Verify the fix:

```bash
grep "ansible_host" ~/ansible/inventory/hosts.yml
```

Expected output (yours will differ):

```
          ansible_host: 172.31.19.86
          ansible_host: 172.31.22.69
          ansible_host: 34.235.89.112
          ansible_host: 172.31.26.19
```

The pg-primary IP should be `172.31.19.86` again.

Test Ansible connectivity:

```bash
ansible pg_primary -i inventory/hosts.yml -m ping
```

Expected output (yours will differ):

```
pg-primary | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

Ansible can reach pg-primary again.

### Fix 2: Restore pg_hba.conf and Reload PostgreSQL

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

Restore the backup:

```bash
cp /var/lib/pgsql/17/data/pg_hba.conf.chaos_backup /var/lib/pgsql/17/data/pg_hba.conf
```

Verify the reject rule is gone:

```bash
grep -c "reject" /var/lib/pgsql/17/data/pg_hba.conf
```

Expected output (yours will differ):

```
0
```

Zero matches means the reject rule has been removed.

Verify the replication allow rule still exists:

```bash
grep "replicator" /var/lib/pgsql/17/data/pg_hba.conf
```

Expected output (yours will differ):

```
host    replication     replicator      172.31.22.69/32       scram-sha-256
```

Good - the allow rule for the replicator user is still there.

```bash
exit
```

Now reload PostgreSQL to apply the fixed pg_hba.conf. On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl reload postgresql-17
```

`systemctl reload` tells PostgreSQL to re-read its configuration files without restarting. This is safe - existing connections are not dropped.

Verify the reload worked:

```bash
sudo systemctl status postgresql-17 | head -5
```

Expected output (yours will differ):

```
   postgresql-17.service - PostgreSQL 17 database server
   Loaded: loaded
   Active: active (running)
```

---

## Phase 4: Verify Everything Is Working

### Check 1: Ansible Can Reach All Nodes

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

```bash
ansible all -i inventory/hosts.yml -m ping
```

Expected output (yours will differ):

```
pg-primary | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
pg-replica | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
pg-container | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
pg-ops | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

All four nodes should respond with "pong."

### Check 2: pg_hba.conf Allows Replication

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres grep "replicator" /var/lib/pgsql/17/data/pg_hba.conf
```

You should see an allow rule (scram-sha-256 or md5) for the replicator user, and NO reject rules.

### Check 3: Replication Is Streaming

The replica may reconnect automatically within a few seconds. Check the primary.

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "SELECT client_addr, state, sent_lsn, replay_lsn, replay_lag FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
  client_addr   |  state    |   sent_lsn   |  replay_lsn  | replay_lag
----------------+-----------+--------------+--------------+------------
 172.31.22.69   | streaming | 0/1A000148   | 0/1A000148   | 00:00:00
```

If you see `streaming` with near-zero lag, replication is restored.

If the replica has not reconnected yet, you may need to check the replica side.

```bash
exit
```

### Check 4: If Replica Has Not Reconnected

Sometimes the replica needs a nudge. SSH into pg-replica.

On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.144.241.128
```

On **pg-replica**, as **ec2-user**:

Check the replica's PostgreSQL log for connection errors:

```bash
sudo tail -20 /var/lib/pgsql/17/data/log/postgresql-*.log
```

If you see errors like "FATAL: could not connect to the primary server", restart the replica's PostgreSQL:

```bash
sudo systemctl restart postgresql-17
```

Then check back on pg-primary to verify the replica reconnected (repeat the pg_stat_replication query above).

```bash
exit
```

### Check 5: Run the Full Status Playbook

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

```bash
ansible-playbook -i inventory/hosts.yml playbooks/check-pg-status.yml
```

All checks should pass. If any fail, review the specific failure message and fix it before proceeding.

---

## Phase 5: Post-Mortem - Preventing This in the Future

### Root Cause

Two manual changes caused this outage:

1. Someone edited the Ansible inventory file and put in a wrong IP address
2. Someone added a reject rule to pg_hba.conf without testing

### Prevention Measures

**1. Version control for all configuration files**

The Ansible inventory, playbooks, and any config templates should be in git. Changes go through pull requests with review before merging.

```
# Good: change goes through git
git checkout -b fix/update-primary-ip
vi inventory/hosts.yml
git add inventory/hosts.yml
git commit -m "fix: update pg-primary IP after migration"
git push origin fix/update-primary-ip
# Create PR, get review, merge
```

**2. Always use --check mode first**

Before running any Ansible playbook that modifies servers, run it with `--check --diff` to see what would change without actually changing it:

```bash
ansible-playbook playbooks/update-pg-param.yml --check --diff -e "param=work_mem value=8MB"
```

**3. Ansible validation playbook**

Run a validation playbook after any pg_hba.conf change to verify replication is still working:

```bash
ansible-playbook playbooks/check-pg-status.yml
```

**4. Automated drift detection**

Schedule the pg-config-check playbook to run via cron or Jenkins every hour. If it detects drift (manual changes), it alerts the team.

**5. Backup before modify**

Before editing any configuration file manually, always create a backup:

```bash
cp pg_hba.conf pg_hba.conf.backup.$(date +%Y%m%d-%H%M%S)
```

This way you can always restore the previous version.

**6. Test pg_hba.conf changes with a dry-run**

PostgreSQL does not have a built-in pg_hba.conf test mode, but you can validate the syntax by reloading and immediately checking the logs:

```bash
sudo systemctl reload postgresql-17
sudo tail -5 /var/lib/pgsql/17/data/log/postgresql-*.log
```

If the log shows errors about pg_hba.conf, the reload still applies valid rules up to the error line. Fix the error immediately.

---

## Interview Talking Points

When discussing this scenario in an interview:

- **Triage order matters** - Check Ansible connectivity first (can you reach the servers?), then check the database layer (is replication healthy?)
- **pg_hba.conf is order-dependent** - PostgreSQL reads rules top to bottom and uses the first match. A reject rule before an allow rule blocks the connection even if the allow rule exists later in the file
- **Automation tools need protection too** - The Ansible inventory is critical infrastructure. Treat it like a database config file - version it, review changes, back it up
- **Reload vs. restart** - pg_hba.conf changes only need a reload (`pg_ctl reload` or `systemctl reload`), not a full restart. This means zero downtime for connection rule changes
- **Idempotent fixes** - Restoring from a backup is idempotent. You can run it multiple times safely without causing additional problems
