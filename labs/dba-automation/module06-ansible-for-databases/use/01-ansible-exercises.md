# USE: Ansible Exercises

**Module 06: Ansible for Database Configuration**

---

## Exercise 1: PostgreSQL Install Playbook

**Objective:** Write a playbook that installs and initializes PostgreSQL 16 on a target server.

### Requirements

Write `playbook-install.yml` that:

1. Installs the PGDG repository
2. Disables the built-in PostgreSQL module
3. Installs `postgresql16-server` and `postgresql16-contrib`
4. Checks if the data directory is already initialized
5. Runs `initdb` only if the data directory does not exist
6. Starts and enables the PostgreSQL service
7. Verifies PostgreSQL is accepting connections with `pg_isready`

### Constraints

- Every task must have a descriptive `name:`
- Use variables for `pg_version` (so changing to PG 17 requires changing one value)
- The playbook must be idempotent (running twice changes nothing)
- `initdb` must only run if the data directory is empty (use `stat` module + `when` condition)

### Acceptance Criteria

- [ ] Playbook runs without errors on a CentOS Stream 9 server
- [ ] Running the playbook a second time shows all tasks as `ok` (no `changed`)
- [ ] PostgreSQL is running and accepting connections
- [ ] `pg_isready` returns exit code 0

### Testing (Local)

If you do not have a remote server, test with `--check` mode:

```bash
ansible-playbook -i inventory.ini playbook-install.yml --check --diff
```

---

## Exercise 2: Configuration Management

**Objective:** Create Jinja2 templates for `postgresql.conf` and `pg_hba.conf` with dynamic variables.

### Requirements

1. Create `templates/postgresql.conf.j2` that dynamically calculates:
   - `shared_buffers` = 25% of server RAM
   - `effective_cache_size` = 75% of server RAM
   - `work_mem` = RAM / max_connections / 4
   - `maintenance_work_mem` = 256MB (or 512MB if RAM > 16GB)
   - All logging parameters from variables

2. Create `templates/pg_hba.conf.j2` that:
   - Allows local peer auth for postgres
   - Allows scram-sha-256 for application users from a configurable network
   - Allows replication connections from a configurable network (primary only)
   - Uses a loop to generate entries from a `pg_hba_entries` variable

3. Create `group_vars/postgresql.yml` with all variables

4. Write a playbook that deploys both templates with:
   - `backup: true` (creates backup before overwriting)
   - Handler to restart PostgreSQL when `postgresql.conf` changes
   - Handler to reload PostgreSQL when only `pg_hba.conf` changes

### Acceptance Criteria

- [ ] Templates render correctly with `ansible-playbook --check --diff`
- [ ] Memory calculations are correct for your system's RAM
- [ ] pg_hba.conf entries are generated from the loop variable
- [ ] Handlers fire only when files actually change
- [ ] Running twice shows no changes on the second run

### Verification

Generate the rendered templates locally:

```bash
ansible localhost -m template -a "src=templates/postgresql.conf.j2 dest=/tmp/rendered-postgresql.conf" -e "@group_vars/postgresql.yml"
cat /tmp/rendered-postgresql.conf
```

---

## Exercise 3: User and Database Setup

**Objective:** Create databases, users, and grant permissions using Ansible's `postgresql_*` modules.

### Requirements

Write a playbook that creates:

**Databases:**
- `production_app` (encoding: UTF8)
- `analytics` (encoding: UTF8)
- `staging_app` (encoding: UTF8)

**Users:**
- `app_user` - full access to `production_app`
- `analytics_ro` - read-only access to `analytics`
- `staging_user` - full access to `staging_app`
- `backup_user` - replication role for pg_basebackup

**Extensions (in production_app):**
- `pg_stat_statements`
- `pgcrypto`
- `uuid-ossp`

### Constraints

- Use `loop` to iterate over databases, users, and extensions (no copy-paste)
- Store passwords in an Ansible Vault encrypted file
- Use `no_log: true` on tasks that handle passwords
- Use variables for all database names, usernames, and privileges

### Acceptance Criteria

- [ ] All databases exist with UTF8 encoding
- [ ] All users exist with correct passwords
- [ ] Privileges are correctly assigned
- [ ] Extensions are installed in production_app
- [ ] backup_user has the REPLICATION attribute
- [ ] No passwords appear in Ansible output (no_log)
- [ ] Playbook is idempotent

### Verification

```sql
-- Run on the target server
\l          -- List all databases
\du         -- List all users and their attributes
\dx         -- List extensions in production_app

-- Check privileges
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public';
```

---

## Exercise 4: Replication Playbook

**Objective:** Set up PostgreSQL streaming replication across 2 servers using Ansible.

### Requirements

Write a playbook that configures:

**On the primary:**
1. Create a replication user
2. Configure `postgresql.conf` for replication (wal_level, max_wal_senders, etc.)
3. Add replication entry to `pg_hba.conf`
4. Restart PostgreSQL

**On the standby:**
1. Stop PostgreSQL
2. Remove existing data directory
3. Run `pg_basebackup` from the primary
4. Configure `postgresql.conf` with `primary_conninfo`
5. Create `standby.signal` file
6. Start PostgreSQL

### Inventory

```ini
[primary]
pg-primary ansible_host=PRIMARY_IP

[standbys]
pg-standby ansible_host=STANDBY_IP

[postgresql:children]
primary
standbys
```

### Constraints

- Primary and standby tasks must be in the SAME playbook (two plays)
- Use `when: pg_role == 'primary'` and `when: pg_role == 'standby'` conditions
- The replication password must be in Ansible Vault
- Include a verification task that checks `pg_stat_replication` on the primary

### Acceptance Criteria

- [ ] Primary is in "streaming" state with standby connected
- [ ] Standby is in recovery mode (`SELECT pg_is_in_recovery();` returns true)
- [ ] Replication lag is under 1 second
- [ ] WAL is being shipped and applied
- [ ] Playbook is documented with comments explaining each step

### Verification Tasks (include in playbook)

```yaml
- name: Check replication on primary
  postgresql_query:
    db: postgres
    query: |
      SELECT client_addr, state, sent_lsn, replay_lsn
      FROM pg_stat_replication;
  register: repl_status

- name: Check standby status
  postgresql_query:
    db: postgres
    query: "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();"
  register: standby_status
```

---

## Exercise 5: Health Check Playbook

**Objective:** Write a playbook that queries all PostgreSQL servers and generates a health report.

### Requirements

Write `playbook-health-check.yml` that collects from every PostgreSQL server:

1. **Server info:** hostname, IP, PostgreSQL version, uptime
2. **Replication status:** role (primary/standby), replication lag in seconds
3. **Connections:** active, idle, idle_in_transaction, total vs max_connections
4. **Disk space:** data directory usage, WAL directory usage, percentage used
5. **Performance:** current TPS (from pg_stat_database), cache hit ratio

### Output Format

The playbook should output a formatted report for each server:

```
=== pg-primary (10.0.1.20) ===
PostgreSQL: 16.3
Role: primary
Uptime: 15 days
Connections: 45/200 (22.5%)
  Active: 12 | Idle: 30 | IdleTxn: 3
Disk: 45GB / 100GB (45%)
Replication: 2 standbys connected
Cache Hit Ratio: 99.2%
TPS (last 5 min): 1,250

=== pg-standby (10.0.1.21) ===
PostgreSQL: 16.3
Role: standby
Replication Lag: 0.3 seconds
Connections: 20/200 (10%)
Disk: 44GB / 100GB (44%)
```

### Constraints

- Use `postgresql_query` module for all database queries (not `command` with psql)
- Use `register` and `debug` for formatted output
- The playbook must work against both primary and standby servers
- Include a summary task that flags any warnings:
  - Connections > 80% of max
  - Replication lag > 10 seconds
  - Disk > 80%
  - Cache hit ratio < 95%

### Acceptance Criteria

- [ ] Runs against all PostgreSQL hosts in inventory
- [ ] Collects all 5 categories of information
- [ ] Formats output in human-readable format
- [ ] Flags warnings for threshold breaches
- [ ] Does not modify any server state (all tasks should be `changed_when: false`)

### Bonus

Add a task that writes the health report to a local file:

```yaml
- name: Write health report to file
  local_action:
    module: copy
    content: "{{ health_report }}"
    dest: "/tmp/pg-health-{{ ansible_date_time.date }}.txt"
```
