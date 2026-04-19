# BUILD 01 - Cloud SQL for PostgreSQL: Instance Setup

## What You Will Build

A production-ready Cloud SQL for PostgreSQL instance with proper networking, authentication, and connectivity. By the end, you will connect to your managed PostgreSQL database using both direct connection and the Cloud SQL Auth Proxy.

---

## Prerequisites

- A Google Cloud Platform account with billing enabled
- The `gcloud` CLI installed on your workstation
- A GCP project created and selected
- `psql` client installed locally

---

## Step 1 - Authenticate and Set Your Project

Log in to your GCP account. This opens a browser for OAuth authentication.

```bash
gcloud auth login
```

Set your default project. Replace `[PROJECT_ID]` with your actual project ID.

```bash
gcloud config set project [PROJECT_ID]
```

Expected output (yours will differ):

```
Updated property [core/project].
```

Enable the Cloud SQL Admin API. This is required before you can create any Cloud SQL resources.

```bash
gcloud services enable sqladmin.googleapis.com
```

Expected output (yours will differ):

```
Operation "operations/acf.p2-123456789-abc123" finished successfully.
```

Verify the API is enabled.

```bash
gcloud services list --filter="name:sqladmin.googleapis.com"
```

Expected output (yours will differ):

```
NAME                          TITLE
sqladmin.googleapis.com       Cloud SQL Admin API
```

---

## Step 2 - Choose Your Region and Zone

List all available regions for Cloud SQL.

```bash
gcloud sql tiers list --filter="tier:db-custom" --format="table(region)"
```

For this lab, we use `us-central1`. Choose the region closest to your users for lowest latency.

Check which zones are available in your region. The `--filter` flag narrows results to your region.

```bash
gcloud compute zones list --filter="region:us-central1"
```

Expected output (yours will differ):

```
NAME               REGION       STATUS
us-central1-a      us-central1  UP
us-central1-b      us-central1  UP
us-central1-c      us-central1  UP
us-central1-f      us-central1  UP
```

---

## Step 3 - Understand Machine Types

Cloud SQL uses `db-custom-` or predefined tiers. Here are the common options:

| Machine Type | vCPUs | RAM | Use Case |
|---|---|---|---|
| db-f1-micro | Shared | 0.6 GB | Dev/test only |
| db-g1-small | Shared | 1.7 GB | Small apps |
| db-custom-2-7680 | 2 | 7.5 GB | Small production |
| db-custom-4-15360 | 4 | 15 GB | Medium production |
| db-custom-8-30720 | 8 | 30 GB | Large production |
| db-custom-16-61440 | 16 | 60 GB | Heavy workloads |

The naming pattern is `db-custom-[vCPUs]-[RAM_in_MB]`. RAM must be between 3840 MB per vCPU and 6400 MB per vCPU.

List all available tiers to see what is supported.

```bash
gcloud sql tiers list
```

---

## Step 4 - Create the Cloud SQL Instance

Create a PostgreSQL 16 instance. Each flag is explained below.

- `--database-version`: PostgreSQL major version
- `--tier`: Machine type (2 vCPUs, 7.5 GB RAM)
- `--region`: GCP region for the instance
- `--storage-type`: SSD for production, HDD for cost savings
- `--storage-size`: Initial disk size in GB
- `--storage-auto-increase`: Automatically grow disk when running low
- `--storage-auto-increase-limit`: Maximum disk size in GB (0 means no limit)
- `--backup-start-time`: Daily backup window in UTC (HH:MM format)
- `--availability-type`: `regional` for HA (standby in another zone), `zonal` for single zone
- `--maintenance-window-day`: Day of week for maintenance (SUN=1 through SAT=7)
- `--maintenance-window-hour`: Hour in UTC for maintenance window

```bash
gcloud sql instances create suta-pg-lab \
  --database-version=POSTGRES_16 \
  --tier=db-custom-2-7680 \
  --region=us-central1 \
  --storage-type=SSD \
  --storage-size=20 \
  --storage-auto-increase \
  --storage-auto-increase-limit=100 \
  --backup-start-time=04:00 \
  --availability-type=zonal \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=2
```

This takes 3-5 minutes. Wait for the operation to complete.

Expected output (yours will differ):

```
Creating Cloud SQL instance for POSTGRES_16...done.
Created [https://sqladmin.googleapis.com/sql/v1beta4/projects/my-project/instances/suta-pg-lab].
NAME          DATABASE_VERSION  LOCATION       TIER              PRIMARY_ADDRESS  PRIVATE_ADDRESS  STATUS
suta-pg-lab   POSTGRES_16       us-central1-a  db-custom-2-7680  34.71.xx.xx      -                RUNNABLE
```

---

## Step 5 - Verify Instance Details

Describe the instance to confirm all settings. The `--format` flag outputs YAML for readability.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(name,databaseVersion,settings.tier,settings.dataDiskSizeGb,settings.backupConfiguration,settings.availabilityType,settings.maintenanceWindow)"
```

Expected output (yours will differ):

```yaml
databaseVersion: POSTGRES_16
name: suta-pg-lab
settings:
  availabilityType: ZONAL
  backupConfiguration:
    enabled: true
    startTime: '04:00'
  dataDiskSizeGb: '20'
  maintenanceWindow:
    day: 7
    hour: 2
  tier: db-custom-2-7680
```

---

## Step 6 - Set Database Flags

Database flags are Cloud SQL's equivalent of `postgresql.conf` parameters. Not all PostgreSQL parameters are available - Google controls the ones that could affect managed infrastructure.

Set logging and performance flags. Each flag is a key=value pair passed with `--database-flags`.

IMPORTANT: When you set flags, you must include ALL flags you want active. Omitting a previously set flag will reset it to default.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=log_statement=all,log_min_duration_statement=1000,log_connections=on,log_disconnections=on
```

Expected output (yours will differ):

```
The following message will be used for the patch API method.
{"project": "my-project", "name": "suta-pg-lab", ...}
Patching Cloud SQL instance...done.
```

List all supported flags for PostgreSQL 16. The `--database-version` flag filters to your version.

```bash
gcloud sql flags list --database-version=POSTGRES_16 --format="table(name,type,allowedStringValues,minValue,maxValue)"
```

---

## Step 7 - Configure Authorized Networks (Public IP)

By default, no external IP can connect. You must whitelist your IP address.

Find your current public IP.

```bash
curl -s ifconfig.me
```

Authorize your IP. The `--authorized-networks` flag takes a CIDR range. Use /32 for a single IP.

Replace `[YOUR_IP]` with the IP from the previous command.

```bash
gcloud sql instances patch suta-pg-lab \
  --authorized-networks=[YOUR_IP]/32
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

WARNING: For production, use Private IP or the Auth Proxy instead of authorized networks. Public IP with authorized networks is acceptable for development only.

---

## Step 8 - Set the postgres User Password

Set a strong password for the default `postgres` superuser.

```bash
gcloud sql users set-password postgres \
  --instance=suta-pg-lab \
  --password=[STRONG_PASSWORD]
```

Expected output (yours will differ):

```
Updating Cloud SQL user...done.
```

---

## Step 9 - Connect Directly with psql

Get the public IP of your instance.

```bash
gcloud sql instances describe suta-pg-lab --format="value(ipAddresses[0].ipAddress)"
```

Expected output (yours will differ):

```
34.71.123.45
```

Connect with psql. The `-h` flag is the host IP, `-U` is the user, `-d` is the database.

```bash
psql -h 34.71.123.45 -U postgres -d postgres
```

Once connected, verify you are on Cloud SQL.

```sql
SELECT version();
```

Expected output (yours will differ):

```
                                            version
-------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (Debian ...) ...
```

Check the instance identifier (Cloud SQL sets this automatically).

```sql
SHOW cloud_sql.iam_authentication;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 10 - Install and Use Cloud SQL Auth Proxy

The Auth Proxy provides a secure tunnel to your Cloud SQL instance without needing to whitelist IPs or manage SSL certificates. It handles authentication via IAM.

Download the Auth Proxy binary for your platform.

For macOS (Apple Silicon):

```bash
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.darwin.arm64
```

For macOS (Intel):

```bash
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.darwin.amd64
```

For Linux (x86_64):

```bash
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.linux.amd64
```

Make it executable.

```bash
chmod +x cloud-sql-proxy
```

Move it to your PATH.

```bash
sudo mv cloud-sql-proxy /usr/local/bin/
```

Get your instance connection name. This is the unique identifier in the format `project:region:instance`.

```bash
gcloud sql instances describe suta-pg-lab --format="value(connectionName)"
```

Expected output (yours will differ):

```
my-project:us-central1:suta-pg-lab
```

Start the proxy. It listens on localhost:5432 by default.

Replace `[CONNECTION_NAME]` with the output from the previous command.

```bash
cloud-sql-proxy [CONNECTION_NAME]
```

Expected output (yours will differ):

```
2026/04/19 10:00:00 Authorizing with Application Default Credentials
2026/04/19 10:00:00 [my-project:us-central1:suta-pg-lab] Listening on 127.0.0.1:5432
2026/04/19 10:00:00 The proxy has started successfully and is ready for new connections!
```

Leave the proxy running. Open a NEW terminal and connect through it. Since the proxy runs on localhost, you connect to 127.0.0.1.

```bash
psql -h 127.0.0.1 -U postgres -d postgres
```

Verify the connection works.

```sql
SELECT current_database(), current_user, inet_server_addr();
```

Type `\q` to exit psql.

```
\q
```

To stop the proxy, go back to the terminal where it is running and press `Ctrl+C`.

---

## Step 11 - Use a Custom Port for the Proxy

If port 5432 is already in use (for example, by a local PostgreSQL), run the proxy on a different port.

The `--port` flag sets the local listening port.

```bash
cloud-sql-proxy --port 15432 [CONNECTION_NAME]
```

Connect to the custom port.

```bash
psql -h 127.0.0.1 -p 15432 -U postgres -d postgres
```

---

## Step 12 - Create a Database and Table

Connect to the instance (via proxy or direct).

```bash
psql -h 127.0.0.1 -U postgres -d postgres
```

Create a database for the lab exercises.

```sql
CREATE DATABASE suta_lab;
```

Connect to the new database.

```
\c suta_lab
```

Create a test table.

```sql
CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    enrolled_at TIMESTAMPTZ DEFAULT now()
);
```

Insert sample data.

```sql
INSERT INTO students (name, email) VALUES
    ('Alice Chen', 'alice@example.com'),
    ('Bob Smith', 'bob@example.com'),
    ('Carol Davis', 'carol@example.com');
```

Verify the data.

```sql
SELECT * FROM students;
```

Expected output (yours will differ):

```
 student_id |    name     |       email        |         enrolled_at
------------+-------------+--------------------+-------------------------------
          1 | Alice Chen  | alice@example.com  | 2026-04-19 10:15:00.123456+00
          2 | Bob Smith   | bob@example.com    | 2026-04-19 10:15:00.123456+00
          3 | Carol Davis | carol@example.com  | 2026-04-19 10:15:00.123456+00
(3 rows)
```

Type `\q` to exit psql.

```
\q
```

---

## Cleanup (Optional)

If you want to delete the instance after the lab (do NOT do this if continuing to other BUILD guides).

```bash
gcloud sql instances delete suta-pg-lab
```

Type `Y` when prompted to confirm deletion.

---

## Summary

| Task | Command |
|---|---|
| Create instance | `gcloud sql instances create` |
| Set flags | `gcloud sql instances patch --database-flags=` |
| Authorize IP | `gcloud sql instances patch --authorized-networks=` |
| Set password | `gcloud sql users set-password` |
| Get connection name | `gcloud sql instances describe --format="value(connectionName)"` |
| Start proxy | `cloud-sql-proxy [CONNECTION_NAME]` |
| Connect via proxy | `psql -h 127.0.0.1 -U postgres` |

You now have a running Cloud SQL PostgreSQL instance with proper configuration, networking, and two ways to connect.
