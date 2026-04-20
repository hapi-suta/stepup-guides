# SURVIVE 03: Terraform State Drift - Runbook

## Symptom

Monitoring alerts fire for slow query logging being effectively disabled. Investigation reveals that PostgreSQL parameters differ from what is defined in the Terraform/IaC configuration.

---

## Step 1: Check Expected Configuration

Look at what the IaC says the settings should be.

```bash
cat /tmp/tf-drift-lab/expected_params.txt
```

Key expected values:
- `log_min_duration_statement = 1000` (log queries over 1 second)
- `idle_in_transaction_session_timeout = 300000` (5 minutes)

---

## Step 2: Check Actual Configuration

Switch to the postgres user.

```bash
sudo -iu postgres
```

Query the current running values.

```bash
psql -c "SELECT name, setting, unit, source FROM pg_settings WHERE name IN ('log_min_duration_statement', 'idle_in_transaction_session_timeout', 'log_connections', 'log_disconnections', 'shared_preload_libraries') ORDER BY name;"
```

Compare each value against the expected configuration.

Also check if there are overrides in postgresql.auto.conf. This file is where `ALTER SYSTEM` writes its changes.

```bash
cat /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):
```
log_min_duration_statement = '5000'
idle_in_transaction_session_timeout = '0'
```

You should see the drifted values here - someone used ALTER SYSTEM to change them manually.

---

## Step 3: Identify the Drift

Create a comparison:

| Parameter | Expected | Actual | Drifted? |
|-----------|----------|--------|----------|
| log_min_duration_statement | 1000 | 5000 | YES |
| idle_in_transaction_session_timeout | 300000 | 0 | YES |
| log_connections | 1 | 1 | No |
| log_disconnections | 1 | 1 | No |

---

## Step 4: Restore Correct Values

Fix `log_min_duration_statement`.

```bash
psql -c "ALTER SYSTEM SET log_min_duration_statement = 1000;"
```

Fix `idle_in_transaction_session_timeout`.

```bash
psql -c "ALTER SYSTEM SET idle_in_transaction_session_timeout = 300000;"
```

Reload the configuration.

```bash
psql -c "SELECT pg_reload_conf();"
```

---

## Step 5: Verify the Fix

```bash
psql -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('log_min_duration_statement', 'idle_in_transaction_session_timeout') ORDER BY name;"
```

Expected output:
```
                name                 | setting | unit
-------------------------------------+---------+------
 idle_in_transaction_session_timeout | 300000  | ms
 log_min_duration_statement          | 1000    | ms
```

Exit the postgres user.

```bash
exit
```

---

## Step 6: Document Prevention Measures

To prevent drift in the future:

1. **Remove manual access** - Do not give DBAs `ALTER SYSTEM` privileges in production unless through a change management process
2. **Run drift detection** - Schedule `terraform plan` nightly and alert if it shows changes
3. **Use Ansible enforcement** - Run config playbooks on a schedule to detect and auto-correct drift
4. **Audit ALTER SYSTEM** - Monitor postgresql.auto.conf changes with a file watcher
5. **Lock down pg_settings** - Use `ALTER SYSTEM RESET ALL` after applying IaC to remove any manual overrides

---

## Discussion Points

- In a real Terraform setup, `terraform plan` would show the drift as a diff
- The RDS parameter group would show "pending-reboot" or "in-sync" status
- ALTER SYSTEM writes to postgresql.auto.conf which takes precedence over postgresql.conf
- Team process matters more than tooling - agree that all changes go through IaC pull requests
