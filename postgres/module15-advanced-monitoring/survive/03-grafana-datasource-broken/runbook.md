# SURVIVE Runbook - 03: Grafana Datasource Broken

**Scenario:** Grafana's Prometheus datasource URL points to the wrong port
**Symptom:** All dashboard panels show "No data" or "datasource not connected"
**Severity:** High - visualization is down but monitoring data collection continues

---

## Layer 1: Quick Triage

The key insight here: Prometheus may be perfectly healthy while Grafana cannot reach it.

Check Prometheus directly first (this works independently of Grafana):

```bash
curl -s http://localhost:9090/-/healthy
```

Expected output:

```
Prometheus Server is Healthy.
```

If Prometheus is healthy but Grafana shows no data, the problem is the connection between Grafana and Prometheus - not the data itself.

Open Grafana and look at the top of any dashboard panel. If you see a red or orange icon indicating "datasource error", click it. The error message will say something like:

```
Post "http://localhost:9999/api/v1/query": dial tcp 127.0.0.1:9999: connect: connection refused
```

This tells you exactly which URL Grafana is trying to connect to and that it is wrong.

---

## Layer 2: Root Cause Analysis

Check the Grafana datasource configuration via the API:

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources | python3 -m json.tool | grep -A3 '"url"'
```

Expected output when broken (yours will differ):

```json
        "url": "http://localhost:9999",
```

Compare this to where Prometheus actually runs:

```bash
ss -tlnp | grep 9090
```

The mismatch confirms the datasource URL is wrong.

Also check Grafana logs for datasource errors:

```bash
sudo journalctl -u grafana-server -n 50 --no-pager | grep -i "error\|datasource\|refused"
```

---

## Layer 3: Fix and Verify

### Step 1 - Open the datasource settings in Grafana

1. Log in to Grafana at `http://<your-server-ip>:3000`
2. Click the **hamburger menu** (three horizontal lines)
3. Click **Connections**
4. Click **Data sources**
5. Click the **Prometheus** datasource

### Step 2 - Fix the URL

In the **HTTP** section, find the **URL** field. Change it from the wrong value to:

```
http://localhost:9090
```

Click **Save & test**.

### Step 3 - Verify the save succeeded

Expected result: a green banner reading **"Successfully queried the Prometheus API."**

If you see an error, double-check the URL. Common mistakes:
- Extra space in the URL
- Wrong protocol (http vs https)
- Wrong port number

### Step 4 - Fix via the API (alternative if the UI is inaccessible)

First get the datasource ID:

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources | python3 -m json.tool | grep '"id"'
```

Then update it (replace `1` with your actual datasource ID):

```bash
curl -s -u admin:admin \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }' \
  http://localhost:3000/api/datasources/1
```

### Step 5 - Verify dashboards show data again

1. Open the PostgreSQL dashboard in Grafana
2. All panels should now show live data
3. Set the time range to "Last 15 minutes" and confirm data appears

---

## Prevention

- Store Grafana datasource configuration as code (Grafana provisioning YAML files)
- Never change the datasource URL without testing first
- If you must change the URL, use the "Save & test" button before saving
