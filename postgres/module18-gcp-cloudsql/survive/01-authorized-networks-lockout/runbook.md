# RUNBOOK: Authorized Networks Lockout

## Symptom

Applications connecting via public IP are receiving connection timeouts. The Cloud SQL instance shows RUNNABLE but no external clients can connect.

---

## Step 1 - Verify the Instance Is Running

Check the instance state.

```bash
gcloud sql instances describe suta-pg-lab --format="value(state)"
```

Expected: `RUNNABLE`. If not, this is a different problem.

---

## Step 2 - Check Authorized Networks

List the current authorized networks.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.ipConfiguration.authorizedNetworks)"
```

If the output is empty or missing `authorizedNetworks`, that is the problem. No IPs are whitelisted.

---

## Step 3 - Get Your Public IP

Find your current public IP address.

```bash
curl -s ifconfig.me
```

---

## Step 4 - Add Your IP Back

Add your IP to the authorized networks. Replace `[YOUR_IP]` with the output from Step 3.

```bash
gcloud sql instances patch suta-pg-lab \
  --authorized-networks=[YOUR_IP]/32
```

For multiple IPs (e.g., your IP plus the application server), use a comma-separated list:

```bash
gcloud sql instances patch suta-pg-lab \
  --authorized-networks=[YOUR_IP]/32,[APP_SERVER_IP]/32
```

---

## Step 5 - Verify Connectivity

Get the instance public IP.

```bash
gcloud sql instances describe suta-pg-lab --format="value(ipAddresses[0].ipAddress)"
```

Test the connection.

```bash
psql -h [INSTANCE_IP] -U postgres -d postgres -c "SELECT 1 AS connected;"
```

Expected output:

```
 connected
-----------
         1
(1 row)
```

---

## Step 6 - Confirm Authorized Networks

Verify the authorized network was added correctly.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.ipConfiguration.authorizedNetworks)"
```

---

## Prevention

- Use the Auth Proxy instead of authorized networks for production
- Use Private IP to avoid public internet exposure
- Document required authorized networks in your runbook
- Set up alerts for Cloud SQL configuration changes via Cloud Audit Logs
