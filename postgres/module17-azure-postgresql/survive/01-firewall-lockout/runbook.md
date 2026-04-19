# SURVIVE 01 - Firewall Lockout Runbook

## Symptom

You cannot connect to the Azure Database for PostgreSQL Flexible Server. psql hangs or returns a connection timeout. The server shows as `Ready` in the Azure portal, but no external connections succeed.

---

## Diagnosis

### Step 1 - Check Server State

Verify the server is actually running.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, State:state}" \
  --output table
```

If `State` is `Ready`, the server is fine - the problem is network access.

### Step 2 - List Firewall Rules

Check if there are any firewall rules.

```bash
az postgres flexible-server firewall-rule list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

If this returns an empty table, that is the problem. No firewall rules means no IPs are allowed.

### Step 3 - Find Your Public IP

Get your current public IP address.

```bash
curl -s https://ifconfig.me
```

---

## Fix

### Step 4 - Add a Firewall Rule for Your IP

Replace `[YOUR_IP]` with the IP from Step 3.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name allow-my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

### Step 5 - Test Connection

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Enter the password when prompted. If the connection succeeds, the fix is complete.

Exit psql.

```sql
\q
```

---

## Prevention

- Always maintain at least one firewall rule for your admin IP
- Use Azure AD and conditional access policies for additional security layers
- Consider VNet integration for production workloads (no firewall rules needed)
- Set up alerts for firewall rule changes using Azure Activity Log alerts
