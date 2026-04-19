# USE 02 - Server Parameters Management

## Objective

List, modify, and verify server parameters on your Flexible Server. Understand the difference between dynamic and static parameters.

---

## Exercise

### Task 1 - List All Parameters

List every server parameter and display the first 20 results.

```bash
az postgres flexible-server parameter list \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --query "[0:20].{Name:name, Value:value, Source:source, DataType:dataType}" \
  --output table
```

The `--query "[0:20]"` limits the output to the first 20 entries. Without it, you would see hundreds of parameters.

Expected output (yours will differ):

```
Name                        Value      Source           DataType
--------------------------  ---------  ---------------  --------
archive_command              (disabled) system-default   String
archive_mode                 off        system-default   Boolean
autovacuum                   on         system-default   Boolean
...
```

---

### Task 2 - View a Specific Parameter

Check the current value of `shared_buffers`.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name shared_buffers \
  --query "{Name:name, Value:value, DefaultValue:defaultValue, AllowedValues:allowedValues, Source:source, IsConfigPendingRestart:isConfigPendingRestart}" \
  --output table
```

Expected output (yours will differ):

```
Name            Value   DefaultValue  AllowedValues  Source           IsConfigPendingRestart
--------------  ------  ------------  -------------  ---------------  ----------------------
shared_buffers  131072  131072        ...            system-default   False
```

The `IsConfigPendingRestart` field tells you if a change requires a server restart to take effect.

---

### Task 3 - Modify a Dynamic Parameter

Dynamic parameters take effect immediately without a restart. Change `work_mem` to 8192 KB (8 MB).

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name work_mem \
  --value 8192
```

Expected output (yours will differ):

```json
{
  "allowedValues": "4096-2097151",
  "dataType": "Integer",
  "defaultValue": "4096",
  "name": "work_mem",
  "source": "user-override",
  "value": "8192"
}
```

Notice the `source` changed from `system-default` to `user-override`.

---

### Task 4 - Verify Dynamic Change in psql

Connect and confirm the change took effect immediately.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 8MB
```

Exit psql.

```sql
\q
```

---

### Task 5 - Modify a Static Parameter

Static parameters require a server restart. Change `max_connections` to 300.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name max_connections \
  --value 300
```

Check if a restart is pending.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name max_connections \
  --query "{Name:name, Value:value, IsConfigPendingRestart:isConfigPendingRestart}" \
  --output table
```

Expected output (yours will differ):

```
Name              Value  IsConfigPendingRestart
----------------  -----  ----------------------
max_connections   300    True
```

The `IsConfigPendingRestart` is `True`, meaning the server needs a restart for this change to apply.

---

### Task 6 - Restart the Server

Restart the server to apply the static parameter change.

```bash
az postgres flexible-server restart \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server
```

Wait for the restart to complete (30-60 seconds).

---

### Task 7 - Verify Static Change in psql

Connect and confirm `max_connections` is now 300.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SHOW max_connections;
```

Expected output:

```
 max_connections
-----------------
 300
```

---

### Task 8 - Compare Azure CLI with pg_settings

Compare the parameter value from Azure CLI with what PostgreSQL reports internally.

```sql
SELECT name, setting, unit, source, pending_restart
FROM pg_settings
WHERE name IN ('max_connections', 'work_mem', 'shared_buffers')
ORDER BY name;
```

Expected output (yours will differ):

```
      name       | setting | unit |       source       | pending_restart
-----------------+---------+------+--------------------+----------------
 max_connections  | 300     |      | configuration file | f
 shared_buffers   | 131072  | 8kB  | configuration file | f
 work_mem         | 8192    | kB   | configuration file | f
```

The `pending_restart` column shows `f` (false) for all parameters, meaning all changes are applied.

Exit psql.

```sql
\q
```

---

### Task 9 - Reset a Parameter to Default

Reset `work_mem` back to its default value.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name work_mem \
  --value 4096
```

Verify it changed.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name work_mem \
  --query "{Name:name, Value:value, Source:source}" \
  --output table
```

Expected output (yours will differ):

```
Name      Value  Source
--------  -----  ---------------
work_mem  4096   user-override
```

---

## Checklist

- [ ] Listed all server parameters
- [ ] Viewed a specific parameter with full details
- [ ] Modified a dynamic parameter (`work_mem`) - no restart needed
- [ ] Verified dynamic change in psql immediately
- [ ] Modified a static parameter (`max_connections`) - restart required
- [ ] Restarted the server and verified the change
- [ ] Compared Azure CLI values with `pg_settings`
- [ ] Reset a parameter to its default value
