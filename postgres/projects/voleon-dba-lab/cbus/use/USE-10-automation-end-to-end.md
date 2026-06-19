# USE Exercise 10: End-to-End Automation Workflows

| | |
|---|---|
| **Time** | 100 minutes total (five exercises) |
| **Servers** | pg-ops (34.228.32.17), pg-primary (100.26.54.122), pg-replica (54.144.241.128), pg-container (34.228.73.232) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Lukasz Mucha - Senior DevOps Engineer, The Voleon Group |

## What You'll Practice

- Running Ansible rolling config changes with `serial: 1` and `--check` mode
- Detecting and remediating configuration drift with Ansible
- Reviewing Terraform plan output and making approve/reject decisions
- Running Jenkins pipelines and diagnosing failures
- Building an end-to-end workflow: plan, automate, deploy, verify

## Prerequisites

- Completed BUILD-07 (Ansible), BUILD-08 (Prometheus/Grafana), BUILD-12 (Terraform)
- Ansible inventory at `~/ansible/inventory/hosts.yml` on pg-ops
- Jenkins running on pg-container:8080 in Docker
- PostgreSQL 17 running on pg-primary and pg-replica

---

## Exercise 1: Ansible Rolling Config Change (20 min)

**Scenario:** A Voleon quant researcher reports that complex portfolio queries are running out of memory during sort operations. The team decides to increase `work_mem` from 4MB to 8MB across all PG servers.

### Step 1.1: Check the Current Value

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

```bash
ansible pg_servers -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -t -c 'SHOW work_mem;'" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 4MB

pg-replica | CHANGED | rc=0 >>
 4MB
```

Both servers show `4MB`. This is your baseline.

### Step 1.2: Dry Run with --check Mode

Before making any changes, see what Ansible would do without actually doing it.

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/update-pg-param.yml \
  -e "param=work_mem value=8MB" \
  --check --diff
```

The `--check` flag tells Ansible to simulate the run. The `--diff` flag shows what file changes would be made. No files are actually modified.

Expected output (yours will differ):

```
TASK [Update parameter in postgresql.conf] *************************************
--- before: /var/lib/pgsql/17/data/postgresql.conf
+++ after: /var/lib/pgsql/17/data/postgresql.conf
@@ -1,1 +1,1 @@
-work_mem = '4MB'
+work_mem = '8MB'

changed: [pg-replica]

--- before: /var/lib/pgsql/17/data/postgresql.conf
+++ after: /var/lib/pgsql/17/data/postgresql.conf
@@ -1,1 +1,1 @@
-work_mem = '4MB'
+work_mem = '8MB'

changed: [pg-primary]
```

The diff shows exactly what will change in each file. Review this carefully before proceeding.

### Step 1.3: Apply the Change for Real

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/update-pg-param.yml \
  -e "param=work_mem value=8MB"
```

Expected output (yours will differ):

```
PLAY [Update PostgreSQL parameter] ********************************************

TASK [Pre-check - get current value] ******************************************
ok: [pg-replica]

TASK [Display current value] **************************************************
ok: [pg-replica] => {
    "msg": "pg-replica: work_mem =  4MB (changing to 8MB)"
}

TASK [Update parameter in postgresql.conf] ************************************
changed: [pg-replica]

TASK [Reload PostgreSQL] ******************************************************
changed: [pg-replica]

TASK [Post-check - verify new value] ******************************************
ok: [pg-replica] => {
    "msg": "pg-replica: work_mem changed from  4MB to  8MB"
}

PLAY [Update PostgreSQL parameter] ********************************************
... (same for pg-primary) ...

PLAY RECAP ********************************************************************
pg-replica                 : ok=7    changed=2    unreachable=0    failed=0
pg-primary                 : ok=7    changed=2    unreachable=0    failed=0
```

Notice the order: `pg-replica` first, then `pg-primary`. The playbook uses `serial: 1` with `order: reverse_sorted`, so it updates the replica before the primary. This is the safe pattern - if something breaks, it breaks on the replica first and the primary stays healthy.

### Step 1.4: Verify Replication Is Still Working

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/check-pg-status.yml
```

Confirm both servers are OK and replication is streaming. If the replication check passes, the rolling change was successful.

### Step 1.5: Verify the New Value on Both Servers

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -t -c 'SHOW work_mem;'" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 8MB

pg-replica | CHANGED | rc=0 >>
 8MB
```

Both servers now show `8MB`.

---

## Exercise 2: Ansible Drift Detection (15 min)

**Scenario:** Someone logged into pg-primary and ran `ALTER SYSTEM SET log_min_duration_statement = 500;` followed by `SELECT pg_reload_conf();`. This changed a setting outside of Ansible. Your job is to detect and remediate the drift.

### Step 2.1: Inject the Drift

SSH into pg-primary to make the manual change. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
psql -d quantdb -c "ALTER SYSTEM SET log_min_duration_statement = 500;"
```

```bash
psql -d quantdb -c "SELECT pg_reload_conf();"
```

Verify the change took effect:

```bash
psql -d quantdb -t -c "SHOW log_min_duration_statement;"
```

Expected output (yours will differ):

```
 500ms
```

```bash
exit
```

```bash
exit
```

Now the primary has a different `log_min_duration_statement` than what Ansible expects.

### Step 2.2: Run the Drift Detection Playbook

Go back to pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

```bash
ansible-playbook -i inventory/hosts.yml playbooks/pg-config-check.yml
```

Expected output (yours will differ):

```
TASK [Compare expected vs actual] *********************************************
ok: [pg-primary] => (item=shared_buffers) => {
    "msg": "shared_buffers: expected=512MB, actual=512MB MATCH"
}
ok: [pg-primary] => (item=log_statement) => {
    "msg": "log_statement: expected=ddl, actual=ddl MATCH"
}
...
ok: [pg-replica] => (item=shared_buffers) => {
    "msg": "shared_buffers: expected=512MB, actual=512MB MATCH"
}
```

The playbook checks a predefined list of parameters. If `log_min_duration_statement` is in the list, you will see `DRIFT DETECTED` next to it on pg-primary.

### Step 2.3: Remediate the Drift

Reset the parameter to the desired value using the update-pg-param playbook. Since this is a parameter set via `ALTER SYSTEM`, we need to clear the override first.

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_primary -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -c \"ALTER SYSTEM RESET log_min_duration_statement;\"" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
ALTER SYSTEM
```

Now reload the config to apply the reset:

```bash
ansible pg_primary -i inventory/hosts.yml -m systemd \
  -a "name=postgresql-17 state=reloaded" \
  --become
```

### Step 2.4: Verify the Drift Is Gone

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_primary -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -t -c 'SHOW log_min_duration_statement;'" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 -1
```

The value is back to `-1` (disabled), which is the default. The drift is remediated.

### Key Takeaway

Configuration drift happens when someone makes manual changes on a server. Ansible's value is that it detects and remediates drift automatically. In an interview, explain that you run config check playbooks on a schedule (via cron or Jenkins) to catch drift early.

---

## Exercise 3: Terraform Plan Review (15 min)

**Scenario:** A colleague sends you a Terraform plan for review. They want to resize the pg-replica instance from `t3.medium` to `t3.large` and add a new 200GB EBS volume for WAL archives. Review the plan and decide: approve or reject?

### Step 3.1: Read the Plan Output

Here is the plan output (read it carefully):

```
Terraform will perform the following actions:

  # aws_instance.node["replica"] must be replaced
-/+ resource "aws_instance" "node" {
      ~ instance_type = "t3.medium" -> "t3.large" # forces replacement
      ~ id            = "i-0b66c57b5dbab1d7b" -> (known after apply)
      ~ public_ip     = "54.144.241.128" -> (known after apply)
      ~ private_ip    = "172.31.22.69" -> (known after apply)
        tags          = {
            "Name" = "voleon-lab-pg-replica"
        }
    }

  # aws_ebs_volume.wal_archive will be created
  + resource "aws_ebs_volume" "wal_archive" {
      + availability_zone = "us-east-1a"
      + size              = 200
      + type              = "gp3"
      + iops              = 3000
      + throughput        = 125
      + tags              = {
          + "Name" = "voleon-lab-wal-archive"
        }
    }

  # aws_volume_attachment.wal_archive will be created
  + resource "aws_volume_attachment" "wal_archive" {
      + device_name = "/dev/xvdf"
      + instance_id = (known after apply)
      + volume_id   = (known after apply)
    }

Plan: 2 to add, 0 to change, 1 to destroy.
```

### Step 3.2: Identify the Risks

Walk through the plan and answer these questions:

1. **What will be created?** Two resources - an EBS volume and a volume attachment. These are additive, low risk.

2. **What will be destroyed?** The replica instance (`-/+` means destroy and recreate). This is HIGH risk.

3. **Why is the instance being replaced?** Changing `instance_type` forces replacement in many cases. The plan says `# forces replacement` next to the change.

4. **What are the consequences?**
   - The replica's public IP will change (`known after apply`)
   - The replica's private IP will change
   - All data on the replica's root volume will be lost
   - Replication will break until the new replica is rebuilt
   - Ansible inventory will need updating with the new IP
   - Any pg_hba.conf rules referencing the old IP will break

### Step 3.3: Your Decision

**REJECT this plan.** Here is why:

- Changing instance type does not always require replacement. With modern AWS, you can stop the instance, change the type, and start it again - preserving the IP and data.
- The better approach: stop the instance manually (or with Terraform's `aws_instance` `instance_type` change combined with a stop/start lifecycle), change the type, and start it.
- The EBS volume creation is fine and can be approved separately.

In an interview, explaining why you would reject a plan shows deeper understanding than blindly approving everything.

---

## Exercise 4: Jenkins Pipeline Run (20 min)

**Scenario:** You have a Jenkins health-check pipeline that verifies PostgreSQL status across the cluster. Run it, observe the output, then trigger a failure and watch the pipeline catch it.

### Step 4.1: Access Jenkins

Open your browser and navigate to:

```
http://34.228.73.232:8080
```

Log in with the Jenkins admin credentials (set during BUILD-06).

### Step 4.2: Find and Run the Health Check Pipeline

In the Jenkins dashboard:

1. Click on the **pg-health-check** pipeline (if it exists)
2. Click **Build Now** on the left sidebar
3. Click on the build number (e.g., #1) that appears
4. Click **Console Output** to see the live output

Expected behavior:

```
[Pipeline] stage (Check Primary)
+ ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122 ...
PostgreSQL is running on pg-primary
[Pipeline] stage (Check Replica)
+ ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519 ec2-user@54.144.241.128 ...
PostgreSQL is running on pg-replica
[Pipeline] stage (Check Replication)
...streaming...
SUCCESS
```

### Step 4.3: Inject a Failure

SSH into pg-replica and stop PostgreSQL.

On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.144.241.128
```

On **pg-replica**, as **ec2-user**:

```bash
sudo systemctl stop postgresql-17
```

Verify it is stopped:

```bash
sudo systemctl status postgresql-17 | head -5
```

Expected output (yours will differ):

```
   postgresql-17.service - PostgreSQL 17 database server
   Loaded: loaded
   Active: inactive (dead)
```

### Step 4.4: Re-Run the Pipeline

Go back to Jenkins in your browser:

1. Click **Build Now** again
2. Watch the Console Output

Expected behavior:

```
[Pipeline] stage (Check Replica)
+ ssh ... ec2-user@54.144.241.128 ...
PostgreSQL is NOT running on pg-replica
FAILURE
```

The pipeline should fail at the replica check stage. This is the expected behavior - the pipeline catches the outage.

### Step 4.5: Fix and Re-Run

On **pg-replica**, as **ec2-user**:

```bash
sudo systemctl start postgresql-17
```

Verify it started:

```bash
sudo systemctl status postgresql-17 | head -5
```

Expected output (yours will differ):

```
   Active: active (running)
```

```bash
exit
```

Go back to Jenkins and click **Build Now** one more time. The pipeline should pass again.

### Key Takeaway

Jenkins pipelines automate health checks that you would otherwise run manually. In production at Voleon, these run on a schedule (every 5 minutes) and alert the team via Slack or PagerDuty when they fail.

---

## Exercise 5: Full Workflow - New Parameter Deployment (30 min)

**Scenario:** A request comes in from the research team: "Enable `pg_stat_statements` on all PostgreSQL servers so we can track query performance." This requires changes at multiple levels - a perfect end-to-end automation exercise.

### Step 5.1: Plan the Changes

Before writing any automation, plan what needs to happen:

1. **shared_preload_libraries** must include `pg_stat_statements` - this requires a PostgreSQL **restart** (not just a reload)
2. **CREATE EXTENSION pg_stat_statements** must run in the `quantdb` database
3. The change must be applied to the replica first, then the primary (rolling)
4. Replication must be verified after each server is restarted

### Step 5.2: Check Current State

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

On **pg-ops**, as **ec2-user**:

```bash
cd ~/ansible
```

Check if pg_stat_statements is already loaded:

```bash
ansible pg_servers -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -t -c \"SHOW shared_preload_libraries;\"" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 (empty or some other libraries)

pg-replica | CHANGED | rc=0 >>
 (empty or some other libraries)
```

If `pg_stat_statements` is not in the output, we need to add it.

### Step 5.3: Write the Playbook

On **pg-ops**, as **ec2-user**:

```bash
vi ~/ansible/playbooks/enable-pg-stat-statements.yml
```

Press `i` to enter insert mode and type:

```yaml
---
# enable-pg-stat-statements.yml - Enable pg_stat_statements on all PG servers
# Requires restart (shared_preload_libraries change), so we do rolling restart
- name: Enable pg_stat_statements
  hosts: pg_servers
  become: true
  serial: 1
  order: reverse_sorted

  tasks:
    - name: Pre-check - verify PostgreSQL is running
      command: sudo -u postgres {{ pg_bin }}/pg_isready -p 5432
      register: pre_check
      changed_when: false

    - name: Get current shared_preload_libraries
      command: >
        sudo -u postgres {{ pg_bin }}/psql -t -c
        "SHOW shared_preload_libraries;"
      register: current_libs
      changed_when: false

    - name: Display current libraries
      debug:
        msg: "{{ inventory_hostname }}: shared_preload_libraries = {{ current_libs.stdout | trim }}"

    - name: Add pg_stat_statements to shared_preload_libraries
      lineinfile:
        path: "{{ pg_data }}/postgresql.conf"
        regexp: "^#?shared_preload_libraries\\s*="
        line: "shared_preload_libraries = 'pg_stat_statements'"
        owner: postgres
        group: postgres
      when: "'pg_stat_statements' not in current_libs.stdout"

    - name: Restart PostgreSQL (required for shared_preload_libraries)
      systemd:
        name: postgresql-17
        state: restarted
      when: "'pg_stat_statements' not in current_libs.stdout"

    - name: Wait for PostgreSQL to be ready after restart
      command: sudo -u postgres {{ pg_bin }}/pg_isready -p 5432
      retries: 10
      delay: 3
      register: ready_check
      until: ready_check.rc == 0
      changed_when: false

    - name: Create pg_stat_statements extension in quantdb
      command: >
        sudo -u postgres {{ pg_bin }}/psql -d {{ pg_db }} -c
        "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
      register: create_ext
      changed_when: "'CREATE EXTENSION' in create_ext.stdout"

    - name: Verify extension is loaded
      command: >
        sudo -u postgres {{ pg_bin }}/psql -d {{ pg_db }} -t -c
        "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
      register: ext_check
      changed_when: false

    - name: Display extension status
      debug:
        msg: "{{ inventory_hostname }}: {{ ext_check.stdout | trim }}"

    - name: Verify replication still working (primary only)
      command: >
        sudo -u postgres {{ pg_bin }}/psql -t -c
        "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';"
      register: repl_check
      changed_when: false
      when: pg_role == 'primary'

    - name: Display replication status (primary only)
      debug:
        msg: "Streaming replicas: {{ repl_check.stdout | trim }}"
      when: pg_role == 'primary'
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 5.4: Dry Run First

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/enable-pg-stat-statements.yml --check
```

Review the output. The `--check` flag simulates the run without making changes. You should see "changed" next to the lineinfile and restart tasks (indicating they would run).

### Step 5.5: Apply for Real

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/enable-pg-stat-statements.yml
```

Expected output (yours will differ):

```
PLAY [Enable pg_stat_statements] **********************************************

TASK [Pre-check - verify PostgreSQL is running] *******************************
ok: [pg-replica]

TASK [Add pg_stat_statements to shared_preload_libraries] *********************
changed: [pg-replica]

TASK [Restart PostgreSQL (required for shared_preload_libraries)] *************
changed: [pg-replica]

TASK [Create pg_stat_statements extension in quantdb] *************************
changed: [pg-replica]

TASK [Verify extension is loaded] *********************************************
ok: [pg-replica] => {
    "msg": "pg-replica: pg_stat_statements | 1.11"
}

... (then pg-primary) ...

PLAY RECAP ********************************************************************
pg-replica                 : ok=10   changed=3   unreachable=0   failed=0
pg-primary                 : ok=12   changed=3   unreachable=0   failed=0
```

### Step 5.6: Verify on Both Servers

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_servers -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -d quantdb -t -c \"SELECT count(*) FROM pg_stat_statements;\"" \
  --become
```

Expected output (yours will differ):

```
pg-primary | CHANGED | rc=0 >>
 42

pg-replica | CHANGED | rc=0 >>
 15
```

If you get a number (even 0), the extension is working. The primary typically has more entries because it handles writes.

### Step 5.7: Query pg_stat_statements

Let's run a useful query to see the top queries by total time.

On **pg-ops**, as **ec2-user**:

```bash
ansible pg_primary -i inventory/hosts.yml -m command \
  -a "sudo -u postgres /usr/pgsql-17/bin/psql -d quantdb -c \"SELECT LEFT(query, 60) AS query, calls, round(total_exec_time::numeric, 2) AS total_ms, round(mean_exec_time::numeric, 2) AS mean_ms FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 5;\"" \
  --become
```

Expected output (yours will differ):

```
           query            | calls | total_ms | mean_ms
----------------------------+-------+----------+---------
 SELECT * FROM trades WHERE |    42 |   123.45 |    2.94
 INSERT INTO signals        |   100 |    89.21 |    0.89
 ...
```

This is exactly the kind of performance data the Voleon research team wanted.

---

## Summary

You have practiced five core automation workflows:

| Exercise | Skill | Interview Relevance |
|---|---|---|
| 1. Rolling Config Change | Ansible serial execution, --check mode | "How do you make config changes without downtime?" |
| 2. Drift Detection | Detecting and remediating manual changes | "How do you prevent configuration drift?" |
| 3. Terraform Plan Review | Reading plan output, identifying risks | "Walk me through reviewing a Terraform plan" |
| 4. Jenkins Pipeline | CI/CD for database operations | "How do you automate health checks?" |
| 5. Full Workflow | End-to-end: plan, automate, deploy, verify | "Describe your change management process" |

Each of these maps directly to questions Lukasz is likely to ask about automation maturity and operational discipline.
