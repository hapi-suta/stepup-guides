# BUILD 03: Grafana Dashboards for PostgreSQL

**Module 04 - Database Observability**
**Time Estimate:** 75 minutes
**Prerequisites:** Prometheus + postgres_exporter running (from BUILD 01 and BUILD 02)

---

## Step 1: Understand What Grafana Is

**Analogy:** Grafana is a visual query tool for metrics - like pgAdmin for Prometheus data. Where pgAdmin lets you browse tables and run SQL with visual results, Grafana lets you browse metrics and run PromQL with visual charts, graphs, and gauges.

**Key concepts:**

| Grafana Concept | DBA Analogy |
|---|---|
| Data source | A database connection (like a connection in pgAdmin) |
| Dashboard | A saved set of queries with visualizations (like a saved report) |
| Panel | One chart or visualization (like one query result) |
| Variable | A dropdown parameter (like a parameterized report - pick a database) |
| Alert | A threshold check on a panel (like a monitoring check) |

**Grafana does NOT store metrics.** It queries Prometheus (or other data sources) and visualizes the results. If Prometheus goes down, Grafana dashboards show "No data."

---

## Step 2: Install Grafana on Mac

**On your Mac, in your terminal:**

**Option A: Homebrew (recommended)**

```bash
brew install grafana
```

Start Grafana:

```bash
brew services start grafana
```

Expected output:
```
==> Successfully started `grafana`
```

**Option B: Docker**

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  grafana/grafana:latest
```

**Note:** If port 3000 is already in use by another application (like a Next.js dev server), either stop that application first or use an alternate port. For Docker, change `-p 3000:3000` to `-p 3001:3000` and access Grafana at `http://localhost:3001`. For Homebrew, edit the Grafana config at `/opt/homebrew/etc/grafana/grafana.ini` and change `http_port = 3000` to another port.

Verify Grafana is running by opening your browser to: [http://localhost:3000](http://localhost:3000)

**Default login:**
- Username: `admin`
- Password: `admin`
- You will be prompted to change the password. Set it to something you will remember for this lab.

---

## Step 3: Add Prometheus as a Data Source

This connects Grafana to your Prometheus instance so it can query metrics.

**In the Grafana web UI (http://localhost:3000):**

1. Click the hamburger menu (three lines) in the top-left corner
2. Click **Connections** then **Data sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Set these fields:
   - **Name:** `Prometheus`
   - **URL:** `http://localhost:9090`
   - Leave all other settings at defaults
6. Scroll down and click **Save & test**

Expected result: A green banner saying "Successfully queried the Prometheus API."

**DBA analogy:** This is like adding a server connection in pgAdmin. You just told Grafana where to find the metrics database.

---

## Step 4: Import a Pre-Built PostgreSQL Dashboard

The Grafana community publishes thousands of dashboards. Instead of building from scratch, start by importing one that is designed for postgres_exporter.

**In Grafana:**

1. Click the hamburger menu, then **Dashboards**
2. Click **New** then **Import**
3. In the "Import via grafana.com" field, enter dashboard ID: `9628`
   - This is the "PostgreSQL Database" dashboard by Grafana Labs
4. Click **Load**
5. In the "Prometheus" dropdown, select your `Prometheus` data source
6. Click **Import**

You should now see a dashboard with panels for:
- Database size
- Active connections
- Transactions per second
- Cache hit ratio
- Tuple operations
- And more

**If some panels show "No data":** This usually means the metric names in the dashboard do not match your postgres_exporter version. This is normal - we will build a custom dashboard next.

---

## Step 5: Understanding Dashboard Panel Types

Before building your own dashboard, understand what each panel type does:

| Panel Type | What It Shows | When to Use | DBA Example |
|---|---|---|---|
| **Time series** | Line/area chart over time | Trends and patterns | Connections over 24 hours |
| **Stat** | Single big number | Current value at a glance | Current connection count |
| **Gauge** | Colored arc meter | Value relative to a range | CPU percentage (0-100%) |
| **Bar gauge** | Horizontal or vertical bars | Comparing values across items | Database sizes side by side |
| **Table** | Tabular data | Lists and details | Top queries by execution time |
| **Heatmap** | Color-coded matrix | Distribution over time | Query latency distribution |
| **Alert list** | Active alerts | On-call dashboards | Currently firing alerts |

---

## Step 6: Build a Custom PostgreSQL Dashboard

We will build a dashboard from scratch with 6 panels covering the most important PostgreSQL metrics.

**In Grafana:**

1. Click the hamburger menu, then **Dashboards**
2. Click **New** then **New dashboard**
3. Click the gear icon (Dashboard settings) at the top
4. Set **Name** to: `PostgreSQL DBA Overview`
5. Click **Save dashboard** then **Save**

Now we add panels one at a time.

### Panel 1: Connection Count (Current vs Max)

1. Click **Add visualization**
2. Select your `Prometheus` data source
3. In the query field at the bottom, enter:
   ```promql
   pg_stat_activity_count
   ```
4. Click **+ Query** to add a second query:
   ```promql
   pg_settings_setting{name="max_connections"}
   ```
5. In the right sidebar:
   - **Title:** `Connections (Current vs Max)`
   - **Panel type:** Time series (default)
6. Click the **Overrides** tab in the right sidebar
   - Add override for query B (max_connections)
   - Set line style to "dashed" so it shows as a threshold line
7. Click **Apply** in the top right

### Panel 2: Transactions Per Second

1. Click **Add** then **Visualization**
2. Query:
   ```promql
   sum(rate(pg_stat_database_xact_commit[5m]))
   ```
3. Add a second query for rollbacks:
   ```promql
   sum(rate(pg_stat_database_xact_rollback[5m]))
   ```
4. Right sidebar:
   - **Title:** `Transactions Per Second`
   - **Panel type:** Time series
5. In the legend, rename queries to "Commits/s" and "Rollbacks/s"
6. Click **Apply**

### Panel 3: Cache Hit Ratio

1. Click **Add** then **Visualization**
2. Query (use the custom metric from BUILD 02):
   ```promql
   pg_cache_hit_ratio_cache_hit_ratio
   ```
   If you do not have the custom metric, use:
   ```promql
   sum(pg_stat_database_blks_hit) / (sum(pg_stat_database_blks_hit) + sum(pg_stat_database_blks_read)) * 100
   ```
3. Right sidebar:
   - **Title:** `Cache Hit Ratio`
   - **Panel type:** Gauge
   - Under "Standard options", set **Min:** `0`, **Max:** `100`, **Unit:** `percent (0-100)`
   - Under "Thresholds": set green > 95, yellow > 90, red < 90
4. Click **Apply**

### Panel 4: Replication Lag

1. Click **Add** then **Visualization**
2. Query:
   ```promql
   pg_replication_lag
   ```
   If this metric is not available (no replicas), use:
   ```promql
   pg_stat_replication_pg_wal_lsn_diff
   ```
3. Right sidebar:
   - **Title:** `Replication Lag`
   - **Panel type:** Stat
   - **Unit:** `seconds (s)` or `bytes` depending on the metric
   - **Thresholds:** green < 5, yellow < 30, red >= 30
4. Click **Apply**

If you do not have replication set up locally, this panel will show "No data" - that is fine.

### Panel 5: Database Sizes

1. Click **Add** then **Visualization**
2. Query:
   ```promql
   pg_database_size_bytes{datname!~"template.*"}
   ```
3. Right sidebar:
   - **Title:** `Database Sizes`
   - **Panel type:** Bar gauge
   - **Unit:** `bytes (IEC)` - this auto-formats to KB, MB, GB
   - **Orientation:** Horizontal
4. Under **Legend**, set to show `{{datname}}` so each bar shows the database name
5. Click **Apply**

### Panel 6: Dead Tuples by Table (Top 10)

1. Click **Add** then **Visualization**
2. Query:
   ```promql
   topk(10, pg_stat_user_tables_n_dead_tup > 0)
   ```
3. Right sidebar:
   - **Title:** `Top Tables by Dead Tuples`
   - **Panel type:** Table
4. Under **Legend**, set to show `{{relname}}`
5. Click **Apply**

**Save the dashboard:** Click the floppy disk icon at the top or press Ctrl+S.

---

## Step 7: Variables and Templates

**Analogy:** Variables are like parameterized queries. Instead of hardcoding a database name in every panel, you create a dropdown that lets you select the database at the top of the dashboard.

**In your PostgreSQL DBA Overview dashboard:**

1. Click the gear icon (Dashboard settings)
2. Click **Variables** in the left sidebar
3. Click **New variable**
4. Set:
   - **Name:** `database`
   - **Type:** Query
   - **Data source:** Prometheus
   - **Query:** `label_values(pg_database_size_bytes, datname)`
   - **Multi-value:** Enable (allows selecting multiple databases)
   - **Include All option:** Enable
5. Click **Apply** then **Save dashboard**

Now you have a `$database` dropdown at the top of the dashboard.

**Use the variable in a panel:**

Edit any panel and change the query to use the variable:

```promql
pg_database_size_bytes{datname=~"$database"}
```

The `=~` operator with `$database` lets Prometheus match the selected value(s) from the dropdown. If the user selects "All", it becomes a regex matching all databases.

**Add another variable for the instance (useful when monitoring multiple PostgreSQL servers):**

1. Add a new variable:
   - **Name:** `instance`
   - **Query:** `label_values(pg_stat_activity_count, instance)`
2. Use in panels: `pg_stat_activity_count{instance=~"$instance"}`

---

## Step 8: Time Range Controls and Refresh

**Top-right corner of any dashboard:**

| Control | What It Does |
|---|---|
| Time range picker | Change the viewing window (last 1h, 6h, 24h, 7d, custom) |
| Refresh interval | Auto-refresh the dashboard (off, 5s, 10s, 30s, 1m, 5m) |
| Zoom (click+drag on graph) | Zoom into a specific time range on any time series panel |

**Best practices:**

- Set default time range to **Last 6 hours** for operational dashboards
- Set refresh interval to **30s** for real-time monitoring
- Use **Last 7 days** for capacity planning views

**In dashboard settings:**

1. Click the gear icon
2. Under **General**, set **Auto-refresh** list to: `5s,10s,30s,1m,5m,15m`
3. Set **Time options** - Default time range: `now-6h to now`
4. Save

---

## Step 9: Sharing and Exporting Dashboards

### Export as JSON

1. Click the gear icon (Dashboard settings)
2. Click **JSON Model** in the left sidebar
3. Copy the JSON or click **Copy to clipboard**
4. Save to a file for version control:

```bash
# Save the dashboard JSON
vi ~/lab-prometheus/grafana-postgresql-dashboard.json
# Paste the JSON content
```

### Import from JSON

1. Go to **Dashboards** then **Import**
2. Click **Upload JSON file** or paste the JSON
3. Select the data source and click **Import**

### Share a snapshot (read-only link)

1. Click the share icon at the top of the dashboard
2. Click **Snapshot** tab
3. Set an expiration time
4. Click **Publish to snapshots.raintank.io** for a public link, or **Local Snapshot** for internal sharing

**Best practice:** Store dashboard JSON files in Git alongside your infrastructure code. This makes dashboards reproducible and reviewable.

---

## Step 10: Dashboard Organization Tips

As you build more dashboards, organize them:

**Folder structure:**

- **PostgreSQL** (folder)
  - PostgreSQL DBA Overview (the one we built)
  - PostgreSQL Replication
  - PostgreSQL Vacuum & Bloat
  - PostgreSQL Query Performance

- **Infrastructure** (folder)
  - Node Overview (OS metrics)
  - Disk I/O
  - Network

**Naming conventions:**
- Start with the system name: `PostgreSQL - Connection Health`
- Include the audience: `PostgreSQL - DBA Detail` vs `PostgreSQL - Team Overview`

**To create a folder:**

1. Go to **Dashboards**
2. Click **New** then **New folder**
3. Name it `PostgreSQL`
4. Move dashboards into the folder by editing each dashboard's settings

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Grafana purpose | Visual query tool for metrics - connects to Prometheus, does not store data |
| Data sources | Connection between Grafana and a metrics backend (Prometheus) |
| Importing dashboards | Use community dashboard IDs for quick starts |
| Panel types | Time series for trends, stat for current values, gauge for ranges, table for details |
| Building panels | Write PromQL queries, set visualization options, apply thresholds |
| Variables | Parameterized dropdowns - filter dashboards by database, instance, environment |
| Time controls | Range picker, auto-refresh, zoom-by-drag |
| Exporting | Save dashboard JSON to Git for version control and reproducibility |
| Key panels for DBAs | Connections, TPS, cache hit ratio, replication lag, database sizes, dead tuples |
