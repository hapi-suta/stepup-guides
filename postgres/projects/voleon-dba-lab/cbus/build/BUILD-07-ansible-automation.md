# Build Guide 07: Ansible Automation for PostgreSQL Operations

| | |
|---|---|
| **Time** | 60 minutes |
| **Server** | pg-ops (54.209.143.137) - Ansible control node; pg-primary (3.90.199.62); pg-replica (3.91.32.84); pg-container (34.235.89.112) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- Why Ansible is a good fit for database operations teams
- How to install Ansible and verify it is ready to use
- How to set up SSH key access so Ansible can reach all managed nodes
- How to write an inventory file that groups your PostgreSQL servers
- How to write and run playbooks that gather PostgreSQL status, check config drift, and perform rolling reloads
- How to organize reusable automation with a basic role structure

## Prerequisites

- You have completed BUILD-01 through BUILD-06
- PostgreSQL 17 is running on pg-primary and pg-replica
- You can SSH from your local machine to all four servers using `~/.ssh/id_ed25519`
- Private IPs: pg-primary=172.31.19.86, pg-replica=172.31.22.69, pg-container=172.31.21.45, pg-ops=172.31.26.19

---

## Step 1: Understand Why Voleon Uses Ansible for Database Work

At a firm like Voleon, Ansible handles the operational side of database management - not just initial deployment. Typical uses include:

- Pushing `postgresql.conf` changes across a fleet of servers consistently
- Detecting config drift (when a setting on one server no longer matches the intended value)
- Running rolling restarts or reloads that touch the replica before the primary
- Executing the same diagnostic queries against 10 or 100 databases and collecting the results

Ansible is agentless - it uses SSH to connect to managed nodes and runs tasks remotely. This matters for database servers because you do not want to install extra software (agents, daemons) on a system where you want minimal attack surface and minimal resource competition with PostgreSQL.

---

## Step 2: Copy Your SSH Key to pg-ops

Ansible on pg-ops will use SSH to reach pg-primary, pg-replica, and pg-container. The key needs to exist on pg-ops itself. Right now it only exists on your local machine.

On your **local machine**, as your local user:

```bash
scp -i ~/.ssh/id_ed25519 ~/.ssh/id_ed25519 ec2-user@54.209.143.137:~/.ssh/id_ed25519
```

`scp` copies files over SSH. The `-i ~/.ssh/id_ed25519` flag tells scp which key to use for the connection to pg-ops. The last argument is the destination path on pg-ops.

Now SSH into pg-ops and set the correct permissions on the key file.

On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

On **pg-ops**, as **ec2-user**:

```bash
chmod 600 ~/.ssh/id_ed25519
```

`chmod 600` sets the file so only the owner can read and write it. SSH refuses to use a private key file that is readable by others.

Verify the file is there:

```bash
ls -la ~/.ssh/id_ed25519
```

Expected output (yours will differ):

```
-rw------- 1 ec2-user ec2-user 411 Jun 15 10:02 /home/ec2-user/.ssh/id_ed25519
```

---

## Step 3: Install Ansible on pg-ops

Still on **pg-ops**, as **ec2-user**:

```bash
sudo dnf install -y ansible-core
```

`dnf install` is the package manager for CentOS Stream 9. The `-y` flag answers "yes" automatically to all prompts. `ansible-core` is the base Ansible package.

Expected output (yours will differ):

```
Updating Subscription Management repositories.
Last metadata expiration check: ...
Dependencies resolved.
...
Installed:
  ansible-core-2.15.x ...
Complete!
```

Confirm the installation worked:

```bash
ansible --version
```

Expected output (yours will differ):

```
ansible [core 2.15.x]
  config file = None
  configured module search path = ['/home/ec2-user/.ansible/plugins/modules', ...]
  ansible python module location = /usr/lib/python3.x/site-packages/ansible
  ansible collection location = /home/ec2-user/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.x.x ...
```

---

## Step 4: Test SSH Connectivity to Managed Nodes

Before writing any Ansible files, confirm that pg-ops can reach each managed node over SSH using the private key. You are connecting over private IPs because pg-ops and the other nodes are in the same VPC.

On **pg-ops**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@172.31.19.86 hostname
```

This SSHes into pg-primary and runs the `hostname` command, then disconnects. You are verifying the key works and the host is reachable.

Expected output (yours will differ):

```
pg-primary
```

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@172.31.22.69 hostname
```

Expected output (yours will differ):

```
pg-replica
```

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@172.31.21.45 hostname
```

Expected output (yours will differ):

```
pg-container
```

If any of these fail, stop here and troubleshoot SSH before continuing.

---

## Step 5: Create the Ansible Project Directory Structure

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/ansible/{inventory,playbooks,roles}
```

`mkdir -p` creates a directory and any parent directories needed. The `{inventory,playbooks,roles}` syntax is brace expansion - it creates three subdirectories in one command.

Verify the structure:

```bash
ls ~/ansible/
```

Expected output (yours will differ):

```
inventory  playbooks  roles
```

---

## Step 6: Create the Inventory File

The inventory file tells Ansible which servers exist and how to group them. Groups let you run a playbook against "all PostgreSQL servers" or "only the replica" without editing the playbook itself.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/inventory/hosts.yml
```

Enter the following content exactly:

```yaml
all:
  vars:
    ansible_user: ec2-user
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  children:
    pg_primary:
      hosts:
        pg-primary:
          ansible_host: 172.31.19.86
    pg_replica:
      hosts:
        pg-replica:
          ansible_host: 172.31.22.69
    pg_container:
      hosts:
        pg-container:
          ansible_host: 172.31.21.45
    pg_servers:
      children:
        pg_primary:
        pg_replica:
    all_db:
      children:
        pg_servers:
        pg_container:
```

Key points:
- `vars` under `all` apply to every host in the inventory
- `ansible_ssh_common_args: '-o StrictHostKeyChecking=no'` prevents Ansible from stopping when it sees a host for the first time (no known_hosts entry yet)
- `pg_servers` groups pg-primary and pg-replica together - this is your "bare-metal PostgreSQL" group
- `all_db` groups everything including the container node
- `children` nests groups inside other groups

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

---

## Step 7: Create ansible.cfg

The `ansible.cfg` file sets defaults so you do not have to pass flags on every command.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/ansible.cfg
```

Enter the following:

```ini
[defaults]
inventory = inventory/hosts.yml
remote_user = ec2-user
private_key_file = ~/.ssh/id_ed25519
host_key_checking = False
```

- `inventory` points to your hosts file so you do not need `-i` on every command
- `remote_user` is the OS user Ansible logs in as on managed nodes
- `private_key_file` is the SSH key to use
- `host_key_checking = False` tells Ansible not to fail when a host is not in known_hosts

Save and exit vi.

---

## Step 8: Test Ansible Connectivity

Now run the built-in `ping` module against all hosts. This is not an ICMP ping - it is an Ansible test that SSHes in, runs a small Python snippet, and confirms Ansible can fully control the node.

On **pg-ops**, as **ec2-user**, change into the ansible directory first:

```bash
cd ~/ansible
```

```bash
ansible all -m ping
```

`-m ping` tells Ansible to use the ping module. Because `ansible.cfg` is in the current directory, Ansible picks it up automatically.

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
```

All three nodes should show `SUCCESS`. If any show `UNREACHABLE`, re-check the private IP in the inventory and re-test the manual SSH from Step 4.

---

## Step 9: Create the PostgreSQL Status Playbook

This playbook SSHes into pg-primary and pg-replica, runs a few `psql` commands as the postgres OS user, and prints the results. It is useful as a quick fleet health check.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/check-pg-status.yml
```

Enter the following:

```yaml
---
- name: Check PostgreSQL status on all pg_servers
  hosts: pg_servers
  become: true
  become_user: postgres

  tasks:
    - name: Get PostgreSQL version
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT version();" -t -A
      register: pg_version

    - name: Print PostgreSQL version
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ pg_version.stdout }}"

    - name: Get active connection count
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" -t -A
      register: conn_count

    - name: Print active connection count
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} active connections: {{ conn_count.stdout }}"

    - name: Get database sizes
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;" -t -A
      register: db_sizes

    - name: Print database sizes
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} database sizes:\n{{ db_sizes.stdout }}"

    - name: Get server uptime from PostgreSQL
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT now() - pg_postmaster_start_time() AS uptime;" -t -A
      register: pg_uptime

    - name: Print PostgreSQL uptime
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} PostgreSQL uptime: {{ pg_uptime.stdout }}"
```

Key points:
- `hosts: pg_servers` runs this play only on the `pg_servers` group (pg-primary and pg-replica)
- `become: true` / `become_user: postgres` tells Ansible to run tasks as the postgres OS user, which is how you avoid passing passwords to psql
- `register:` saves command output into a variable
- `ansible.builtin.debug` prints the variable

Save and exit vi.

---

## Step 10: Run the PostgreSQL Status Playbook

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/check-pg-status.yml
```

`ansible-playbook` is the command that executes a playbook file.

Expected output (yours will differ):

```
PLAY [Check PostgreSQL status on all pg_servers] *****************************

TASK [Get PostgreSQL version] ************************************************
changed: [pg-primary]
changed: [pg-replica]

TASK [Print PostgreSQL version] **********************************************
ok: [pg-primary] => {
    "msg": "pg-primary: PostgreSQL 17.x on x86_64-pc-linux-gnu, ..."
}
ok: [pg-replica] => {
    "msg": "pg-replica: PostgreSQL 17.x on x86_64-pc-linux-gnu, ..."
}
...
PLAY RECAP *******************************************************************
pg-primary     : ok=8    changed=4    unreachable=0    failed=0    skipped=0
pg-replica     : ok=8    changed=4    unreachable=0    failed=0    skipped=0
```

The `PLAY RECAP` at the end shows a summary. `failed=0` means everything worked.

---

## Step 11: Create the Config Drift Check Playbook

This playbook checks that critical PostgreSQL parameters match expected values. If a parameter has drifted (someone changed it manually without going through Ansible), this playbook will flag it.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/pg-config-check.yml
```

Enter the following:

```yaml
---
- name: Check PostgreSQL configuration for drift
  hosts: pg_servers
  become: true
  become_user: postgres

  vars:
    expected_config:
      max_connections: "200"
      wal_level: "replica"
      max_wal_senders: "10"
      hot_standby: "on"

  tasks:
    - name: Get current shared_buffers
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SHOW shared_buffers;" -t -A
      register: shared_buffers_val

    - name: Report shared_buffers
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} shared_buffers = {{ shared_buffers_val.stdout }}"

    - name: Check each expected parameter
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SHOW {{ item.key }};" -t -A
      register: param_result
      loop: "{{ expected_config | dict2items }}"

    - name: Report parameter check results
      ansible.builtin.debug:
        msg: >
          {{ inventory_hostname }} {{ item.item.key }}:
          current={{ item.stdout }}
          expected={{ item.item.value }}
          match={{ item.stdout == item.item.value }}
      loop: "{{ param_result.results }}"
```

- `vars:` defines a dictionary of parameters and their expected values
- `loop:` iterates the task once per item in the list
- `dict2items` converts a YAML dictionary into a list of `{key, value}` pairs so `loop` can iterate it
- The final debug task compares the live value to the expected value and prints `match=True` or `match=False`

Save and exit vi.

Run it:

```bash
ansible-playbook playbooks/pg-config-check.yml
```

Expected output (yours will differ):

```
TASK [Report parameter check results] ****************************************
ok: [pg-primary] => (item={'item': {'key': 'max_connections', 'value': '200'}, 'stdout': '200', ...}) => {
    "msg": "pg-primary max_connections: current=200 expected=200 match=True\n"
}
...
PLAY RECAP *******************************************************************
pg-primary     : ok=4    changed=2    unreachable=0    failed=0
pg-replica     : ok=4    changed=2    unreachable=0    failed=0
```

---

## Step 12: Create the Rolling Reload Playbook

A rolling reload applies `postgresql.conf` changes without a full restart, hitting the replica before the primary. This is the safe order - replica downtime affects only reads, primary downtime affects all writes.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/rolling-reload.yml
```

Enter the following:

```yaml
---
- name: Pre-reload health check
  hosts: pg_servers
  serial: 1
  become: true
  become_user: postgres

  tasks:
    - name: Verify PostgreSQL is accepting connections before reload
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT 1;" -t -A
      register: pre_check

    - name: Fail if pre-check did not return 1
      ansible.builtin.fail:
        msg: "Pre-reload health check failed on {{ inventory_hostname }}"
      when: pre_check.stdout != "1"

- name: Rolling reload - replica first, then primary
  hosts: pg_replica,pg_primary
  serial: 1
  order: inventory

  tasks:
    - name: Reload PostgreSQL configuration
      ansible.builtin.shell: |
        sudo /usr/bin/systemctl reload postgresql-17
      become: true

    - name: Wait 5 seconds for reload to settle
      ansible.builtin.pause:
        seconds: 5

    - name: Post-reload health check
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT 1;" -t -A
      become: true
      become_user: postgres
      register: post_check

    - name: Fail if post-reload health check failed
      ansible.builtin.fail:
        msg: "Post-reload health check failed on {{ inventory_hostname }}"
      when: post_check.stdout != "1"

    - name: Report reload complete
      ansible.builtin.debug:
        msg: "Reload complete on {{ inventory_hostname }} - PostgreSQL is healthy"
```

Key points:
- `serial: 1` means Ansible processes one host at a time (not all at once). Without this, Ansible would reload all servers simultaneously.
- `hosts: pg_replica,pg_primary` - listing replica first means Ansible processes it first
- The `fail` module stops the playbook immediately if a health check fails, preventing the reload from proceeding to the next node

Save and exit vi.

Run the rolling reload:

```bash
ansible-playbook playbooks/rolling-reload.yml
```

Expected output (yours will differ):

```
PLAY [Pre-reload health check] ***********************************************
TASK [Verify PostgreSQL is accepting connections before reload] ***************
changed: [pg-replica]
changed: [pg-primary]

PLAY [Rolling reload - replica first, then primary] **************************
TASK [Reload PostgreSQL configuration] ***************************************
changed: [pg-replica]

TASK [Post-reload health check] **********************************************
changed: [pg-replica]

TASK [Report reload complete] ************************************************
ok: [pg-replica] => {
    "msg": "Reload complete on pg-replica - PostgreSQL is healthy"
}

TASK [Reload PostgreSQL configuration] ***************************************
changed: [pg-primary]
...
PLAY RECAP *******************************************************************
pg-primary     : ok=4    changed=2    unreachable=0    failed=0
pg-replica     : ok=4    changed=2    unreachable=0    failed=0
```

Note the order in the output: pg-replica is fully processed before pg-primary starts.

---

## Step 13: Create a Basic Role Structure

Roles are a way to organize related tasks, variables, and templates into a reusable unit. Instead of one large playbook, you have a `postgresql` role that any playbook can call.

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/ansible/roles/postgresql/{tasks,vars,handlers,templates}
```

Create the main tasks file for the role:

```bash
vi ~/ansible/roles/postgresql/tasks/main.yml
```

Enter the following:

```yaml
---
- name: Ensure PostgreSQL is running
  ansible.builtin.shell: |
    sudo /usr/bin/systemctl is-active postgresql-17
  register: pg_running
  changed_when: false

- name: Report PostgreSQL service status
  ansible.builtin.debug:
    msg: "{{ inventory_hostname }}: postgresql-17 is {{ pg_running.stdout }}"

- name: Get replication status (primary only)
  ansible.builtin.shell: |
    /usr/pgsql-17/bin/psql -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;" -t -A
  become: true
  become_user: postgres
  register: repl_status
  when: "'pg_primary' in group_names"

- name: Report replication status
  ansible.builtin.debug:
    msg: "Replication status on {{ inventory_hostname }}:\n{{ repl_status.stdout }}"
  when: "'pg_primary' in group_names"
```

Create the vars file:

```bash
vi ~/ansible/roles/postgresql/vars/main.yml
```

Enter the following:

```yaml
---
pg_version: "17"
pg_bin_dir: "/usr/pgsql-17/bin"
pg_service_name: "postgresql-17"
pg_data_dir: "/opt/pgsql/data"
```

Create a simple playbook that calls the role:

```bash
vi ~/ansible/playbooks/use-pg-role.yml
```

Enter the following:

```yaml
---
- name: Run postgresql role on all pg_servers
  hosts: pg_servers
  become: true

  roles:
    - postgresql
```

Run the role-based playbook:

```bash
ansible-playbook playbooks/use-pg-role.yml
```

Expected output (yours will differ):

```
PLAY [Run postgresql role on all pg_servers] *********************************
TASK [postgresql : Ensure PostgreSQL is running] *****************************
ok: [pg-primary]
ok: [pg-replica]
...
PLAY RECAP *******************************************************************
pg-primary     : ok=4    changed=0    unreachable=0    failed=0
pg-replica     : ok=4    changed=0    unreachable=0    failed=0
```

---

## Summary

You have:

- Installed Ansible on pg-ops and configured it as the control node
- Set up SSH key access so Ansible can reach all managed nodes over private IPs
- Written an inventory file that logically groups pg-primary, pg-replica, and pg-container
- Created a status-check playbook that collects PostgreSQL health data across the fleet
- Created a config drift detection playbook that compares live settings to expected values
- Created a rolling reload playbook that processes replica before primary, with health checks at every step
- Organized reusable logic into a basic Ansible role

Your final directory structure:

```
~/ansible/
  ansible.cfg
  inventory/
    hosts.yml
  playbooks/
    check-pg-status.yml
    pg-config-check.yml
    rolling-reload.yml
    use-pg-role.yml
  roles/
    postgresql/
      tasks/main.yml
      vars/main.yml
      handlers/
      templates/
```

Continue to BUILD-08 to set up Prometheus and Grafana monitoring on this environment.
