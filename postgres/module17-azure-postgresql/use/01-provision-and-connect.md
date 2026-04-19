# USE 01 - Provision and Connect to Azure Database for PostgreSQL Flexible Server

## Objective

Create a Flexible Server from scratch, configure firewall rules, and verify connectivity. You will do everything from the command line using the Azure CLI.

---

## Exercise

### Task 1 - Create a Resource Group

Create a resource group named `use-lab-rg` in the `eastus` region.

```bash
az group create --name use-lab-rg --location eastus
```

The `--name` flag sets the resource group name. The `--location` flag sets the Azure region.

---

### Task 2 - Create a Flexible Server

Create a Burstable-tier server with these specifications:
- Name: `use-lab-pgserver`
- Admin user: `labadmin`
- Password: `UseLab2026!`
- SKU: `Standard_B1ms`
- PostgreSQL version: 16
- Storage: 32 GB
- Public access enabled

```bash
az postgres flexible-server create \
  --name use-lab-pgserver \
  --resource-group use-lab-rg \
  --location eastus \
  --admin-user labadmin \
  --admin-password 'UseLab2026!' \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 16 \
  --storage-size 32 \
  --public-access 0.0.0.0
```

Wait 3-5 minutes for the server to provision.

---

### Task 3 - Verify the Server Exists

Confirm the server is running and check its configuration.

```bash
az postgres flexible-server show \
  --resource-group use-lab-rg \
  --name use-lab-pgserver \
  --query "{Name:name, State:state, Version:version, SKU:sku.name, Tier:sku.tier, Storage:storage.storageSizeGb}" \
  --output table
```

Expected output (yours will differ):

```
Name              State   Version  SKU            Tier       Storage
----------------  ------  -------  -------------  ---------  -------
use-lab-pgserver  Ready   16       Standard_B1ms  Burstable  32
```

---

### Task 4 - Add a Firewall Rule for Your IP

Find your public IP.

```bash
curl -s https://ifconfig.me
```

Add a firewall rule. Replace `[YOUR_IP]` with the IP from the previous command.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group use-lab-rg \
  --name use-lab-pgserver \
  --rule-name my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

---

### Task 5 - Connect with psql

Connect to the server.

```bash
psql "host=use-lab-pgserver.postgres.database.azure.com port=5432 dbname=postgres user=labadmin sslmode=require"
```

Enter the password `UseLab2026!` when prompted.

Verify you are connected.

```sql
SELECT current_user, current_database(), version();
```

Expected output (yours will differ):

```
 current_user | current_database |                    version
--------------+------------------+----------------------------------------------
 labadmin     | postgres         | PostgreSQL 16.4 on x86_64-pc-linux-gnu ...
```

Exit psql.

```sql
\q
```

---

### Task 6 - Verify Server Settings

Check key server parameters from the Azure CLI.

```bash
az postgres flexible-server parameter show \
  --resource-group use-lab-rg \
  --server-name use-lab-pgserver \
  --name max_connections \
  --query "{Name:name, Value:value, Source:source}" \
  --output table
```

Expected output (yours will differ):

```
Name              Value  Source
----------------  -----  ---------------
max_connections   50     system-default
```

---

## Checklist

- [ ] Resource group `use-lab-rg` created in `eastus`
- [ ] Flexible Server `use-lab-pgserver` is in `Ready` state
- [ ] Firewall rule allows your IP
- [ ] psql connection succeeds with SSL
- [ ] Server version is PostgreSQL 16
- [ ] Compute tier is Burstable with Standard_B1ms SKU

---

## Clean Up

Delete the resource group when done.

```bash
az group delete --name use-lab-rg --yes --no-wait
```
