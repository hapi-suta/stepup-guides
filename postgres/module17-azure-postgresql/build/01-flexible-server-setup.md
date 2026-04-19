# BUILD 01 - Azure Database for PostgreSQL Flexible Server Setup

## Overview

In this guide you will create an Azure Database for PostgreSQL Flexible Server from scratch using the Azure CLI. You will choose a compute tier, configure storage, set up networking, adjust server parameters, and verify connectivity with psql.

---

## Prerequisites

- An active Azure subscription
- Azure CLI installed (version 2.50+)
- psql client installed locally
- Your subscription ID available

---

## Step 1 - Install and Verify Azure CLI

Check your Azure CLI version.

```bash
az --version
```

Expected output (yours will differ):

```
azure-cli                         2.61.0
core                              2.61.0
telemetry                          1.1.0
...
```

If you do not have az installed, follow the official docs for your OS at https://learn.microsoft.com/en-us/cli/azure/install-azure-cli.

---

## Step 2 - Log In to Azure

Authenticate to your Azure account. This opens a browser window for interactive login.

```bash
az login
```

Expected output (yours will differ):

```
A web browser has been opened at https://login.microsoftonline.com/...
[
  {
    "cloudName": "AzureCloud",
    "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "isDefault": true,
    "name": "My Subscription",
    "state": "Enabled",
    "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
]
```

---

## Step 3 - Set Your Subscription

If you have multiple subscriptions, set the one you want to use. Replace `[SUBSCRIPTION_ID]` with your actual subscription ID.

```bash
az account set --subscription [SUBSCRIPTION_ID]
```

This command produces no output on success. Verify it took effect.

```bash
az account show --query "{name:name, id:id}" --output table
```

Expected output (yours will differ):

```
Name               Id
-----------------  ------------------------------------
My Subscription    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

## Step 4 - Create a Resource Group

A resource group is a container that holds related Azure resources. The `--location` flag sets the Azure region. We use `eastus` here - pick the region closest to your students or workload.

```bash
az group create --name suta-pg-lab-rg --location eastus
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../resourceGroups/suta-pg-lab-rg",
  "location": "eastus",
  "name": "suta-pg-lab-rg",
  "properties": {
    "provisioningState": "Succeeded"
  },
  "type": "Microsoft.Resources/resourceGroups"
}
```

---

## Step 5 - Understand Compute Tiers

Azure Flexible Server offers three compute tiers. Pick the one that matches your workload.

| Tier | vCores | Use Case | Example SKU |
|------|--------|----------|-------------|
| Burstable | 1-20 | Dev/test, low-traffic apps | Standard_B1ms |
| General Purpose | 2-96 | Production, balanced workloads | Standard_D2ds_v4 |
| Memory Optimized | 2-96 | High-memory workloads, caching | Standard_E2ds_v4 |

**Burstable** is cheapest - good for labs and development. It can burst above baseline CPU when needed.

**General Purpose** gives consistent CPU performance for production workloads.

**Memory Optimized** provides a higher memory-to-vCPU ratio for workloads like large joins, sorting, or caching.

---

## Step 6 - Understand Storage Options

Flexible Server storage has these characteristics:

- **Minimum**: 32 GB
- **Maximum**: 16 TB
- **Auto-grow**: Can be enabled so storage expands automatically when usage hits a threshold
- **IOPS**: Scales with storage size (3 IOPS per GB baseline, with provisioned IOPS available on Premium SSD v2)
- **Storage type**: Premium SSD (default) or Premium SSD v2

You cannot shrink storage after creation. Plan your initial size carefully.

---

## Step 7 - Create the Flexible Server (Public Access)

This command creates a Flexible Server with public access networking. Each flag is explained below.

- `--name`: Unique server name (becomes part of the FQDN)
- `--resource-group`: The resource group from Step 4
- `--location`: Azure region
- `--admin-user`: The PostgreSQL admin username
- `--admin-password`: The admin password (must be 8-128 chars, with uppercase, lowercase, number, and special character)
- `--sku-name`: The compute SKU (Burstable B1ms for lab use)
- `--tier`: The compute tier
- `--version`: PostgreSQL major version
- `--storage-size`: Initial storage in GB
- `--public-access`: Set to `0.0.0.0` to allow configuring firewall rules later

```bash
az postgres flexible-server create \
  --name suta-pg-lab-server \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --admin-user pgadmin \
  --admin-password 'SutaLab2026!' \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 16 \
  --storage-size 32 \
  --public-access 0.0.0.0
```

Expected output (yours will differ):

```json
{
  "connectionString": "postgresql://pgadmin:SutaLab2026!@suta-pg-lab-server.postgres.database.azure.com/postgres?sslmode=require",
  "host": "suta-pg-lab-server.postgres.database.azure.com",
  "id": "/subscriptions/.../providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server",
  "location": "eastus",
  "resourceGroup": "suta-pg-lab-rg",
  "skuname": "Standard_B1ms",
  "version": "16"
}
```

This takes 3-5 minutes. Wait for it to complete before moving on.

---

## Step 8 - Create the Flexible Server (VNet Integration)

If you need private networking instead of public access, use VNet integration. This creates a server accessible only from within the specified virtual network.

First, create a virtual network and a delegated subnet.

```bash
az network vnet create \
  --name suta-pg-vnet \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --address-prefix 10.0.0.0/16
```

Create a subnet delegated to PostgreSQL Flexible Server. The `--delegations` flag tells Azure this subnet is reserved for Flexible Server.

```bash
az network vnet subnet create \
  --name suta-pg-subnet \
  --resource-group suta-pg-lab-rg \
  --vnet-name suta-pg-vnet \
  --address-prefix 10.0.1.0/24 \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers
```

Now create the server with VNet integration. The `--subnet` flag replaces `--public-access`.

```bash
az postgres flexible-server create \
  --name suta-pg-lab-vnet-server \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --admin-user pgadmin \
  --admin-password 'SutaLab2026!' \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 16 \
  --storage-size 32 \
  --vnet suta-pg-vnet \
  --subnet suta-pg-subnet
```

A VNet-integrated server has no public IP. You can only reach it from within the VNet or via a peered network.

---

## Step 9 - Add a Firewall Rule (Public Access Only)

For public access servers, you must add firewall rules to allow connections. This rule allows your current IP.

First, find your public IP.

```bash
curl -s https://ifconfig.me
```

Now create the firewall rule. Replace `[YOUR_IP]` with the IP from the previous command. The `--start-ip-address` and `--end-ip-address` define the allowed range - use the same IP for both to allow a single address.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name allow-my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

Expected output (yours will differ):

```json
{
  "endIpAddress": "203.0.113.50",
  "name": "allow-my-ip",
  "resourceGroup": "suta-pg-lab-rg",
  "startIpAddress": "203.0.113.50"
}
```

---

## Step 10 - List Firewall Rules

Verify your firewall rules are in place.

```bash
az postgres flexible-server firewall-rule list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

Expected output (yours will differ):

```
Name          StartIpAddress    EndIpAddress
------------  ----------------  ----------------
allow-my-ip   203.0.113.50      203.0.113.50
```

---

## Step 11 - View Server Parameters

List all server parameters. The `--output table` flag makes it readable. The `--query` flag filters to show only name, value, and source columns.

```bash
az postgres flexible-server parameter list \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --query "[].{Name:name, Value:value, Source:source}" \
  --output table
```

Expected output (yours will differ):

```
Name                          Value     Source
----------------------------  --------  ---------------
shared_buffers                131072    system-default
work_mem                      4096      system-default
max_connections               50        system-default
...
```

---

## Step 12 - Set a Server Parameter

Change a server parameter. Here we increase `max_connections` to 200. The `--value` flag sets the new value.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name max_connections \
  --value 200
```

Expected output (yours will differ):

```json
{
  "allowedValues": "25-5000",
  "dataType": "Integer",
  "defaultValue": "50",
  "name": "max_connections",
  "source": "user-override",
  "value": "200"
}
```

Note: `max_connections` is a static parameter. The server will restart automatically to apply it.

---

## Step 13 - Restart the Server

If you changed a static parameter and the server did not auto-restart, trigger a manual restart. This causes a brief downtime (typically 30-60 seconds).

```bash
az postgres flexible-server restart \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server
```

Expected output (yours will differ):

```
Command ran in 45 seconds.
```

---

## Step 14 - Connect with psql

Connect to the server using psql. The `--host` is your server's FQDN. SSL mode is required by default.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Enter your password (`SutaLab2026!`) when prompted.

Expected output (yours will differ):

```
psql (16.3, server 16.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

---

## Step 15 - Verify Server Settings from psql

Once connected, check some key settings.

```sql
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('max_connections', 'shared_buffers', 'work_mem')
ORDER BY name;
```

Expected output (yours will differ):

```
      name       | setting | unit |       source
-----------------+---------+------+-------------------
 max_connections  | 200     |      | configuration file
 shared_buffers   | 131072  | 8kB  | configuration file
 work_mem         | 4096    | kB   | configuration file
```

Check the PostgreSQL version.

```sql
SELECT version();
```

Expected output (yours will differ):

```
                                          version
--------------------------------------------------------------------------------------------
 PostgreSQL 16.4 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 13.2.1, 64-bit
```

Exit psql.

```sql
\q
```

---

## Step 16 - View Server Details

Check the full server configuration.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, State:state, Version:version, SKU:sku.name, Tier:sku.tier, Storage:storage.storageSizeGb, HA:highAvailability.mode, Location:location}" \
  --output table
```

Expected output (yours will differ):

```
Name                 State   Version  SKU            Tier       Storage  HA        Location
-------------------  ------  -------  -------------  ---------  -------  --------  --------
suta-pg-lab-server   Ready   16       Standard_B1ms  Burstable  32       Disabled  eastus
```

---

## Step 17 - Enable Storage Auto-Grow

Enable auto-grow so storage expands automatically when it gets full. This prevents outages caused by running out of disk space.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --storage-auto-grow Enabled
```

Expected output (yours will differ):

```json
{
  "storage": {
    "autoGrow": "Enabled",
    "storageSizeGb": 32
  }
}
```

---

## Summary

You have completed the following:

- Installed and authenticated with Azure CLI
- Created a resource group
- Created a Flexible Server with both public access and VNet integration options
- Added firewall rules for public access
- Modified server parameters
- Connected with psql and verified settings
- Enabled storage auto-grow

Your server FQDN follows this pattern: `[SERVER_NAME].postgres.database.azure.com`

---

## Clean Up (Optional)

To delete everything when you are done with the lab, delete the resource group. The `--yes` flag skips the confirmation prompt. The `--no-wait` flag returns immediately without waiting for deletion.

```bash
az group delete --name suta-pg-lab-rg --yes --no-wait
```

This deletes the resource group and all resources inside it.
