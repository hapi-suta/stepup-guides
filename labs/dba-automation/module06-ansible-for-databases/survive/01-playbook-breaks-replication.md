# SURVIVE 01: The Playbook That Broke Replication

**Module 06: Ansible for Database Configuration**
**Difficulty: Medium**
**Estimated Time: 30-45 minutes**

---

## The Scenario

It is 3:00 PM on a Tuesday. You ran an Ansible playbook to update `max_connections` from 200 to 500 across your PostgreSQL cluster. The playbook updated `postgresql.conf` and restarted PostgreSQL on the primary - but it did NOT update the standby servers.

After the restart, the primary comes back up with `max_connections = 500`. But the standbys still have `max_connections = 200`. When the standbys try to reconnect, replication breaks because the standby's `max_connections` must be greater than or equal to the primary's.

The error in the standby PostgreSQL log:

```
FATAL:  hot standby is not possible because max_connections = 200 is a lower setting than on the primary server (max_connections = 500)
```

Both standbys are down. The primary is running but has no replicas. You have no HA protection.

---

## Setup - Reproduce the Problem

For this exercise, we will simulate the scenario locally.

**On your Mac terminal:**

Create the broken playbook that caused the problem:

```bash
mkdir -p ~/dba-labs/survive-ansible
cd ~/dba-labs/survive-ansible
```

```bash
vi broken-playbook.yml
```

```yaml
---
# THE BROKEN PLAYBOOK - only updates the primary
- name: Update max_connections
  hosts: primary
  become: true

  tasks:
    - name: Update max_connections in postgresql.conf
      lineinfile:
        path: /var/lib/pgsql/16/data/postgresql.conf
        regexp: "^max_connections"
        line: "max_connections = 500"

    - name: Restart PostgreSQL
      service:
        name: postgresql-16
        state: restarted
```

The problem is obvious in hindsight: `hosts: primary` only targets the primary server. The standbys are not updated.

---

## Your Mission

1. **Diagnose the problem:** Identify what went wrong and why replication broke.
2. **Fix the immediate issue:** Get the standbys back online.
3. **Fix the playbook:** Rewrite it so this can never happen again.
4. **Add verification:** Ensure the playbook validates the cluster state after changes.

---

## Part 1: Diagnose

### Check the Standby Logs

On a real server, you would check:

```bash
# On the standby server
sudo tail -50 /var/lib/pgsql/16/data/log/postgresql-*.log
```

You would see:
```
FATAL:  hot standby is not possible because max_connections = 200 is a lower setting than on the primary server (max_connections = 500)
LOG:  startup process (PID 12345) exited with exit code 1
LOG:  aborting startup due to startup process failure
```

### Check Replication on the Primary

```sql
-- On the primary
SELECT client_addr, state, sent_lsn, replay_lsn
FROM pg_stat_replication;
-- Returns 0 rows - no standbys connected
```

### Root Cause

The playbook only targeted `hosts: primary`. When `max_connections` was increased on the primary and PostgreSQL restarted, the standbys (still at 200) could not start in hot standby mode because PostgreSQL requires these parameters to be >= the primary's value:

- `max_connections`
- `max_prepared_transactions`
- `max_locks_per_transaction`
- `max_wal_senders`
- `max_worker_processes`

---

## Part 2: Fix the Immediate Issue

### Step 1: Update the Standby Configuration

On each standby server, update `max_connections`:

```bash
# On standby 1
sudo su - postgres
vi /var/lib/pgsql/16/data/postgresql.conf
```

Change `max_connections = 200` to `max_connections = 500`. Save and exit.

### Step 2: Start the Standby

```bash
# As ec2-user on the standby
sudo systemctl start postgresql-16
```

### Step 3: Verify Replication

```bash
# On the standby, as postgres
psql -c "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();"
```

Expected output:
```
 pg_is_in_recovery | pg_last_wal_replay_lsn
-------------------+------------------------
 t                 | 0/5000148
```

```sql
-- On the primary
SELECT client_addr, state FROM pg_stat_replication;
```

Expected output:
```
 client_addr  |   state
--------------+-----------
 10.0.1.11    | streaming
 10.0.1.12    | streaming
```

---

## Part 3: Fix the Playbook

The corrected playbook must:

1. Update ALL PostgreSQL servers (not just the primary)
2. Update standbys FIRST, then the primary
3. Restart standbys first, verify they come back, then restart the primary
4. Verify replication after all changes

```bash
vi fixed-playbook.yml
```

```yaml
---
# FIXED PLAYBOOK: Update max_connections across the cluster
# Strategy: update standbys first, then primary

# Play 1: Update standbys first
- name: Update max_connections on standbys
  hosts: standbys
  become: true
  serial: 1                    # One standby at a time

  vars:
    pg_max_connections: 500
    pg_version: 16
    pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
    pg_service: "postgresql-{{ pg_version }}"

  tasks:
    - name: Update max_connections in postgresql.conf
      lineinfile:
        path: "{{ pg_data_dir }}/postgresql.conf"
        regexp: "^max_connections"
        line: "max_connections = {{ pg_max_connections }}"
        backup: true
      register: config_changed

    - name: Restart PostgreSQL on standby
      service:
        name: "{{ pg_service }}"
        state: restarted
      when: config_changed.changed

    - name: Wait for standby to be ready
      command: "/usr/pgsql-{{ pg_version }}/bin/pg_isready -p 5432"
      register: pg_ready
      until: pg_ready.rc == 0
      retries: 30
      delay: 2

    - name: Verify standby is in recovery
      become_user: postgres
      command: >
        psql -tAc "SELECT pg_is_in_recovery();"
      register: recovery_check
      failed_when: "'t' not in recovery_check.stdout"

# Play 2: Update primary
- name: Update max_connections on primary
  hosts: primary
  become: true

  vars:
    pg_max_connections: 500
    pg_version: 16
    pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
    pg_service: "postgresql-{{ pg_version }}"

  tasks:
    - name: Update max_connections in postgresql.conf
      lineinfile:
        path: "{{ pg_data_dir }}/postgresql.conf"
        regexp: "^max_connections"
        line: "max_connections = {{ pg_max_connections }}"
        backup: true
      register: config_changed

    - name: Restart PostgreSQL on primary
      service:
        name: "{{ pg_service }}"
        state: restarted
      when: config_changed.changed

    - name: Wait for primary to be ready
      command: "/usr/pgsql-{{ pg_version }}/bin/pg_isready -p 5432"
      register: pg_ready
      until: pg_ready.rc == 0
      retries: 30
      delay: 2

# Play 3: Verify entire cluster
- name: Verify cluster health after change
  hosts: primary
  become: true
  become_user: postgres

  vars:
    pg_max_connections: 500
    expected_standbys: 2

  tasks:
    - name: Verify max_connections on primary
      command: >
        psql -tAc "SHOW max_connections;"
      register: primary_max_conn
      failed_when: primary_max_conn.stdout | trim != pg_max_connections | string

    - name: Wait for standbys to reconnect
      command: >
        psql -tAc "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';"
      register: repl_count
      until: repl_count.stdout | trim | int >= expected_standbys
      retries: 30
      delay: 5
      failed_when: repl_count.stdout | trim | int < expected_standbys

    - name: Display replication status
      command: >
        psql -c "SELECT client_addr, state, sent_lsn, replay_lsn,
                        pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
                 FROM pg_stat_replication;"
      register: repl_status
      changed_when: false

    - name: Show final status
      debug:
        msg: |
          Cluster update complete.
          max_connections = {{ pg_max_connections }}
          Standbys streaming: {{ repl_count.stdout | trim }}
          {{ repl_status.stdout }}
```

---

## Part 4: Prevention

### Checklist for Future Cluster-Wide Changes

- [ ] **Does the playbook target ALL PostgreSQL servers?** Check `hosts:` - it should be `postgresql` (the parent group), not `primary`.
- [ ] **Are standbys updated BEFORE the primary?** For parameters that must be >= primary, update standbys first.
- [ ] **Does the playbook use `serial: 1`?** Never restart all nodes simultaneously.
- [ ] **Is there a verification play at the end?** Check that replication is streaming after changes.
- [ ] **Does the playbook use `backup: true`?** Always keep a backup of the config before overwriting.

### Template Approach (Better Than lineinfile)

The real fix is to use a template instead of `lineinfile`. Templates ensure the ENTIRE config file is consistent:

```yaml
- name: Deploy postgresql.conf from template
  template:
    src: templates/postgresql.conf.j2
    dest: "{{ pg_data_dir }}/postgresql.conf"
    backup: true
  notify: restart postgresql
```

With a template, you define `max_connections` as a variable. Changing the variable automatically updates ALL servers because the template is deployed to all hosts.

---

## Validation Checklist

- [ ] Both standbys are online and in recovery mode
- [ ] Replication is streaming on both standbys
- [ ] `max_connections = 500` on all three nodes
- [ ] Replication lag is under 1 second
- [ ] Playbook has been fixed to target all PostgreSQL hosts
- [ ] Playbook updates standbys before the primary
- [ ] Playbook includes verification tasks

---

## Lessons Learned

1. **Always target the cluster, not a single node.** Use `hosts: postgresql` (group of groups) instead of `hosts: primary`.
2. **Update standbys first for parameters with >= requirements.** `max_connections`, `max_prepared_transactions`, `max_locks_per_transaction`, `max_wal_senders`, `max_worker_processes` must all be >= primary on standbys.
3. **Use templates instead of lineinfile for config management.** Templates ensure consistency; lineinfile is fragile.
4. **Always verify after changes.** Include a play that checks replication status.
5. **Use serial: 1 for rolling restarts.** Never restart all PostgreSQL nodes simultaneously.
