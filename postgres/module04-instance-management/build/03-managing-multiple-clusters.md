# Module 04 - Creating and Managing Instances
## Guide 03: Managing Multiple Clusters

**Objective:** Learn to run multiple independent PostgreSQL clusters on the same server. You will inventory existing clusters, create a third one, give it a systemd service for production-style management, demonstrate cluster independence, and practice connecting to specific clusters.

**Time:** 55-60 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432 with PGDATA at `/opt/pgsql/data`
- PostgreSQL 15 running on port 5433 with PGDATA at `/opt/pgsql/data15`

---

## 1. Inventory Existing Clusters

Before creating a new cluster, confirm what is already running. A well-managed server should have a clear inventory of every cluster.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Check whether the PG16 cluster is accepting connections on port 5432. The `pg_isready` command returns a one-line status:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

Check the PG15 cluster on port 5433:

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - accepting connections
```

List the systemd services for PostgreSQL. The `--type=service` flag filters for services only:

```bash
sudo systemctl list-units --type=service | grep postgresql
```

Expected output (yours will differ):

```
  postgresql-15.service   loaded active running   PostgreSQL 15 database server
  postgresql-16.service   loaded active running   PostgreSQL 16 database server
```

Two services, two clusters, two ports. Now use `pg_controldata` to see their unique identifiers.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Get the system identifier for PG16:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7490123456789012345
```

Get the system identifier for PG15:

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7488765432109876543
```

Different identifiers confirm these are completely independent clusters. They share the same server hardware and the same `postgres` OS user, but nothing else.

> **Concept: Cluster isolation**
> Each PostgreSQL cluster has its own PGDATA directory, its own port, its own PID file, its own Unix socket, its own WAL, and its own system identifier. Stopping one cluster has zero effect on the others. This is how hosting providers run hundreds of PostgreSQL instances on one machine - each customer gets a separate cluster.

Exit the postgres session:

```bash
exit
```

---

## 2. Create a Third Cluster

You will create a new PG16 test cluster on port 5435. This demonstrates that you can run multiple clusters of the same major version side by side.

Switch to root to create the data directory:

```bash
sudo su -
```

Create the directory:

```bash
mkdir /opt/pgsql/data-multi
```

Set ownership to the `postgres` user:

```bash
chown postgres:postgres /opt/pgsql/data-multi
```

Set permissions to 700:

```bash
chmod 700 /opt/pgsql/data-multi
```

Exit the root session:

```bash
exit
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Initialize the new cluster with data checksums enabled:

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data-multi --data-checksums --locale=en_US.UTF-8 --encoding=UTF8
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Data page checksums are enabled.
...
Success. You can now start the database server using:

    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data-multi -l logfile start
```

Configure the port and listen_addresses. Open the configuration file:

```bash
vi /opt/pgsql/data-multi/postgresql.conf
```

Find the `#port = 5432` line (search with `/port` in vi) and change it to:

```
port = 5435
```

Find the `#listen_addresses = 'localhost'` line and change it to:

```
listen_addresses = 'localhost'
```

Save and exit vi (`:wq`).

Start the cluster with `pg_ctl`:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-multi -l /opt/pgsql/log/pg-multi.log
```

Expected output:

```
waiting for server to start.... done
server started
```

Verify it is running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - accepting connections
```

Exit the postgres session:

```bash
exit
```

---

## 3. Create a systemd Service

In production, every cluster should have its own systemd service. This gives you automatic startup on boot, restart-on-failure, standardized log management, and `systemctl start/stop/status` commands that operations teams expect.

First, look at the existing PG16 service to understand the format:

```bash
sudo systemctl cat postgresql-16
```

Expected output (yours will differ):

```
# /usr/lib/systemd/system/postgresql-16.service
[Unit]
Description=PostgreSQL 16 database server
Documentation=https://www.postgresql.org/docs/16/static/
After=syslog.target
After=network-online.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/pgsql/16/data/
...
ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}
ExecReload=/bin/kill -HUP $MAINPID
...

[Install]
WantedBy=multi-user.target
```

Now create a new service for the test cluster. The `systemctl edit --full --force` command creates a new unit file and opens it in vi:

```bash
sudo systemctl edit --full --force postgresql-16-multi
```

Enter this content:

```
[Unit]
Description=PostgreSQL 16 Multi-Test database server
After=syslog.target
After=network-online.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/opt/pgsql/data-multi

ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=infinity

[Install]
WantedBy=multi-user.target
```

Save and exit vi (`:wq`).

> **Concept: systemd unit per cluster**
> Each cluster needs its own systemd unit file because the `PGDATA` environment variable must point to the correct data directory. If two services shared the same unit file, they would both try to use the same PGDATA - which would fail. The unit file also sets the `User` to `postgres`, ensuring the server process runs with the correct permissions.

Before starting with systemd, stop the `pg_ctl`-managed instance first. You cannot have both systemd and `pg_ctl` managing the same cluster:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-multi
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Exit the postgres session:

```bash
exit
```

Now start the cluster using systemd:

```bash
sudo systemctl start postgresql-16-multi
```

Check the status:

```bash
sudo systemctl status postgresql-16-multi
```

Expected output (yours will differ):

```
● postgresql-16-multi.service - PostgreSQL 16 Multi-Test database server
     Loaded: loaded (/etc/systemd/system/postgresql-16-multi.service; disabled; preset: disabled)
     Active: active (running) since ...
   Main PID: 12345 (postgres)
     ...
```

The service is `active (running)`. Notice it says `disabled` - that means it will not start automatically on boot. Enable it:

```bash
sudo systemctl enable postgresql-16-multi
```

Expected output:

```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-16-multi.service → /etc/systemd/system/postgresql-16-multi.service.
```

Verify all three clusters are running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - accepting connections
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - accepting connections
```

Three clusters, three ports, three independent services.

---

## 4. Independent Lifecycle

Each cluster operates independently. Stopping one has no effect on the others. This is critical to understand for production - a maintenance restart on one cluster does not impact other applications.

Stop the PG15 cluster:

```bash
sudo systemctl stop postgresql-15
```

Verify PG15 is stopped:

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - no response
```

Verify PG16 is still running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

Verify the test cluster is still running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - accepting connections
```

PG15 is down. PG16 and the test cluster are unaffected. Start PG15 back up:

```bash
sudo systemctl start postgresql-15
```

Verify PG15 is running again:

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - accepting connections
```

All three clusters are back to normal.

---

## 5. Connecting to the Right Cluster

When you have multiple clusters on one server, you must be explicit about which one you connect to. There are several ways to target a specific cluster.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

**Method 1: Use the -p flag.** The `-p` flag specifies the port directly:

```bash
psql -p 5432 -c "SELECT current_setting('port') AS port, current_setting('data_directory') AS pgdata;"
```

Expected output:

```
 port |      pgdata
------+------------------
 5432 | /opt/pgsql/data
(1 row)
```

```bash
psql -p 5433 -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                  version
-------------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x on x86_64-pc-linux-gnu ...
(1 row)
```

```bash
psql -p 5435 -c "SELECT current_setting('port') AS port, current_setting('data_directory') AS pgdata;"
```

Expected output:

```
 port |        pgdata
------+------------------------
 5435 | /opt/pgsql/data-multi
(1 row)
```

**Method 2: Use the PGPORT environment variable.** Setting `PGPORT` changes the default port for all PostgreSQL client tools in your session:

```bash
export PGPORT=5435
```

Now `psql` without `-p` connects to port 5435:

```bash
psql -c "SELECT current_setting('port');"
```

Expected output:

```
 current_setting
-----------------
 5435
(1 row)
```

Reset to the default:

```bash
export PGPORT=5432
```

**Method 3: Use pg_service.conf for named connections.** For servers with many clusters, you can define named connection profiles. Create a service file in the postgres user's home directory:

```bash
vi ~/.pg_service.conf
```

Add these lines:

```
[pg16]
host=localhost
port=5432
dbname=postgres
user=postgres

[pg15]
host=localhost
port=5433
dbname=postgres
user=postgres

[multi]
host=localhost
port=5435
dbname=postgres
user=postgres
```

Save and exit vi (`:wq`).

Now you can connect using the service name with the `service` parameter:

```bash
psql "service=pg15" -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                  version
-------------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x on x86_64-pc-linux-gnu ...
(1 row)
```

```bash
psql "service=multi" -c "SELECT current_setting('port');"
```

Expected output:

```
 current_setting
-----------------
 5435
(1 row)
```

> **Concept: pg_service.conf for connection management**
> The `pg_service.conf` file eliminates the need to remember port numbers. In production environments with many clusters, teams name their services after the application (e.g., `[billing-prod]`, `[billing-staging]`). Application connection strings use `service=billing-prod` instead of hardcoding host/port/database. This makes failovers simpler - you update the service file instead of every application config.

Exit the postgres session:

```bash
exit
```

---

## 6. Tear Down

Clean up the test cluster. Always remove test instances after labs to keep the server tidy.

Stop the systemd service:

```bash
sudo systemctl stop postgresql-16-multi
```

Disable the service so it does not start on boot:

```bash
sudo systemctl disable postgresql-16-multi
```

Expected output:

```
Removed /etc/systemd/system/multi-user.target.wants/postgresql-16-multi.service.
```

Remove the unit file:

```bash
sudo rm /etc/systemd/system/postgresql-16-multi.service
```

Reload systemd to pick up the removal:

```bash
sudo systemctl daemon-reload
```

Remove the data directory. Switch to root:

```bash
sudo su -
```

```bash
rm -rf /opt/pgsql/data-multi
```

Exit the root session:

```bash
exit
```

Clean up the service config file:

```bash
sudo -iu postgres
```

```bash
rm ~/.pg_service.conf
```

Exit the postgres session:

```bash
exit
```

Verify only the original two clusters are running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - accepting connections
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5435
```

Expected output:

```
/run/postgresql:5435 - no response
```

Back to two clusters. Clean state.

---

## Checkpoint

You have completed Guide 03. Verify you understand the following:

- [ ] You can inventory running clusters using `pg_isready`, `systemctl list-units`, and `pg_controldata`
- [ ] Each cluster has its own PGDATA, port, PID file, Unix socket, and system identifier
- [ ] You can create a new cluster with `initdb` and assign it a unique port
- [ ] You can create a systemd unit file for any cluster using `systemctl edit --full --force`
- [ ] Stopping one cluster has zero effect on other clusters on the same server
- [ ] You can connect to a specific cluster using `-p` (port flag), `PGPORT` (environment variable), or `pg_service.conf` (named connections)
- [ ] You always tear down test clusters: stop service, disable, remove unit file, daemon-reload, remove data directory

---

Proceed to **Guide 04 - Server Start, Stop, and Health Checks**
