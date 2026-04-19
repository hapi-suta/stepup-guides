# USE 05 - Monitoring Setup

## Objective

Enable diagnostic settings, view metrics in Azure Monitor, explore Query Performance Insight data, and create an alert for high connection usage.

---

## Exercise

### Task 1 - Create a Log Analytics Workspace

Create a workspace to store diagnostic logs. The `--sku` flag sets the pricing tier.

```bash
az monitor log-analytics workspace create \
  --resource-group suta-pg-lab-rg \
  --workspace-name suta-pg-monitoring-ws \
  --location eastus \
  --sku PerGB2018
```

Expected output (yours will differ):

```json
{
  "name": "suta-pg-monitoring-ws",
  "provisioningState": "Succeeded",
  "sku": {"name": "PerGB2018"}
}
```

---

### Task 2 - Get the Workspace Resource ID

Save the workspace ID for use in diagnostic settings.

```bash
az monitor log-analytics workspace show \
  --resource-group suta-pg-lab-rg \
  --workspace-name suta-pg-monitoring-ws \
  --query id \
  --output tsv
```

Expected output (yours will differ):

```
/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/suta-pg-lab-rg/providers/Microsoft.OperationalInsights/workspaces/suta-pg-monitoring-ws
```

Copy this value.

---

### Task 3 - Enable Diagnostic Settings

Configure the server to send logs and metrics to Log Analytics. Replace `[WORKSPACE_ID]` with the full ID from Task 2. Replace `[SUBSCRIPTION_ID]` with your subscription ID.

```bash
az monitor diagnostic-settings create \
  --name pg-diagnostics \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --workspace [WORKSPACE_ID] \
  --logs '[{"category": "PostgreSQLLogs", "enabled": true}, {"category": "PostgreSQLFlexSessions", "enabled": true}, {"category": "PostgreSQLFlexQueryStoreRuntime", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

Expected output (yours will differ):

```json
{
  "name": "pg-diagnostics",
  "logs": [
    {"category": "PostgreSQLLogs", "enabled": true},
    {"category": "PostgreSQLFlexSessions", "enabled": true},
    {"category": "PostgreSQLFlexQueryStoreRuntime", "enabled": true}
  ]
}
```

---

### Task 4 - View CPU Metrics

Check CPU utilization for the last 3 hours. Replace `[SUBSCRIPTION_ID]` with your subscription ID.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "cpu_percent" \
  --interval PT1H \
  --query "value[0].timeseries[0].data[-3:].{Time:timeStamp, AvgCPU:average, MaxCPU:maximum}" \
  --output table
```

Expected output (yours will differ):

```
Time                           AvgCPU  MaxCPU
-----------------------------  ------  ------
2026-04-19T14:00:00+00:00      2.34    5.67
2026-04-19T15:00:00+00:00      3.15    8.12
2026-04-19T16:00:00+00:00      1.87    4.23
```

---

### Task 5 - View Connection Metrics

Check active connections over the last hour.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "active_connections" \
  --interval PT5M \
  --query "value[0].timeseries[0].data[-6:].{Time:timeStamp, Avg:average, Max:maximum}" \
  --output table
```

Expected output (yours will differ):

```
Time                           Avg   Max
-----------------------------  ----  ----
2026-04-19T16:25:00+00:00      3.0   5.0
2026-04-19T16:30:00+00:00      4.0   6.0
2026-04-19T16:35:00+00:00      3.0   4.0
2026-04-19T16:40:00+00:00      5.0   8.0
2026-04-19T16:45:00+00:00      3.0   5.0
2026-04-19T16:50:00+00:00      4.0   6.0
```

---

### Task 6 - Enable Query Store

Enable Query Store to collect query performance data.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name pg_qs.query_capture_mode \
  --value top
```

The `top` mode captures only the most resource-intensive queries. This minimizes overhead while still collecting useful data.

---

### Task 7 - Generate Some Query Activity

Connect and run some queries so Query Store has data to show.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
CREATE TABLE monitor_test (
    id serial PRIMARY KEY,
    data text,
    created_at timestamptz DEFAULT now()
);
```

```sql
INSERT INTO monitor_test (data)
SELECT md5(random()::text)
FROM generate_series(1, 10000);
```

```sql
SELECT count(*), min(created_at), max(created_at) FROM monitor_test;
```

Expected output (yours will differ):

```
 count |            min             |            max
-------+----------------------------+----------------------------
 10000 | 2026-04-19 16:50:00.123456 | 2026-04-19 16:50:01.456789
```

Run a query that takes some time.

```sql
SELECT data, count(*) FROM monitor_test GROUP BY data HAVING count(*) > 1;
```

Exit psql.

```sql
\q
```

---

### Task 8 - Query Performance Data from Log Analytics

Wait 10-15 minutes for Query Store data to flow to Log Analytics, then query it.

```bash
az monitor log-analytics query \
  --workspace suta-pg-monitoring-ws \
  --analytics-query "AzureDiagnostics | where Category == 'PostgreSQLFlexQueryStoreRuntime' | project TimeGenerated, query_id_d, calls_d, total_time_d, mean_time_d | order by total_time_d desc | take 5" \
  --output table
```

Expected output (yours will differ):

```
TimeGenerated                  query_id_d  calls_d  total_time_d  mean_time_d
-----------------------------  ----------  -------  ------------  -----------
2026-04-19T17:00:00.000Z       12345       1        250.5         250.5
2026-04-19T17:00:00.000Z       12346       10000    125.3         0.013
...
```

---

### Task 9 - Create an Action Group

Create an action group for alert notifications.

```bash
az monitor action-group create \
  --resource-group suta-pg-lab-rg \
  --name monitoring-exercise-ag \
  --short-name monitorag \
  --action email lab-admin afopzhappy@gmail.com
```

---

### Task 10 - Create a Connection Alert

Create an alert that fires when active connections exceed 240 (80% of 300 max_connections). Replace `[SUBSCRIPTION_ID]` with your subscription ID.

```bash
az monitor metrics alert create \
  --name pg-connections-alert \
  --resource-group suta-pg-lab-rg \
  --scopes "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --condition "avg active_connections > 240" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action monitoring-exercise-ag \
  --description "Connections at 80% of max_connections (300)" \
  --severity 2
```

---

### Task 11 - Verify Alert

List alerts to confirm it was created.

```bash
az monitor metrics alert list \
  --resource-group suta-pg-lab-rg \
  --query "[].{Name:name, Enabled:enabled, Severity:severity}" \
  --output table
```

Expected output (yours will differ):

```
Name                    Enabled  Severity
----------------------  -------  --------
pg-connections-alert    True     2
```

---

### Task 12 - Clean Up Test Table

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
DROP TABLE IF EXISTS monitor_test;
```

```sql
\q
```

---

## Checklist

- [ ] Log Analytics workspace created
- [ ] Diagnostic settings configured (PostgreSQLLogs, Sessions, QueryStore)
- [ ] CPU metrics viewable via CLI
- [ ] Connection metrics viewable via CLI
- [ ] Query Store enabled
- [ ] Query activity generated
- [ ] Query performance data visible in Log Analytics
- [ ] Action group created
- [ ] Connection alert created and verified
