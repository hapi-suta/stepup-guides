# BUILD 02: Managing PostgreSQL Configuration with Ansible

**Module 06: Ansible for Database Configuration**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to use Ansible templates, handlers, vault, and roles to manage PostgreSQL configuration files across all your servers from a single source of truth.

---

## The Problem

You manage PostgreSQL across multiple datacenters. Every server has a `postgresql.conf` and `pg_hba.conf`. Making a change means:

1. SSH into each server
2. Edit the config file
3. Reload or restart PostgreSQL
4. Verify the change took effect
5. Repeat for every server

With Ansible templates, you define the configuration once and deploy it everywhere. Variables handle the differences between servers (e.g., `shared_buffers` based on available RAM).

---

## Step 1: Set Up the Project Structure

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/ansible-pgconfig
cd ~/dba-labs/ansible-pgconfig
mkdir -p templates group_vars host_vars
```

Create the inventory:

```bash
vi inventory.ini
```

```ini
[primary]
localhost ansible_connection=local

[standbys]
# standby1 ansible_host=10.0.1.11 ansible_user=ec2-user
# standby2 ansible_host=10.0.1.12 ansible_user=ec2-user

[postgresql:children]
primary
standbys
```

---

## Step 2: Jinja2 Templates for postgresql.conf

The `template` module copies a file to the target server, replacing `{{ variables }}` with actual values. The template engine is Jinja2 - the same one used by Flask and Django.

**DBA Analogy:** Imagine you have a `postgresql.conf` with placeholders: `shared_buffers = [CALCULATED_VALUE]`. A template is exactly that - one file with placeholders that gets filled in differently for each server based on its RAM, role, and workload.

Create the template:

```bash
vi templates/postgresql.conf.j2
```

```ini
# PostgreSQL {{ pg_version }} Configuration
# Managed by Ansible - DO NOT EDIT MANUALLY
# Last deployed: {{ ansible_facts['date_time']['iso8601'] }}
# Target host: {{ ansible_facts['hostname'] }}

# ---- Connection Settings ----
listen_addresses = '{{ pg_listen_addresses | default("*") }}'
port = {{ pg_port | default(5432) }}
max_connections = {{ pg_max_connections | default(200) }}

# ---- Memory Settings ----
# shared_buffers: 25% of total RAM
shared_buffers = '{{ pg_shared_buffers | default((ansible_facts['memtotal_mb'] * 0.25) | int | string + "MB") }}'

# effective_cache_size: 75% of total RAM
effective_cache_size = '{{ pg_effective_cache_size | default((ansible_facts['memtotal_mb'] * 0.75) | int | string + "MB") }}'

# work_mem: total RAM / max_connections / 4
work_mem = '{{ pg_work_mem | default(((ansible_facts['memtotal_mb'] / pg_max_connections | default(200)) / 4) | int | string + "MB") }}'

maintenance_work_mem = '{{ pg_maintenance_work_mem | default("256MB") }}'

# ---- WAL Settings ----
wal_level = '{{ pg_wal_level | default("replica") }}'
max_wal_senders = {{ pg_max_wal_senders | default(10) }}
max_replication_slots = {{ pg_max_replication_slots | default(10) }}
wal_keep_size = '{{ pg_wal_keep_size | default("1GB") }}'

{% if pg_archive_mode | default(false) %}
# ---- Archive Settings ----
archive_mode = on
archive_command = '{{ pg_archive_command | default("cp %p /var/lib/pgsql/archive/%f") }}'
{% endif %}

# ---- Logging ----
logging_collector = on
log_directory = '{{ pg_log_directory | default("log") }}'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = {{ pg_log_min_duration | default(1000) }}
log_line_prefix = '%m [%p] %u@%d '
log_statement = '{{ pg_log_statement | default("ddl") }}'

# ---- Replication Settings (standby) ----
{% if pg_role | default("primary") == "standby" %}
hot_standby = on
hot_standby_feedback = on
primary_conninfo = 'host={{ pg_primary_host }} port={{ pg_port | default(5432) }} user=replicator'
{% endif %}

# ---- Performance ----
random_page_cost = {{ pg_random_page_cost | default(1.1) }}
effective_io_concurrency = {{ pg_effective_io_concurrency | default(200) }}
checkpoint_completion_target = 0.9
default_statistics_target = 200

# ---- Autovacuum ----
autovacuum = on
autovacuum_max_workers = {{ pg_autovacuum_max_workers | default(3) }}
autovacuum_naptime = '{{ pg_autovacuum_naptime | default("30s") }}'
autovacuum_vacuum_scale_factor = {{ pg_autovacuum_vacuum_scale_factor | default(0.1) }}
```

### Template Features Used

| Feature | Syntax | What It Does |
|---------|--------|-------------|
| Variable substitution | `{{ pg_port }}` | Inserts the variable value |
| Default values | `{{ pg_port \| default(5432) }}` | Uses 5432 if pg_port is not defined |
| Math expressions | `{{ (ansible_facts['memtotal_mb'] * 0.25) \| int }}` | Calculates 25% of RAM |
| Conditionals | `{% if pg_role == "standby" %}` | Includes block only if condition is true |
| Comments | `{# This is a Jinja2 comment #}` | Not included in output |

---

## Step 3: Template for pg_hba.conf

```bash
vi templates/pg_hba.conf.j2
```

```ini
# PostgreSQL Client Authentication Configuration
# Managed by Ansible - DO NOT EDIT MANUALLY
# Last deployed: {{ ansible_facts['date_time']['iso8601'] }}

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections
host    all             all             ::1/128                 scram-sha-256

{% if pg_hba_entries is defined %}
# Custom entries from Ansible variables
{% for entry in pg_hba_entries %}
{{ entry.type }}    {{ entry.database }}    {{ entry.user }}    {{ entry.address }}    {{ entry.method }}
{% endfor %}
{% endif %}

{% if pg_role | default("primary") == "primary" %}
# Replication connections (primary only)
host    replication     replicator      {{ pg_replication_network | default("10.0.0.0/8") }}    scram-sha-256
{% endif %}
```

---

## Step 4: Group Variables

Group variables apply to all servers in a group. Store them in `group_vars/` with a file named after the group.

```bash
vi group_vars/postgresql.yml
```

```yaml
---
# Variables for ALL PostgreSQL servers
pg_version: 16
pg_port: 5432
pg_max_connections: 200
pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
pg_service: "postgresql-{{ pg_version }}"
pg_log_directory: "log"
pg_log_min_duration: 1000
pg_log_statement: "ddl"
pg_wal_level: "replica"
pg_archive_mode: true
pg_archive_command: "cp %p /var/lib/pgsql/archive/%f"

# pg_hba entries for application access
pg_hba_entries:
  - { type: "host", database: "myapp", user: "app_user", address: "10.0.0.0/8", method: "scram-sha-256" }
  - { type: "host", database: "myapp", user: "readonly", address: "10.0.0.0/8", method: "scram-sha-256" }
```

```bash
vi group_vars/primary.yml
```

```yaml
---
pg_role: primary
pg_replication_network: "10.0.0.0/8"
```

```bash
vi group_vars/standbys.yml
```

```yaml
---
pg_role: standby
pg_primary_host: "10.0.1.10"
```

---

## Step 5: Host Variables

Host variables override group variables for a specific server. Useful when one server needs different settings.

```bash
vi host_vars/localhost.yml
```

```yaml
---
# Override for local development
pg_max_connections: 100
pg_shared_buffers: "256MB"
pg_effective_cache_size: "768MB"
pg_work_mem: "4MB"
pg_role: primary
```

### Variable Precedence Recap

When the same variable is defined in multiple places, Ansible uses this priority (highest wins):

```
Command line (-e "pg_port=5433")
  > Host vars (host_vars/server1.yml)
    > Group vars (group_vars/primary.yml)
      > Group of groups vars (group_vars/postgresql.yml)
        > Playbook vars
          > Role defaults
```

**DBA Analogy:** This is like PostgreSQL's parameter precedence - `ALTER DATABASE SET` overrides `postgresql.conf`, and `ALTER ROLE SET` overrides `ALTER DATABASE SET`.

---

## Step 6: Handlers - Restart Only When Needed

Handlers are special tasks that run only when triggered by a change. This prevents unnecessary PostgreSQL restarts.

**DBA Analogy:** Think of the "pending restart" indicator in `pg_settings`. You only restart PostgreSQL when a parameter actually changed, not every time you check. Handlers work the same way - they fire only when a task reports `changed`.

```bash
vi playbook-configure-pg.yml
```

```yaml
---
- name: Configure PostgreSQL
  hosts: primary
  become: true

  handlers:
    - name: Reload PostgreSQL
      service:
        name: "{{ pg_service }}"
        state: reloaded
      listen: "reload postgresql"

    - name: Restart PostgreSQL
      service:
        name: "{{ pg_service }}"
        state: restarted
      listen: "restart postgresql"

  tasks:
    - name: Deploy postgresql.conf
      template:
        src: templates/postgresql.conf.j2
        dest: "{{ pg_data_dir }}/postgresql.conf"
        owner: postgres
        group: postgres
        mode: '0600'
        backup: true
      notify: restart postgresql

    - name: Deploy pg_hba.conf
      template:
        src: templates/pg_hba.conf.j2
        dest: "{{ pg_data_dir }}/pg_hba.conf"
        owner: postgres
        group: postgres
        mode: '0600'
        backup: true
      notify: reload postgresql

    - name: Verify PostgreSQL is running
      become_user: postgres
      command: "pg_isready -p {{ pg_port }}"
      register: pg_status
      changed_when: false

    - name: Show PostgreSQL status
      debug:
        msg: "PostgreSQL is {{ 'accepting connections' if pg_status.rc == 0 else 'NOT running' }}"
```

### How Handlers Work

1. Task "Deploy postgresql.conf" runs the template module
2. If the generated file differs from the current file on the server, the task reports `changed`
3. The `notify: restart postgresql` triggers the handler
4. Handlers run at the END of all tasks (not immediately)
5. If the template produces an identical file, the task reports `ok` and the handler does NOT fire

**Key detail:** `notify: reload postgresql` vs `notify: restart postgresql`:
- `pg_hba.conf` changes only need a `reload` (SIGHUP)
- `postgresql.conf` changes to parameters like `shared_buffers` need a `restart`

The `backup: true` option creates a timestamped backup of the old file before overwriting. This is your safety net.

---

## Step 7: Ansible Vault for Secrets

Database passwords should never be stored in plain text. Ansible Vault encrypts sensitive data.

**DBA Analogy:** This is like `.pgpass` but encrypted. Instead of a plain text password file, the passwords are AES-256 encrypted and only decrypted at runtime.

### Create an Encrypted Variables File

```bash
ansible-vault create group_vars/vault.yml
```

Ansible will prompt for a vault password, then open an editor. Enter:

```yaml
---
vault_pg_replication_password: "SuperSecretReplPassword123"
vault_pg_app_user_password: "AppPassword456"
vault_pg_readonly_password: "ReadOnly789"
```

Save and exit. The file is now encrypted:

```bash
cat group_vars/vault.yml
```

Expected output (yours will differ):
```
$ANSIBLE_VAULT;1.1;AES256
38616162623464633338663266373463653362346265353135323662633465363862656561613266
...
```

### Reference Vault Variables in Playbooks

In your playbook or variables files, reference vault variables:

```yaml
# In group_vars/postgresql.yml
pg_replication_password: "{{ vault_pg_replication_password }}"
pg_app_user_password: "{{ vault_pg_app_user_password }}"
```

### Running Playbooks with Vault

```bash
# Prompt for vault password
ansible-playbook -i inventory.ini playbook-configure-pg.yml --ask-vault-pass

# Use a password file (better for CI/CD)
echo "my-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
ansible-playbook -i inventory.ini playbook-configure-pg.yml --vault-password-file ~/.vault_pass
```

### Edit Encrypted Files

```bash
ansible-vault edit group_vars/vault.yml
```

### View Encrypted Files

```bash
ansible-vault view group_vars/vault.yml
```

### Change Vault Password

```bash
ansible-vault rekey group_vars/vault.yml
```

---

## Step 8: Roles - Reusable Playbook Packages

Roles organize playbooks into reusable, shareable packages with a standard directory structure.

**DBA Analogy:** A role is like a PostgreSQL extension. `CREATE EXTENSION pg_stat_statements` gives you a complete monitoring toolkit in one command. An Ansible role gives you a complete PostgreSQL installation in one `include_role` call.

### Create a Role

```bash
mkdir -p ~/dba-labs/ansible-pgconfig/roles/postgresql/{tasks,templates,handlers,defaults,vars,files}
```

### Role Directory Structure

```
roles/postgresql/
  tasks/
    main.yml          # Main task file (entry point)
    install.yml        # Installation tasks
    configure.yml      # Configuration tasks
    users.yml          # User management tasks
  templates/
    postgresql.conf.j2 # Config templates
    pg_hba.conf.j2
  handlers/
    main.yml           # Handler definitions
  defaults/
    main.yml           # Default variables (lowest priority)
  vars/
    main.yml           # Role variables (higher priority)
  files/
    pg_custom.sh       # Static files to copy
```

### Role Tasks - main.yml

```bash
vi roles/postgresql/tasks/main.yml
```

```yaml
---
- name: Include installation tasks
  include_tasks: install.yml
  tags: [install]

- name: Include configuration tasks
  include_tasks: configure.yml
  tags: [configure]

- name: Include user management tasks
  include_tasks: users.yml
  tags: [users]
```

### Role Tasks - users.yml

```bash
vi roles/postgresql/tasks/users.yml
```

```yaml
---
- name: Create application database
  become_user: postgres
  community.postgresql.postgresql_db:
    name: "{{ item.name }}"
    encoding: UTF8
    state: present
  loop: "{{ pg_databases }}"

- name: Create application users
  become_user: postgres
  community.postgresql.postgresql_user:
    name: "{{ item.name }}"
    password: "{{ item.password }}"
    state: present
  loop: "{{ pg_users }}"
  no_log: true    # Do not log passwords

- name: Grant privileges
  become_user: postgres
  community.postgresql.postgresql_privs:
    database: "{{ item.database }}"
    roles: "{{ item.user }}"
    type: database
    privs: "{{ item.privs }}"
    state: present
  loop: "{{ pg_grants }}"
```

### Role Defaults

```bash
vi roles/postgresql/defaults/main.yml
```

```yaml
---
pg_version: 16
pg_port: 5432
pg_max_connections: 200
pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
pg_service: "postgresql-{{ pg_version }}"

pg_databases:
  - { name: "myapp" }

pg_users:
  - { name: "app_user", password: "{{ vault_pg_app_user_password | default('changeme') }}" }
  - { name: "readonly", password: "{{ vault_pg_readonly_password | default('changeme') }}" }

pg_grants:
  - { database: "myapp", user: "app_user", privs: "ALL" }
  - { database: "myapp", user: "readonly", privs: "CONNECT" }
```

### Using the Role in a Playbook

```bash
vi playbook-with-role.yml
```

```yaml
---
- name: Deploy PostgreSQL with role
  hosts: primary
  become: true

  roles:
    - role: postgresql
      vars:
        pg_max_connections: 300
```

Run it:

```bash
ansible-playbook -i inventory.ini playbook-with-role.yml --tags configure
```

The `--tags` flag runs only tasks tagged with `configure`, skipping installation and user tasks.

---

## Step 9: Galaxy Roles - Community Packages

Ansible Galaxy is a repository of community-built roles. Instead of writing everything from scratch, you can use pre-built roles.

**DBA Analogy:** Galaxy is like the PGDG repository - community-maintained, well-tested packages ready to install.

### Browse and Install Galaxy Roles

```bash
# Search for PostgreSQL roles
ansible-galaxy search postgresql

# Install a popular PostgreSQL role
ansible-galaxy install geerlingguy.postgresql

# List installed roles
ansible-galaxy list
```

### Using a Galaxy Role

```yaml
---
- name: Deploy PostgreSQL with Galaxy role
  hosts: primary
  become: true

  roles:
    - role: geerlingguy.postgresql
      vars:
        postgresql_version: "16"
        postgresql_databases:
          - name: myapp
        postgresql_users:
          - name: app_user
            password: "{{ vault_pg_app_user_password }}"
            db: myapp
            priv: "ALL"
```

Galaxy roles save time for standard setups, but for complex configurations (Patroni HA, custom replication), you will likely write your own roles.

---

## Step 10: Managing Extensions with Ansible

```yaml
- name: Install pg_stat_statements extension package
  dnf:
    name: "postgresql{{ pg_version }}-contrib"
    state: present

- name: Enable pg_stat_statements in postgresql.conf
  lineinfile:
    path: "{{ pg_data_dir }}/postgresql.conf"
    regexp: "^shared_preload_libraries"
    line: "shared_preload_libraries = 'pg_stat_statements'"
  notify: restart postgresql

- name: Create pg_stat_statements extension
  become_user: postgres
  community.postgresql.postgresql_ext:
    name: pg_stat_statements
    db: myapp
    state: present
```

---

## Step 11: Practical - Complete Configuration Playbook

```bash
vi playbook-full-config.yml
```

```yaml
---
- name: Complete PostgreSQL Configuration
  hosts: primary
  become: true

  vars:
    pg_version: 16
    pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
    pg_service: "postgresql-{{ pg_version }}"
    pg_port: 5432

    pg_databases:
      - { name: "production_app" }
      - { name: "analytics" }

    pg_users:
      - { name: "app_user", password: "{{ vault_pg_app_user_password | default('app_pass') }}" }
      - { name: "analytics_ro", password: "{{ vault_pg_readonly_password | default('ro_pass') }}" }

    pg_extensions:
      - pg_stat_statements
      - pgcrypto

  handlers:
    - name: Restart PostgreSQL
      service:
        name: "{{ pg_service }}"
        state: restarted
      listen: "restart postgresql"

    - name: Reload PostgreSQL
      service:
        name: "{{ pg_service }}"
        state: reloaded
      listen: "reload postgresql"

  tasks:
    - name: Deploy postgresql.conf from template
      template:
        src: templates/postgresql.conf.j2
        dest: "{{ pg_data_dir }}/postgresql.conf"
        owner: postgres
        group: postgres
        mode: '0600'
        backup: true
      notify: restart postgresql

    - name: Deploy pg_hba.conf from template
      template:
        src: templates/pg_hba.conf.j2
        dest: "{{ pg_data_dir }}/pg_hba.conf"
        owner: postgres
        group: postgres
        mode: '0600'
        backup: true
      notify: reload postgresql

    - name: Create databases
      become_user: postgres
      community.postgresql.postgresql_db:
        name: "{{ item.name }}"
        encoding: UTF8
        state: present
      loop: "{{ pg_databases }}"

    - name: Create users
      become_user: postgres
      community.postgresql.postgresql_user:
        name: "{{ item.name }}"
        password: "{{ item.password }}"
        state: present
      loop: "{{ pg_users }}"
      no_log: true

    - name: Install extensions
      become_user: postgres
      community.postgresql.postgresql_ext:
        name: "{{ item }}"
        db: "{{ pg_databases[0].name }}"
        state: present
      loop: "{{ pg_extensions }}"

    - name: Grant app_user full access to production_app
      become_user: postgres
      community.postgresql.postgresql_privs:
        database: production_app
        roles: app_user
        type: database
        privs: ALL
        state: present

    - name: Grant analytics_ro connect to analytics
      become_user: postgres
      community.postgresql.postgresql_privs:
        database: analytics
        roles: analytics_ro
        type: database
        privs: CONNECT
        state: present

    - name: Verify final state
      become_user: postgres
      community.postgresql.postgresql_query:
        db: production_app
        query: "SELECT current_database(), current_user, version()"
      register: pg_info

    - name: Display database info
      debug:
        msg: "Connected to {{ pg_info.query_result[0].current_database }} as {{ pg_info.query_result[0].current_user }}"
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Jinja2 templates | Parameterized config files - one template, many servers |
| postgresql.conf template | Dynamic memory settings calculated from server RAM |
| pg_hba.conf template | Centrally managed authentication rules with loops |
| Handlers | Restart/reload PostgreSQL only when config actually changes |
| Ansible Vault | AES-256 encryption for passwords and secrets |
| Roles | Reusable playbook packages with standard directory structure |
| Galaxy roles | Community pre-built roles (like PGDG for Ansible) |
| Group variables | Shared config per server role (primary, standby) |
| Host variables | Server-specific overrides |
| postgresql_* modules | Native Ansible modules for DB, user, privilege, and extension management |
| no_log | Prevents passwords from appearing in Ansible output |

---

**Next:** BUILD 03 - Deploying HA PostgreSQL with Ansible - Patroni, etcd, PgBouncer across multiple servers.
