# Build Guide 04 - Install Grafana

**Module:** 15 - Advanced Monitoring
**Node:** pg-primary
**Time:** ~30 minutes

---

## Overview

Grafana is the visualization layer of your monitoring stack. Prometheus stores raw metrics - Grafana lets you turn those metrics into dashboards with graphs, gauges, and tables. You can build dashboards from scratch or import pre-built ones from the Grafana community.

In this guide you will install Grafana OSS (the free, open-source version), connect it to your Prometheus server, and import a pre-built PostgreSQL dashboard so you have immediate visibility into your database.

---

## Step 1 - Log in to pg-primary

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

---

## Step 2 - Add the Grafana yum repository

The Grafana project provides an official RPM repository for RHEL-compatible systems. Adding this repo lets you install and upgrade Grafana through the standard package manager.

```bash
sudo tee /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=Grafana OSS
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
```

---

## Step 3 - Verify the repo file was created

```bash
cat /etc/yum.repos.d/grafana.repo
```

Expected output (yours will differ):

```
[grafana]
name=Grafana OSS
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
...
```

---

## Step 4 - Install Grafana

`dnf install -y` installs the package and automatically answers "yes" to all prompts.

```bash
sudo dnf install -y grafana
```

Expected output (yours will differ):

```
Updating Subscription Management repositories.
Last metadata expiration check: ...
Dependencies resolved.
================================================================================
 Package         Arch    Version   Repository  Size
================================================================================
Installing:
 grafana         x86_64  10.4.x    grafana     90 M
...
Complete!
```

---

## Step 5 - Enable Grafana to start on boot

```bash
sudo systemctl enable grafana-server
```

Expected output (yours will differ):

```
Created symlink /etc/systemd/system/multi-user.target.wants/grafana-server.service -> /usr/lib/systemd/system/grafana-server.service.
```

---

## Step 6 - Start Grafana

```bash
sudo systemctl start grafana-server
```

---

## Step 7 - Check Grafana status

```bash
sudo systemctl status grafana-server
```

Expected output (yours will differ):

```
● grafana-server.service - Grafana instance
     Loaded: loaded (/usr/lib/systemd/system/grafana-server.service; enabled; preset: disabled)
     Active: active (running) since Tue 2024-03-01 14:40:00 UTC; 5s ago
   Main PID: 14567 (grafana)
      Tasks: 12 (limit: 4915)
     Memory: 78.4M
     CGroup: /system.slice/grafana-server.service
             └─14567 /usr/sbin/grafana server --config=/etc/grafana/grafana.ini ...
```

---

## Step 8 - Verify Grafana is listening on port 3000

```bash
ss -tlnp | grep 3000
```

Expected output (yours will differ):

```
LISTEN 0      128          0.0.0.0:3000      0.0.0.0:*    users:(("grafana",pid=14567,fd=12))
```

---

## Step 9 - Open Grafana in your browser

Navigate to:

```
http://<your-server-ip>:3000
```

If you cannot reach this address, add an inbound rule in your AWS security group: `TCP port 3000, source: My IP`.

---

## Step 10 - Log in to Grafana

The default credentials are:
- **Username:** `admin`
- **Password:** `admin`

Grafana will immediately ask you to change the password. Set a new password you will remember.

---

## Step 11 - Add Prometheus as a data source

A data source tells Grafana where to fetch metric data. You need to connect Grafana to your local Prometheus instance.

1. In the left sidebar, click the **three horizontal lines** (hamburger menu)
2. Click **Connections**
3. Click **Data sources**
4. Click **Add data source**
5. Click **Prometheus** from the list

---

## Step 12 - Configure the Prometheus data source

Fill in the following fields:

| Field | Value |
|---|---|
| Name | `Prometheus` |
| URL | `http://localhost:9090` |
| Scrape interval | `15s` |

Leave all other fields at their defaults.

Scroll down and click **Save & test**.

Expected result: A green banner appears with the message **"Successfully queried the Prometheus API"**. If you see a red error, check that Prometheus is running with `sudo systemctl status prometheus`.

---

## Step 13 - Import the PostgreSQL overview dashboard

The Grafana community dashboard library has a pre-built PostgreSQL dashboard with ID **9628**. This dashboard uses metrics from postgres_exporter and gives you immediate visibility into connections, cache hit ratio, transaction rate, and more.

1. In the left sidebar, click the **four squares** icon (Dashboards)
2. Click **New**
3. Click **Import**
4. In the "Import via grafana.com" field, type `9628`
5. Click **Load**

---

## Step 14 - Configure the imported dashboard

After clicking Load, Grafana shows a configuration screen:

| Field | Value |
|---|---|
| Name | `PostgreSQL Database` |
| Folder | `General` |
| Prometheus | Select `Prometheus` from the dropdown |

Click **Import**.

---

## Step 15 - Explore the dashboard

You should now see a dashboard with multiple panels. Key panels to look at:

- **Connections** - total active and idle connections over time
- **Cache Hit Ratio** - percentage of blocks served from shared_buffers vs disk
- **Transaction Rate** - commits and rollbacks per second
- **Tuple Operations** - inserts, updates, deletes per second
- **WAL Generation** - write-ahead log bytes written per second

Wait 2-3 minutes for data to accumulate if the graphs look empty. Prometheus only has data from the time it started scraping.

---

## Step 16 - Generate some traffic to see data

Open a second terminal, log in, and run pgbench so the dashboard has something to show.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

```bash
sudo -u postgres /usr/pgsql-16/bin/pgbench -c 10 -T 120 -d stepup_store
```

Switch back to your browser and watch the dashboard panels update. The connection count, transaction rate, and tuple operation panels should show increased activity.

---

## Step 17 - Explore PromQL in the Explore view

Grafana has an Explore view for running ad-hoc PromQL queries directly, without building a dashboard panel.

1. In the left sidebar, click the **compass icon** (Explore)
2. Make sure **Prometheus** is selected as the data source
3. In the query field, type:

```
pg_stat_activity_count{job="postgres"}
```

4. Click **Run query**

You should see a time-series graph showing connection counts grouped by state.

---

## Step 18 - Try a few more PromQL queries in Explore

Cache hit ratio:

```
pg_stat_database_blks_hit{datname="stepup_store"} /
(pg_stat_database_blks_hit{datname="stepup_store"} + pg_stat_database_blks_read{datname="stepup_store"})
```

Transaction rate (transactions per second, calculated over 5-minute windows):

```
rate(pg_stat_database_xact_commit{datname="stepup_store"}[5m]) +
rate(pg_stat_database_xact_rollback{datname="stepup_store"}[5m])
```

---

## Step 19 - Check Grafana logs if something is not working

```bash
sudo journalctl -u grafana-server -n 50 --no-pager
```

---

## Summary

You have:
- Added the official Grafana yum repository
- Installed Grafana OSS
- Logged in and changed the default password
- Connected Grafana to your Prometheus data source
- Imported the community PostgreSQL dashboard (ID 9628)
- Verified live data is flowing through the full stack

In the next guide you will configure Prometheus alerting rules so you get notified when something goes wrong.
