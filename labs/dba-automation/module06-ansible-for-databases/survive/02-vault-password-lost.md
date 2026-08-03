# SURVIVE 02: The Lost Vault Password

**Module 06: Ansible for Database Configuration**
**Difficulty: Medium**
**Estimated Time: 30 minutes**

---

## The Scenario

It is Monday morning. Your colleague who managed the Ansible Vault password left the company last Friday. They stored the vault password in their head (and nowhere else). Your Ansible playbooks reference vault-encrypted files for all database passwords:

- PostgreSQL superuser password
- Replication user password
- Application user passwords
- PgBouncer auth file passwords

You need to run the Ansible playbook to update a configuration across the cluster, but every playbook references `group_vars/vault.yml` which you cannot decrypt.

The databases are running. The passwords work. You just cannot decrypt the vault file to read or change them, and you cannot run any playbook that references vault variables.

---

## Your Mission

1. **Assess the impact:** What is locked? What still works?
2. **Recover or reset:** You cannot recover the vault password - you must rotate credentials.
3. **Create a new vault:** Re-encrypt all credentials with a new password.
4. **Implement proper vault management:** Ensure this never happens again.

---

## Part 1: Assess the Impact

### What Is Locked

The encrypted vault file (`group_vars/vault.yml`) contains:

```yaml
# You cannot read this, but it contains:
vault_pg_superuser_password: "OldSuperSecret123"
vault_pg_replication_password: "OldReplSecret456"
vault_pg_app_user_password: "OldAppSecret789"
vault_pg_readonly_password: "OldReadonly012"
vault_pgbouncer_admin_password: "OldBouncer345"
```

### What Still Works

- The databases are running with the OLD passwords
- Application connections work (passwords are in the database, not in the vault)
- You can still SSH to servers
- You can still connect to PostgreSQL as postgres using peer auth (locally)

### What Does NOT Work

- `ansible-playbook` fails on any playbook that references vault variables
- You cannot read or edit the vault file
- Any deployment that needs passwords is blocked

---

## Part 2: Rotate All Database Passwords

Since you cannot recover the old vault password, you must create new passwords and update them everywhere.

### Step 1: Generate New Passwords

**On your Mac terminal:**

```bash
# Generate strong random passwords
openssl rand -base64 24  # For superuser
openssl rand -base64 24  # For replication
openssl rand -base64 24  # For app_user
openssl rand -base64 24  # For readonly
openssl rand -base64 24  # For pgbouncer
```

Save these in a temporary secure location (you will put them in the new vault shortly).

### Step 2: Update Passwords Directly on the Primary

Since Ansible is blocked, you must update passwords manually. Connect to the primary via SSH:

**On the primary server, as postgres:**

```bash
sudo su - postgres
psql
```

```sql
-- Rotate all passwords
ALTER ROLE postgres PASSWORD 'NewSuperSecret_REPLACE_ME';
ALTER ROLE replicator PASSWORD 'NewReplSecret_REPLACE_ME';
ALTER ROLE app_user PASSWORD 'NewAppSecret_REPLACE_ME';
ALTER ROLE readonly PASSWORD 'NewReadonly_REPLACE_ME';

-- Verify the changes
SELECT rolname, rolpassword IS NOT NULL AS has_password
FROM pg_authid
WHERE rolname IN ('postgres', 'replicator', 'app_user', 'readonly');
```

Expected output:
```
  rolname   | has_password
------------+--------------
 postgres   | t
 replicator | t
 app_user   | t
 readonly   | t
```

```sql
\q
```

```bash
exit
```

### Step 3: Update PgBouncer Auth File

**On the PgBouncer server, as ec2-user:**

```bash
sudo vi /etc/pgbouncer/userlist.txt
```

Update with the new passwords (PgBouncer uses MD5 or SCRAM hashes):

```
"postgres" "NewSuperSecret_REPLACE_ME"
"app_user" "NewAppSecret_REPLACE_ME"
"readonly" "NewReadonly_REPLACE_ME"
```

Reload PgBouncer:

```bash
sudo systemctl reload pgbouncer
```

### Step 4: Update Application Connection Strings

Notify the application team that database passwords have changed. They need to update their connection strings or secrets manager.

### Step 5: Verify All Connections

```bash
# Test from PgBouncer
psql -h pgbouncer-host -p 6432 -U app_user -d myapp -c "SELECT 1;"

# Test replication
psql -h primary-host -U replicator -c "IDENTIFY_SYSTEM;" "dbname=replication"

# Test direct connection
psql -h primary-host -U postgres -c "SELECT version();"
```

---

## Part 3: Create New Vault

### Step 1: Delete the Old (Unrecoverable) Vault File

```bash
cd ~/dba-labs/ansible-pgconfig
rm group_vars/vault.yml
```

### Step 2: Create a New Vault with a New Password

Choose a strong vault password and store it properly (see Part 4).

```bash
ansible-vault create group_vars/vault.yml
```

When prompted, enter your NEW vault password. Then enter the new credentials:

```yaml
---
vault_pg_superuser_password: "NewSuperSecret_REPLACE_ME"
vault_pg_replication_password: "NewReplSecret_REPLACE_ME"
vault_pg_app_user_password: "NewAppSecret_REPLACE_ME"
vault_pg_readonly_password: "NewReadonly_REPLACE_ME"
vault_pgbouncer_admin_password: "NewBouncer_REPLACE_ME"
```

Save and exit.

### Step 3: Verify the New Vault Works

```bash
ansible-vault view group_vars/vault.yml
```

Enter the new vault password. You should see the decrypted contents.

### Step 4: Test a Playbook

```bash
ansible-playbook -i inventory.ini playbook-health-check.yml --ask-vault-pass
```

Enter the new vault password. The playbook should run without errors.

---

## Part 4: Implement Proper Vault Password Management

The root cause was a single person holding the vault password in their head. Here are three strategies to prevent this:

### Strategy 1: Vault Password File (Simplest)

Store the vault password in a file that is NOT in version control:

```bash
# Create the password file
echo "YourVaultPassword123" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Add to .gitignore
echo ".vault_pass" >> .gitignore

# Configure Ansible to use it automatically
echo "vault_password_file = ~/.vault_pass" >> ansible.cfg
```

Now `ansible-playbook` reads the password automatically. Share the password file securely with team members (password manager, not email).

### Strategy 2: Vault Password from Environment Variable

```bash
# Set the password in a script
export ANSIBLE_VAULT_PASSWORD="YourVaultPassword123"

# Create a script that reads from environment
cat > vault-pass.sh <<'EOF'
#!/bin/bash
echo "$ANSIBLE_VAULT_PASSWORD"
EOF
chmod +x vault-pass.sh

# Configure Ansible to use it
echo "vault_password_file = ./vault-pass.sh" >> ansible.cfg
```

### Strategy 3: External Secrets Manager (Production)

For production environments, store the vault password in AWS Secrets Manager, HashiCorp Vault, or 1Password:

```bash
# vault-pass-aws.sh - reads from AWS Secrets Manager
#!/bin/bash
aws secretsmanager get-secret-value \
  --secret-id ansible-vault-password \
  --query SecretString \
  --output text
```

```bash
chmod +x vault-pass-aws.sh
echo "vault_password_file = ./vault-pass-aws.sh" >> ansible.cfg
```

### Documentation Checklist

After implementing vault password management:

- [ ] Vault password is stored in at least 2 locations (redundancy)
- [ ] At least 2 team members know where the vault password is
- [ ] `.vault_pass` is in `.gitignore`
- [ ] `ansible.cfg` references the vault password file
- [ ] README documents where the vault password lives
- [ ] Password rotation schedule is documented (quarterly recommended)

---

## Validation Checklist

- [ ] All database passwords have been rotated
- [ ] New vault file created with new passwords
- [ ] Application connections work with new passwords
- [ ] Replication works with new replication password
- [ ] PgBouncer auth file updated and working
- [ ] Ansible playbooks run successfully with new vault
- [ ] Vault password stored in at least 2 accessible locations
- [ ] `.vault_pass` is in `.gitignore`

---

## Lessons Learned

1. **Never store the vault password in one person's head.** Use a password manager shared with the team.
2. **Use a vault password file with `.gitignore`.** This is simpler than typing passwords every time.
3. **External secrets managers are best for production.** AWS Secrets Manager, HashiCorp Vault, or 1Password CLI.
4. **Document where the vault password lives.** The README should say "Vault password is in 1Password under 'Ansible Vault'" (without the actual password).
5. **Password rotation is a skill to practice.** When you rotate passwords, you need to update: the database, pg_hba.conf, PgBouncer auth, application configs, and the Ansible vault - all atomically.
