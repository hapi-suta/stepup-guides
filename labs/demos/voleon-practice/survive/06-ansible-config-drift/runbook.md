# Runbook 06: Ansible Config Drift

## Alert
> HIGH: Streaming replication has broken after an Ansible playbook run.
> pg-replica reports: `FATAL: could not connect to the primary server: FATAL: no pg_hba.conf entry for replication connection from host "172.31.22.69"`
> quantdb replica is no longer receiving WAL. Replication lag is growing.

---

## Lab Environment

| Node | Public IP | Private IP | Role |
|------|-----------|------------|------|
| pg-primary | 3.90.199.62 | 172.31.19.86 | Primary |
| pg-replica | 3.91.32.84 | 172.31.22.69 | Replica |
| pg-ops | 54.209.143.137 | 172.31.26.19 | Ops/Ansible |

SSH command: `ssh -i ~/.ssh/id_ed25519 ec2-user@<IP>`

Ansible lives on pg-ops. Playbooks are in `/opt/ansible/voleon/`.

---

## Layer 1 - Junior DBA: Assess and Contain

Your job is to confirm replication is broken, gather the exact error messages, and document what changed.

### Step 1 - SSH into the replica

From your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

### Step 2 - Check the replica's PostgreSQL service status

On **pg-replica**, as **ec2-user**:

```bash
systemctl status postgresql-17
```

Expected output (yours will differ):

```
* postgresql-17.service - PostgreSQL 17 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled)
     Active: active (running) since ...
```

PostgreSQL itself may still be running on the replica - it just cannot receive WAL from the primary. Note the status.

### Step 3 - Check PostgreSQL logs on the replica

On **pg-replica**, as **ec2-user**:

```bash
sudo ls -lt /var/lib/pgsql/17/data/log/
```

Note the most recent log file, then read its tail:

```bash
sudo tail -100 /var/lib/pgsql/17/data/log/postgresql-<date>.log
```

Expected output (yours will differ):

```
2024-01-15 15:00:01 UTC [5678]: FATAL:  could not connect to the primary server:
        FATAL:  no pg_hba.conf entry for replication connection from host "172.31.22.69",
        user "replicator", database "replication", no encryption
2024-01-15 15:00:31 UTC [5679]: FATAL:  could not connect to the primary server:
        FATAL:  no pg_hba.conf entry for replication connection from host "172.31.22.69", ...
```

The replica is trying to connect every 30 seconds and being rejected. Copy the exact error.

### Step 4 - Check replication status from the primary

Open a second terminal and SSH into the primary:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT client_addr, state, sent_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;
```

Expected output:

```
 client_addr | state | sent_lsn | replay_lsn | lag
-------------+-------+----------+------------+-----
(0 rows)
```

Zero rows means no replica is connected. Confirm this matches the error on the replica.

```bash
exit
```

```bash
exit
```

### Step 5 - Note the time the Ansible playbook ran

On **pg-ops**, check recent Ansible activity (open a third terminal):

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

On **pg-ops**, as **ec2-user**:

```bash
ls -lt /opt/ansible/voleon/logs/
```

Note the most recent log file timestamp. This tells you roughly when the playbook ran and correlates with when replication broke.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

You know replication is broken and an Ansible run happened before it broke. Now find what the playbook changed and fix it.

### Step 1 - Identify what changed: compare pg_hba.conf to expected

The most common Ansible drift scenario is a change to `pg_hba.conf` - specifically the replication entry's CIDR.

On **pg-primary**, as **ec2-user**:

```bash
sudo cat /var/lib/pgsql/17/data/pg_hba.conf | grep replication
```

Expected output showing the bad config (yours will differ):

```
host    replication     replicator      10.0.0.0/8              scram-sha-256
```

The correct CIDR for this lab is `172.31.0.0/16` (the VPC CIDR). The Ansible playbook changed it to `10.0.0.0/8`, which does not match the replica's IP of `172.31.22.69`.

For reference, the correct line should read:

```
host    replication     replicator      172.31.0.0/16           scram-sha-256
```

### Step 2 - Check the Ansible playbook for the bug

On **pg-ops**, as **ec2-user**:

```bash
grep -n "replication\|hba\|cidr\|10\.0\|172\.31" /opt/ansible/voleon/roles/postgres/templates/pg_hba.conf.j2
```

Expected output (yours will differ):

```
14:host    replication     replicator      {{ replication_cidr }}             scram-sha-256
```

Now check the variable value:

```bash
grep -r "replication_cidr" /opt/ansible/voleon/
```

Expected output (yours will differ):

```
/opt/ansible/voleon/group_vars/all.yml:replication_cidr: "10.0.0.0/8"
/opt/ansible/voleon/group_vars/production.yml:replication_cidr: "172.31.0.0/16"
```

There it is. The variable in `all.yml` was set to `10.0.0.0/8`. The production override in `production.yml` has the correct value, but the playbook ran with `--limit all` or targeted a group that picked up `all.yml` instead of `production.yml`. This is the config drift.

### Step 3 - Fix pg_hba.conf on the primary

On **pg-primary**, as **ec2-user**:

```bash
sudo vi /var/lib/pgsql/17/data/pg_hba.conf
```

Find the line:

```
host    replication     replicator      10.0.0.0/8              scram-sha-256
```

Change it to:

```
host    replication     replicator      172.31.0.0/16           scram-sha-256
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

### Step 4 - Reload PostgreSQL configuration (no restart needed)

pg_hba.conf changes take effect on reload. A restart is not required and would cause a brief outage.

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

```bash
exit
```

### Step 5 - Verify the replica reconnects

Wait 30-60 seconds for the replica to retry its connection, then check the primary:

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT client_addr, state, sent_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;
```

Expected output (yours will differ):

```
  client_addr  |   state   |  sent_lsn  | replay_lsn |  lag
---------------+-----------+------------+------------+--------
 172.31.22.69  | streaming | 0/C1000000 | 0/C0FF0000 | 64 kB
(1 row)
```

One row is back. Lag will be catching up from the time replication was broken - this is normal.

```bash
exit
```

```bash
exit
```

### Step 6 - Also check replica logs to confirm it reconnected

On **pg-replica**, as **ec2-user**:

```bash
sudo tail -20 /var/lib/pgsql/17/data/log/postgresql-<date>.log
```

Expected output (yours will differ):

```
2024-01-15 15:12:45 UTC [5701]: LOG:  started streaming WAL from primary at 0/C0000000 on timeline 1
```

The streaming line confirms the replica is receiving WAL again.

---

## Layer 3 - Senior DBA: Root Cause and Prevent

The immediate fix was a one-line change to pg_hba.conf. The real problem is that Ansible can silently break production with no pre-flight validation. Fix the process.

### Step 1 - Fix the variable in Ansible so the bug cannot recur

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/ansible/voleon/group_vars/all.yml
```

Find the line:

```yaml
replication_cidr: "10.0.0.0/8"
```

Change it to:

```yaml
replication_cidr: "172.31.0.0/16"
```

Save and exit: `Esc`, `:wq`, `Enter`.

Commit the change to version control:

```bash
cd /opt/ansible/voleon
git add group_vars/all.yml
git commit -m "fix: correct replication_cidr to match VPC CIDR 172.31.0.0/16"
```

### Step 2 - Add a pre-flight replication health check to the playbook

Before any postgres configuration playbook runs, it should verify replication is healthy. Add a pre-task that will abort the run if replication is already broken.

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/ansible/voleon/playbooks/postgres_config.yml
```

Add this block at the top of the play, before any tasks:

```yaml
  pre_tasks:
    - name: Verify replication is healthy before making changes
      become: yes
      become_user: postgres
      command: >
        /usr/pgsql-17/bin/psql -d quantdb -tAc
        "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'"
      register: replication_check
      delegate_to: "{{ groups['primary'][0] }}"
      failed_when: replication_check.stdout | int == 0
      tags: preflight
```

This causes the playbook to abort with an error if no replicas are streaming before changes begin.

### Step 3 - Always run with --check --diff before applying changes

Add a wrapper script that enforces check mode first:

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/ansible/voleon/scripts/safe-apply.sh
```

Add this content:

```bash
#!/bin/bash
set -euo pipefail

PLAYBOOK=$1
shift

echo "--- Running in CHECK mode first ---"
ansible-playbook "$PLAYBOOK" --check --diff "$@"

echo ""
read -p "Check mode passed. Apply changes? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo "--- Applying changes ---"
ansible-playbook "$PLAYBOOK" "$@"
```

```bash
chmod +x /opt/ansible/voleon/scripts/safe-apply.sh
```

Now use this script instead of calling ansible-playbook directly:

```bash
/opt/ansible/voleon/scripts/safe-apply.sh playbooks/postgres_config.yml -i inventory/production.ini
```

### Step 4 - Add a post-deployment validation task

At the end of the postgres configuration playbook, add a post-task that confirms replication is still healthy after changes:

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/ansible/voleon/playbooks/postgres_config.yml
```

Add at the bottom of the play:

```yaml
  post_tasks:
    - name: Verify replication is healthy after changes
      become: yes
      become_user: postgres
      command: >
        /usr/pgsql-17/bin/psql -d quantdb -tAc
        "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'"
      register: post_replication_check
      delegate_to: "{{ groups['primary'][0] }}"
      failed_when: post_replication_check.stdout | int == 0
      tags: postflight
```

If this fails, the playbook exits non-zero and your CI/CD system will alert.

### Step 5 - Implement Ansible drift detection

Create a read-only drift check playbook that can run on a schedule (e.g., every 15 minutes) to compare the running config against expected:

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/ansible/voleon/playbooks/drift_check.yml
```

Add this content:

```yaml
---
- name: Detect PostgreSQL configuration drift
  hosts: postgres_primary
  gather_facts: no
  tasks:
    - name: Check pg_hba.conf matches expected template
      become: yes
      become_user: postgres
      template:
        src: roles/postgres/templates/pg_hba.conf.j2
        dest: /var/lib/pgsql/17/data/pg_hba.conf
      check_mode: yes
      diff: yes
      register: hba_diff
      changed_when: false
      failed_when: hba_diff.diff is defined and hba_diff.diff | length > 0

    - name: Report drift status
      debug:
        msg: "pg_hba.conf is in sync - no drift detected"
      when: hba_diff.diff is not defined or hba_diff.diff | length == 0
```

Run this as a cron job:

```bash
crontab -e
```

Add:

```
*/15 * * * * /usr/bin/ansible-playbook /opt/ansible/voleon/playbooks/drift_check.yml >> /var/log/ansible-drift.log 2>&1
```

---

## Summary

### Root Cause

An Ansible playbook run used the wrong variable group. The `all.yml` group_vars file had `replication_cidr: "10.0.0.0/8"` (a leftover from a different environment). The production override in `production.yml` had the correct value `172.31.0.0/16`, but the playbook targeted the wrong inventory group, causing the production override to not be applied. The result was `pg_hba.conf` being written with a CIDR that did not match the replica's IP, causing the replication user's connection to be rejected.

### Resolution

1. Identified the drift by comparing the live `pg_hba.conf` to expected config
2. Traced the bug to `all.yml` having the wrong CIDR value
3. Fixed `pg_hba.conf` directly on the primary (one-line change)
4. Reloaded PostgreSQL config with `pg_reload_conf()` - no restart needed
5. Confirmed replication reconnected within 60 seconds via `pg_stat_replication`

### Prevention

- Fixed the incorrect variable in `all.yml` and committed to version control
- Added pre-flight replication health check to abort playbook if replication is already broken
- Added post-deployment validation to confirm replication is healthy after any config change
- Created `safe-apply.sh` wrapper that enforces `--check --diff` before any apply
- Added a cron-driven drift detection playbook that runs every 15 minutes and alerts on deviation
