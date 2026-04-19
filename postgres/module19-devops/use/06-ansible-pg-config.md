# Module 19 - USE 06: Ansible PostgreSQL Configuration Exercise

## Objective

Write an Ansible playbook to manage postgresql.conf and pg_hba.conf, deploy configuration changes, perform a rolling restart with health checks, and verify changes via pg_settings.

---

## Setup

Install Ansible if not already installed.

```bash
sudo dnf install -y ansible-core
```

Verify the install.

```bash
ansible --version
```

Create the project directory.

```bash
mkdir -p /opt/pgsql/ansible-exercise/roles/pgconfig/tasks
```

```bash
mkdir -p /opt/pgsql/ansible-exercise/roles/pgconfig/templates
```

```bash
mkdir -p /opt/pgsql/ansible-exercise/roles/pgconfig/handlers
```

```bash
mkdir -p /opt/pgsql/ansible-exercise/inventory
```

---

## Exercise 1: Write the Inventory

For this exercise, we will manage localhost. In production you would list real server IPs.

```bash
vi /opt/pgsql/ansible-exercise/inventory/hosts.yml
```

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_become: true
  vars:
    pg_version: "16"
    pg_data_dir: "/opt/pgsql/data"
    pg_log_dir: "/opt/pgsql/log"
    pg_port: 5432
    pg_bin_dir: "/usr/pgsql-16/bin"
```

---

## Exercise 2: Write the postgresql.conf Template

```bash
vi /opt/pgsql/ansible-exercise/roles/pgconfig/templates/postgresql.conf.j2
```

```ini
# postgresql.conf - Managed by Ansible
# Last updated: {{ ansible_date_time.iso8601 }}
# DO NOT EDIT MANUALLY

# Connection Settings
listen_addresses = '{{ pg_listen_addresses | default("*") }}'
port = {{ pg_port | default(5432) }}
max_connections = {{ pg_max_connections | default(200) }}

# Memory
shared_buffers = '{{ pg_shared_buffers | default("256MB") }}'
effective_cache_size = '{{ pg_effective_cache_size | default("1GB") }}'
work_mem = '{{ pg_work_mem | default("4MB") }}'
maintenance_work_mem = '{{ pg_maintenance_work_mem | default("128MB") }}'

# WAL
wal_level = '{{ pg_wal_level | default("replica") }}'
max_wal_senders = {{ pg_max_wal_senders | default(10) }}
max_replication_slots = {{ pg_max_replication_slots | default(10) }}

# Checkpoints
checkpoint_completion_target = {{ pg_checkpoint_completion_target | default(0.9) }}
min_wal_size = '{{ pg_min_wal_size | default("256MB") }}'
max_wal_size = '{{ pg_max_wal_size | default("1GB") }}'

# Logging
logging_collector = on
log_directory = '{{ pg_log_dir }}'
log_filename = 'postgresql-%Y-%m-%d.log'
log_min_duration_statement = {{ pg_log_min_duration | default(1000) }}
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_connections = {{ pg_log_connections | default("on") }}
log_disconnections = {{ pg_log_disconnections | default("on") }}
log_lock_waits = on
log_statement = 'ddl'
log_checkpoints = on

# Statistics
shared_preload_libraries = 'pg_stat_statements'

# Data Directory
data_directory = '{{ pg_data_dir }}'
```

---

## Exercise 3: Write the pg_hba.conf Template

```bash
vi /opt/pgsql/ansible-exercise/roles/pgconfig/templates/pg_hba.conf.j2
```

```
# pg_hba.conf - Managed by Ansible
# Last updated: {{ ansible_date_time.iso8601 }}
# DO NOT EDIT MANUALLY

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# Localhost
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# Application connections
{% for entry in pg_hba_entries | default([]) %}
host    {{ entry.database | default('all') }}    {{ entry.user }}    {{ entry.address }}    {{ entry.method | default('scram-sha-256') }}
{% endfor %}
```

---

## Exercise 4: Write Tasks and Handlers

Create the tasks file.

```bash
vi /opt/pgsql/ansible-exercise/roles/pgconfig/tasks/main.yml
```

```yaml
---
- name: Backup current postgresql.conf
  copy:
    src: "{{ pg_data_dir }}/postgresql.conf"
    dest: "{{ pg_data_dir }}/postgresql.conf.bak.{{ ansible_date_time.epoch }}"
    remote_src: yes
    owner: postgres
    group: postgres
    mode: '0600'

- name: Deploy postgresql.conf
  template:
    src: postgresql.conf.j2
    dest: "{{ pg_data_dir }}/postgresql.conf"
    owner: postgres
    group: postgres
    mode: '0600'
  register: pg_conf_result
  notify: Reload PostgreSQL

- name: Backup current pg_hba.conf
  copy:
    src: "{{ pg_data_dir }}/pg_hba.conf"
    dest: "{{ pg_data_dir }}/pg_hba.conf.bak.{{ ansible_date_time.epoch }}"
    remote_src: yes
    owner: postgres
    group: postgres
    mode: '0600'

- name: Deploy pg_hba.conf
  template:
    src: pg_hba.conf.j2
    dest: "{{ pg_data_dir }}/pg_hba.conf"
    owner: postgres
    group: postgres
    mode: '0600'
  register: hba_conf_result
  notify: Reload PostgreSQL

- name: Check if restart is needed
  become_user: postgres
  command: >
    psql -tAc "SELECT count(*) FROM pg_settings WHERE pending_restart = true;"
  register: restart_needed
  changed_when: false

- name: Display pending restart count
  debug:
    msg: "Settings pending restart: {{ restart_needed.stdout }}"

- name: Warn if restart is needed
  debug:
    msg: "WARNING: {{ restart_needed.stdout }} setting(s) require a PostgreSQL restart to take effect"
  when: restart_needed.stdout | int > 0
```

Create the handlers file.

```bash
vi /opt/pgsql/ansible-exercise/roles/pgconfig/handlers/main.yml
```

```yaml
---
- name: Reload PostgreSQL
  become_user: postgres
  command: "{{ pg_bin_dir }}/pg_ctl -D {{ pg_data_dir }} reload"
  listen: "Reload PostgreSQL"

- name: Restart PostgreSQL
  become_user: postgres
  command: >
    {{ pg_bin_dir }}/pg_ctl -D {{ pg_data_dir }}
    -l {{ pg_log_dir }}/startup.log
    restart -m fast
  listen: "Restart PostgreSQL"
```

---

## Exercise 5: Write the Main Playbook

```bash
vi /opt/pgsql/ansible-exercise/deploy-config.yml
```

```yaml
---
- name: Deploy PostgreSQL Configuration
  hosts: all
  become: true

  vars:
    pg_shared_buffers: "512MB"
    pg_effective_cache_size: "2GB"
    pg_work_mem: "8MB"
    pg_maintenance_work_mem: "256MB"
    pg_max_connections: 200
    pg_log_min_duration: 500
    pg_hba_entries:
      - user: "appuser"
        address: "10.0.0.0/8"
        database: "appdb"
      - user: "monitoring"
        address: "127.0.0.1/32"
        database: "all"

  roles:
    - pgconfig

  post_tasks:
    - name: Verify PostgreSQL is running
      become_user: postgres
      command: "{{ pg_bin_dir }}/pg_ctl -D {{ pg_data_dir }} status"
      register: pg_status
      changed_when: false

    - name: Display PostgreSQL status
      debug:
        msg: "{{ pg_status.stdout_lines }}"
```

---

## Exercise 6: Dry Run First

Always run with `--check --diff` first. The `--check` flag simulates the run without making changes. The `--diff` flag shows line-by-line differences.

```bash
cd /opt/pgsql/ansible-exercise
```

```bash
ansible-playbook -i inventory/hosts.yml deploy-config.yml --check --diff
```

Expected output (yours will differ):
```
PLAY [Deploy PostgreSQL Configuration] ******************

TASK [Gathering Facts] **********************************
ok: [localhost]

TASK [pgconfig : Backup current postgresql.conf] ********
changed: [localhost]

TASK [pgconfig : Deploy postgresql.conf] ****************
--- before: /opt/pgsql/data/postgresql.conf
+++ after: /tmp/ansible_template_xyz.conf
@@ -3,7 +3,7 @@
-shared_buffers = '256MB'
+shared_buffers = '512MB'
changed: [localhost]
...
```

Review the diff output. Make sure only the settings you intended to change are different.

---

## Exercise 7: Apply the Configuration

Run for real (without --check).

```bash
ansible-playbook -i inventory/hosts.yml deploy-config.yml --diff
```

---

## Exercise 8: Verify via pg_settings

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check specific settings that were changed.

```bash
psql -c "SELECT name, setting, unit, pending_restart FROM pg_settings WHERE name IN ('shared_buffers', 'work_mem', 'log_min_duration_statement', 'effective_cache_size') ORDER BY name;"
```

Expected output (yours will differ):
```
            name            | setting | unit | pending_restart
----------------------------+---------+------+-----------------
 effective_cache_size       | 262144  |  8kB | f
 log_min_duration_statement | 500     | ms   | f
 shared_buffers             | 65536   |  8kB | t
 work_mem                   | 8192    | kB   | f
(4 rows)
```

Note: shared_buffers shows `pending_restart = t` because changing shared_buffers requires a PostgreSQL restart, not just a reload.

Check pg_hba.conf was applied.

```bash
psql -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules ORDER BY line_number;"
```

Expected output (yours will differ):
```
 line_number | type  | database  | user_name  |   address    | auth_method
-------------+-------+-----------+------------+--------------+--------------
           7 | local | {all}     | {postgres} |              | peer
           8 | local | {all}     | {all}      |              | peer
          11 | host  | {all}     | {all}      | 127.0.0.1/32 | scram-sha-256
          12 | host  | {all}     | {all}      | ::1/128      | scram-sha-256
          15 | host  | {appdb}   | {appuser}  | 10.0.0.0/8   | scram-sha-256
          16 | host  | {all}     | {monitoring}| 127.0.0.1/32| scram-sha-256
(6 rows)
```

Exit the postgres user.

```bash
exit
```

---

## Exercise 9: Rolling Restart with Health Checks

Create a restart playbook.

```bash
vi /opt/pgsql/ansible-exercise/restart-pg.yml
```

```yaml
---
- name: Rolling restart PostgreSQL
  hosts: all
  become: true
  serial: 1

  tasks:
    - name: Check PostgreSQL is running before restart
      become_user: postgres
      command: "{{ pg_bin_dir }}/pg_ctl -D {{ pg_data_dir }} status"
      register: pre_status
      changed_when: false
      failed_when: pre_status.rc != 0

    - name: Record pending restart settings
      become_user: postgres
      command: >
        psql -tAc "SELECT string_agg(name, ', ') FROM pg_settings WHERE pending_restart = true;"
      register: pending_settings
      changed_when: false

    - name: Display what requires restart
      debug:
        msg: "Settings requiring restart: {{ pending_settings.stdout | default('none') }}"

    - name: Restart PostgreSQL
      become_user: postgres
      command: >
        {{ pg_bin_dir }}/pg_ctl -D {{ pg_data_dir }}
        -l {{ pg_log_dir }}/startup.log
        restart -m fast

    - name: Wait for PostgreSQL to accept connections
      wait_for:
        port: "{{ pg_port }}"
        delay: 3
        timeout: 60

    - name: Verify PostgreSQL is healthy
      become_user: postgres
      command: psql -tAc "SELECT 1;"
      register: health_check
      retries: 5
      delay: 3
      until: health_check.rc == 0

    - name: Verify no more pending restarts
      become_user: postgres
      command: >
        psql -tAc "SELECT count(*) FROM pg_settings WHERE pending_restart = true;"
      register: post_restart_pending
      changed_when: false

    - name: Confirm all settings applied
      debug:
        msg: "Pending restarts remaining: {{ post_restart_pending.stdout }}"
```

Run the restart playbook.

```bash
ansible-playbook -i inventory/hosts.yml restart-pg.yml
```

Expected output (yours will differ):
```
TASK [Display what requires restart] *******************
ok: [localhost] => {
    "msg": "Settings requiring restart: shared_buffers"
}

TASK [Restart PostgreSQL] ******************************
changed: [localhost]

TASK [Wait for PostgreSQL to accept connections] *******
ok: [localhost]

TASK [Verify PostgreSQL is healthy] ********************
ok: [localhost]

TASK [Confirm all settings applied] ********************
ok: [localhost] => {
    "msg": "Pending restarts remaining: 0"
}
```

---

## Cleanup

Switch to the postgres user.

```bash
sudo -iu postgres
```

Restore the original postgresql.conf from backup if needed.

```bash
ls -la /opt/pgsql/data/postgresql.conf.bak.*
```

Exit the postgres user.

```bash
exit
```

---

## Checklist

- [ ] Created Ansible inventory with PostgreSQL variables
- [ ] Wrote postgresql.conf Jinja2 template with configurable parameters
- [ ] Wrote pg_hba.conf Jinja2 template with dynamic entries
- [ ] Created tasks that back up configs before deploying
- [ ] Ran dry run with --check --diff before applying
- [ ] Applied configuration and verified changes via pg_settings
- [ ] Verified pg_hba_file_rules shows correct entries
- [ ] Created rolling restart playbook with health checks
- [ ] Confirmed pending_restart cleared after restart
