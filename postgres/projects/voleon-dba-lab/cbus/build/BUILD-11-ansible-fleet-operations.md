# Build Guide 11: Ansible Fleet Operations for PostgreSQL

| | |
|---|---|
| **Time** | 90 minutes |
| **Servers** | pg-ops (34.228.32.17) - Ansible control node; pg-primary (100.26.54.122); pg-replica (54.144.241.128); pg-container (34.228.73.232) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Mark Selby - Senior Systems Infrastructure Engineer, The Voleon Group |

## Why This Matters

At The Voleon Group, the infrastructure team manages dozens of PostgreSQL servers across multiple environments. When Mark Selby asks about automation and configuration management, he wants to know whether you can push a `postgresql.conf` change to 50 servers safely, detect when someone hand-edits a config on one server, and handle emergencies like a failover without logging into each box manually.

BUILD-07 introduced Ansible basics - inventory, ad-hoc commands, and simple playbooks. This guide takes you to production-grade patterns: Jinja2 templates, group variables, rolling deployments, drift detection, emergency playbooks, and secrets management. Everything runs on your existing lab servers with the Ansible setup already in place on pg-ops.

## What You'll Learn

- How to use group variables and host variables to manage different configs for primary vs replica
- How to write Jinja2 templates for `postgresql.conf` and `pg_hba.conf`
- How to deploy config changes with rolling updates (replica first, primary last)
- How to detect and auto-remediate configuration drift across a fleet
- How to write emergency playbooks for failover, session cleanup, and config rollback
- How to manage database secrets with Ansible Vault

## Prerequisites

- You have completed BUILD-07 (Ansible Automation)
- Ansible is installed on pg-ops and can reach all managed nodes
- PostgreSQL 17 is running on pg-primary and pg-replica
- You can SSH from your local machine to pg-ops using `~/.ssh/id_ed25519`
- The `~/ansible/` directory on pg-ops has inventory, playbooks, and roles from BUILD-07

---

## Section 1: Production Ansible Patterns for DBAs

Before writing any code, you need to understand three concepts that separate "Ansible for labs" from "Ansible for production."

### Idempotency

An idempotent playbook produces the same result whether you run it once or twenty times. If `shared_buffers` is already set to `256MB`, the playbook should not change it again and should not reload PostgreSQL. This matters because unnecessary reloads disrupt connection pools and running queries.

Ansible modules like `ansible.builtin.template` are idempotent by default - they compare the file on disk to the rendered template and only write if something changed. When you use `ansible.builtin.shell` to run `ALTER SYSTEM`, you lose that automatic idempotency and must add your own checks.

### Rolling Changes

Never push a config change to all PostgreSQL servers at once. The safe order is:

1. Update the replica first
2. Verify it is healthy and replication is caught up
3. Then update the primary
4. Verify the primary is healthy

If the change breaks something, you find out on the replica - where the blast radius is limited to read queries - before it touches the primary that handles all writes.

### Fleet Consistency

When you manage 50+ servers, manual SSH becomes impossible. You need a single source of truth (Ansible variables) and a way to verify every server matches it (drift detection). The combination of templates, group variables, and drift-check playbooks gives you that.

---

## Section 2: Advanced Inventory with Group Variables

In BUILD-07, all variables lived inside the inventory file or inside individual playbooks. In production, you separate variables by group and by host. This lets you define settings that differ between primary and replica without duplicating playbooks.

### Create Group Variables

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/ansible/group_vars
```

`mkdir -p` creates the directory if it does not already exist.

Now create variables for the primary group.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/group_vars/pg_primary.yml
```

Enter the following:

```yaml
---
pg_role: primary
pg_shared_buffers: "256MB"
pg_work_mem: "16MB"
pg_max_connections: 200
pg_wal_level: "replica"
pg_max_wal_senders: 10
pg_max_replication_slots: 10
pg_hot_standby: "on"
pg_archive_mode: "on"
pg_archive_command: "/bin/true"
pg_hba_replication_hosts:
  - "172.31.22.69/32"
pg_hba_app_hosts:
  - "172.31.0.0/16"
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

Now create variables for the replica group.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/group_vars/pg_replica.yml
```

Enter the following:

```yaml
---
pg_role: replica
pg_shared_buffers: "256MB"
pg_work_mem: "16MB"
pg_max_connections: 200
pg_wal_level: "replica"
pg_max_wal_senders: 0
pg_max_replication_slots: 0
pg_hot_standby: "on"
pg_archive_mode: "off"
pg_archive_command: ""
pg_hba_replication_hosts: []
pg_hba_app_hosts:
  - "172.31.0.0/16"
```

The key differences: the replica has `max_wal_senders: 0` (it has no downstream replicas), `archive_mode: off` (only the primary archives WAL), and an empty `pg_hba_replication_hosts` list (no one replicates from the replica).

Save and exit vi.

### Create Host-Specific Overrides

Host variables override group variables for a single server. This is useful when one server has different hardware (more RAM means a bigger `shared_buffers`).

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/ansible/host_vars
```

```bash
vi ~/ansible/host_vars/pg-primary.yml
```

Enter the following:

```yaml
---
pg_maintenance_work_mem: "128MB"
pg_effective_cache_size: "768MB"
```

Save and exit vi.

```bash
vi ~/ansible/host_vars/pg-replica.yml
```

Enter the following:

```yaml
---
pg_maintenance_work_mem: "64MB"
pg_effective_cache_size: "512MB"
```

Save and exit vi.

### Verify the Variable Hierarchy

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
cd ~/ansible
```

```bash
ansible-inventory --graph
```

This shows all groups and hosts as a tree.

Expected output (yours will differ):

```
@all:
  |--@ungrouped:
  |--@pg_primary:
  |  |--pg-primary
  |--@pg_replica:
  |  |--pg-replica
  |--@pg_container:
  |  |--pg-container
  |--@pg_servers:
  |  |--pg-primary
  |  |--pg-replica
  ...
```

Now check what variables Ansible will apply to pg-primary:

```bash
ansible-inventory --host pg-primary
```

Expected output (yours will differ):

```json
{
    "ansible_host": "172.31.19.86",
    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
    "ansible_ssh_private_key_file": "~/.ssh/id_ed25519",
    "ansible_user": "ec2-user",
    "pg_role": "primary",
    "pg_shared_buffers": "256MB",
    "pg_max_connections": 200,
    "pg_maintenance_work_mem": "128MB",
    ...
}
```

Notice how group variables (`pg_role`, `pg_shared_buffers`) and host variables (`pg_maintenance_work_mem`) are merged together. Ansible's variable precedence is: host_vars overrides group_vars, which overrides inventory vars.

### Dynamic Inventory (Concept)

In cloud environments, you do not hardcode IPs. Instead, you use a dynamic inventory plugin that queries the AWS API and builds the inventory at runtime. For example, the `amazon.aws.aws_ec2` plugin discovers all EC2 instances tagged `role: postgresql` and groups them automatically. You do not need to set this up in the lab, but Mark may ask about it.

---

## Section 3: Jinja2 Templates for PostgreSQL Configuration

Instead of running `ALTER SYSTEM` for each parameter, you define the entire `postgresql.conf` as a Jinja2 template. Ansible renders the template using your group and host variables, then deploys it. If nothing changed, Ansible skips the file and does not trigger a reload.

### Create the Template

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/ansible/templates
```

```bash
vi ~/ansible/templates/postgresql.conf.j2
```

Enter the following:

```jinja
# ============================================================
# PostgreSQL Configuration - Managed by Ansible
# DO NOT EDIT MANUALLY - Changes will be overwritten
# Role: {{ pg_role }}
# Host: {{ inventory_hostname }}
# Generated: {{ ansible_date_time.iso8601 }}
# ============================================================

# -----------------------------------------------------------
# Connection Settings
# -----------------------------------------------------------
listen_addresses = '*'
port = 5432
max_connections = {{ pg_max_connections }}

# -----------------------------------------------------------
# Memory Settings
# -----------------------------------------------------------
shared_buffers = '{{ pg_shared_buffers }}'
work_mem = '{{ pg_work_mem }}'
maintenance_work_mem = '{{ pg_maintenance_work_mem | default("64MB") }}'
effective_cache_size = '{{ pg_effective_cache_size | default("512MB") }}'

# -----------------------------------------------------------
# WAL Settings
# -----------------------------------------------------------
wal_level = '{{ pg_wal_level }}'
max_wal_senders = {{ pg_max_wal_senders }}
max_replication_slots = {{ pg_max_replication_slots }}
wal_keep_size = '256MB'

{% if pg_role == 'primary' %}
# -----------------------------------------------------------
# Primary-Only Settings
# -----------------------------------------------------------
archive_mode = on
archive_command = '{{ pg_archive_command }}'
{% endif %}

# -----------------------------------------------------------
# Replication Settings
# -----------------------------------------------------------
hot_standby = {{ pg_hot_standby }}

{% if pg_role == 'replica' %}
# -----------------------------------------------------------
# Replica-Only Settings
# -----------------------------------------------------------
hot_standby_feedback = on
max_standby_streaming_delay = 30s
max_standby_archive_delay = 60s
{% endif %}

# -----------------------------------------------------------
# Logging
# -----------------------------------------------------------
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 0
log_min_duration_statement = 1000
log_line_prefix = '%m [%p] %u@%d '

# -----------------------------------------------------------
# Data Directory
# -----------------------------------------------------------
data_directory = '/var/lib/pgsql/17/data'
```

Key things to notice:

- `{{ pg_max_connections }}` pulls the value from group_vars or host_vars
- `{{ pg_maintenance_work_mem | default("64MB") }}` uses a fallback if the variable is not defined
- `{% if pg_role == 'primary' %}` is a conditional block - these lines only appear in the rendered file when deployed to a primary server
- The header comment warns anyone who opens the file that Ansible manages it

Save and exit vi.

### Create the Deployment Playbook

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/deploy-pg-config.yml
```

Enter the following:

```yaml
---
- name: Deploy PostgreSQL configuration from template
  hosts: pg_servers
  become: true

  tasks:
    - name: Render and deploy postgresql.conf
      ansible.builtin.template:
        src: ~/ansible/templates/postgresql.conf.j2
        dest: /var/lib/pgsql/17/data/postgresql.conf
        owner: postgres
        group: postgres
        mode: '0600'
        backup: yes
      register: pg_conf_result

    - name: Report whether config changed
      ansible.builtin.debug:
        msg: >
          {{ inventory_hostname }}: postgresql.conf
          {{ 'CHANGED - reload needed' if pg_conf_result.changed else 'unchanged - no action needed' }}

    - name: Reload PostgreSQL if config changed
      ansible.builtin.systemd:
        name: postgresql-17
        state: reloaded
      when: pg_conf_result.changed

    - name: Verify PostgreSQL is accepting connections after reload
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT 1;" -t -A
      become_user: postgres
      register: post_check
      when: pg_conf_result.changed

    - name: Fail if health check failed after reload
      ansible.builtin.fail:
        msg: "PostgreSQL health check failed on {{ inventory_hostname }} after config deploy"
      when: pg_conf_result.changed and post_check.stdout != "1"
```

Key points:

- `ansible.builtin.template` renders the `.j2` file and copies the result to the target path. It only writes the file if the content actually changed.
- `backup: yes` saves a timestamped copy of the old file before overwriting, so you can roll back manually if needed
- `mode: '0600'` ensures only the postgres user can read the config (it may contain sensitive settings)
- The reload and health check only run `when: pg_conf_result.changed` - if the config did not change, nothing happens. This is idempotency in action.

Save and exit vi.

### Run the Playbook in Check Mode First

Check mode (`--check`) shows what Ansible would do without actually doing it. Always run this before deploying config changes.

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/deploy-pg-config.yml --check --diff
```

`--check` simulates the run. `--diff` shows a line-by-line comparison of what would change.

Expected output (yours will differ):

```
TASK [Render and deploy postgresql.conf] *************************************
--- before: /var/lib/pgsql/17/data/postgresql.conf
+++ after: /home/ec2-user/.ansible/tmp/...
@@ -1,3 +1,12 @@
+# ============================================================
+# PostgreSQL Configuration - Managed by Ansible
...
changed: [pg-primary]
changed: [pg-replica]
```

Review the diff. If it looks correct, run for real:

```bash
ansible-playbook playbooks/deploy-pg-config.yml
```

Expected output (yours will differ):

```
TASK [Render and deploy postgresql.conf] *************************************
changed: [pg-primary]
changed: [pg-replica]

TASK [Reload PostgreSQL if config changed] ***********************************
changed: [pg-primary]
changed: [pg-replica]

TASK [Verify PostgreSQL is accepting connections after reload] ****************
changed: [pg-primary]
changed: [pg-replica]

PLAY RECAP *******************************************************************
pg-primary     : ok=5    changed=3    unreachable=0    failed=0
pg-replica     : ok=5    changed=3    unreachable=0    failed=0
```

Run the same playbook again immediately:

```bash
ansible-playbook playbooks/deploy-pg-config.yml
```

Expected output (yours will differ):

```
TASK [Render and deploy postgresql.conf] *************************************
ok: [pg-primary]
ok: [pg-replica]

TASK [Reload PostgreSQL if config changed] ***********************************
skipping: [pg-primary]
skipping: [pg-replica]

PLAY RECAP *******************************************************************
pg-primary     : ok=2    changed=0    unreachable=0    failed=0
pg-replica     : ok=2    changed=0    unreachable=0    failed=0
```

Notice `changed=0` and the reload was `skipping`. The config did not change, so Ansible did nothing. This is idempotency.

---

## Section 4: pg_hba.conf Management

The `pg_hba.conf` file controls who can connect and how they authenticate. Managing it with a template ensures every server in your fleet has consistent access rules.

### Create the Template

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/templates/pg_hba.conf.j2
```

Enter the following:

```jinja
# ============================================================
# PostgreSQL HBA Configuration - Managed by Ansible
# DO NOT EDIT MANUALLY - Changes will be overwritten
# Host: {{ inventory_hostname }}
# Generated: {{ ansible_date_time.iso8601 }}
# ============================================================

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections - trust for postgres user, md5 for others
local   all             postgres                                peer
local   all             all                                     md5

# IPv4 local connections
host    all             all             127.0.0.1/32            md5

# IPv6 local connections
host    all             all             ::1/128                 md5

# Application hosts - allow connections to quantdb
{% for host in pg_hba_app_hosts %}
host    quantdb         quant_app       {{ host }}              md5
host    quantdb         quant_readonly  {{ host }}              md5
{% endfor %}

{% if pg_role == 'primary' %}
# Replication connections - primary only
{% for host in pg_hba_replication_hosts %}
host    replication     replicator      {{ host }}              md5
{% endfor %}
{% endif %}
```

Key things:

- `{% for host in pg_hba_app_hosts %}` loops over the list defined in group_vars, generating one `host` line per allowed network
- The replication block only appears on the primary (controlled by `{% if pg_role == 'primary' %}`)
- `peer` authentication for local postgres connections means the OS username must match the database username - no password needed

Save and exit vi.

### Create the Deployment Playbook

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/deploy-pg-hba.yml
```

Enter the following:

```yaml
---
- name: Deploy pg_hba.conf from template
  hosts: pg_servers
  become: true

  tasks:
    - name: Render and deploy pg_hba.conf
      ansible.builtin.template:
        src: ~/ansible/templates/pg_hba.conf.j2
        dest: /var/lib/pgsql/17/data/pg_hba.conf
        owner: postgres
        group: postgres
        mode: '0600'
        backup: yes
      register: hba_result

    - name: Report whether pg_hba.conf changed
      ansible.builtin.debug:
        msg: >
          {{ inventory_hostname }}: pg_hba.conf
          {{ 'CHANGED - reload needed' if hba_result.changed else 'unchanged' }}

    - name: Reload PostgreSQL if pg_hba.conf changed
      ansible.builtin.systemd:
        name: postgresql-17
        state: reloaded
      when: hba_result.changed

    - name: Verify pg_hba rules loaded correctly
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules ORDER BY line_number;" -x
      become_user: postgres
      register: hba_rules
      when: hba_result.changed

    - name: Print loaded HBA rules
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} HBA rules:\n{{ hba_rules.stdout }}"
      when: hba_result.changed

    - name: Check for HBA parse errors
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT line_number, error FROM pg_hba_file_rules WHERE error IS NOT NULL;" -t -A
      become_user: postgres
      register: hba_errors
      when: hba_result.changed

    - name: Fail if HBA has parse errors
      ansible.builtin.fail:
        msg: "pg_hba.conf has errors on {{ inventory_hostname }}: {{ hba_errors.stdout }}"
      when: hba_result.changed and hba_errors.stdout != ""
```

The `pg_hba_file_rules` view is a PostgreSQL system catalog that shows how PG parsed the `pg_hba.conf` file. If there are syntax errors, the `error` column will be non-null, and this playbook will stop immediately.

Save and exit vi.

### Run the Playbook

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/deploy-pg-hba.yml --check --diff
```

Review the diff, then run for real:

```bash
ansible-playbook playbooks/deploy-pg-hba.yml
```

Expected output (yours will differ):

```
TASK [Render and deploy pg_hba.conf] *****************************************
changed: [pg-primary]
changed: [pg-replica]

TASK [Reload PostgreSQL if pg_hba.conf changed] ******************************
changed: [pg-primary]
changed: [pg-replica]

TASK [Check for HBA parse errors] ********************************************
changed: [pg-primary]
changed: [pg-replica]

PLAY RECAP *******************************************************************
pg-primary     : ok=6    changed=4    unreachable=0    failed=0
pg-replica     : ok=6    changed=4    unreachable=0    failed=0
```

---

## Section 5: Rolling Configuration Changes

This playbook changes `work_mem` across all PostgreSQL servers one at a time, with health checks and replication lag verification between each server. This is how you push parameter changes in production.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/rolling-config-change.yml
```

Enter the following:

```yaml
---
- name: Rolling work_mem update - replica first, then primary
  hosts: pg_replica,pg_primary
  serial: 1
  order: inventory
  become: true
  become_user: postgres

  vars:
    target_param: "work_mem"
    target_value: "32MB"

  tasks:
    - name: Pre-check - verify PostgreSQL is healthy
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT pg_is_in_recovery();" -t -A
      register: recovery_check

    - name: Print current role
      ansible.builtin.debug:
        msg: >
          {{ inventory_hostname }} is
          {{ 'a replica (in recovery)' if recovery_check.stdout == 't' else 'the primary' }}

    - name: Get current value of target parameter
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SHOW {{ target_param }};" -t -A
      register: current_value

    - name: Print current value
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ target_param }} current={{ current_value.stdout }} target={{ target_value }}"

    - name: Skip if already at target value
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ target_param }} already at {{ target_value }} - skipping"
      when: current_value.stdout == target_value

    - name: Apply ALTER SYSTEM SET
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "ALTER SYSTEM SET {{ target_param }} = '{{ target_value }}';"
      when: current_value.stdout != target_value

    - name: Reload PostgreSQL to apply change
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT pg_reload_conf();"
      when: current_value.stdout != target_value

    - name: Wait 3 seconds for reload to settle
      ansible.builtin.pause:
        seconds: 3
      when: current_value.stdout != target_value

    - name: Post-check - verify new value
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SHOW {{ target_param }};" -t -A
      register: new_value

    - name: Confirm change applied
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ target_param }} is now {{ new_value.stdout }}"

    - name: Fail if new value does not match target
      ansible.builtin.fail:
        msg: >
          ROLLBACK NEEDED on {{ inventory_hostname }}.
          Expected {{ target_param }}={{ target_value }} but got {{ new_value.stdout }}.
          Stopping playbook. Fix before proceeding to next server.
      when: current_value.stdout != target_value and new_value.stdout != target_value

    - name: Check replication lag (primary only)
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "
          SELECT client_addr,
                 state,
                 pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
          FROM pg_stat_replication;" -t -A
      register: repl_lag
      when: recovery_check.stdout == 'f'

    - name: Print replication status
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} replication status:\n{{ repl_lag.stdout }}"
      when: recovery_check.stdout == 'f'
```

Key design decisions:

- `hosts: pg_replica,pg_primary` with `order: inventory` processes the replica before the primary
- `serial: 1` ensures only one server is touched at a time
- The playbook checks the current value and skips the change if it already matches - this is manual idempotency for `ALTER SYSTEM`
- If the post-check fails, the playbook stops immediately with a clear error before touching the next server
- Replication lag is checked after updating the primary to confirm the replica is keeping up

Save and exit vi.

Run the playbook:

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/rolling-config-change.yml
```

Expected output (yours will differ):

```
PLAY [Rolling work_mem update - replica first, then primary] *****************

TASK [Pre-check - verify PostgreSQL is healthy] ******************************
changed: [pg-replica]

TASK [Print current role] ****************************************************
ok: [pg-replica] => {
    "msg": "pg-replica is a replica (in recovery)"
}

TASK [Apply ALTER SYSTEM SET] ************************************************
changed: [pg-replica]

TASK [Reload PostgreSQL to apply change] *************************************
changed: [pg-replica]

TASK [Confirm change applied] ************************************************
ok: [pg-replica] => {
    "msg": "pg-replica: work_mem is now 32MB"
}
...
PLAY RECAP *******************************************************************
pg-primary     : ok=10   changed=4    unreachable=0    failed=0
pg-replica     : ok=9    changed=4    unreachable=0    failed=0
```

To roll back, change `target_value` to the previous value and run the playbook again.

---

## Section 6: Configuration Drift Detection

Drift happens when someone logs into a server and runs `ALTER SYSTEM SET` manually, or edits `postgresql.conf` by hand. This playbook compares the running PostgreSQL configuration against your Ansible variables and reports any mismatches.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/detect-drift.yml
```

Enter the following:

```yaml
---
- name: Detect PostgreSQL configuration drift
  hosts: pg_servers
  become: true
  become_user: postgres

  vars:
    desired_config:
      shared_buffers: "{{ pg_shared_buffers }}"
      work_mem: "{{ pg_work_mem }}"
      max_connections: "{{ pg_max_connections }}"
      wal_level: "{{ pg_wal_level }}"
      max_wal_senders: "{{ pg_max_wal_senders }}"
      hot_standby: "{{ pg_hot_standby }}"

  tasks:
    - name: Query all desired parameters from pg_settings
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -t -A -c "
          SELECT name, setting, unit
          FROM pg_settings
          WHERE name = '{{ item.key }}';"
      register: live_settings
      loop: "{{ desired_config | dict2items }}"

    - name: Build drift report
      ansible.builtin.set_fact:
        drift_report: >-
          {% set drifts = [] %}
          {% for result in live_settings.results %}
          {% set parts = result.stdout.split('|') %}
          {% set param_name = parts[0] | default('') %}
          {% set live_val = parts[1] | default('') %}
          {% set unit = parts[2] | default('') %}
          {% set desired_val = result.item.value | string %}
          {% if live_val != desired_val %}
          {% set _ = drifts.append(param_name ~ ': live=' ~ live_val ~ unit ~ ' desired=' ~ desired_val) %}
          {% endif %}
          {% endfor %}
          {{ drifts | join('\n') if drifts | length > 0 else 'NO DRIFT DETECTED' }}

    - name: Print drift report
      ansible.builtin.debug:
        msg: |
          === DRIFT REPORT for {{ inventory_hostname }} ({{ pg_role }}) ===
          {{ drift_report }}

    - name: Set drift flag
      ansible.builtin.set_fact:
        has_drift: "{{ 'NO DRIFT' not in drift_report }}"

    - name: Warn if drift detected
      ansible.builtin.debug:
        msg: "WARNING: {{ inventory_hostname }} has configuration drift. Run deploy-pg-config.yml to remediate."
      when: has_drift | bool

- name: Summary
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Print remediation instructions
      ansible.builtin.debug:
        msg: |
          To auto-remediate all drift, run:
            ansible-playbook playbooks/deploy-pg-config.yml
          To remediate a single parameter, run:
            ansible-playbook playbooks/rolling-config-change.yml -e "target_param=work_mem target_value=16MB"
```

How drift detection works:

- `desired_config` pulls values from your group_vars (the same variables used by the template). This is your source of truth.
- The playbook queries `pg_settings` for each parameter's live value.
- Jinja2 logic compares live vs desired and builds a human-readable report.
- If drift exists, it tells you exactly which playbook to run to fix it.

Save and exit vi.

### Run the Drift Check

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/detect-drift.yml
```

Expected output (yours will differ):

```
TASK [Print drift report] ****************************************************
ok: [pg-primary] => {
    "msg": "=== DRIFT REPORT for pg-primary (primary) ===\nwork_mem: live=32MB desired=16MB\n"
}
ok: [pg-replica] => {
    "msg": "=== DRIFT REPORT for pg-replica (replica) ===\nwork_mem: live=32MB desired=16MB\n"
}
```

This detects the `work_mem` change we made in Section 5. To remediate, either update the group_vars to `32MB` (if the new value is intentional) or run the config deployment playbook to push the original value back.

---

## Section 7: Emergency Playbooks

These playbooks handle urgent situations. Each supports `--check` mode so you can preview the action before committing.

### Emergency Playbook 1: Promote Replica to Primary

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/emergency-promote.yml
```

Enter the following:

```yaml
---
- name: Emergency - Promote replica to primary
  hosts: pg_replica
  become: true
  become_user: postgres

  vars_prompt:
    - name: confirm_promote
      prompt: "Type YES to confirm promotion of pg-replica to primary"
      private: false

  tasks:
    - name: Abort if not confirmed
      ansible.builtin.fail:
        msg: "Promotion cancelled. You typed '{{ confirm_promote }}' instead of 'YES'."
      when: confirm_promote != "YES"

    - name: Check if this server is actually a replica
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT pg_is_in_recovery();" -t -A
      register: is_replica

    - name: Abort if server is already a primary
      ansible.builtin.fail:
        msg: "{{ inventory_hostname }} is already a primary (not in recovery). Aborting."
      when: is_replica.stdout != "t"

    - name: Promote replica to primary
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/pg_ctl promote -D /var/lib/pgsql/17/data
      when: not ansible_check_mode

    - name: Wait for promotion to complete
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT pg_is_in_recovery();" -t -A
      register: post_promote
      retries: 10
      delay: 2
      until: post_promote.stdout == "f"
      when: not ansible_check_mode

    - name: Confirm promotion succeeded
      ansible.builtin.debug:
        msg: >
          {{ inventory_hostname }} has been promoted.
          pg_is_in_recovery={{ post_promote.stdout }}.
          This server is now a PRIMARY.
          IMPORTANT: Update your application connection strings and DNS.
      when: not ansible_check_mode
```

`vars_prompt` asks for confirmation before running. This prevents accidental promotions. `retries: 10` with `delay: 2` gives PostgreSQL up to 20 seconds to complete the promotion, checking every 2 seconds.

Save and exit vi.

### Emergency Playbook 2: Push Known-Good pg_hba.conf

When someone locks themselves out by pushing a bad `pg_hba.conf`, this playbook restores the Ansible-managed version.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/emergency-hba-restore.yml
```

Enter the following:

```yaml
---
- name: Emergency - Restore known-good pg_hba.conf
  hosts: pg_servers
  become: true

  vars_prompt:
    - name: confirm_restore
      prompt: "This will overwrite pg_hba.conf on ALL pg_servers. Type YES to confirm"
      private: false

  tasks:
    - name: Abort if not confirmed
      ansible.builtin.fail:
        msg: "Restore cancelled."
      when: confirm_restore != "YES"

    - name: Deploy known-good pg_hba.conf from template
      ansible.builtin.template:
        src: ~/ansible/templates/pg_hba.conf.j2
        dest: /var/lib/pgsql/17/data/pg_hba.conf
        owner: postgres
        group: postgres
        mode: '0600'
        backup: yes
      register: hba_result

    - name: Reload PostgreSQL
      ansible.builtin.systemd:
        name: postgresql-17
        state: reloaded
      when: hba_result.changed

    - name: Verify connections work
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "SELECT 1;" -t -A
      become_user: postgres
      register: verify

    - name: Report result
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: pg_hba.conf restored. Health check={{ 'PASS' if verify.stdout == '1' else 'FAIL' }}"
```

Save and exit vi.

### Emergency Playbook 3: Kill Idle-in-Transaction Sessions

Sessions stuck in "idle in transaction" hold locks and block other operations. This playbook finds and terminates them.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/emergency-kill-idle.yml
```

Enter the following:

```yaml
---
- name: Emergency - Kill idle-in-transaction sessions
  hosts: pg_servers
  become: true
  become_user: postgres

  vars:
    idle_threshold_minutes: 5

  tasks:
    - name: Find idle-in-transaction sessions older than threshold
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -t -A -c "
          SELECT pid, usename, datname, state,
                 now() - state_change AS idle_duration,
                 left(query, 80) AS query_preview
          FROM pg_stat_activity
          WHERE state = 'idle in transaction'
            AND now() - state_change > interval '{{ idle_threshold_minutes }} minutes'
          ORDER BY state_change;"
      register: idle_sessions

    - name: Report idle sessions found
      ansible.builtin.debug:
        msg: |
          {{ inventory_hostname }}: Found idle-in-transaction sessions:
          {{ idle_sessions.stdout if idle_sessions.stdout != '' else '(none)' }}

    - name: Terminate idle-in-transaction sessions
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -t -A -c "
          SELECT pg_terminate_backend(pid), pid, usename, datname
          FROM pg_stat_activity
          WHERE state = 'idle in transaction'
            AND now() - state_change > interval '{{ idle_threshold_minutes }} minutes';"
      register: killed
      when: idle_sessions.stdout != "" and not ansible_check_mode

    - name: Report terminated sessions
      ansible.builtin.debug:
        msg: |
          {{ inventory_hostname }}: Terminated sessions:
          {{ killed.stdout if killed is defined and killed.stdout != '' else '(none terminated)' }}

    - name: Verify no remaining idle-in-transaction beyond threshold
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -t -A -c "
          SELECT count(*)
          FROM pg_stat_activity
          WHERE state = 'idle in transaction'
            AND now() - state_change > interval '{{ idle_threshold_minutes }} minutes';"
      register: remaining

    - name: Report cleanup result
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ remaining.stdout }} idle-in-transaction sessions remaining above threshold"
```

Save and exit vi.

### Test Emergency Playbooks in Check Mode

Always preview emergency playbooks before running them for real.

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/emergency-kill-idle.yml --check
```

In check mode, Ansible will show what it would do without actually terminating any sessions. The `when: not ansible_check_mode` guard in the promote playbook prevents accidental promotions during dry runs.

Expected output (yours will differ):

```
TASK [Find idle-in-transaction sessions older than threshold] ****************
skipping: [pg-primary]
skipping: [pg-replica]

PLAY RECAP *******************************************************************
pg-primary     : ok=1    changed=0    unreachable=0    failed=0    skipped=4
pg-replica     : ok=1    changed=0    unreachable=0    failed=0    skipped=4
```

---

## Section 8: Ansible Vault for Database Secrets

Passwords, API keys, and replication credentials should never be stored in plain text in your Ansible files. Ansible Vault encrypts sensitive data so you can safely commit it to version control.

### Create an Encrypted Vault File

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
cd ~/ansible
```

```bash
ansible-vault create group_vars/vault.yml
```

Ansible will ask you to create a password. Choose something you will remember for this lab (for example: `VoleonVault2024`). It will then open vi with an empty file.

Enter the following:

```yaml
---
vault_pg_replicator_password: "R3pl1cat0r_S3cure!"
vault_pg_app_password: "Quant_App_2024!"
vault_pg_admin_password: "Adm1n_Str0ng_Pass!"
```

Save and exit vi. The file is now encrypted on disk.

### Verify the File is Encrypted

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
cat group_vars/vault.yml
```

Expected output (yours will differ):

```
$ANSIBLE_VAULT;1.1;AES256
35323864363039633733623961343032623637613536343738626232383466653939396338393339
61383362303831663266636665626135333033393462620a333231653134666532303537616534...
```

The file is unreadable without the vault password. This is what gets committed to git - the password stays out of the repository.

### View or Edit the Vault File

To view the decrypted contents:

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-vault view group_vars/vault.yml
```

Enter your vault password when prompted. Ansible decrypts and displays the contents.

To edit:

```bash
ansible-vault edit group_vars/vault.yml
```

This decrypts the file, opens it in vi, and re-encrypts it when you save and exit.

### Encrypt a Single String Inline

Sometimes you want to embed an encrypted value directly in a variable file rather than creating a separate vault file. This is useful for mixing encrypted and plain-text variables in the same file.

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-vault encrypt_string 'MySecretPassword123' --name 'pg_monitoring_password'
```

Enter your vault password when prompted.

Expected output (yours will differ):

```
pg_monitoring_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          61626364656667686970...
Encryption successful
```

You can paste this output directly into any variable file and Ansible will decrypt it at runtime.

### Use Vault Variables in a Playbook

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/create-app-user.yml
```

Enter the following:

```yaml
---
- name: Create application database user with vault password
  hosts: pg_primary
  become: true
  become_user: postgres

  vars_files:
    - ~/ansible/group_vars/vault.yml

  tasks:
    - name: Check if quant_app user exists
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -t -A -c "
          SELECT 1 FROM pg_roles WHERE rolname = 'quant_app';"
      register: user_exists

    - name: Create quant_app user if it does not exist
      ansible.builtin.shell: |
        /usr/pgsql-17/bin/psql -c "
          CREATE ROLE quant_app WITH LOGIN PASSWORD '{{ vault_pg_app_password }}';"
      when: user_exists.stdout != "1"

    - name: Report result
      ansible.builtin.debug:
        msg: >
          quant_app user
          {{ 'already exists - skipped' if user_exists.stdout == '1' else 'created successfully' }}
```

`vars_files` loads the encrypted vault file. Ansible decrypts it in memory - the password never appears in logs or on disk in plain text.

Save and exit vi.

### Run a Playbook That Uses Vault

On **pg-ops**, as **ec2-user**, from `~/ansible`:

```bash
ansible-playbook playbooks/create-app-user.yml --ask-vault-pass
```

`--ask-vault-pass` prompts you for the vault password before the playbook runs. Enter the password you chose earlier.

Expected output (yours will differ):

```
Vault password:

TASK [Check if quant_app user exists] ****************************************
changed: [pg-primary]

TASK [Create quant_app user if it does not exist] ****************************
changed: [pg-primary]

TASK [Report result] *********************************************************
ok: [pg-primary] => {
    "msg": "quant_app user created successfully"
}

PLAY RECAP *******************************************************************
pg-primary     : ok=3    changed=2    unreachable=0    failed=0
```

### Vault Best Practices

- **One vault per environment**: Create separate vault files for dev, staging, and production. Never share vault passwords across environments.
- **Git-ignore vault passwords**: Add your vault password file to `.gitignore`. Never commit the password itself.
- **Use a password file for CI/CD**: Instead of `--ask-vault-pass`, use `--vault-password-file /path/to/password-file` in automated pipelines. The file contains just the password and is injected by your CI system.
- **Rotate vault passwords**: When someone leaves the team, re-key the vault with `ansible-vault rekey group_vars/vault.yml`.

---

## Summary

You have built production-grade Ansible automation for PostgreSQL fleet management:

- **Group and host variables** let you manage different configs for primary vs replica from a single set of playbooks
- **Jinja2 templates** for `postgresql.conf` and `pg_hba.conf` give you a single source of truth with conditional logic for role-specific settings
- **Rolling configuration changes** update the replica first, verify health and replication, then move to the primary
- **Drift detection** compares live settings against your Ansible variables and reports mismatches
- **Emergency playbooks** handle failover, HBA restore, and idle session cleanup with confirmation prompts and check-mode safety
- **Ansible Vault** keeps database passwords encrypted at rest while allowing playbooks to use them at runtime

Your updated directory structure on pg-ops:

```
~/ansible/
  ansible.cfg
  inventory/
    hosts.yml
  group_vars/
    pg_primary.yml
    pg_replica.yml
    vault.yml              (encrypted)
  host_vars/
    pg-primary.yml
    pg-replica.yml
  templates/
    postgresql.conf.j2
    pg_hba.conf.j2
  playbooks/
    check-pg-status.yml         (from BUILD-07)
    pg-config-check.yml         (from BUILD-07)
    rolling-reload.yml          (from BUILD-07)
    deploy-pg-config.yml        (new)
    deploy-pg-hba.yml           (new)
    rolling-config-change.yml   (new)
    detect-drift.yml            (new)
    emergency-promote.yml       (new)
    emergency-hba-restore.yml   (new)
    emergency-kill-idle.yml     (new)
    create-app-user.yml         (new)
  roles/
    postgresql/
    common/
    monitoring/
    pgbackrest/
    pgbouncer/
    redis/
```

### Interview Talking Points for Mark Selby

When Mark asks about automation and configuration management:

1. **Idempotency**: "I use Ansible templates so configs are only deployed when they actually differ. No unnecessary reloads."
2. **Rolling updates**: "Replica first, health check, then primary. `serial: 1` ensures we never update all servers at once."
3. **Drift detection**: "I query `pg_settings` and compare against Ansible variables. Drift gets flagged and can be auto-remediated."
4. **Secrets management**: "Database passwords live in Ansible Vault, encrypted at rest. They are decrypted in memory during playbook runs."
5. **Emergency procedures**: "I have pre-built playbooks for failover, HBA restore, and session cleanup - all with confirmation prompts and `--check` mode."
