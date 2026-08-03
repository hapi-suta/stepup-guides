# Interview Questions: Ansible for Database Configuration

**Module 06**

---

## Question 1: What is idempotency and why does it matter for database configuration?

### What the interviewer is looking for
- Clear definition with practical examples
- Understanding of why it matters for database safety
- Comparison between idempotent and non-idempotent operations

### Strong Answer Framework

"Idempotency means that running an operation multiple times produces the same result as running it once. In Ansible, this means running a playbook twice changes nothing the second time."

**Database examples:**

- `CREATE TABLE IF NOT EXISTS users (...)` is idempotent - safe to run twice
- `CREATE TABLE users (...)` is NOT idempotent - fails on second run
- `ALTER TABLE users ADD COLUMN email VARCHAR(255)` is NOT idempotent - fails if column exists
- Ansible's `postgresql_db: name=myapp state=present` IS idempotent - creates if missing, skips if exists

**Why it matters for database configuration:**

1. **Safety:** You can re-run playbooks without fear. If a playbook fails halfway through, you fix the issue and re-run. The tasks that already succeeded simply show `ok` and skip.

2. **Drift correction:** If someone manually changes a config file on a server, the next playbook run detects the difference and corrects it back to the desired state.

3. **CI/CD pipelines:** Automated deployments often run the same playbook on every deployment. Without idempotency, you would need to track which tasks have already been applied.

"The Ansible `template` module is a perfect example. It compares the rendered template against the file on the server. If they match, it reports `ok`. If they differ, it overwrites and reports `changed`. This triggers handlers (like restarting PostgreSQL) only when something actually changed."

---

## Question 2: How do you handle secrets in Ansible playbooks?

### What the interviewer is looking for
- Knowledge of Ansible Vault
- Awareness of security best practices
- Understanding of CI/CD secret management

### Strong Answer Framework

"I use a layered approach depending on the environment:"

**Layer 1 - Ansible Vault (standard approach):**
- Encrypt sensitive variables with `ansible-vault create group_vars/vault.yml`
- Reference vault variables with the `vault_` prefix convention: `vault_pg_password`
- Map vault variables to regular variables in group_vars: `pg_password: "{{ vault_pg_password }}"`
- Use `no_log: true` on tasks that handle passwords to prevent them from appearing in output

**Layer 2 - Vault password management:**
- Store the vault password in a password file (`~/.vault_pass`) that is in `.gitignore`
- For CI/CD, set `ANSIBLE_VAULT_PASSWORD` as a pipeline secret
- For production, use a script that reads from AWS Secrets Manager or HashiCorp Vault

**Layer 3 - External secrets (production):**
- For enterprise environments, use `ansible-modules-hashivault` or AWS Secrets Manager lookups
- Ansible `lookup('hashi_vault', ...)` retrieves secrets at runtime without storing them on disk
- This means even the Ansible controller never has plaintext passwords in files

**Key practices:**
- Never commit unencrypted passwords to Git
- Use `no_log: true` on any task that handles credentials
- Rotate vault passwords quarterly
- Ensure at least two people have access to the vault password
- Use separate vault files for different environments (dev, staging, prod)

---

## Question 3: Walk through deploying a PostgreSQL HA cluster with Ansible

### What the interviewer is looking for
- Understanding of HA architecture (etcd + Patroni + PgBouncer)
- Knowledge of Ansible features for multi-server deployments
- Awareness of deployment order and safety

### Strong Answer Framework

"I would deploy a Patroni-based HA cluster with etcd for consensus and PgBouncer for connection pooling. Here is the approach:"

**Inventory structure:**

```
[etcd]        - 3 nodes for distributed consensus
[patroni]     - 3 nodes (1 primary, 2 standbys - Patroni manages roles)
[pgbouncer]   - 1-2 nodes for connection pooling
```

**Deployment order (three playbooks imported by a master playbook):**

1. **etcd cluster first** - Patroni depends on etcd for leader election. Deploy all 3 etcd nodes, verify cluster health with `etcdctl endpoint health`.

2. **Patroni nodes second** - Deploy with `serial: 1` (one at a time). The first node bootstraps the primary. Subsequent nodes join as standbys automatically. Patroni handles `initdb`, `pg_basebackup`, and replication setup.

3. **PgBouncer last** - Configure to connect to the Patroni primary. PgBouncer follows failovers via the Patroni REST API.

**Key Ansible features used:**
- `serial: 1` for rolling deployment - never restart all nodes simultaneously
- Jinja2 templates with `{% for host in groups['etcd'] %}` to generate cluster-aware configs
- `uri` module to check Patroni REST API (`/health` endpoint)
- `until/retries/delay` to wait for services to become healthy
- Ansible Vault for all database passwords
- Handlers for restarting only when config changes
- A final verification play that checks replication status on all nodes

**For rolling updates:**
- Update standbys first (in the inventory, standbys come after primary)
- Verify each standby is healthy before proceeding to the next
- Use `max_fail_percentage: 0` to stop on any failure
- The primary is updated last

---

## Question 4: How do you manage different configurations for dev/staging/prod?

### What the interviewer is looking for
- Variable precedence understanding
- Environment-specific configuration patterns
- Inventory organization strategies

### Strong Answer Framework

"I use Ansible's variable hierarchy to layer environment-specific values on top of shared defaults:"

**Directory structure:**

```
inventories/
  dev/
    inventory.ini       # Dev server IPs
    group_vars/
      all.yml           # Dev-specific overrides
      vault.yml          # Dev passwords
  staging/
    inventory.ini
    group_vars/
      all.yml
      vault.yml
  production/
    inventory.ini
    group_vars/
      all.yml
      vault.yml

group_vars/              # Shared across all environments
  postgresql.yml         # Default PostgreSQL config
```

**Variable layering example:**

```yaml
# group_vars/postgresql.yml (shared defaults)
pg_max_connections: 200
pg_shared_buffers: "256MB"
pg_log_min_duration_statement: 1000

# inventories/dev/group_vars/all.yml
pg_max_connections: 50        # Dev needs fewer connections
pg_log_min_duration_statement: 0  # Log everything in dev

# inventories/production/group_vars/all.yml
pg_max_connections: 500       # Production needs more
pg_shared_buffers: "8GB"      # Production has more RAM
```

**Running against specific environments:**

```bash
ansible-playbook -i inventories/dev/inventory.ini playbook.yml
ansible-playbook -i inventories/staging/inventory.ini playbook.yml
ansible-playbook -i inventories/production/inventory.ini playbook.yml
```

"The same playbook, same templates, same roles - just different inventory and variables per environment. This eliminates the 'it works in dev but not in prod' problem because the automation is identical."

---

## Question 5: Terraform provisions, Ansible configures. Explain this workflow.

### What the interviewer is looking for
- Clear understanding of tool boundaries
- Knowledge of the handoff mechanism
- Practical CI/CD pipeline experience

### Strong Answer Framework

"Terraform and Ansible are complementary tools that each handle a different layer of the stack:"

**Terraform's domain (infrastructure):**
- Create EC2 instances, VPCs, security groups, EBS volumes
- Manage DNS records, load balancers, S3 buckets
- Tracks state in a state file (what exists in the cloud)
- Declarative: "I want 3 servers with these specs"

**Ansible's domain (configuration):**
- Install PostgreSQL, Patroni, PgBouncer
- Deploy postgresql.conf, pg_hba.conf
- Create databases, users, grant privileges
- Idempotent: "These servers should have this software configured this way"

**The handoff mechanism:**

Terraform outputs the IP addresses of created instances. These are passed to Ansible as inventory:

```
terraform apply -> terraform output -> generate inventory -> ansible-playbook
```

Three ways to pass IPs:
1. **Script:** `terraform output -json | jq` generates `inventory.ini`
2. **Dynamic inventory:** Ansible's AWS EC2 plugin discovers instances by tags
3. **Terraform provisioner:** (Not recommended - mixing concerns)

**CI/CD pipeline:**

```yaml
jobs:
  terraform:
    - terraform apply
    - output IPs to GitHub Actions outputs

  ansible:
    needs: terraform
    - generate inventory from terraform outputs
    - ansible-playbook install-pg.yml
    - ansible-playbook configure-ha.yml
    - ansible-playbook health-check.yml
```

"The golden rule: Terraform answers 'what servers exist?' and Ansible answers 'what software runs on them?' Mixing these concerns (like using Terraform provisioners for config or Ansible for cloud resources) creates fragile automation that is hard to maintain."
