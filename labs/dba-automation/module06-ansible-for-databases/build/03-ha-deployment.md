# BUILD 03: Deploying HA PostgreSQL with Ansible

**Module 06: Ansible for Database Configuration**
**Estimated Time: 75-90 minutes**

---

## What You Will Learn

How to use Ansible to deploy a complete high-availability PostgreSQL cluster: etcd + Patroni + PgBouncer across multiple servers, all automated from a single playbook.

---

## The Goal

By the end of this guide, you will have an Ansible project that deploys:

- **3 etcd nodes** - distributed key-value store for leader election
- **3 Patroni nodes** - PostgreSQL HA management (1 primary, 2 standbys)
- **1 PgBouncer node** - connection pooler that follows the primary

This is a production-grade HA stack. Without Ansible, deploying this manually takes hours. With Ansible, it takes minutes.

---

## Step 1: Multi-Server Inventory

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/ansible-ha
cd ~/dba-labs/ansible-ha
mkdir -p group_vars host_vars templates roles
```

Create the inventory:

```bash
vi inventory.ini
```

```ini
# HA PostgreSQL Cluster Inventory

[etcd]
etcd1 ansible_host=10.0.1.10 ansible_user=ec2-user
etcd2 ansible_host=10.0.1.11 ansible_user=ec2-user
etcd3 ansible_host=10.0.1.12 ansible_user=ec2-user

[patroni]
pg-node1 ansible_host=10.0.1.20 ansible_user=ec2-user etcd_name=etcd1
pg-node2 ansible_host=10.0.1.21 ansible_user=ec2-user etcd_name=etcd2
pg-node3 ansible_host=10.0.1.22 ansible_user=ec2-user etcd_name=etcd3

[pgbouncer]
pgb1 ansible_host=10.0.1.30 ansible_user=ec2-user

[primary]
# Managed by Patroni - do not hardcode

[all:vars]
ansible_ssh_private_key_file=~/.ssh/ha-cluster.pem
```

**DBA Analogy:** This inventory is your cluster topology document. Each group represents a role in the HA architecture: etcd for consensus, patroni for PostgreSQL management, pgbouncer for connection pooling.

---

## Step 2: Group Variables

```bash
vi group_vars/all.yml
```

```yaml
---
# Common variables for all hosts
pg_version: 16
pg_port: 5432
pg_data_dir: "/var/lib/pgsql/{{ pg_version }}/data"
pg_bin_dir: "/usr/pgsql-{{ pg_version }}/bin"

# Cluster settings
cluster_name: "ha-cluster"
patroni_scope: "{{ cluster_name }}"

# etcd settings
etcd_version: "3.5.12"
etcd_client_port: 2379
etcd_peer_port: 2380

# Patroni settings
patroni_version: "3.2.2"
patroni_rest_api_port: 8008

# PgBouncer settings
pgbouncer_port: 6432
pgbouncer_max_client_conn: 1000
pgbouncer_default_pool_size: 25

# PostgreSQL superuser (managed by Patroni)
pg_superuser: postgres
pg_replication_user: replicator
```

```bash
vi group_vars/patroni.yml
```

```yaml
---
# Patroni-specific variables
pg_max_connections: 200
pg_shared_buffers: "{{ (ansible_memtotal_mb * 0.25) | int }}MB"
pg_effective_cache_size: "{{ (ansible_memtotal_mb * 0.75) | int }}MB"
pg_work_mem: "8MB"
pg_wal_level: "replica"
pg_max_wal_senders: 10
pg_max_replication_slots: 10
```

---

## Step 3: etcd Cluster Playbook

etcd provides the distributed consensus that Patroni uses for leader election. If the primary PostgreSQL node fails, etcd helps the remaining nodes agree on which standby should be promoted.

```bash
vi templates/etcd.conf.j2
```

```yaml
# etcd configuration - Managed by Ansible
name: '{{ inventory_hostname }}'
data-dir: /var/lib/etcd/{{ inventory_hostname }}.etcd

# Client communication
listen-client-urls: http://{{ ansible_host }}:{{ etcd_client_port }},http://127.0.0.1:{{ etcd_client_port }}
advertise-client-urls: http://{{ ansible_host }}:{{ etcd_client_port }}

# Peer communication
listen-peer-urls: http://{{ ansible_host }}:{{ etcd_peer_port }}
initial-advertise-peer-urls: http://{{ ansible_host }}:{{ etcd_peer_port }}

# Cluster bootstrap
initial-cluster: >-
  {% for host in groups['etcd'] %}
  {{ host }}=http://{{ hostvars[host].ansible_host }}:{{ etcd_peer_port }}{% if not loop.last %},{% endif %}
  {% endfor %}

initial-cluster-token: etcd-{{ cluster_name }}
initial-cluster-state: new
```

Create the etcd playbook:

```bash
vi playbook-etcd.yml
```

```yaml
---
- name: Deploy etcd cluster
  hosts: etcd
  become: true

  tasks:
    - name: Download etcd binary
      unarchive:
        src: "https://github.com/etcd-io/etcd/releases/download/v{{ etcd_version }}/etcd-v{{ etcd_version }}-linux-amd64.tar.gz"
        dest: /usr/local/bin/
        remote_src: true
        extra_opts:
          - --strip-components=1
        creates: /usr/local/bin/etcd

    - name: Create etcd data directory
      file:
        path: "/var/lib/etcd/{{ inventory_hostname }}.etcd"
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Deploy etcd configuration
      template:
        src: templates/etcd.conf.j2
        dest: /etc/etcd/etcd.conf.yml
        mode: '0644'
      notify: restart etcd

    - name: Create etcd systemd service
      copy:
        dest: /etc/systemd/system/etcd.service
        content: |
          [Unit]
          Description=etcd key-value store
          After=network.target

          [Service]
          Type=notify
          ExecStart=/usr/local/bin/etcd --config-file /etc/etcd/etcd.conf.yml
          Restart=always
          RestartSec=5
          LimitNOFILE=65536

          [Install]
          WantedBy=multi-user.target
        mode: '0644'
      notify: restart etcd

    - name: Start and enable etcd
      systemd:
        name: etcd
        state: started
        enabled: true
        daemon_reload: true

    - name: Verify etcd cluster health
      command: /usr/local/bin/etcdctl endpoint health --cluster
      register: etcd_health
      changed_when: false

    - name: Display etcd cluster status
      debug:
        msg: "{{ etcd_health.stdout_lines }}"

  handlers:
    - name: restart etcd
      systemd:
        name: etcd
        state: restarted
```

---

## Step 4: Patroni Configuration Template

```bash
vi templates/patroni.yml.j2
```

```yaml
# Patroni Configuration - Managed by Ansible
scope: {{ patroni_scope }}
name: {{ inventory_hostname }}

restapi:
  listen: {{ ansible_host }}:{{ patroni_rest_api_port }}
  connect_address: {{ ansible_host }}:{{ patroni_rest_api_port }}

etcd3:
  hosts: >-
    {% for host in groups['etcd'] %}
    {{ hostvars[host].ansible_host }}:{{ etcd_client_port }}{% if not loop.last %},{% endif %}
    {% endfor %}

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: {{ pg_max_connections }}
        shared_buffers: '{{ pg_shared_buffers }}'
        effective_cache_size: '{{ pg_effective_cache_size }}'
        work_mem: '{{ pg_work_mem }}'
        wal_level: {{ pg_wal_level }}
        max_wal_senders: {{ pg_max_wal_senders }}
        max_replication_slots: {{ pg_max_replication_slots }}
        hot_standby: 'on'
        logging_collector: 'on'
        log_directory: 'log'
        log_filename: 'postgresql-%Y-%m-%d.log'
        log_min_duration_statement: 1000
        log_line_prefix: '%m [%p] %u@%d '

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication {{ pg_replication_user }} 10.0.0.0/8 scram-sha-256
    - host all all 10.0.0.0/8 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256

  users:
    {{ pg_superuser }}:
      password: '{{ vault_pg_superuser_password | default("postgres") }}'
      options:
        - createrole
        - createdb
    {{ pg_replication_user }}:
      password: '{{ vault_pg_replication_password | default("replicator") }}'
      options:
        - replication

postgresql:
  listen: '{{ ansible_host }}:{{ pg_port }}'
  connect_address: '{{ ansible_host }}:{{ pg_port }}'
  data_dir: {{ pg_data_dir }}
  bin_dir: {{ pg_bin_dir }}
  authentication:
    replication:
      username: {{ pg_replication_user }}
      password: '{{ vault_pg_replication_password | default("replicator") }}'
    superuser:
      username: {{ pg_superuser }}
      password: '{{ vault_pg_superuser_password | default("postgres") }}'

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
```

---

## Step 5: Patroni Deployment Playbook

```bash
vi playbook-patroni.yml
```

```yaml
---
- name: Deploy Patroni HA PostgreSQL
  hosts: patroni
  become: true
  serial: 1                    # Deploy one node at a time (rolling)

  tasks:
    # Install PostgreSQL
    - name: Install PGDG repository
      dnf:
        name: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
        state: present
        disable_gpg_check: true

    - name: Disable built-in PostgreSQL module
      command: dnf module disable postgresql -y
      register: disable_result
      changed_when: "'Nothing to do' not in disable_result.stdout"

    - name: Install PostgreSQL {{ pg_version }}
      dnf:
        name:
          - "postgresql{{ pg_version }}-server"
          - "postgresql{{ pg_version }}-contrib"
        state: present

    # Install Patroni
    - name: Install Python prerequisites
      dnf:
        name:
          - python3-pip
          - python3-devel
          - gcc
        state: present

    - name: Install Patroni via pip
      pip:
        name:
          - "patroni[etcd3]=={{ patroni_version }}"
          - psycopg2-binary
        executable: pip3

    # Configure Patroni
    - name: Create Patroni config directory
      file:
        path: /etc/patroni
        state: directory
        mode: '0755'

    - name: Deploy Patroni configuration
      template:
        src: templates/patroni.yml.j2
        dest: /etc/patroni/patroni.yml
        owner: postgres
        group: postgres
        mode: '0600'
      notify: restart patroni

    - name: Create Patroni systemd service
      copy:
        dest: /etc/systemd/system/patroni.service
        content: |
          [Unit]
          Description=Patroni - PostgreSQL HA
          After=network.target etcd.service
          Wants=network-online.target

          [Service]
          Type=simple
          User=postgres
          Group=postgres
          ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
          ExecReload=/bin/kill -HUP $MAINPID
          KillMode=process
          Restart=on-failure
          RestartSec=10
          TimeoutSec=30

          [Install]
          WantedBy=multi-user.target
        mode: '0644'
      notify: restart patroni

    - name: Start and enable Patroni
      systemd:
        name: patroni
        state: started
        enabled: true
        daemon_reload: true

    # Wait for Patroni to initialize
    - name: Wait for Patroni API to respond
      uri:
        url: "http://{{ ansible_host }}:{{ patroni_rest_api_port }}"
        status_code: [200, 503]
      register: patroni_status
      until: patroni_status.status in [200, 503]
      retries: 30
      delay: 5

    - name: Display Patroni status
      debug:
        msg: "Patroni on {{ inventory_hostname }}: role={{ patroni_status.json.role | default('initializing') }}, state={{ patroni_status.json.state | default('starting') }}"

  handlers:
    - name: restart patroni
      systemd:
        name: patroni
        state: restarted
```

### Key Details

- `serial: 1` - deploys one node at a time. This is critical for HA - you never want all nodes restarting simultaneously.
- The first node bootstraps the cluster (creates the primary). Subsequent nodes join as standbys automatically.
- Patroni handles `initdb`, replication setup, and WAL streaming internally. You do not need to configure streaming replication manually.

---

## Step 6: PgBouncer Configuration

```bash
vi templates/pgbouncer.ini.j2
```

```ini
; PgBouncer Configuration - Managed by Ansible

[databases]
; Connect to the current Patroni primary
; PgBouncer will follow failovers via the Patroni API
* = host={{ groups['patroni'][0] }} port={{ pg_port }} dbname=*

[pgbouncer]
listen_addr = *
listen_port = {{ pgbouncer_port }}
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
admin_users = {{ pg_superuser }}

; Connection pooling
pool_mode = transaction
max_client_conn = {{ pgbouncer_max_client_conn }}
default_pool_size = {{ pgbouncer_default_pool_size }}
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3

; Timeouts
server_connect_timeout = 5
server_idle_timeout = 600
client_idle_timeout = 0
query_timeout = 0
query_wait_timeout = 120

; Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
```

```bash
vi playbook-pgbouncer.yml
```

```yaml
---
- name: Deploy PgBouncer
  hosts: pgbouncer
  become: true

  tasks:
    - name: Install PgBouncer
      dnf:
        name: pgbouncer
        state: present

    - name: Create PgBouncer config directory
      file:
        path: /etc/pgbouncer
        state: directory
        owner: pgbouncer
        group: pgbouncer
        mode: '0755'

    - name: Deploy PgBouncer configuration
      template:
        src: templates/pgbouncer.ini.j2
        dest: /etc/pgbouncer/pgbouncer.ini
        owner: pgbouncer
        group: pgbouncer
        mode: '0640'
      notify: restart pgbouncer

    - name: Deploy PgBouncer userlist
      template:
        src: templates/userlist.txt.j2
        dest: /etc/pgbouncer/userlist.txt
        owner: pgbouncer
        group: pgbouncer
        mode: '0600'
      notify: reload pgbouncer

    - name: Start and enable PgBouncer
      systemd:
        name: pgbouncer
        state: started
        enabled: true

  handlers:
    - name: restart pgbouncer
      systemd:
        name: pgbouncer
        state: restarted

    - name: reload pgbouncer
      systemd:
        name: pgbouncer
        state: reloaded
```

---

## Step 7: Complete HA Deployment - Master Playbook

Create a single playbook that deploys the entire stack:

```bash
vi playbook-ha-deploy.yml
```

```yaml
---
# Master playbook: deploy the complete HA stack
# Run: ansible-playbook -i inventory.ini playbook-ha-deploy.yml

- name: Deploy etcd cluster
  import_playbook: playbook-etcd.yml

- name: Deploy Patroni PostgreSQL cluster
  import_playbook: playbook-patroni.yml

- name: Deploy PgBouncer
  import_playbook: playbook-pgbouncer.yml

- name: Verify HA cluster
  hosts: patroni[0]
  become: true
  become_user: postgres

  tasks:
    - name: Check Patroni cluster status
      command: patronictl -c /etc/patroni/patroni.yml list
      register: cluster_status
      changed_when: false

    - name: Display cluster status
      debug:
        msg: "{{ cluster_status.stdout_lines }}"

    - name: Verify replication
      community.postgresql.postgresql_query:
        db: postgres
        query: |
          SELECT
            client_addr,
            state,
            sent_lsn,
            write_lsn,
            flush_lsn,
            replay_lsn,
            sent_lsn - replay_lsn AS replay_lag_bytes
          FROM pg_stat_replication;
      register: repl_status
      when: "'primary' in cluster_status.stdout"

    - name: Display replication status
      debug:
        msg: "{{ repl_status.query_result }}"
      when: repl_status is defined and repl_status.query_result is defined
```

---

## Step 8: Rolling Updates

When you need to update configuration or upgrade PostgreSQL, do it one node at a time:

```yaml
---
- name: Rolling update - PostgreSQL configuration
  hosts: patroni
  become: true
  serial: 1                    # One node at a time
  max_fail_percentage: 0       # Stop if any node fails

  tasks:
    - name: Check current role
      uri:
        url: "http://{{ ansible_host }}:{{ patroni_rest_api_port }}"
      register: node_info

    - name: Display current role
      debug:
        msg: "{{ inventory_hostname }} is currently {{ node_info.json.role }}"

    - name: Update Patroni configuration
      template:
        src: templates/patroni.yml.j2
        dest: /etc/patroni/patroni.yml
        owner: postgres
        group: postgres
        mode: '0600'
      notify: reload patroni

    - name: Wait for node to be healthy
      uri:
        url: "http://{{ ansible_host }}:{{ patroni_rest_api_port }}"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 30
      delay: 5

  handlers:
    - name: reload patroni
      command: patronictl -c /etc/patroni/patroni.yml reload {{ patroni_scope }}
```

**Key detail:** `serial: 1` ensures Ansible updates one node at a time. It updates standbys first (in inventory order), then the primary. If a standby update fails, the playbook stops before touching the primary.

---

## Step 9: Health Check Playbook

Create a playbook that checks the health of your entire HA cluster:

```bash
vi playbook-health-check.yml
```

```yaml
---
- name: HA Cluster Health Check
  hosts: patroni
  become: true
  become_user: postgres
  gather_facts: true

  tasks:
    - name: Check Patroni API
      uri:
        url: "http://{{ ansible_host }}:{{ patroni_rest_api_port }}"
        status_code: [200, 503]
      register: patroni_api

    - name: Check PostgreSQL is accepting connections
      command: "{{ pg_bin_dir }}/pg_isready -p {{ pg_port }}"
      register: pg_ready
      changed_when: false

    - name: Check disk space
      command: df -h {{ pg_data_dir }}
      register: disk_space
      changed_when: false

    - name: Check replication lag (on standbys)
      community.postgresql.postgresql_query:
        db: postgres
        query: |
          SELECT
            CASE WHEN pg_is_in_recovery()
              THEN extract(epoch FROM now() - pg_last_xact_replay_timestamp())
              ELSE 0
            END AS lag_seconds;
      register: repl_lag
      changed_when: false

    - name: Check connection count
      community.postgresql.postgresql_query:
        db: postgres
        query: |
          SELECT
            count(*) AS total_connections,
            count(*) FILTER (WHERE state = 'active') AS active,
            count(*) FILTER (WHERE state = 'idle') AS idle,
            (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
          FROM pg_stat_activity;
      register: conn_count
      changed_when: false

    - name: Generate health report
      debug:
        msg: |
          === {{ inventory_hostname }} Health Report ===
          Role: {{ patroni_api.json.role }}
          State: {{ patroni_api.json.state }}
          PostgreSQL: {{ 'READY' if pg_ready.rc == 0 else 'NOT READY' }}
          Replication Lag: {{ repl_lag.query_result[0].lag_seconds | default(0) }}s
          Connections: {{ conn_count.query_result[0].active }}/{{ conn_count.query_result[0].max_conn }} active
          Disk: {{ disk_space.stdout_lines[-1] }}
```

Run the health check:

```bash
ansible-playbook -i inventory.ini playbook-health-check.yml
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Multi-server inventory | Groups organize hosts by role (etcd, patroni, pgbouncer) |
| Group variables | Shared configuration per role avoids duplication |
| etcd deployment | Ansible templates generate cluster-aware etcd configs |
| Patroni deployment | One playbook bootstraps primary + standbys automatically |
| PgBouncer deployment | Template-driven config that follows the Patroni primary |
| serial: 1 | Rolling deployments - one node at a time for zero downtime |
| Master playbook | `import_playbook` chains multiple playbooks in order |
| Health check playbook | Query replication lag, connections, disk across all nodes |
| Patroni API | HTTP endpoint for checking node role and health |
| Handler chaining | Config changes trigger reload/restart only when needed |

---

**Next:** BUILD 04 - Ansible + Terraform - provision infrastructure with Terraform, then configure it with Ansible.
