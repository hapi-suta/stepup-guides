# BUILD 04 - Monitoring and Diagnostics for Azure Database for PostgreSQL Flexible Server

## Overview

In this guide you will set up monitoring and diagnostics for your Flexible Server. You will configure Azure Monitor metrics, send logs to Log Analytics, explore Query Performance Insight, enable Intelligent Performance features, and create alerts for critical conditions.

---

## Prerequisites

- Completed BUILD 01 (server created and accessible)
- Azure CLI authenticated
- A Log Analytics workspace (we create one in this guide)

---

## Step 1 - Understand Azure Monitor for PostgreSQL

Azure Monitor provides these monitoring layers for Flexible Server:

| Layer | What It Monitors | Retention |
|-------|-----------------|-----------|
| Platform metrics | CPU, memory, storage, IOPS, connections | 93 days |
| Diagnostic logs | PostgreSQL server logs, audit logs, sessions | Depends on destination |
| Query Performance Insight | Top queries by duration, calls, rows | 7 days (portal feature) |
| Intelligent Performance | Automatic tuning recommendations | Ongoing |

Platform metrics are always collected - no setup needed. Diagnostic logs require configuration.

---

## Step 2 - View Platform Metrics

Check the current CPU utilization for your server. The `--metric` flag specifies which metric to retrieve. The `--interval` flag sets the aggregation period.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "cpu_percent" \
  --interval PT1H \
  --query "value[0].timeseries[0].data[-3:].{Time:timeStamp, Average:average}" \
  --output table
```

Replace `[SUBSCRIPTION_ID]` with your actual subscription ID.

Expected output (yours will differ):

```
Time                           Average
-----------------------------  ---------
2026-04-19T13:00:00+00:00      2.34
2026-04-19T14:00:00+00:00      3.15
2026-04-19T15:00:00+00:00      1.87
```

---

## Step 3 - Key Metrics to Monitor

These are the most important metrics for PostgreSQL Flexible Server:

| Metric Name | Description | Alert Threshold |
|-------------|-------------|-----------------|
| cpu_percent | CPU utilization percentage | > 80% for 5 min |
| memory_percent | Memory utilization percentage | > 80% for 5 min |
| storage_percent | Storage utilization percentage | > 85% |
| active_connections | Number of active connections | > 80% of max_connections |
| iops | Read + Write IOPS | > 90% of provisioned IOPS |
| network_bytes_ingress | Bytes received per second | Baseline + 50% |
| network_bytes_egress | Bytes sent per second | Baseline + 50% |
| backup_storage_used | Total backup storage in bytes | Informational |
| maximum_used_transactionIDs | Transaction ID usage | > 500M (wraparound risk) |

---

## Step 4 - Check Storage Metrics

View storage usage. This is critical - running out of storage causes the server to go read-only.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --metric "storage_percent" \
  --interval PT1H \
  --query "value[0].timeseries[0].data[-1].{Time:timeStamp, Average:average}" \
  --output table
```

Expected output (yours will differ):

```
Time                           Average
-----------------------------  ---------
2026-04-19T15:00:00+00:00      12.5
```

---

## Step 5 - Create a Log Analytics Workspace

Log Analytics is where your diagnostic logs will be stored and queried. The `--sku` flag sets the pricing tier (PerGB2018 is the standard tier).

```bash
az monitor log-analytics workspace create \
  --resource-group suta-pg-lab-rg \
  --workspace-name suta-pg-lab-logs \
  --location eastus \
  --sku PerGB2018
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../workspaces/suta-pg-lab-logs",
  "location": "eastus",
  "name": "suta-pg-lab-logs",
  "provisioningState": "Succeeded",
  "sku": {
    "name": "PerGB2018"
  }
}
```

---

## Step 6 - Get the Workspace ID

You need the workspace resource ID for the diagnostic settings. Save it to a variable.

```bash
az monitor log-analytics workspace show \
  --resource-group suta-pg-lab-rg \
  --workspace-name suta-pg-lab-logs \
  --query id \
  --output tsv
```

Expected output (yours will differ):

```
/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/suta-pg-lab-rg/providers/Microsoft.OperationalInsights/workspaces/suta-pg-lab-logs
```

Copy this value. You will use it in the next step.

---

## Step 7 - Enable Diagnostic Settings

Configure the server to send logs to your Log Analytics workspace. Each `--logs` entry enables a specific log category.

Replace `[WORKSPACE_ID]` with the full resource ID from Step 6.

```bash
az monitor diagnostic-settings create \
  --name suta-pg-diagnostics \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --workspace [WORKSPACE_ID] \
  --logs '[{"category": "PostgreSQLLogs", "enabled": true}, {"category": "PostgreSQLFlexSessions", "enabled": true}, {"category": "PostgreSQLFlexQueryStoreRuntime", "enabled": true}, {"category": "PostgreSQLFlexQueryStoreWaitStats", "enabled": true}, {"category": "PostgreSQLFlexTableStats", "enabled": true}, {"category": "PostgreSQLFlexDatabaseXacts", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../diagnosticSettings/suta-pg-diagnostics",
  "logs": [
    {"category": "PostgreSQLLogs", "enabled": true},
    {"category": "PostgreSQLFlexSessions", "enabled": true},
    {"category": "PostgreSQLFlexQueryStoreRuntime", "enabled": true},
    ...
  ],
  "name": "suta-pg-diagnostics"
}
```

Log categories explained:

- **PostgreSQLLogs** - Server log messages (errors, warnings, slow queries)
- **PostgreSQLFlexSessions** - Session-level activity
- **PostgreSQLFlexQueryStoreRuntime** - Query execution statistics
- **PostgreSQLFlexQueryStoreWaitStats** - Wait event statistics
- **PostgreSQLFlexTableStats** - Table-level statistics
- **PostgreSQLFlexDatabaseXacts** - Transaction statistics

---

## Step 8 - Enable Query Store on the Server

Query Store must be enabled as a server parameter for Query Performance Insight to work.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name pg_qs.query_capture_mode \
  --value top
```

Expected output (yours will differ):

```json
{
  "allowedValues": "none, top, all",
  "name": "pg_qs.query_capture_mode",
  "source": "user-override",
  "value": "top"
}
```

The `top` setting captures the most resource-intensive queries. Use `all` to capture every query (higher overhead).

---

## Step 9 - Enable Wait Statistics

Enable wait statistics collection. This shows what your queries are waiting on (locks, I/O, CPU).

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name pgms_wait_sampling.query_capture_mode \
  --value all
```

Expected output (yours will differ):

```json
{
  "allowedValues": "none, all",
  "name": "pgms_wait_sampling.query_capture_mode",
  "source": "user-override",
  "value": "all"
}
```

---

## Step 10 - Enable Slow Query Logging

Configure the server to log slow queries. Set the minimum duration to 5000 milliseconds (5 seconds).

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name log_min_duration_statement \
  --value 5000
```

This logs any query that takes more than 5 seconds. Adjust the threshold based on your workload.

Enable logging of query duration.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name log_duration \
  --value on
```

---

## Step 11 - Query Logs in Log Analytics

After waiting 10-15 minutes for logs to flow, query them using Kusto Query Language (KQL). The `--analytics-query` flag runs a KQL query against your workspace.

```bash
az monitor log-analytics query \
  --workspace suta-pg-lab-logs \
  --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where Category == 'PostgreSQLLogs' | project TimeGenerated, Message, errorLevel_s | order by TimeGenerated desc | take 10" \
  --output table
```

Expected output (yours will differ):

```
TimeGenerated                  Message                                        errorLevel_s
-----------------------------  ---------------------------------------------  ------------
2026-04-19T15:30:00.000Z       LOG:  checkpoint starting: time                LOG
2026-04-19T15:29:55.000Z       LOG:  connection authorized: user=pgadmin      LOG
2026-04-19T15:25:00.000Z       LOG:  checkpoint complete: wrote 42 buffers    LOG
...
```

---

## Step 12 - Query Session Statistics

View active session statistics from Log Analytics.

```bash
az monitor log-analytics query \
  --workspace suta-pg-lab-logs \
  --analytics-query "AzureDiagnostics | where Category == 'PostgreSQLFlexSessions' | summarize count() by usename_s, datname_s | order by count_ desc | take 10" \
  --output table
```

Expected output (yours will differ):

```
usename_s  datname_s    count_
---------  ----------   ------
pgadmin    postgres     45
pgadmin    pitr_test    12
```

---

## Step 13 - Create an Alert for High CPU

Create an alert that fires when CPU exceeds 80% for 5 minutes. First, create an action group for notifications.

```bash
az monitor action-group create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-alerts-ag \
  --short-name sutaalerts \
  --action email admin-email afopzhappy@gmail.com
```

Expected output (yours will differ):

```json
{
  "emailReceivers": [
    {
      "emailAddress": "afopzhappy@gmail.com",
      "name": "admin-email",
      "status": "Enabled"
    }
  ],
  "name": "suta-pg-alerts-ag"
}
```

Now create the alert rule. The `--condition` flag defines when the alert triggers. The `--window-size` flag sets the evaluation period.

```bash
az monitor metrics alert create \
  --name suta-pg-high-cpu \
  --resource-group suta-pg-lab-rg \
  --scopes "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --condition "avg cpu_percent > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action suta-pg-alerts-ag \
  --description "Alert when CPU exceeds 80% for 5 minutes" \
  --severity 2
```

Severity levels: 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose.

---

## Step 14 - Create an Alert for Storage

Create a storage alert at 85% utilization. Storage issues can put your server into read-only mode.

```bash
az monitor metrics alert create \
  --name suta-pg-storage-high \
  --resource-group suta-pg-lab-rg \
  --scopes "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --condition "avg storage_percent > 85" \
  --window-size 5m \
  --evaluation-frequency 5m \
  --action suta-pg-alerts-ag \
  --description "Alert when storage exceeds 85%" \
  --severity 1
```

---

## Step 15 - Create an Alert for Connections

Create a connection alert. This fires when active connections exceed 80% of max_connections.

```bash
az monitor metrics alert create \
  --name suta-pg-connections-high \
  --resource-group suta-pg-lab-rg \
  --scopes "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --condition "avg active_connections > 160" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action suta-pg-alerts-ag \
  --description "Alert when connections exceed 80% of max (200)" \
  --severity 2
```

---

## Step 16 - List All Alert Rules

Verify your alerts are in place.

```bash
az monitor metrics alert list \
  --resource-group suta-pg-lab-rg \
  --query "[].{Name:name, Severity:severity, Enabled:enabled, Condition:criteria.allOf[0].metricName}" \
  --output table
```

Expected output (yours will differ):

```
Name                       Severity  Enabled  Condition
-------------------------  --------  -------  ------------------
suta-pg-high-cpu           2         True     cpu_percent
suta-pg-storage-high       1         True     storage_percent
suta-pg-connections-high   2         True     active_connections
```

---

## Step 17 - Intelligent Performance

Azure Flexible Server includes Intelligent Performance features that provide automatic recommendations:

- **Index recommendations** - Suggests creating or dropping indexes based on query patterns
- **Schema recommendations** - Identifies schema improvements
- **Query statistics** - Tracks top queries by execution time, calls, and rows

These features use Query Store data. Since you enabled Query Store in Step 8, recommendations will start appearing after the server collects enough query data (typically 24-48 hours).

View available recommendations.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name index_tuning.mode
```

Enable index tuning if not already enabled.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name index_tuning.mode \
  --value report
```

The `report` mode shows recommendations without applying them. Use `apply` to let Azure automatically create recommended indexes.

---

## Step 18 - Verify Diagnostic Settings

Confirm your diagnostic settings are working.

```bash
az monitor diagnostic-settings show \
  --name suta-pg-diagnostics \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --query "{Name:name, Workspace:workspaceId, LogCategories:logs[].{Category:category, Enabled:enabled}}" \
  --output json
```

Expected output (yours will differ):

```json
{
  "Name": "suta-pg-diagnostics",
  "Workspace": "/subscriptions/.../workspaces/suta-pg-lab-logs",
  "LogCategories": [
    {"Category": "PostgreSQLLogs", "Enabled": true},
    {"Category": "PostgreSQLFlexSessions", "Enabled": true},
    {"Category": "PostgreSQLFlexQueryStoreRuntime", "Enabled": true},
    {"Category": "PostgreSQLFlexQueryStoreWaitStats", "Enabled": true},
    {"Category": "PostgreSQLFlexTableStats", "Enabled": true},
    {"Category": "PostgreSQLFlexDatabaseXacts", "Enabled": true}
  ]
}
```

---

## Summary

You have completed the following:

- Explored Azure Monitor platform metrics (CPU, memory, storage, connections)
- Created a Log Analytics workspace for log storage
- Configured diagnostic settings for all log categories
- Enabled Query Store and wait statistics collection
- Configured slow query logging
- Queried logs using KQL in Log Analytics
- Created alerts for CPU, storage, and connections
- Enabled Intelligent Performance index tuning

Key takeaway: Platform metrics are free and always on. Diagnostic logs require setup but give you PostgreSQL-level visibility. Query Store is essential for Query Performance Insight and Intelligent Performance features.
