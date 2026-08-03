# BUILD 01: Ansible Fundamentals for DBAs

**Module 06: Ansible for Database Configuration**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to use Ansible to automate database server configuration - install PostgreSQL, manage configs, and run commands across multiple servers from a single control machine.

---

## What is Ansible?

**DBA Analogy:** Imagine you have 15,000 databases across 11 datacenters. You need to change a `postgresql.conf` parameter on every server. Today, you SSH into each one, edit the file, and restart PostgreSQL. With Ansible, you write the change once and Ansible applies it to every server simultaneously.

Ansible is an automation tool that:
- Connects to remote servers via SSH (no agent software to install on targets)
- Runs commands and manages configurations across many servers at once
- Uses YAML files ("playbooks") to define what to do
- Is idempotent - running the same playbook twice changes nothing the second time

**Key concept: Agentless architecture.** Unlike Chef or Puppet, Ansible does not require any software installed on the target servers. It uses SSH - the same protocol you already use to connect to your database servers. If you can SSH to a server, Ansible can manage it.

---

## Step 1: Install Ansible

**On your Mac terminal:**

```bash
pip3 install ansible
```

Expected output (yours will differ):
```
Collecting ansible
  Downloading ansible-9.x.x-py3-none-any.whl (46.2 MB)
...
Successfully installed ansible-9.x.x ansible-core-2.16.x
```

Verify the installation:

```bash
ansible --version
```

Expected output (yours will differ):
```
ansible [core 2.16.x]
  config file = None
  configured module search path = ['/Users/you/.ansible/plugins/modules']
  ansible python module location = /opt/homebrew/lib/python3.12/site-packages/ansible
  executable location = /opt/homebrew/bin/ansible
  python version = 3.12.x
```

---

## Step 2: Understand the Inventory File

The inventory file defines which servers Ansible manages. Think of it as a roster of your database servers.

**DBA Analogy:** You probably have a spreadsheet or wiki page listing all your database servers - hostname, IP, role (primary/standby), datacenter. An Ansible inventory is the same thing, but in a format Ansible can read.

Create a project directory:

```bash
mkdir -p ~/dba-labs/ansible-demo
cd ~/dba-labs/ansible-demo
```

Create an inventory file:

```bash
vi inventory.ini
```

```ini
# Ansible Inventory - My PostgreSQL Servers
# Format: hostname_or_ip ansible_connection=type

# For this lab, we use localhost with a local connection
# In production, you would list actual server IPs

[primary]
localhost ansible_connection=local

[standbys]
# standby1 ansible_host=10.0.1.11 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/standby1.pem
# standby2 ansible_host=10.0.1.12 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/standby2.pem

[pgbouncer]
# pgbouncer1 ansible_host=10.0.1.20 ansible_user=ec2-user

# Group of groups: all PostgreSQL servers
[postgresql:children]
primary
standbys

# Variables that apply to all PostgreSQL servers
[postgresql:vars]
pg_version=16
pg_data_dir=/var/lib/pgsql/16/data
pg_port=5432
```

### Inventory Concepts

| Concept | What It Is | DBA Analogy |
|---------|-----------|-------------|
| **Host** | A single server entry | One database server |
| **Group** | A collection of hosts `[primary]` | A cluster role (primaries, standbys) |
| **Group of groups** | `[postgresql:children]` | All database servers regardless of role |
| **Group vars** | `[postgresql:vars]` | Shared parameters across a cluster |
| **Host vars** | Variables per host | Server-specific config (IP, SSH key) |

---

## Step 3: Test Connectivity with Ansible Ping

The `ping` module verifies Ansible can connect to your servers. It is not a network ping (ICMP) - it connects via SSH and confirms Python is available on the target.

**On your Mac terminal, in ~/dba-labs/ansible-demo:**

```bash
ansible all -i inventory.ini -m ping
```

Expected output (yours will differ):
```
localhost | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

- `all` - target all hosts in the inventory
- `-i inventory.ini` - use this inventory file
- `-m ping` - run the ping module

If you get `pong`, Ansible can connect. If you get an error, check your SSH configuration.

---

## Step 4: Ad-Hoc Commands

Ad-hoc commands let you run a single command across all servers without writing a playbook. Think of them as one-liners.

**DBA Analogy:** These are like running a quick `psql -c "SELECT version();"` on every server, but without SSHing to each one individually.

### Check Uptime on All Servers

```bash
ansible all -i inventory.ini -m command -a "uptime"
```

Expected output (yours will differ):
```
localhost | CHANGED | rc=0 >>
10:30  up 5 days,  2:15, 3 users, load averages: 1.23 0.98 0.87
```

### Check Disk Space

```bash
ansible all -i inventory.ini -m command -a "df -h /var/lib/pgsql"
```

### Check PostgreSQL Version (if installed)

```bash
ansible all -i inventory.ini -m command -a "psql --version"
```

### Run as a Specific User

```bash
ansible all -i inventory.ini -m command -a "psql -c 'SELECT version();'" --become --become-user=postgres
```

The `--become` flag uses sudo, and `--become-user=postgres` switches to the postgres OS user.

---

## Step 5: YAML Basics for Ansible

Ansible playbooks are written in YAML. If you have never used YAML, here are the essentials:

```yaml
# This is a comment

# Key-value pair (like a PostgreSQL parameter)
key: value

# List (like multiple values)
fruits:
  - apple
  - banana
  - cherry

# Dictionary (like a configuration block)
database:
  host: localhost
  port: 5432
  name: myapp

# Boolean values
enabled: true
disabled: false

# Multi-line string
description: |
  This is a multi-line
  string in YAML.
```

**DBA Analogy:** YAML is to Ansible what `postgresql.conf` is to PostgreSQL - a human-readable configuration format. Indentation matters (like Python), and it uses colons instead of equals signs.

**Common YAML mistakes:**
- Tabs are not allowed - use spaces only (2 spaces per indent is standard)
- Colons must have a space after them: `key: value` not `key:value`
- Strings with special characters need quotes: `password: "p@ss:word"`

---

## Step 6: Your First Playbook

A playbook is a YAML file that describes a series of tasks to execute on target servers.

**On your Mac terminal, in ~/dba-labs/ansible-demo:**

```bash
vi playbook-hello.yml
```

```yaml
---
# A playbook starts with three dashes
# Each play targets a group of hosts

- name: My first Ansible playbook
  hosts: all                      # Which hosts from inventory to target
  gather_facts: true              # Collect system info before running tasks

  tasks:
    - name: Print a greeting
      debug:
        msg: "Hello from Ansible! Running on {{ ansible_facts['hostname'] }}"

    - name: Show operating system
      debug:
        msg: "OS: {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}"

    - name: Check if PostgreSQL is installed
      command: which psql
      register: psql_check        # Save the output to a variable
      ignore_errors: true         # Do not fail if psql is not found

    - name: Report PostgreSQL status
      debug:
        msg: "PostgreSQL client found at: {{ psql_check.stdout }}"
      when: psql_check.rc == 0    # Only run if the previous command succeeded

    - name: Report PostgreSQL not found
      debug:
        msg: "PostgreSQL client is NOT installed"
      when: psql_check.rc != 0
```

Run the playbook:

```bash
ansible-playbook -i inventory.ini playbook-hello.yml
```

Expected output (yours will differ):
```
PLAY [My first Ansible playbook] *********************************************

TASK [Gathering Facts] ********************************************************
ok: [localhost]

TASK [Print a greeting] *******************************************************
ok: [localhost] => {
    "msg": "Hello from Ansible! Running on MacBook-Pro"
}

TASK [Show operating system] **************************************************
ok: [localhost] => {
    "msg": "OS: MacOSX 14.5"
}

TASK [Check if PostgreSQL is installed] ***************************************
changed: [localhost]

TASK [Report PostgreSQL status] ***********************************************
ok: [localhost] => {
    "msg": "PostgreSQL client found at: /opt/homebrew/bin/psql"
}

TASK [Report PostgreSQL not found] ********************************************
skipping: [localhost]

PLAY RECAP ********************************************************************
localhost                  : ok=5    changed=1    unreachable=0    failed=0    skipped=1
```

### Playbook Anatomy

| Element | Purpose | DBA Analogy |
|---------|---------|-------------|
| `name:` | Human-readable description | A comment in your SQL script |
| `hosts:` | Which servers to target | Which databases to connect to |
| `gather_facts:` | Collect system info | Like querying `pg_settings` before making changes |
| `tasks:` | Ordered list of actions | Steps in a maintenance runbook |
| `register:` | Save command output | Like `\gset` in psql |
| `when:` | Conditional execution | Like `IF` in PL/pgSQL |
| `ignore_errors:` | Continue on failure | Like `IF EXISTS` guards |

---

## Step 7: Understanding Modules

Modules are Ansible's built-in commands. Instead of running raw shell commands, you use modules that handle edge cases and provide idempotency.

### Common Modules for DBAs

| Module | What It Does | Example Use |
|--------|-------------|-------------|
| `command` | Run a command | `command: psql -c "SELECT 1"` |
| `shell` | Run a shell command (supports pipes) | `shell: "ps aux \| grep postgres"` |
| `copy` | Copy a file to the server | Copy pg_hba.conf to remote server |
| `template` | Copy a file with variable substitution | Generate postgresql.conf from template |
| `file` | Manage files/directories | Create /var/lib/pgsql/data |
| `service` | Start/stop/restart services | Restart postgresql |
| `apt` / `yum` / `dnf` | Install packages | Install postgresql-16 |
| `postgresql_db` | Manage PostgreSQL databases | Create/drop databases |
| `postgresql_user` | Manage PostgreSQL users | Create roles, set passwords |
| `postgresql_privs` | Manage PostgreSQL privileges | GRANT/REVOKE |
| `postgresql_query` | Run SQL queries | Execute any SQL |
| `lineinfile` | Edit a single line in a file | Change a pg parameter |
| `blockinfile` | Insert a block of text | Add pg_hba.conf entries |
| `stat` | Check if a file/directory exists | Check if data dir exists |

---

## Step 8: Idempotency - The Core Principle

Idempotency means running the same playbook multiple times produces the same result as running it once.

**DBA Analogy:** `CREATE TABLE IF NOT EXISTS users (...)` is idempotent - you can run it 100 times and it creates the table only once. Ansible works the same way for every operation.

Example:

```yaml
tasks:
  - name: Ensure PostgreSQL data directory exists
    file:
      path: /opt/pgsql/data
      state: directory
      owner: postgres
      group: postgres
      mode: '0700'
```

First run: creates the directory, sets permissions. Output shows `changed`.
Second run: directory already exists with correct permissions. Output shows `ok` (no change).

This is why Ansible is safe to run repeatedly. If your playbook configures a PostgreSQL server, running it again does nothing unless something has drifted from the desired state.

---

## Step 9: Variables and Facts

### Facts - Auto-Collected System Info

When `gather_facts: true`, Ansible collects system information automatically:

```yaml
- name: Show useful facts
  debug:
    msg: |
      Hostname: {{ ansible_facts['hostname'] }}
      OS: {{ ansible_facts['distribution'] }}
      CPUs: {{ ansible_facts['processor_vcpus'] }}
      Memory MB: {{ ansible_facts['memtotal_mb'] }}
      IP: {{ ansible_facts['default_ipv4']['address'] }}
```

**DBA Analogy:** Facts are like `pg_settings` - system properties you can reference in your configuration. Just as you might set `shared_buffers` based on available RAM, you can use `ansible_facts['memtotal_mb']` to calculate PostgreSQL memory parameters dynamically.

**Note:** Older Ansible examples use `ansible_hostname`, `ansible_distribution`, etc. as top-level variables. As of ansible-core 2.21+, use `ansible_facts['hostname']`, `ansible_facts['distribution']`, etc. instead. The old syntax is deprecated and will stop working in ansible-core 2.24.

### Custom Variables

Define variables in the playbook, inventory, or separate files:

```yaml
- name: Configure PostgreSQL
  hosts: primary
  vars:
    pg_version: 16
    pg_port: 5432
    pg_max_connections: 200
    pg_shared_buffers: "{{ (ansible_memtotal_mb * 0.25) | int }}MB"

  tasks:
    - name: Display configuration
      debug:
        msg: "PG {{ pg_version }} on port {{ pg_port }}, shared_buffers={{ pg_shared_buffers }}"
```

### Variable Precedence (simplified)

Variables can be defined in many places. When there is a conflict, Ansible uses this priority (highest wins):

1. Command line (`-e "pg_version=15"`)
2. Task-level vars
3. Play-level vars
4. Host vars (per server)
5. Group vars (per group)
6. Inventory vars
7. Role defaults

---

## Step 10: Practical - PostgreSQL Installation Playbook

This playbook installs PostgreSQL 16 on a CentOS/RHEL server. For this lab, we will write it to target localhost and use `--check` mode (dry run) to see what it would do.

```bash
vi playbook-install-pg.yml
```

```yaml
---
- name: Install and configure PostgreSQL 16
  hosts: primary
  become: true                    # Run tasks as root (sudo)

  vars:
    pg_version: 16
    pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
    pg_service: "postgresql-{{ pg_version }}"
    pg_packages:
      - "postgresql{{ pg_version }}-server"
      - "postgresql{{ pg_version }}-contrib"

  tasks:
    # Step 1: Install the PGDG repository
    - name: Install PGDG repository RPM
      dnf:
        name: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
        state: present
        disable_gpg_check: true

    # Step 2: Disable the built-in PostgreSQL module
    - name: Disable built-in PostgreSQL module
      command: dnf module disable postgresql -y
      register: disable_result
      changed_when: "'Nothing to do' not in disable_result.stdout"

    # Step 3: Install PostgreSQL packages
    - name: Install PostgreSQL {{ pg_version }} packages
      dnf:
        name: "{{ pg_packages }}"
        state: present

    # Step 4: Check if database is initialized
    - name: Check if PostgreSQL data directory exists
      stat:
        path: "{{ pg_data_dir }}/PG_VERSION"
      register: pg_data_check

    # Step 5: Initialize the database
    - name: Initialize PostgreSQL database
      command: "/usr/pgsql-{{ pg_version }}/bin/postgresql-{{ pg_version }}-setup initdb"
      when: not pg_data_check.stat.exists

    # Step 6: Start and enable PostgreSQL
    - name: Start PostgreSQL service
      service:
        name: "{{ pg_service }}"
        state: started
        enabled: true

    # Step 7: Verify PostgreSQL is running
    - name: Check PostgreSQL is accepting connections
      become_user: postgres
      command: "/usr/pgsql-{{ pg_version }}/bin/pg_isready"
      register: pg_ready
      changed_when: false

    - name: Display PostgreSQL status
      debug:
        msg: "PostgreSQL {{ pg_version }} is {{ 'READY' if pg_ready.rc == 0 else 'NOT READY' }}"
```

### Dry Run (Check Mode)

Since we are on a Mac and not a CentOS server, run in check mode to see what Ansible would do:

```bash
ansible-playbook -i inventory.ini playbook-install-pg.yml --check --diff
```

The `--check` flag runs the playbook without making changes. The `--diff` flag shows what would change in files. On a real CentOS server, removing `--check` would execute the actual installation.

---

## Step 11: Running Playbooks Against Real Servers

When you have actual remote servers, your inventory looks like this:

```ini
[primary]
pg-primary-1 ansible_host=10.0.1.10 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/pg-primary.pem

[standbys]
pg-standby-1 ansible_host=10.0.1.11 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/pg-standby.pem
pg-standby-2 ansible_host=10.0.1.12 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/pg-standby.pem
```

And you run:

```bash
# Target all servers
ansible-playbook -i inventory.ini playbook-install-pg.yml

# Target only standbys
ansible-playbook -i inventory.ini playbook-install-pg.yml --limit standbys

# Target a single server
ansible-playbook -i inventory.ini playbook-install-pg.yml --limit pg-standby-1
```

The `--limit` flag restricts which hosts the playbook runs against. This is essential for rolling updates - update standbys first, verify, then update the primary.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Ansible | Automation tool that runs commands on remote servers via SSH |
| Agentless | No software needed on target servers - just SSH access |
| Inventory | A file defining your servers, groups, and connection details |
| Ad-hoc commands | One-liner commands across all servers (`ansible all -m command -a "uptime"`) |
| Playbooks | YAML files defining ordered tasks to execute |
| Modules | Built-in commands (file, service, dnf, postgresql_db, etc.) |
| Idempotency | Running a playbook twice produces the same result as once |
| Facts | Auto-collected system info (RAM, CPU, OS, IP) |
| Variables | Custom parameters for dynamic configuration |
| Check mode | `--check` flag for dry runs without making changes |
| Become | `become: true` to run tasks with sudo privileges |

---

**Next:** BUILD 02 - Managing PostgreSQL Configuration with Ansible - templates, handlers, vault, and roles.
