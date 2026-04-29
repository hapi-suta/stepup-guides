# Use Exercise 02 - Connection Monitoring Dashboard

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 45 minutes
**Prerequisite:** Build Guides 02-04 complete

---

## Objective

Build a custom Grafana dashboard from scratch that tracks PostgreSQL connection states over time. This teaches you how Grafana panels work and gives you a dashboard tailored to connection exhaustion monitoring.

---

## Background

Connection exhaustion is one of the most common PostgreSQL incidents. When you hit `max_connections`, new connections get rejected immediately. Most applications retry, which makes the problem worse. A good connection dashboard shows you:

- Total connections right now
- How many are active vs idle vs idle-in-transaction
- Which databases are consuming connections
- A trend line so you can predict when you will hit the limit

---

## Part 1 - Create a new dashboard

Log in to Grafana at `http://<your-server-ip>:3000`.

1. In the left sidebar, click the **four squares icon** (Dashboards)
2. Click **New**
3. Click **New dashboard**
4. Click **Add visualization**

---

## Part 2 - Build Panel 1: Total Active Connections (Stat panel)

This panel shows a single large number - current active connections. This is the first thing you look at during an incident.

In the panel editor:

**Query:**

```
sum(pg_stat_activity_count{job="postgres", state!="idle"})
```

**Panel settings (right sidebar):**
- Panel type: **Stat**
- Title: `Active Connections`
- Unit: **none** (short)
- Color mode: **Value**

**Threshold settings:**
- Add threshold at `50` - color: **Yellow**
- Add threshold at `80` - color: **Red**
- Base color: **Green**

Click **Apply** to save this panel.

---

## Part 3 - Build Panel 2: Connections by State (Time series)

This panel shows how connection states have evolved over time.

Click **Add** then **Visualization**.

**Query A:**

```
pg_stat_activity_count{job="postgres", state="active"}
```

Legend: `Active`

**Query B:**

```
pg_stat_activity_count{job="postgres", state="idle"}
```

Legend: `Idle`

**Query C:**

```
pg_stat_activity_count{job="postgres", state="idle in transaction"}
```

Legend: `Idle in Transaction`

**Query D:**

```
pg_stat_activity_count{job="postgres", state="idle in transaction (aborted)"}
```

Legend: `Idle in Txn (aborted)`

**Panel settings:**
- Panel type: **Time series**
- Title: `Connection States Over Time`
- Unit: **none** (short)
- Stack series: **Normal**
- Fill opacity: **20**

Click **Apply**.

---

## Part 4 - Build Panel 3: Connections by Database (Bar gauge)

This panel breaks down connections by database name, useful when multiple databases share one PostgreSQL instance.

Click **Add** then **Visualization**.

**Query:**

```
sum by (datname) (pg_stat_activity_count{job="postgres", datname!=""})
```

**Panel settings:**
- Panel type: **Bar gauge**
- Title: `Connections by Database`
- Orientation: **Horizontal**
- Display mode: **Basic**
- Unit: **none** (short)

Click **Apply**.

---

## Part 5 - Build Panel 4: Connection Utilization % (Gauge)

This panel shows what percentage of `max_connections` is currently in use.

Click **Add** then **Visualization**.

**Query:**

```
100 * sum(pg_stat_activity_count{job="postgres"}) / pg_settings_max_connections{job="postgres"}
```

**Panel settings:**
- Panel type: **Gauge**
- Title: `Connection Utilization %`
- Unit: **Percent (0-100)**
- Min: `0`
- Max: `100`

**Thresholds:**
- `70` - Yellow
- `85` - Red
- Base: Green

Click **Apply**.

---

## Part 6 - Build Panel 5: max_connections setting (Stat)

This panel shows the configured max_connections value. It rarely changes, but having it visible helps during incidents.

Click **Add** then **Visualization**.

**Query:**

```
pg_settings_max_connections{job="postgres"}
```

**Panel settings:**
- Panel type: **Stat**
- Title: `max_connections`
- Color mode: **None**
- Graph mode: **None**

Click **Apply**.

---

## Part 7 - Build Panel 6: Idle-in-Transaction Duration (Stat with alert annotation)

Long idle-in-transaction sessions hold locks. This panel shows the longest current idle-in-transaction duration.

Click **Add** then **Visualization**.

**Query:**

```
max(pg_stat_activity_max_tx_duration{job="postgres", state="idle in transaction"})
```

**Panel settings:**
- Panel type: **Stat**
- Title: `Max Idle-in-Transaction Duration`
- Unit: **Duration (s)**
- Color mode: **Value**

**Thresholds:**
- `60` (1 minute) - Yellow
- `300` (5 minutes) - Red
- Base: Green

Click **Apply**.

---

## Part 8 - Arrange the dashboard layout

Drag and resize panels to create a logical layout:

- Row 1 (small): Active Connections stat | Connection Utilization % gauge | max_connections stat
- Row 2 (large): Connection States Over Time (full width)
- Row 3: Connections by Database (left half) | Max Idle-in-Transaction (right half)

---

## Part 9 - Add a dashboard variable for database name

Dashboard variables let you filter all panels dynamically. You will add a variable that lets you select a specific database.

1. Click the **gear icon** (Dashboard settings) at the top right
2. Click **Variables** in the left sidebar
3. Click **Add variable**
4. Configure:
   - Type: **Query**
   - Name: `datname`
   - Label: `Database`
   - Query type: **Label values**
   - Label: `datname`
   - Metric: `pg_stat_activity_count`
   - Data source: `Prometheus`
   - Include All option: **On**
   - Default: **All**
5. Click **Update**
6. Click **Save dashboard** (back arrow then save)

Now update Query A in Panel 2 to use the variable:

```
pg_stat_activity_count{job="postgres", state="active", datname=~"$datname"}
```

Do the same for Queries B, C, D in Panel 2, and Panel 3's query. Now the dropdown at the top of the dashboard will filter all panels.

---

## Part 10 - Generate traffic to see the dashboard in action

Open a terminal and run this to simulate a connection leak (idle-in-transaction sessions).

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

```bash
sudo -i -u postgres
```

Run 5 concurrent pgbench sessions for 3 minutes:

```bash
/usr/pgsql-16/bin/pgbench -c 5 -T 180 -d stepup_store &
```

Simulate idle-in-transaction by opening several psql sessions that start a transaction but do not commit:

```bash
for i in 1 2 3; do
  psql -d stepup_store -c "BEGIN; SELECT pg_sleep(120);" &
done
```

Watch the dashboard. The **Idle in Transaction** line on Panel 2 should rise. The **Max Idle-in-Transaction Duration** stat should turn yellow then red.

---

## Part 11 - Save and set the dashboard as your home dashboard

1. Click the **save icon** at the top of the dashboard
2. Name it: `PostgreSQL - Connection Monitoring`
3. Click **Save**
4. Click the **star icon** next to the dashboard name to mark it as a favorite

---

## Reflection Questions

1. What PromQL aggregation function did you use to sum connections across all databases? Why `sum` and not `avg`?
2. What does `state="idle in transaction"` mean for a session? Why is it a problem?
3. If max_connections is 100 and you set a warning at 70%, what is the actual connection count that triggers the warning?
4. Why is the **Connection States Over Time** panel more useful than the **Active Connections** stat panel for diagnosing incidents?
5. What happens to the application when PostgreSQL reaches max_connections?
