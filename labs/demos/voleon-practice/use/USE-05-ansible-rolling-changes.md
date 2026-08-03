# USE Exercise 05: Ansible Rolling Configuration Changes

| | |
|---|---|
| **Time** | 45 minutes |
| **Server** | pg-ops (54.209.143.137), pg-primary (3.90.199.62), pg-replica (3.91.32.84) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice

- Running existing Ansible playbooks to check cluster status
- Writing a playbook that makes a rolling configuration change to PostgreSQL
- Using `serial: 1` to update one server at a time (replica first, then primary)
- Reloading PostgreSQL without restarting it (zero downtime)
- Gathering log files from multiple servers with one command
- Rolling back a configuration change using the same playbook pattern

---

## Exercise 1: Verify Your Starting Point

Before touching anything, confirm the cluster is healthy.

SSH into pg-ops. On **pg-ops**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

Confirm Ansible can reach all nodes. On **pg-ops**, as **ec2-user**:

```bash
ansible all -i ~/ansible/inventory/hosts.yml -m ping
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
```

If any node shows UNREACHABLE, stop and fix SSH connectivity before continuing.

---

## Exercise 2: Run the Cluster Status Playbook

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
ansible-playbook -i inventory/hosts.yml playbooks/check-pg-status.yml
```

Expected output (yours will differ):

```
PLAY [Check PostgreSQL status on all PG servers] *******************************

TASK [Check PostgreSQL service] ************************************************
ok: [pg-primary]
ok: [pg-replica]

TASK [Check replication lag] ***************************************************
ok: [pg-primary]
ok: [pg-replica]

PLAY RECAP *********************************************************************
pg-primary                 : ok=3    changed=0    unreachable=0    failed=0
pg-replica                 : ok=3    changed=0    unreachable=0    failed=0
```

Read through the output carefully. The play recap line at the bottom tells you whether anything failed. `failed=0` means you are safe to continue.

---

## Exercise 3: Check the Current work_mem Value

Before making a change, record what the current value is. This gives you a baseline to compare against after the change.

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i ~/ansible/inventory/hosts.yml \
  -m shell \
  -a "sudo -u postgres psql -d quantdb -c 'SHOW work_mem;'"
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 work_mem
----------
 4MB
(1 row)

pg-replica | CHANGED | rc=0 >>
 work_mem
----------
 4MB
(1 row)
```

Write down `4MB`. That is your rollback target.

---

## Exercise 4: Create the Rolling work_mem Playbook

You will write a playbook that:
- Updates `work_mem` in `postgresql.conf` using `lineinfile`
- Runs on replica first, then primary (one server at a time)
- Reloads PostgreSQL after each change (no restart needed)
- Includes a pre-check and post-check so you can confirm the change took effect

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/update-work-mem.yml
```

Paste in the following content exactly:

```yaml
---
- name: Update work_mem on PostgreSQL servers (replica first)
  hosts: pg_servers
  order: reverse_inventory
  serial: 1
  become: true

  vars:
    new_work_mem: "8MB"
    pg_conf: /var/lib/pgsql/17/data/postgresql.conf

  tasks:

    - name: Pre-check - show current work_mem value
      become_user: postgres
      shell: psql -d quantdb -c "SHOW work_mem;"
      register: before_value
      changed_when: false

    - name: Print current work_mem
      debug:
        msg: "{{ inventory_hostname }} current work_mem: {{ before_value.stdout }}"

    - name: Update work_mem in postgresql.conf
      lineinfile:
        path: "{{ pg_conf }}"
        regexp: "^#?work_mem\\s*="
        line: "work_mem = {{ new_work_mem }}"
        backup: yes

    - name: Reload PostgreSQL to apply the change
      service:
        name: postgresql-17
        state: reloaded

    - name: Wait 3 seconds for reload to complete
      pause:
        seconds: 3

    - name: Post-check - show new work_mem value
      become_user: postgres
      shell: psql -d quantdb -c "SHOW work_mem;"
      register: after_value
      changed_when: false

    - name: Print new work_mem
      debug:
        msg: "{{ inventory_hostname }} new work_mem: {{ after_value.stdout }}"
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

---

## Exercise 5: Verify Your Inventory Order

The `order: reverse_inventory` directive tells Ansible to run in reverse order of how hosts appear in the inventory. This only works if your inventory lists `pg-primary` before `pg-replica`.

Check your inventory file. On **pg-ops**, as **ec2-user**:

```bash
cat ~/ansible/inventory/hosts.yml
```

Confirm that `pg-primary` is listed before `pg-replica` under the `pg_servers` group. If the order is reversed in your file, change `reverse_inventory` to `inventory` in the playbook so replica still runs first.

---

## Exercise 6: Run the Rolling Change

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i ~/ansible/inventory/hosts.yml \
  ~/ansible/playbooks/update-work-mem.yml
```

Watch the output carefully. Because `serial: 1` is set, Ansible finishes the entire play on one host before moving to the next. You should see pg-replica complete all tasks before pg-primary starts.

Expected output (yours will differ):

```
PLAY [Update work_mem on PostgreSQL servers (replica first)] *******************

TASK [Pre-check - show current work_mem value] *********************************
ok: [pg-replica]

TASK [Print current work_mem] **************************************************
ok: [pg-replica] => {
    "msg": "pg-replica current work_mem:  work_mem \n----------\n 4MB\n(1 row)"
}

TASK [Update work_mem in postgresql.conf] **************************************
changed: [pg-replica]

TASK [Reload PostgreSQL to apply the change] ***********************************
changed: [pg-replica]
...
TASK [Post-check - show new work_mem value] ************************************
ok: [pg-replica] => {
    "msg": "pg-replica new work_mem:  work_mem \n----------\n 8MB\n(1 row)"
}
...
PLAY RECAP *********************************************************************
pg-replica                 : ok=7    changed=2    unreachable=0    failed=0
pg-primary                 : ok=7    changed=2    unreachable=0    failed=0
```

Both pre-check and post-check messages confirm the value changed from 4MB to 8MB.

---

## Exercise 7: Run pg-config-check.yml to Confirm Propagation

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i ~/ansible/inventory/hosts.yml \
  ~/ansible/playbooks/pg-config-check.yml
```

Look for `work_mem` in the output. Both servers should now report `8MB`. If either still shows `4MB`, the reload did not apply - check the service status on that server.

---

## Exercise 8: Ad-hoc Commands for Quick Checks

You do not always need a full playbook. Ansible ad-hoc commands let you run a single module against any group of hosts.

Check disk space on all nodes at once. On **pg-ops**, as **ec2-user**:

```bash
ansible all -i ~/ansible/inventory/hosts.yml \
  -m shell \
  -a "df -h /var/lib/pgsql"
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G  4.2G   16G  21% /

pg-replica | CHANGED | rc=0 >>
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G  3.9G   16G  20% /
```

Check uptime on all nodes. On **pg-ops**, as **ec2-user**:

```bash
ansible all -i ~/ansible/inventory/hosts.yml -m shell -a "uptime"
```

Check PostgreSQL process count on all PG servers. On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i ~/ansible/inventory/hosts.yml \
  -m shell \
  -a "pgrep -c postgres"
```

---

## Exercise 9: Gather Log Files from All PG Servers

Ansible can pull files from remote hosts to your local ops server using the `fetch` module.

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i ~/ansible/inventory/hosts.yml \
  -m shell \
  -a "ls -t /var/lib/pgsql/17/data/log/ | head -1" \
  --become
```

This shows you the most recent log file name on each server. Now fetch them to pg-ops. On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i ~/ansible/inventory/hosts.yml \
  -m fetch \
  -a "src=/var/lib/pgsql/17/data/log/postgresql-$(date +%Y-%m-%d).log dest=/tmp/pg-logs/ flat=no" \
  --become
```

List what was pulled. On **pg-ops**, as **ec2-user**:

```bash
find /tmp/pg-logs/ -name "*.log"
```

Expected output (yours will differ):

```
/tmp/pg-logs/pg-primary/var/lib/pgsql/17/data/log/postgresql-2026-06-15.log
/tmp/pg-logs/pg-replica/var/lib/pgsql/17/data/log/postgresql-2026-06-15.log
```

Each file is stored under a subdirectory named after the host, so you always know which log came from which server.

---

## Exercise 10: Rollback - Revert work_mem to 4MB

Rolling back is the same playbook with a different variable value. Ansible's `lineinfile` will find the line you changed and overwrite it again.

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i ~/ansible/inventory/hosts.yml \
  ~/ansible/playbooks/update-work-mem.yml \
  --extra-vars "new_work_mem=4MB"
```

The `--extra-vars` flag overrides the `new_work_mem` variable defined inside the playbook without editing the file. Watch the post-check output and confirm both servers report `4MB` again.

Verify the rollback succeeded. On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i ~/ansible/inventory/hosts.yml \
  -m shell \
  -a "sudo -u postgres psql -d quantdb -c 'SHOW work_mem;'"
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 work_mem
----------
 4MB
(1 row)

pg-replica | CHANGED | rc=0 >>
 work_mem
----------
 4MB
(1 row)
```

---

## Summary

In this exercise you:
- Confirmed cluster health using an existing playbook before making changes
- Recorded the baseline value of a configuration parameter
- Wrote a playbook using `lineinfile` to update `postgresql.conf`
- Used `serial: 1` with `order: reverse_inventory` to update replica before primary
- Reloaded PostgreSQL (not restarted) so connections were not dropped
- Used ad-hoc Ansible commands to check disk and process counts across nodes
- Pulled log files from multiple servers to a central location with one command
- Rolled back the change using `--extra-vars` without editing the playbook

The key skill here is the pattern: pre-check, change, reload, post-check, rollback-ready. Any safe DBA change follows this same structure.
