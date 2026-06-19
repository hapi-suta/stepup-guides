# Build Guide 10: Jenkins CI/CD Pipelines for Database Operations

| | |
|---|---|
| **Time** | 90 minutes |
| **Servers** | pg-container (34.228.73.232) - Jenkins at :8080; pg-primary (100.26.54.122); pg-replica (54.144.241.128); pg-ops (34.228.32.17) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Mark Selby - Senior Systems Infrastructure Engineer, The Voleon Group |

## Why This Matters

At The Voleon Group, infrastructure changes - including database migrations, config pushes, and backup verification - flow through automated pipelines. Mark Selby will expect you to understand how CI/CD tools like Jenkins orchestrate database operations safely, with approval gates, rollback plans, and audit trails. A DBA who can build and maintain these pipelines is far more valuable than one who runs ad-hoc commands on production servers.

## What You'll Learn

- Why Jenkins is used for database operations and how it compares to alternatives
- How to access and navigate the Jenkins UI
- How to build a pipeline that checks PostgreSQL health across multiple servers
- How to create a database migration pipeline with backup, validation, and rollback
- How to integrate Ansible playbooks into Jenkins pipelines
- How to schedule recurring jobs and configure notifications
- Jenkins best practices for production database work

## Prerequisites

- Completed BUILD-01 through BUILD-09
- PostgreSQL 17 running on pg-primary and pg-replica with the `quantdb` database
- pgBackRest configured on pg-replica (BUILD-04)
- Ansible installed on pg-ops (BUILD-07)
- Jenkins running in Docker on pg-container (container name: `voleon-jenkins`, port 8080)
- SSH key at `~/.ssh/id_ed25519` with access to all four servers

---

## Section 1: Why Jenkins for Database Operations

### CI/CD for Databases - The Problem It Solves

Without automation, database changes follow a risky pattern: a DBA SSHs into a production server, types SQL commands, and hopes nothing goes wrong. There is no audit trail, no rollback plan, and no way to reproduce the exact steps later.

A CI/CD pipeline for databases solves this by turning every change into a repeatable, auditable process:

- **Database migrations** - Schema changes (CREATE TABLE, ALTER COLUMN) go through a pipeline that backs up first, applies the change, validates, and rolls back on failure.
- **Config changes** - A `postgresql.conf` update goes through lint, dry-run, apply, and verify stages instead of someone editing a file by hand.
- **Backup verification** - A nightly pipeline restores the latest backup to a test server and runs validation queries. You find out at 2 AM if your backups are broken - not during a disaster.

### Jenkins vs GitHub Actions vs Manual Scripts

| Approach | Best For | Downsides |
|---|---|---|
| **Jenkins** | Self-hosted, complex workflows, approval gates, integrates with on-prem infrastructure | Requires server to run, more setup |
| **GitHub Actions** | Cloud-native teams, simple CI/CD, tight GitHub integration | Limited for on-prem, less control over runners |
| **Manual scripts** | One-off tasks, emergencies | No audit trail, no approval gates, error-prone |

Voleon uses Jenkins because their infrastructure spans on-prem and cloud. Jenkins runs inside their network, can SSH directly to database servers, and supports multi-stage pipelines with human approval gates - critical when a wrong migration could corrupt trading data.

### How Jenkins Fits Into Voleon's IaC Pipeline

The typical flow looks like this:

1. Engineer commits a change (Terraform module, Ansible playbook, SQL migration) to Git
2. Jenkins detects the commit (webhook or poll)
3. Pipeline runs: lint - dry-run - approval gate - apply - verify
4. Results are logged, artifacts are saved, notifications are sent
5. If anything fails, the pipeline stops and alerts the team

This is Infrastructure as Code (IaC) - every change is versioned, reviewed, and applied through automation.

---

## Section 2: Access Jenkins and Initial Setup

Jenkins is already running in a Docker container on pg-container. In this section you will log in and complete the initial setup wizard.

### Step 2.1: Verify Jenkins Is Running

On **pg-container**, as **ec2-user**:

```bash
docker ps --filter name=voleon-jenkins
```

`docker ps` lists running containers. The `--filter` flag narrows the list to containers matching the name.

Expected output (yours will differ):

```
CONTAINER ID   IMAGE           COMMAND                  STATUS          PORTS                    NAMES
a1b2c3d4e5f6   jenkins/jenkins "/usr/bin/tini -- /u..." Up 2 hours      0.0.0.0:8080->8080/tcp   voleon-jenkins
```

If the container is not running, start it:

On **pg-container**, as **ec2-user**:

```bash
docker start voleon-jenkins
```

### Step 2.2: Open the Jenkins UI

Open your web browser and go to:

```
http://34.228.73.232:8080
```

You will see the "Unlock Jenkins" page asking for the initial admin password.

### Step 2.3: Enter the Admin Password

The initial admin password is:

```
c4166e6fb4394a4a976b4fe554f376f9
```

Paste this into the "Administrator password" field and click **Continue**.

If you ever need to retrieve this password again, you can get it from inside the container.

On **pg-container**, as **ec2-user**:

```bash
docker exec voleon-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

`docker exec` runs a command inside a running container. This reads the password file that Jenkins generated on first startup.

### Step 2.4: Install Suggested Plugins

On the "Customize Jenkins" page, click **Install suggested plugins**.

This installs common plugins including Git, Pipeline, SSH Agent, and Credentials. The installation takes 2-5 minutes. Wait for all plugins to show a green checkmark.

### Step 2.5: Create an Admin User

On the "Create First Admin User" page, fill in:

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `voleon-admin-2026` |
| Confirm password | `voleon-admin-2026` |
| Full name | `DBA Admin` |
| E-mail address | `admin@lab.local` |

Click **Save and Continue**.

On the "Instance Configuration" page, leave the Jenkins URL as `http://34.228.73.232:8080/` and click **Save and Finish**.

Click **Start using Jenkins**. You are now on the Jenkins Dashboard.

### Step 2.6: Navigate the Jenkins UI

Take a moment to understand the main areas:

- **Dashboard** - Shows all jobs (pipelines) and their status. Green = last build passed, red = failed, gray = never run.
- **New Item** (left sidebar) - Creates a new pipeline, freestyle job, or folder.
- **Manage Jenkins** (left sidebar) - System settings, plugin management, credentials, security.
- **Build History** (left sidebar) - Global view of all recent builds across all jobs.

Click **Manage Jenkins** and then **Plugins**. You will see the list of installed plugins. Click **Available plugins** and search for "SSH Agent". If it is not already installed, install it now - you will need it for SSH-based pipelines.

---

## Section 3: Create Your First Pipeline - Database Health Check

This pipeline will SSH into your PostgreSQL servers, check database health, verify replication, and print a summary report.

### Step 3.1: Add SSH Credentials to Jenkins

Before Jenkins can SSH to your servers, it needs the private key.

First, get the contents of the SSH key.

On **pg-container**, as **ec2-user**:

```bash
cat ~/.ssh/id_ed25519
```

Copy the entire output, including the `-----BEGIN` and `-----END` lines.

Now add the key to Jenkins:

1. In the Jenkins UI, click **Manage Jenkins** - **Credentials**
2. Click **(global)** under "Stores scoped to Jenkins"
3. Click **Add Credentials** (top right)
4. Fill in the form:

| Field | Value |
|---|---|
| Kind | SSH Username with private key |
| Scope | Global |
| ID | `lab-ssh-key` |
| Description | `Lab server SSH key` |
| Username | `ec2-user` |
| Private Key | Select "Enter directly", click **Add**, paste the key content |

5. Click **Create**

### Step 3.2: Install the SSH Agent Plugin

If the SSH Agent plugin was not included in the suggested plugins, install it now.

1. Click **Manage Jenkins** - **Plugins** - **Available plugins**
2. Search for `SSH Agent`
3. Check the box next to "SSH Agent" and click **Install**
4. Check "Restart Jenkins when installation is complete and no jobs are running"
5. Wait for Jenkins to restart, then log back in

### Step 3.3: Create the Health Check Pipeline

1. From the Dashboard, click **New Item** (left sidebar)
2. Enter the name: `pg-health-check`
3. Select **Pipeline**
4. Click **OK**

You are now on the pipeline configuration page.

Scroll down to the **Pipeline** section. In the **Definition** dropdown, select "Pipeline script". This lets you write the pipeline directly in the UI. In production, you would store this in a Git repo - you will learn that approach in Section 7.

Paste the following into the **Script** box:

```groovy
pipeline {
    agent any

    environment {
        PG_PRIMARY = '172.31.19.86'
        PG_REPLICA = '172.31.22.69'
    }

    stages {
        stage('Check Primary') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                            echo "=== pg_isready ==="
                            /usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5432
                            echo ""
                            echo "=== PostgreSQL uptime ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -c "SELECT now() - pg_postmaster_start_time() AS uptime;"
                            echo ""
                            echo "=== Active connections ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -c "SELECT count(*) AS active_connections FROM pg_stat_activity WHERE state = '\\''active'\\'';"
                        '
                    """
                }
            }
        }

        stage('Check Replication') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                            echo "=== Replication Status ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -c "
                                SELECT client_addr,
                                       state,
                                       sent_lsn,
                                       write_lsn,
                                       flush_lsn,
                                       replay_lsn,
                                       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
                                FROM pg_stat_replication;
                            "
                        '
                    """
                }
            }
        }

        stage('Check Backup') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_REPLICA} '
                            echo "=== pgBackRest Info ==="
                            sudo -u postgres pgbackrest --stanza=quantdb-stanza info
                        '
                    """
                }
            }
        }

        stage('Report') {
            steps {
                echo '==========================================='
                echo '  DATABASE HEALTH CHECK COMPLETE'
                echo '==========================================='
                echo "Primary: ${PG_PRIMARY}"
                echo "Replica: ${PG_REPLICA}"
                echo 'All checks passed. Review stage logs above for details.'
            }
        }
    }

    post {
        failure {
            echo 'ONE OR MORE HEALTH CHECKS FAILED - Review the logs above.'
        }
        success {
            echo 'All health checks passed successfully.'
        }
    }
}
```

Click **Save**.

### Step 3.4: Understanding the Pipeline Script

Here is what each part does:

- `pipeline { agent any }` - Tells Jenkins to run this pipeline on any available executor (worker).
- `environment { }` - Defines variables available to all stages. You use private IPs because Jenkins on pg-container can reach the other servers over the private network.
- `stage('Check Primary')` - A named phase. Each stage shows up as a separate column in the Jenkins UI so you can see exactly where a failure happened.
- `sshagent(credentials: ['lab-ssh-key'])` - Loads the SSH key you added in Step 3.1 into the SSH agent for the duration of this block.
- `sh """..."""` - Runs a shell command. The triple quotes allow multi-line scripts.
- `post { failure { } }` - Runs after all stages complete. The `failure` block runs only if a stage failed.

### Step 3.5: Run the Pipeline

1. From the `pg-health-check` job page, click **Build Now** (left sidebar)
2. A build appears under **Build History** (bottom left). Click the build number (e.g., `#1`)
3. Click **Console Output** to see the full log

You should see output from each stage - pg_isready, replication status, and pgBackRest info. If any stage fails, the console output will show the exact error.

Expected output (abbreviated, yours will differ):

```
[Pipeline] stage (Check Primary)
=== pg_isready ===
127.0.0.1:5432 - accepting connections
=== PostgreSQL uptime ===
      uptime
------------------
 2 days 04:15:32

[Pipeline] stage (Check Replication)
=== Replication Status ===
  client_addr   | state     | replay_lag_bytes
----------------+-----------+-----------------
 172.31.22.69   | streaming |                0

[Pipeline] stage (Check Backup)
=== pgBackRest Info ===
stanza: quantdb-stanza
    status: ok
...
Finished: SUCCESS
```

### Step 3.6: View the Stage View

Go back to the `pg-health-check` job page. You will see a **Stage View** showing each stage as a colored box:

- Green = passed
- Red = failed
- Gray = not run (skipped because an earlier stage failed)

This visual breakdown is why Jenkins pipelines are useful - you can instantly see which stage of a multi-step process failed.

---

## Section 4: Database Migration Pipeline

This pipeline automates the safest way to run database migrations: check the system, back up, migrate, validate, and roll back if anything goes wrong.

### Step 4.1: Create the Migration Pipeline

1. From the Dashboard, click **New Item**
2. Name: `db-migration`
3. Select **Pipeline**
4. Click **OK**

Scroll to the **Pipeline** section, select "Pipeline script", and paste:

```groovy
pipeline {
    agent any

    environment {
        PG_PRIMARY = '172.31.19.86'
        PG_REPLICA = '172.31.22.69'
        DB_NAME    = 'quantdb'
    }

    stages {
        stage('Pre-check') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                            echo "=== Checking PostgreSQL is accepting connections ==="
                            /usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5432

                            echo ""
                            echo "=== Current tables in quantdb ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -c "
                                SELECT schemaname, tablename
                                FROM pg_tables
                                WHERE schemaname = '\\''public'\\''
                                ORDER BY tablename;
                            "

                            echo ""
                            echo "=== Checking for active locks ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -c "
                                SELECT count(*) AS blocking_locks
                                FROM pg_locks
                                WHERE NOT granted;
                            "
                        '
                    """
                }
            }
        }

        stage('Backup Before Migration') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_REPLICA} '
                            echo "=== Taking pgBackRest backup before migration ==="
                            sudo -u postgres pgbackrest --stanza=quantdb-stanza --type=diff backup
                            echo ""
                            echo "=== Backup complete ==="
                            sudo -u postgres pgbackrest --stanza=quantdb-stanza info | tail -5
                        '
                    """
                }
            }
        }

        stage('Approval Gate') {
            steps {
                input message: 'Backup complete. Proceed with migration?',
                      ok: 'Apply Migration',
                      submitter: 'admin'
            }
        }

        stage('Migrate') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                            echo "=== Running migration ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -c "
                                CREATE TABLE IF NOT EXISTS audit_log (
                                    id BIGSERIAL PRIMARY KEY,
                                    event_type VARCHAR(50) NOT NULL,
                                    table_name VARCHAR(100),
                                    changed_by VARCHAR(100) DEFAULT current_user,
                                    changed_at TIMESTAMPTZ DEFAULT now(),
                                    details JSONB
                                );
                            "
                            echo ""
                            echo "=== Adding index ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -c "
                                CREATE INDEX IF NOT EXISTS idx_audit_log_event_type
                                ON audit_log (event_type);
                            "
                            echo ""
                            echo "=== Adding index on timestamp ==="
                            sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -c "
                                CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at
                                ON audit_log (changed_at);
                            "
                            echo "Migration applied successfully."
                        '
                    """
                }
            }
        }

        stage('Validate') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                            echo "=== Validating migration ==="

                            echo "Checking table exists..."
                            TABLE_EXISTS=\$(sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -tAc "
                                SELECT count(*) FROM pg_tables
                                WHERE schemaname = '\\''public'\\'' AND tablename = '\\''audit_log'\\'';"
                            )

                            if [ "\$TABLE_EXISTS" != "1" ]; then
                                echo "VALIDATION FAILED: audit_log table does not exist"
                                exit 1
                            fi
                            echo "  audit_log table exists: OK"

                            echo "Checking columns..."
                            COLUMN_COUNT=\$(sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -tAc "
                                SELECT count(*) FROM information_schema.columns
                                WHERE table_name = '\\''audit_log'\\'' AND table_schema = '\\''public'\\'';
                            ")

                            if [ "\$COLUMN_COUNT" != "6" ]; then
                                echo "VALIDATION FAILED: Expected 6 columns, found \$COLUMN_COUNT"
                                exit 1
                            fi
                            echo "  Column count (6): OK"

                            echo "Checking indexes..."
                            IDX_COUNT=\$(sudo -u postgres /usr/pgsql-17/bin/psql -d ${DB_NAME} -tAc "
                                SELECT count(*) FROM pg_indexes
                                WHERE tablename = '\\''audit_log'\\'';
                            ")
                            echo "  Index count: \$IDX_COUNT"

                            echo ""
                            echo "=== VALIDATION PASSED ==="
                        '
                    """
                }
            }
        }
    }

    post {
        failure {
            echo '============================================'
            echo '  MIGRATION FAILED - ROLLBACK MAY BE NEEDED'
            echo '============================================'
            echo 'Check the stage logs above to determine which step failed.'
            echo 'If the Migrate stage failed, the backup taken in the Backup stage can be used for recovery.'
        }
        success {
            echo '============================================'
            echo '  MIGRATION COMPLETED SUCCESSFULLY'
            echo '============================================'
        }
    }
}
```

Click **Save**.

### Step 4.2: Understanding the Migration Pipeline

Key concepts in this pipeline:

- **Pre-check stage** - Verifies PG is up, lists existing tables, and checks for blocking locks. Never migrate into a database that is unhealthy or has contention.
- **Backup stage** - Takes a differential pgBackRest backup before any changes. This is your safety net.
- **Approval gate** - The `input` step pauses the pipeline and waits for a human to click "Apply Migration". In production, this is how you prevent automated pipelines from making database changes without a DBA reviewing the pre-check results.
- **Migrate stage** - Runs the actual DDL. Uses `IF NOT EXISTS` guards so the migration is idempotent (safe to run twice).
- **Validate stage** - Checks that the table exists, has the correct number of columns, and indexes were created. If validation fails, the `exit 1` causes the stage to fail.
- **post { failure }** - Tells you that something went wrong and points you to the backup.

### Step 4.3: Run the Migration Pipeline

1. Click **Build Now**
2. The pipeline will run Pre-check and Backup, then pause at the Approval Gate
3. You will see a blue "paused" indicator. Click on it or go to the Console Output
4. Click **Apply Migration** to proceed
5. Watch the Migrate and Validate stages complete

Expected output for the Validate stage (yours will differ):

```
=== Validating migration ===
Checking table exists...
  audit_log table exists: OK
Checking columns...
  Column count (6): OK
Checking indexes...
  Index count: 3
=== VALIDATION PASSED ===
```

### Step 4.4: Verify on the Server

Confirm the migration actually happened.

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres /usr/pgsql-17/bin/psql -d quantdb -c "\d audit_log"
```

Expected output (yours will differ):

```
                                          Table "public.audit_log"
   Column    |           Type           | Collation | Nullable |               Default
-------------+--------------------------+-----------+----------+--------------------------------------
 id          | bigint                   |           | not null | nextval('audit_log_id_seq'::regclass)
 event_type  | character varying(50)    |           | not null |
 table_name  | character varying(100)   |           |          |
 changed_by  | character varying(100)   |           |          | CURRENT_USER
 changed_at  | timestamp with time zone |           |          | now()
 details     | jsonb                    |           |          |
Indexes:
    "audit_log_pkey" PRIMARY KEY, btree (id)
    "idx_audit_log_changed_at" btree (changed_at)
    "idx_audit_log_event_type" btree (event_type)
```

---

## Section 5: Ansible Integration Pipeline

This pipeline triggers Ansible playbooks from Jenkins, adding lint checks, dry runs, and approval gates to your configuration management workflow.

### Step 5.1: Verify Ansible Is Available on pg-ops

On **pg-ops**, as **ec2-user**:

```bash
ansible --version
```

Expected output (yours will differ):

```
ansible [core 2.16.x]
  config file = /etc/ansible/ansible.cfg
...
```

### Step 5.2: Create a Test Playbook on pg-ops

This playbook gathers PostgreSQL status from all database servers. You will trigger it from Jenkins.

On **pg-ops**, as **ec2-user**:

```bash
mkdir -p ~/jenkins-playbooks
```

`mkdir -p` creates the directory and any parent directories that do not exist.

On **pg-ops**, as **ec2-user**:

```bash
vi ~/jenkins-playbooks/pg-status.yml
```

Press `i` to enter insert mode, then type (or paste) the following:

```yaml
---
- name: PostgreSQL status check
  hosts: db_servers
  become: yes
  become_user: postgres
  tasks:
    - name: Check if PostgreSQL is running
      command: /usr/pgsql-17/bin/pg_isready -h 127.0.0.1
      register: pg_ready
      changed_when: false

    - name: Display pg_isready result
      debug:
        msg: "{{ pg_ready.stdout }}"

    - name: Get PostgreSQL version
      command: /usr/pgsql-17/bin/psql -tAc "SELECT version();"
      register: pg_version
      changed_when: false

    - name: Display version
      debug:
        msg: "{{ pg_version.stdout }}"

    - name: Get database sizes
      command: /usr/pgsql-17/bin/psql -tAc "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datistemplate = false ORDER BY pg_database_size(datname) DESC;"
      register: db_sizes
      changed_when: false

    - name: Display database sizes
      debug:
        msg: "{{ db_sizes.stdout_lines }}"
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

### Step 5.3: Create an Inventory File

On **pg-ops**, as **ec2-user**:

```bash
vi ~/jenkins-playbooks/inventory.ini
```

Press `i` to enter insert mode, then type:

```ini
[db_servers]
pg-primary ansible_host=172.31.19.86
pg-replica ansible_host=172.31.22.69

[db_servers:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Press `Esc`, then type `:wq` and press `Enter`.

### Step 5.4: Test the Playbook Manually

On **pg-ops**, as **ec2-user**:

```bash
ansible-playbook -i ~/jenkins-playbooks/inventory.ini ~/jenkins-playbooks/pg-status.yml
```

Verify the playbook runs successfully before wiring it into Jenkins. You should see green "ok" results for each task on both servers.

Expected output (yours will differ):

```
PLAY [PostgreSQL status check] *************************************************

TASK [Check if PostgreSQL is running] ******************************************
ok: [pg-primary]
ok: [pg-replica]

TASK [Display pg_isready result] ***********************************************
ok: [pg-primary] => msg: 127.0.0.1:5432 - accepting connections
ok: [pg-replica] => msg: 127.0.0.1:5432 - accepting connections
...
PLAY RECAP *********************************************************************
pg-primary  : ok=6    changed=0    unreachable=0    failed=0
pg-replica  : ok=6    changed=0    unreachable=0    failed=0
```

### Step 5.5: Create the Ansible Integration Pipeline

Back in the Jenkins UI:

1. Click **New Item**
2. Name: `ansible-config-push`
3. Select **Pipeline**
4. Click **OK**

Paste the following pipeline script:

```groovy
pipeline {
    agent any

    environment {
        PG_OPS = '172.31.26.19'
        PLAYBOOK_DIR = '/home/ec2-user/jenkins-playbooks'
    }

    stages {
        stage('Lint') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_OPS} '
                            echo "=== Validating playbook syntax ==="
                            ansible-playbook --syntax-check \
                                -i ${PLAYBOOK_DIR}/inventory.ini \
                                ${PLAYBOOK_DIR}/pg-status.yml
                            echo "Syntax check passed."
                        '
                    """
                }
            }
        }

        stage('Dry Run') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_OPS} '
                            echo "=== Running in check mode (dry run) ==="
                            ansible-playbook --check \
                                -i ${PLAYBOOK_DIR}/inventory.ini \
                                ${PLAYBOOK_DIR}/pg-status.yml
                        '
                    """
                }
            }
        }

        stage('Approval') {
            steps {
                input message: 'Dry run passed. Apply the playbook to production servers?',
                      ok: 'Apply',
                      submitter: 'admin'
            }
        }

        stage('Apply') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_OPS} '
                            echo "=== Applying playbook ==="
                            ansible-playbook \
                                -i ${PLAYBOOK_DIR}/inventory.ini \
                                ${PLAYBOOK_DIR}/pg-status.yml
                        '
                    """
                }
            }
        }

        stage('Verify') {
            steps {
                sshagent(credentials: ['lab-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ec2-user@${PG_OPS} '
                            echo "=== Verifying PostgreSQL is responsive on all servers ==="
                            ansible -i ${PLAYBOOK_DIR}/inventory.ini db_servers \
                                -m command -a "/usr/pgsql-17/bin/pg_isready -h 127.0.0.1" \
                                --become --become-user postgres
                        '
                    """
                }
            }
        }
    }

    post {
        failure {
            echo 'Ansible pipeline failed. Check stage logs for details.'
        }
        success {
            echo 'Ansible playbook applied and verified successfully.'
        }
    }
}
```

Click **Save**.

### Step 5.6: Run the Ansible Pipeline

1. Click **Build Now**
2. The Lint and Dry Run stages will complete automatically
3. The pipeline pauses at the Approval gate - review the dry run output in the Console
4. Click **Apply** to run the actual playbook
5. The Verify stage confirms PostgreSQL is responsive after the playbook ran

This pattern - lint, dry-run, approve, apply, verify - is how production Ansible changes should always flow. Jenkins enforces this process so no one can skip the safety steps.

---

## Section 6: Scheduled Jobs and Notifications

### Step 6.1: Add a Cron Schedule to the Health Check

You want the `pg-health-check` pipeline to run automatically every night at 2 AM.

1. From the Dashboard, click on **pg-health-check**
2. Click **Configure** (left sidebar)
3. Scroll to the **Build Triggers** section
4. Check **Build periodically**
5. In the Schedule box, enter:

```
0 2 * * *
```

This is cron syntax: minute(0) hour(2) day-of-month(*) month(*) day-of-week(*). It means "run at 2:00 AM every day".

Jenkins shows a helpful message below the box confirming when the next run will happen.

6. Click **Save**

### Step 6.2: Understand Build Triggers

Jenkins supports several trigger types:

| Trigger | Syntax/Config | Use Case |
|---|---|---|
| **Build periodically** | `0 2 * * *` | Nightly backup verification, health checks |
| **Poll SCM** | `H/5 * * * *` | Check Git repo every 5 min for new commits |
| **Webhook** | GitHub/GitLab sends HTTP POST to Jenkins | Instant trigger on code push |
| **Upstream job** | "Build after other projects" | Run migration after backup succeeds |

For database work, the most common pattern is:

- **Cron** for recurring checks (backup verification, replication lag monitoring)
- **Webhook** for migration pipelines (triggered by a merge to the migration branch)

### Step 6.3: Configure Email Notifications (Overview)

In a production Jenkins setup, you would configure email notifications so failed builds alert the DBA team. Here is how the configuration works - you do not need to set up a real SMTP server in this lab.

1. Go to **Manage Jenkins** - **System**
2. Scroll to **Extended E-mail Notification**
3. Set the SMTP server (e.g., `smtp.gmail.com`), port (`587`), and credentials
4. Set a default recipient list (e.g., `dba-team@voleon.com`)

Then in your pipeline, you would add a notification step:

```groovy
post {
    failure {
        emailext (
            subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
            body: "Build failed. Check: ${env.BUILD_URL}",
            to: 'dba-team@voleon.com'
        )
    }
}
```

This sends an email only when a build fails, including a direct link to the build log.

### Step 6.4: Review Build History and Trends

After running your pipelines several times, explore the history:

1. Click on any pipeline job (e.g., `pg-health-check`)
2. **Build History** (left sidebar) shows every run with timestamps and status icons
3. Click a specific build number to see its Console Output, parameters, and duration
4. The **Stage View** on the job page shows a timeline of recent builds across all stages
5. **Trend** - After 5+ builds, Jenkins shows a trend graph of build durations and pass/fail rates

On **pg-container**, as **ec2-user**, you can also check build history from the command line:

```bash
docker exec voleon-jenkins ls /var/jenkins_home/jobs/pg-health-check/builds/
```

`docker exec` runs a command inside the Jenkins container. Each build gets a numbered directory containing logs, status files, and artifacts.

Expected output (yours will differ):

```
1
2
3
legacyIds
permalinks
```

---

## Section 7: Jenkins Best Practices for DBAs

This section covers the patterns that separate a basic Jenkins setup from a production-grade pipeline. Mark Selby will ask about these.

### 7.1: Pipeline as Code (Jenkinsfile in Git)

In this lab, you typed pipeline scripts directly into the Jenkins UI. In production, the pipeline definition lives in a file called `Jenkinsfile` at the root of a Git repository. This gives you:

- **Version control** - Every pipeline change is tracked in Git with commit history
- **Code review** - Pipeline changes go through the same pull request process as application code
- **Reproducibility** - You can see exactly what the pipeline did on any given date

To use a Jenkinsfile from Git, you would change the Pipeline Definition from "Pipeline script" to "Pipeline script from SCM" and point it to your Git repo.

### 7.2: Secrets Management

Never hardcode passwords, API keys, or connection strings in a Jenkinsfile. Use the Jenkins Credentials Store:

- **SSH keys** - You did this in Step 3.1 with the `lab-ssh-key` credential
- **Username/password** - Use `usernamePassword` binding in your pipeline:

```groovy
withCredentials([usernamePassword(
    credentialsId: 'pg-admin-creds',
    usernameVariable: 'PG_USER',
    passwordVariable: 'PG_PASS'
)]) {
    sh "PGPASSWORD=${PG_PASS} psql -U ${PG_USER} -d quantdb -c 'SELECT 1;'"
}
```

- **Secret text** - For API tokens or single-value secrets
- **Secret file** - For certificates or config files with sensitive content

### 7.3: Approval Gates for Production

You used the `input` step in the migration pipeline. In production, this pattern is essential:

- **Who can approve** - The `submitter` parameter restricts who can click the button. Set this to your DBA team.
- **Timeout** - Add a timeout so pipelines do not hang forever waiting for approval:

```groovy
stage('Production Approval') {
    steps {
        timeout(time: 30, unit: 'MINUTES') {
            input message: 'Deploy to production?',
                  ok: 'Deploy',
                  submitter: 'dba-team'
        }
    }
}
```

- **Environment-based gates** - Use different approval requirements for dev (none), staging (team lead), and production (two approvers).

### 7.4: Build Artifacts

Save important output from your pipelines so you can review it later:

```groovy
stage('Report') {
    steps {
        sshagent(credentials: ['lab-ssh-key']) {
            sh """
                ssh -o StrictHostKeyChecking=no ec2-user@${PG_PRIMARY} '
                    sudo -u postgres /usr/pgsql-17/bin/psql -d quantdb -c "
                        SELECT schemaname, tablename, n_tup_ins, n_tup_upd, n_tup_del
                        FROM pg_stat_user_tables
                        ORDER BY n_tup_ins DESC;
                    "
                ' > migration_report.txt
            """
        }
        archiveArtifacts artifacts: 'migration_report.txt', fingerprint: true
    }
}
```

The `archiveArtifacts` step saves the file with the build. You can download it from the build page at any time. The `fingerprint: true` flag tracks which builds produced or used this file.

### 7.5: Safe Database Change Patterns

When Mark asks about database change management in CI/CD, these patterns matter:

**Blue/green for schema changes:**
1. Create the new table (blue) alongside the old one
2. Migrate data in batches
3. Switch the application to use the new table
4. Drop the old table after a soak period

**Canary deployments for config changes:**
1. Apply the config change to the replica first
2. Monitor for 30 minutes
3. If metrics are stable, apply to the primary
4. This is exactly what the Ansible pipeline does with `--limit pg-replica` first

**Migration safety checklist (automate these as pipeline stages):**
- Take a backup before any DDL
- Use `IF NOT EXISTS` / `IF EXISTS` guards on all DDL
- Run migrations during low-traffic windows
- Validate the migration with automated checks
- Keep rollback SQL ready (a `DOWN` migration for every `UP`)

---

## Summary

You now have three working Jenkins pipelines:

| Pipeline | Purpose | Key Feature |
|---|---|---|
| `pg-health-check` | Monitors PG primary, replication, and backups | Scheduled cron trigger |
| `db-migration` | Applies schema changes with safety gates | Approval gate, validation, rollback awareness |
| `ansible-config-push` | Runs Ansible playbooks with lint and dry-run | Lint - dry-run - approve - apply - verify |

### What to Tell Mark Selby

When Mark asks about automation and CI/CD for database operations:

- **Jenkins vs alternatives**: Jenkins is ideal for on-prem/hybrid infrastructure because it runs inside your network, supports SSH-based pipelines, and has approval gates. GitHub Actions works better for cloud-native teams with everything in GitHub.
- **Pipeline stages**: Every database change should go through pre-check, backup, approval, apply, validate. If validation fails, you have the backup.
- **Secrets**: Never hardcode credentials. Use the Jenkins Credentials Store with SSH keys, username/password bindings, or secret text.
- **Ansible integration**: Jenkins triggers Ansible for fleet-wide config changes. The pipeline adds lint, dry-run, and approval gates that Ansible alone does not enforce.
- **Scheduled jobs**: Nightly backup verification and health checks catch problems before they become incidents.
- **Pipeline as Code**: Jenkinsfiles live in Git, go through code review, and provide a complete audit trail of what ran and when.
