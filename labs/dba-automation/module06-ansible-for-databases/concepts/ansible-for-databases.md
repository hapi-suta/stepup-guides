# Concepts: Ansible for Database Configuration

**Module 06 Reference Material**

---

## Ansible Architecture Diagram

```
+-------------------+
|  Control Machine  |     Your Mac / CI runner
|  (Ansible)        |     - Has Ansible installed
|  - Playbooks      |     - Has SSH keys
|  - Inventory      |     - Runs ansible-playbook
|  - Roles          |
+--------+----------+
         |
         | SSH (no agent on targets)
         |
    +----+----+----+----+----+
    |         |         |         |
    v         v         v         v
+-------+ +-------+ +-------+ +-------+
| etcd1 | | pg-1  | | pg-2  | | pg-3  |
|       | | (pri) | | (stby)| | (stby)|
+-------+ +-------+ +-------+ +-------+
    Target servers: only need SSH + Python
```

### How Ansible Executes

1. Reads the playbook (YAML)
2. Reads the inventory (which servers)
3. Gathers facts from each target (SSH in, collect system info)
4. For each task, generates a Python script
5. Copies the script to the target via SSH
6. Executes the script on the target
7. Returns the result to the control machine
8. Moves to the next task

No daemon running on targets. No pull mechanism. Push-based via SSH.

---

## Playbook Structure Reference

```yaml
---
# A playbook contains one or more plays
- name: Play description              # Human-readable name
  hosts: target_group                  # Which inventory group
  become: true                         # Use sudo
  become_user: postgres                # sudo as this user
  gather_facts: true                   # Collect system info
  serial: 1                            # How many hosts at once
  max_fail_percentage: 0               # Stop on any failure

  vars:                                # Play-level variables
    pg_version: 16
    pg_port: 5432

  vars_files:                          # Load variables from files
    - group_vars/vault.yml

  pre_tasks:                           # Run before roles
    - name: Verify connectivity
      ping:

  roles:                               # Include roles
    - role: postgresql
      tags: [postgresql]

  tasks:                               # Main task list
    - name: Task description
      module_name:
        parameter1: value1
        parameter2: value2
      register: result                 # Save output
      when: condition                  # Conditional execution
      notify: handler_name             # Trigger handler on change
      loop: "{{ list_variable }}"      # Iterate
      tags: [tag1, tag2]               # Task tags
      ignore_errors: true              # Continue on failure
      no_log: true                     # Hide output (for secrets)
      changed_when: false              # Override change detection
      failed_when: result.rc > 1       # Custom failure condition
      become_user: postgres            # Task-level user override

  post_tasks:                          # Run after tasks
    - name: Final verification
      command: pg_isready

  handlers:                            # Triggered by notify
    - name: handler_name
      service:
        name: postgresql
        state: restarted
```

---

## PostgreSQL Ansible Modules Reference Table

### Core Modules (community.postgresql collection)

Install: `ansible-galaxy collection install community.postgresql`

| Module | Purpose | Example |
|--------|---------|---------|
| `postgresql_db` | Create/drop databases | `postgresql_db: name=myapp state=present` |
| `postgresql_user` | Create/manage roles | `postgresql_user: name=app_user password=secret` |
| `postgresql_privs` | Grant/revoke privileges | `postgresql_privs: db=myapp roles=app_user privs=ALL type=database` |
| `postgresql_query` | Execute SQL | `postgresql_query: db=myapp query="SELECT count(*) FROM users"` |
| `postgresql_ext` | Manage extensions | `postgresql_ext: name=pg_stat_statements db=myapp` |
| `postgresql_schema` | Manage schemas | `postgresql_schema: name=analytics db=myapp owner=analytics_user` |
| `postgresql_tablespace` | Manage tablespaces | `postgresql_tablespace: name=fast_ssd location=/ssd/pgdata` |
| `postgresql_slot` | Manage replication slots | `postgresql_slot: name=standby1 slot_type=physical` |
| `postgresql_set` | Set run-time parameters | `postgresql_set: name=work_mem value=64MB` |
| `postgresql_info` | Gather PostgreSQL info | `postgresql_info: filter=databases,settings` |
| `postgresql_pg_hba` | Manage pg_hba.conf entries | `postgresql_pg_hba: dest=/var/lib/pgsql/16/data/pg_hba.conf contype=host` |
| `postgresql_membership` | Manage role memberships | `postgresql_membership: group=developers target_roles=new_dev` |
| `postgresql_owner` | Change object ownership | `postgresql_owner: db=myapp new_owner=app_user obj_name=users obj_type=table` |
| `postgresql_copy` | Copy data between table/file | `postgresql_copy: db=myapp copy_from=/tmp/data.csv dest=import_table` |
| `postgresql_publication` | Manage logical replication pubs | `postgresql_publication: name=my_pub db=myapp tables=users,orders` |
| `postgresql_subscription` | Manage logical replication subs | `postgresql_subscription: name=my_sub db=myapp connparams=...` |

### Common Parameters for All postgresql_* Modules

| Parameter | Description | Default |
|-----------|-------------|---------|
| `login_host` | PostgreSQL server hostname | localhost |
| `login_port` | PostgreSQL server port | 5432 |
| `login_user` | PostgreSQL login user | postgres |
| `login_password` | PostgreSQL login password | (peer auth) |
| `login_db` | Database to connect to | postgres |
| `login_unix_socket` | Unix socket path | /var/run/postgresql |

### General-Purpose Modules Commonly Used for PostgreSQL

| Module | Purpose | Example Use |
|--------|---------|-------------|
| `template` | Deploy config files with variables | postgresql.conf, pg_hba.conf |
| `copy` | Copy static files | SSL certificates |
| `file` | Manage directories/permissions | Data directories, log directories |
| `lineinfile` | Edit single line in file | Quick postgresql.conf tweak |
| `blockinfile` | Insert block of text | pg_hba.conf entries |
| `service` / `systemd` | Start/stop/restart services | PostgreSQL, Patroni, PgBouncer |
| `dnf` / `apt` | Install packages | PostgreSQL, contrib, extensions |
| `pip` | Install Python packages | Patroni, psycopg2 |
| `command` | Run a command | pg_isready, pg_basebackup |
| `shell` | Run shell command (pipes ok) | `pg_dump \| gzip > backup.gz` |
| `cron` | Manage cron jobs | Backup schedules |
| `uri` | HTTP requests | Patroni REST API checks |
| `wait_for` | Wait for port/file | Wait for PostgreSQL to start |
| `stat` | Check file existence | Check if data dir is initialized |
| `unarchive` | Extract archives | Install etcd from tarball |

---

## Ansible vs Other Configuration Management Tools

| Feature | Ansible | Chef | Puppet | Salt |
|---------|---------|------|--------|------|
| **Architecture** | Agentless (SSH) | Agent + Server | Agent + Server | Agent + Master (or agentless) |
| **Language** | YAML (declarative) | Ruby DSL | Puppet DSL | YAML + Jinja2 |
| **Learning curve** | Low | High | Medium | Medium |
| **Push/Pull** | Push | Pull | Pull | Both |
| **State tracking** | Idempotent (no state file) | Server stores state | Server stores state | Master stores state |
| **Secret management** | Ansible Vault | Chef Vault / data bags | Hiera + eyaml | Pillar |
| **Community** | Huge (most popular) | Large (enterprise) | Large (enterprise) | Medium |
| **PostgreSQL support** | Excellent (community.postgresql) | Custom cookbooks | Custom modules | Custom states |
| **Best for** | Multi-purpose automation | Complex infrastructure | Compliance/policy | Real-time infra |
| **Install overhead** | pip install ansible | Chef server + client | Puppet server + agent | Salt master + minion |

**Why Ansible wins for DBAs:**
- No agent to install on database servers (security teams like this)
- YAML is readable by non-developers
- SSH is already available on every server
- `community.postgresql` collection is comprehensive
- Easy to start - one pip install on your laptop

---

## Inventory File Format Reference

### INI Format

```ini
# Ungrouped hosts
server1 ansible_host=10.0.1.10

# Group definition
[webservers]
web1 ansible_host=10.0.1.20
web2 ansible_host=10.0.1.21

# Group with variables
[databases]
pg1 ansible_host=10.0.1.30 pg_role=primary
pg2 ansible_host=10.0.1.31 pg_role=standby

# Group of groups
[all_servers:children]
webservers
databases

# Group variables
[databases:vars]
ansible_user=ec2-user
pg_version=16
```

### YAML Format

```yaml
all:
  hosts:
    server1:
      ansible_host: 10.0.1.10
  children:
    webservers:
      hosts:
        web1:
          ansible_host: 10.0.1.20
    databases:
      hosts:
        pg1:
          ansible_host: 10.0.1.30
          pg_role: primary
        pg2:
          ansible_host: 10.0.1.31
          pg_role: standby
      vars:
        ansible_user: ec2-user
        pg_version: 16
```

---

## Jinja2 Template Basics for postgresql.conf

### Variable Substitution

```ini
# Simple variable
port = {{ pg_port }}

# Variable with default
max_connections = {{ pg_max_connections | default(200) }}

# Calculated value
shared_buffers = '{{ (ansible_memtotal_mb * 0.25) | int }}MB'
```

### Conditionals

```ini
{% if pg_role == 'primary' %}
archive_mode = on
archive_command = 'cp %p /archive/%f'
{% else %}
# Standby - archive_mode inherited from primary
{% endif %}
```

### Loops

```ini
{% for ext in pg_shared_preload_libraries %}
{% if loop.first %}shared_preload_libraries = '{% endif %}{{ ext }}{% if not loop.last %},{% endif %}{% if loop.last %}'{% endif %}

{% endfor %}
```

### Filters

| Filter | What It Does | Example |
|--------|-------------|---------|
| `default(x)` | Use x if variable undefined | `{{ port \| default(5432) }}` |
| `int` | Convert to integer | `{{ (ram * 0.25) \| int }}` |
| `string` | Convert to string | `{{ port \| string }}` |
| `lower` | Lowercase | `{{ role \| lower }}` |
| `upper` | Uppercase | `{{ name \| upper }}` |
| `join(',')` | Join list with separator | `{{ hosts \| join(',') }}` |
| `regex_replace` | Regex substitution | `{{ val \| regex_replace('old', 'new') }}` |
| `to_json` | Convert to JSON | `{{ dict_var \| to_json }}` |
| `to_yaml` | Convert to YAML | `{{ dict_var \| to_yaml }}` |

---

## Quick Reference: Common Ansible Commands

| Command | Purpose |
|---------|---------|
| `ansible all -i inv -m ping` | Test connectivity to all hosts |
| `ansible-playbook -i inv play.yml` | Run a playbook |
| `ansible-playbook -i inv play.yml --check` | Dry run (no changes) |
| `ansible-playbook -i inv play.yml --diff` | Show file changes |
| `ansible-playbook -i inv play.yml --limit pg1` | Target specific host |
| `ansible-playbook -i inv play.yml --tags configure` | Run only tagged tasks |
| `ansible-playbook -i inv play.yml --ask-vault-pass` | Prompt for vault password |
| `ansible-vault create secrets.yml` | Create encrypted file |
| `ansible-vault edit secrets.yml` | Edit encrypted file |
| `ansible-vault view secrets.yml` | View encrypted file |
| `ansible-vault rekey secrets.yml` | Change vault password |
| `ansible-galaxy install role_name` | Install a Galaxy role |
| `ansible-galaxy collection install name` | Install a collection |
| `ansible-inventory -i inv --graph` | Show inventory tree |
| `ansible-inventory -i inv --list` | Show inventory as JSON |
