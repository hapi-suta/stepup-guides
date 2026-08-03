# USE 03: State Management Exercise

**Module:** DevOps DBA Training Track - Module 03
**Time Estimate:** 30-45 minutes
**Prerequisites:** BUILD 01-06 completed (especially BUILD 03 and BUILD 05)
**Lab Type:** LOCAL (no AWS cost)

---

## The Scenario

You are taking over Terraform management of a project from a colleague who left the company. The project has grown organically - resource names are inconsistent, some resources were renamed in code but not in state, and there are orphaned state entries for resources that no longer exist.

Your job: clean up the state so it matches reality and the configuration.

---

## Setup

**In your terminal:**

```bash
mkdir -p ~/terraform-labs/use03-state
```

```bash
cd ~/terraform-labs/use03-state
```

```bash
vi ~/terraform-labs/use03-state/main.tf
```

Press `i` to enter insert mode and type:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "primary_config" {
  content  = "cluster=aurora-prod\nrole=writer\nendpoint=prod.cluster-abc.rds.amazonaws.com"
  filename = "${path.module}/primary.conf"
}

resource "local_file" "replica_config" {
  content  = "cluster=aurora-prod\nrole=reader\nendpoint=prod.cluster-ro-abc.rds.amazonaws.com"
  filename = "${path.module}/replica.conf"
}

resource "local_file" "monitoring" {
  content  = "check_interval=30\nalert_threshold=90\nnotify=dba@company.com"
  filename = "${path.module}/monitoring.conf"
}

resource "local_file" "backup_policy" {
  content  = "retention=35\nschedule=daily\nverification=weekly"
  filename = "${path.module}/backup.conf"
}

resource "local_file" "security_rules" {
  content  = "allow 10.0.0.0/8 port 5432\nallow 172.16.0.0/12 port 5432"
  filename = "${path.module}/security.conf"
}
```

Save and exit (`:wq`).

Initialize and apply:

```bash
terraform init
```

```bash
terraform apply -auto-approve
```

Expected output:

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

---

## Exercise 1: List and Inspect State

**Task:** List all resources in state, then inspect the `primary_config` resource to see all its attributes.

**Commands to use:**

```bash
terraform state list
```

```bash
terraform state show local_file.primary_config
```

**Questions:**

1. How many resources are in state?
2. What is the `id` attribute of `primary_config`?
3. What `file_permission` was set?

---

## Exercise 2: Rename a Resource in State

**Task:** Your colleague named the resource `replica_config`, but your team standard is `reader_config`. Rename it in state AND update the `.tf` file to match.

**Step 1:** Rename in state:

```bash
terraform state mv local_file.replica_config local_file.reader_config
```

**Step 2:** Update `main.tf` - change `replica_config` to `reader_config`:

```bash
vi ~/terraform-labs/use03-state/main.tf
```

Change this line:

```hcl
resource "local_file" "replica_config" {
```

To:

```hcl
resource "local_file" "reader_config" {
```

Save and exit (`:wq`).

**Step 3:** Verify no changes:

```bash
terraform plan
```

Expected output:

```
No changes. Your infrastructure matches the configuration.
```

If you see Terraform wanting to destroy `replica_config` and create `reader_config`, you forgot one of the steps.

---

## Exercise 3: Remove a Resource from State

**Task:** The monitoring configuration is now managed by a separate monitoring tool (Datadog/Grafana). You want Terraform to stop managing it WITHOUT deleting the actual file.

**Step 1:** Remove from state:

```bash
terraform state rm local_file.monitoring
```

**Step 2:** Remove from `main.tf` (delete the entire `monitoring` resource block):

```bash
vi ~/terraform-labs/use03-state/main.tf
```

Delete the `local_file.monitoring` resource block entirely.

Save and exit (`:wq`).

**Step 3:** Verify:

```bash
terraform plan
```

Expected: "No changes."

```bash
ls ~/terraform-labs/use03-state/monitoring.conf
```

Expected: The file still exists on disk. Terraform stopped tracking it, but did not delete it.

---

## Exercise 4: Import a Resource

**Task:** Someone manually created a connection pooler configuration file. You need to bring it under Terraform management.

**Step 1:** Create the "manually created" file:

```bash
echo "pool_mode=transaction
max_client_conn=1000
default_pool_size=25
server_idle_timeout=600" > ~/terraform-labs/use03-state/pgbouncer.conf
```

**Step 2:** Add the resource to `main.tf`:

```bash
vi ~/terraform-labs/use03-state/main.tf
```

Add this resource block:

```hcl
resource "local_file" "pgbouncer" {
  content  = "pool_mode=transaction\nmax_client_conn=1000\ndefault_pool_size=25\nserver_idle_timeout=600"
  filename = "${path.module}/pgbouncer.conf"
}
```

Save and exit (`:wq`).

**Step 3:** Import:

```bash
terraform import local_file.pgbouncer ~/terraform-labs/use03-state/pgbouncer.conf
```

**Step 4:** Verify:

```bash
terraform plan
```

Expected: "No changes."

---

## Exercise 5: Detect and Resolve Drift

**Task:** Someone manually edited the security rules file outside of Terraform. Detect and resolve the drift.

**Step 1:** Simulate manual change:

```bash
echo "allow 10.0.0.0/8 port 5432
allow 172.16.0.0/12 port 5432
allow 192.168.1.0/24 port 5432" > ~/terraform-labs/use03-state/security.conf
```

**Step 2:** Detect drift:

```bash
terraform plan
```

**Questions:**

1. What does the plan show?
2. Is Terraform trying to add or remove the `192.168.1.0/24` rule?
3. What would `terraform apply` do?

**Step 3:** Decide how to resolve:

**Option A:** If the manual change was correct, update `main.tf` to include the new rule.

**Option B:** If the manual change was a mistake, run `terraform apply` to revert to the defined state.

For this exercise, choose Option A - update your `.tf` file to include the new CIDR block, then verify the plan shows no changes.

---

## Exercise 6: Full State Audit

**Task:** After all the changes above, perform a full state audit.

```bash
terraform state list
```

**Questions:**

1. How many resources are now in state?
2. Which resource was renamed?
3. Which resource was removed from state?
4. Which resource was imported?
5. Does `terraform plan` show "No changes"?

---

## Final Cleanup

```bash
terraform destroy -auto-approve
```

Also remove the monitoring file that Terraform no longer manages:

```bash
rm ~/terraform-labs/use03-state/monitoring.conf
```

---

## Scoring Guide

| Exercise | Points | Key Skill |
|---|---|---|
| 1 - List and inspect | 10 | `state list`, `state show` |
| 2 - Rename resource | 20 | `state mv` + update HCL |
| 3 - Remove from state | 20 | `state rm` + remove from HCL |
| 4 - Import resource | 25 | `import` + write matching HCL |
| 5 - Detect drift | 15 | Understanding plan output, resolving drift |
| 6 - Full audit | 10 | Verifying state matches reality |
| **Total** | **100** |

---

## Common Mistakes

| Mistake | What Happens | How to Fix |
|---|---|---|
| `state mv` without updating HCL | Plan shows destroy + create | Update the resource name in `.tf` file |
| `state rm` without removing from HCL | Plan shows resource will be created | Remove the resource block from `.tf` file |
| Import with wrong content in HCL | Plan shows changes after import | Fix HCL to match actual resource |
| Forgetting to re-plan after changes | State drift goes undetected | Always run `terraform plan` after state operations |
