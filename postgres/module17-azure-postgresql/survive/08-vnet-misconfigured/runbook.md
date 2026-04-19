# SURVIVE 08 - VNet Misconfigured Runbook

## Symptom

You cannot connect to the Azure Database for PostgreSQL Flexible Server. The connection times out. The server shows as `Ready` in Azure, but no client can establish a connection.

---

## Diagnosis

### Step 1 - Verify Server is Running

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, State:state}" \
  --output table
```

If `State` is `Ready`, the problem is networking.

### Step 2 - Check Firewall Rules

List all firewall rules and check if your IP is allowed.

```bash
az postgres flexible-server firewall-rule list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

Check the IP ranges. If they do not include your IP, that is the problem.

### Step 3 - Find Your Public IP

```bash
curl -s https://ifconfig.me
```

Compare this IP with the firewall rules. If your IP is not in any allowed range, that explains the timeout.

### Step 4 - Check for NSG Rules (VNet scenarios)

If the server uses VNet integration, check for Network Security Group rules that might be blocking traffic.

```bash
az network nsg list \
  --resource-group suta-pg-lab-rg \
  --query "[].{Name:name, Rules:securityRules[].{RuleName:name, Access:access, Direction:direction, Port:destinationPortRange, Priority:priority}}" \
  --output json
```

Look for any `Deny` rules on port 5432.

---

## Fix

### Step 5 - Remove Wrong Firewall Rules

Delete the incorrect firewall rule.

```bash
az postgres flexible-server firewall-rule delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name wrong-network \
  --yes
```

### Step 6 - Add Correct Firewall Rule

Replace `[YOUR_IP]` with your actual IP from Step 3.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name allow-my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

### Step 7 - Fix NSG Rules (if applicable)

Delete the blocking NSG rule.

```bash
az network nsg rule delete \
  --resource-group suta-pg-lab-rg \
  --nsg-name suta-pg-block-nsg \
  --name deny-postgres
```

Or delete the entire NSG if it was created for testing.

```bash
az network nsg delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-block-nsg
```

### Step 8 - Test Connectivity

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Once connected, run a quick test.

```sql
SELECT current_user, inet_server_addr(), inet_server_port();
```

Exit psql.

```sql
\q
```

### Step 9 - Verify All Rules

Confirm the firewall rules look correct.

```bash
az postgres flexible-server firewall-rule list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

---

## Prevention

- Document all firewall rules and their purpose
- Use infrastructure-as-code to manage firewall rules (prevents manual errors)
- For production, prefer VNet integration over public access with firewall rules
- Never create blanket NSG deny rules without understanding the impact
- Test connectivity after any network configuration change
- Set up connectivity alerts to detect access issues quickly
