# SURVIVE 04 - Parameter Misconfigured Runbook

## Symptom

Queries are being killed after 1 second, the log storage is filling up rapidly, and complex queries perform poorly (sorting spills to disk).

---

## Diagnosis

### Step 1 - Check Parameters with Non-Default Values

List all parameters that have been overridden from their defaults.

```bash
az postgres flexible-server parameter list \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --query "[?source=='user-override'].{Name:name, Value:value, DefaultValue:defaultValue, Source:source}" \
  --output table
```

This filters to only parameters that have been manually changed. Review each one.

### Step 2 - Check Specific Suspicious Parameters

Check `statement_timeout` - if this is set too low, queries get killed.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name statement_timeout \
  --query "{Name:name, Value:value, DefaultValue:defaultValue}" \
  --output table
```

Check `log_min_duration_statement` - if this is 0, every query is logged.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name log_min_duration_statement \
  --query "{Name:name, Value:value, DefaultValue:defaultValue}" \
  --output table
```

Check `work_mem` - if this is too low, sorts spill to disk.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name work_mem \
  --query "{Name:name, Value:value, DefaultValue:defaultValue}" \
  --output table
```

---

## Fix

### Step 3 - Fix statement_timeout

Set `statement_timeout` to 0 (disabled) or a reasonable value like 30000 (30 seconds).

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name statement_timeout \
  --value 30000
```

### Step 4 - Fix log_min_duration_statement

Set it to 5000ms (5 seconds) to only log slow queries.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name log_min_duration_statement \
  --value 5000
```

### Step 5 - Fix work_mem

Set it to a reasonable value like 16384 (16 MB).

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name work_mem \
  --value 16384
```

### Step 6 - Verify the Fixes

Connect and test that a query running over 1 second no longer gets killed.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SELECT pg_sleep(3);
```

Expected output:

```
 pg_sleep
----------

(1 row)
```

If this returns successfully (instead of a timeout error), the fix worked.

Check the current settings.

```sql
SHOW statement_timeout;
```

```sql
SHOW log_min_duration_statement;
```

```sql
SHOW work_mem;
```

Expected output (yours will differ):

```
 work_mem
----------
 16MB
(1 row)
```

Exit psql.

```sql
\q
```

---

## Prevention

- Document all parameter changes and the reason for each change
- Use infrastructure-as-code (ARM templates, Terraform) to manage parameters
- Review `user-override` parameters regularly
- Set up alerts for parameter changes via Activity Log
- Test parameter changes in a non-production environment first
