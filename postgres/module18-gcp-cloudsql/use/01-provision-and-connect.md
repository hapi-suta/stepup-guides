# USE 01 - Provision and Connect to Cloud SQL

## Objective

Create a Cloud SQL PostgreSQL instance from scratch, connect via the Auth Proxy, and verify the configuration matches production standards.

---

## Exercise 1 - Create the Instance

Create a PostgreSQL 16 instance with the following requirements:
- Instance name: `exercise-pg`
- Machine type: 2 vCPUs, 7.5 GB RAM
- Region: `us-central1`
- SSD storage, 25 GB, auto-increase enabled (limit 50 GB)
- Backup at 05:00 UTC
- Zonal availability
- Maintenance window: Saturday at 4:00 AM UTC

```bash
gcloud sql instances create exercise-pg \
  --database-version=POSTGRES_16 \
  --tier=db-custom-2-7680 \
  --region=us-central1 \
  --storage-type=SSD \
  --storage-size=25 \
  --storage-auto-increase \
  --storage-auto-increase-limit=50 \
  --backup-start-time=05:00 \
  --availability-type=zonal \
  --maintenance-window-day=SAT \
  --maintenance-window-hour=4
```

Wait for creation to complete (3-5 minutes).

---

## Exercise 2 - Set the Password

Set a strong password for the postgres user.

```bash
gcloud sql users set-password postgres \
  --instance=exercise-pg \
  --password=SecureLabPassword123
```

---

## Exercise 3 - Connect via Cloud SQL Auth Proxy

Get the connection name.

```bash
gcloud sql instances describe exercise-pg --format="value(connectionName)"
```

Start the proxy in a terminal.

```bash
cloud-sql-proxy [CONNECTION_NAME]
```

Open a new terminal and connect.

```bash
psql -h 127.0.0.1 -U postgres -d postgres
```

Run these verification queries:

```sql
SELECT version();
```

```sql
SHOW server_version;
```

```sql
SELECT current_database(), current_user;
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 4 - Verify Configuration

Check that your instance matches the requirements.

```bash
gcloud sql instances describe exercise-pg --format="yaml(name,databaseVersion,settings.tier,settings.dataDiskSizeGb,settings.dataDiskType,settings.storageAutoResize,settings.storageAutoResizeLimit,settings.backupConfiguration.startTime,settings.availabilityType,settings.maintenanceWindow)"
```

---

## Checklist

- [ ] Instance created with PostgreSQL 16
- [ ] Machine type is db-custom-2-7680
- [ ] Storage is SSD, 25 GB, auto-increase to 50 GB
- [ ] Backup window at 05:00 UTC
- [ ] Maintenance window Saturday at 04:00 UTC
- [ ] Connected via Auth Proxy
- [ ] Verified PostgreSQL version
- [ ] Verified database and user

---

## Cleanup

```bash
gcloud sql instances delete exercise-pg
```

Type `Y` to confirm.
