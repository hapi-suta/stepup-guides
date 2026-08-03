# BUILD 01: Docker Fundamentals for DBAs

**Module:** Kubernetes for Databases
**Prerequisites:** Mac with Homebrew installed, PostgreSQL 16 client (`psql`) on your Mac
**Time:** 45-60 minutes

---

## What You Will Build

By the end of this guide, you will have Docker Desktop running on your Mac, a containerized PostgreSQL 16 instance with persistent storage, and a custom Docker image. You will also run a primary + replica pair using Docker Compose.

---

## Step 1: Understand What a Container Is

Think of a container as a **portable, isolated database instance**. You know how painful it is to set up PostgreSQL on a new server - install packages, configure `postgresql.conf`, set up users, create directories? A container packages ALL of that into a single, runnable unit.

**DBA Analogy:**

| Concept | DBA Equivalent |
|---------|---------------|
| Container | A fully configured PostgreSQL instance in a box - OS, binaries, config, everything |
| Image | A pg_basebackup snapshot - a template you can spin up anytime |
| Docker Hub | A package repository (like PGDG RPM repo) where pre-built images live |
| VM vs Container | A VM is a full server with its own OS kernel. A container shares the host OS kernel but isolates everything else. Think: VM = dedicated server, Container = lightweight isolated process |

A container starts in **seconds**, not minutes. You can run 10 PostgreSQL containers on your laptop simultaneously - each on a different port, each with different versions, each completely isolated.

---

## Step 2: Install Docker Desktop on Mac

**On your Mac, in Terminal:**

```bash
brew install --cask docker
```

Expected output (yours will differ):
```
==> Downloading https://desktop.docker.com/mac/main/arm64/Docker.dmg
==> Installing Cask docker
==> Moving App 'Docker.app' to '/Applications/Docker.app'
...
docker was successfully installed!
```

Now open Docker Desktop from your Applications folder (or Spotlight search "Docker"). You will see a whale icon appear in your menu bar. Wait until it says "Docker Desktop is running."

Verify the installation:

```bash
docker --version
```

Expected output (yours will differ):
```
Docker version 27.4.0, build bde2b89
```

```bash
docker info | head -5
```

Expected output (yours will differ):
```
Client:
 Version:    27.4.0
 Context:    desktop-linux
 Debug Mode: false
 Plugins:
```

---

## Step 3: Run Your First Container

**On your Mac, in Terminal:**

```bash
docker run hello-world
```

This command does three things:
1. Looks for the `hello-world` image locally (it will not find it)
2. Downloads (pulls) the image from Docker Hub
3. Runs a container from that image

Expected output (yours will differ):
```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

**DBA Analogy:** This is like running `SELECT 1;` after connecting to a new PostgreSQL instance - just a quick sanity check.

---

## Step 4: Run PostgreSQL in a Container

Now the real work. Let's run PostgreSQL 16 in a container.

**On your Mac, in Terminal:**

```bash
docker run --name pg16 -e POSTGRES_PASSWORD=dbalab123 -d postgres:16
```

Let's break down every flag:

| Flag | What It Does | DBA Analogy |
|------|-------------|-------------|
| `--name pg16` | Names the container "pg16" | Like naming a database cluster |
| `-e POSTGRES_PASSWORD=dbalab123` | Sets an environment variable inside the container | Like setting a password in `pg_hba.conf` |
| `-d` | Runs the container in the background (detached) | Like starting PostgreSQL with `pg_ctl start` |
| `postgres:16` | The image to use - PostgreSQL version 16 from Docker Hub | Like specifying which PGDG RPM to install |

Expected output (yours will differ):
```
Unable to find image 'postgres:16' locally
16: Pulling from library/postgres
...
Status: Downloaded newer image for postgres:16
a3b4c5d6e7f8g9h0i1j2k3l4m5n6o7p8q9r0s1t2u3v4w5x6y7z8
```

That long string at the end is the container ID - like a PID for your container.

Check that it is running:

```bash
docker ps
```

Expected output (yours will differ):
```
CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS          PORTS      NAMES
a3b4c5d6e7f8   postgres:16   "docker-entrypoint.s..."   10 seconds ago   Up 9 seconds    5432/tcp   pg16
```

**DBA Analogy:** `docker ps` is like `pg_lsclusters` or `systemctl status postgresql` - it shows you what is running.

---

## Step 5: Port Mapping - Expose PostgreSQL to Your Mac

The container has PostgreSQL running on port 5432, but that port is **inside the container**. Your Mac cannot reach it yet.

First, stop and remove the existing container:

```bash
docker stop pg16 && docker rm pg16
```

Now run it again with port mapping:

```bash
docker run --name pg16 -e POSTGRES_PASSWORD=dbalab123 -p 5432:5432 -d postgres:16
```

The `-p 5432:5432` flag maps port 5432 on your Mac to port 5432 inside the container.

**DBA Analogy:** This is like configuring `listen_addresses = '*'` and adding a rule in `pg_hba.conf` to allow connections from outside. The format is `-p HOST_PORT:CONTAINER_PORT`. You could map `-p 5433:5432` if port 5432 is already in use on your Mac.

Verify the port mapping:

```bash
docker ps
```

Expected output (yours will differ):
```
CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS          PORTS                    NAMES
a3b4c5d6e7f8   postgres:16   "docker-entrypoint.s..."   5 seconds ago    Up 4 seconds    0.0.0.0:5432->5432/tcp   pg16
```

Notice `0.0.0.0:5432->5432/tcp` - your Mac port 5432 now routes to the container.

---

## Step 6: Connect to Containerized PostgreSQL with psql

**On your Mac, in Terminal:**

```bash
psql -h localhost -U postgres -p 5432
```

When prompted for the password, enter `dbalab123`.

Expected output (yours will differ):
```
Password for user postgres:
psql (16.4)
Type "help" for help.

postgres=#
```

You are now connected to PostgreSQL running **inside a container**. Run a few familiar commands:

```sql
SELECT version();
```

Expected output (yours will differ):
```
                                                  version
------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.4 (Debian 16.4-1.pgdg120+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 12.2.0-14)
```

Notice it says "Debian" and "linux-gnu" - the container is running Linux even though your Mac runs macOS. That is the magic of containers.

```sql
\q
```

---

## Step 7: Volumes - Persistent Data Storage

Here is a critical concept for DBAs. By default, when you delete a container, **all data inside it is lost**. This is like reformatting the disk your `PGDATA` lives on.

**DBA Analogy:** A Docker volume is like mounting a dedicated tablespace directory (`/opt/pgsql/data`) that lives **outside** the container. Even if the container is destroyed, the data on the volume survives.

Stop and remove the current container:

```bash
docker stop pg16 && docker rm pg16
```

Create a named volume:

```bash
docker volume create pgdata16
```

Run PostgreSQL with the volume mounted:

```bash
docker run --name pg16 \
  -e POSTGRES_PASSWORD=dbalab123 \
  -p 5432:5432 \
  -v pgdata16:/var/lib/postgresql/data \
  -d postgres:16
```

The `-v pgdata16:/var/lib/postgresql/data` flag mounts the `pgdata16` volume to the data directory inside the container.

| Flag | What It Does |
|------|-------------|
| `-v pgdata16:/var/lib/postgresql/data` | Mounts the named volume `pgdata16` at the PostgreSQL data directory |

Now create some test data:

```bash
psql -h localhost -U postgres -p 5432 -c "CREATE DATABASE testdb;"
psql -h localhost -U postgres -p 5432 -d testdb -c "CREATE TABLE lab (id serial PRIMARY KEY, note text); INSERT INTO lab (note) VALUES ('data survives container deletion');"
```

Enter the password `dbalab123` when prompted.

Now destroy the container:

```bash
docker stop pg16 && docker rm pg16
```

Create a brand new container using the **same volume**:

```bash
docker run --name pg16-new \
  -e POSTGRES_PASSWORD=dbalab123 \
  -p 5432:5432 \
  -v pgdata16:/var/lib/postgresql/data \
  -d postgres:16
```

Check if your data survived:

```bash
psql -h localhost -U postgres -p 5432 -d testdb -c "SELECT * FROM lab;"
```

Expected output (yours will differ):
```
 id |               note
----+----------------------------------
  1 | data survives container deletion
(1 row)
```

The data survived because it lives on the **volume**, not inside the container. This is the most important concept for running databases in containers.

---

## Step 8: docker exec - Get a Shell Inside the Container

Sometimes you need to get inside the container to inspect files, check logs, or run commands directly.

**On your Mac, in Terminal:**

```bash
docker exec -it pg16-new bash
```

| Flag | What It Does |
|------|-------------|
| `-i` | Interactive - keeps STDIN open |
| `-t` | Allocates a terminal (TTY) |
| `pg16-new` | The container name |
| `bash` | The command to run inside the container |

**DBA Analogy:** This is like SSH-ing into a remote database server. Once inside, you can run any command.

Expected output (yours will differ):
```
root@a3b4c5d6e7f8:/#
```

You are now **inside the container** as root. Explore:

```bash
cat /var/lib/postgresql/data/postgresql.conf | head -20
```

```bash
psql -U postgres -c "SELECT datname FROM pg_database;"
```

Expected output (yours will differ):
```
  datname
-----------
 postgres
 testdb
 template1
 template0
(4 rows)
```

Exit the container:

```bash
exit
```

You are back on your Mac.

---

## Step 9: Docker Logs - Your Container's Log File

**On your Mac, in Terminal:**

```bash
docker logs pg16-new
```

**DBA Analogy:** This is like running `tail -f /var/log/postgresql/postgresql-16-main.log`. It shows the PostgreSQL startup messages and any errors.

Expected output (yours will differ):
```
PostgreSQL init process complete; ready for start up.
...
LOG:  database system is ready to accept connections
LOG:  listening on IPv4 address "0.0.0.0", port 5432
```

To follow logs in real time (like `tail -f`):

```bash
docker logs -f pg16-new
```

Press `Ctrl+C` to stop following.

---

## Step 10: Build a Custom PostgreSQL Image with a Dockerfile

A Dockerfile is a script that tells Docker how to build a custom image. Think of it as an automation script for provisioning a database server.

**On your Mac, in Terminal:**

```bash
mkdir -p /tmp/pg-custom && cd /tmp/pg-custom
```

Create a Dockerfile:

**In `/tmp/pg-custom/`, open vi:**

```bash
vi Dockerfile
```

Enter the following content (press `i` to enter insert mode, paste, then press `Esc` followed by `:wq` to save):

```dockerfile
FROM postgres:16

# Install useful DBA tools
RUN apt-get update && apt-get install -y \
    postgresql-16-pg-stat-statements \
    procps \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Copy custom configuration
COPY postgresql.conf /etc/postgresql/custom.conf

# Copy initialization SQL (runs on first startup)
COPY init.sql /docker-entrypoint-initdb.d/

# Tell PostgreSQL to use our custom config
CMD ["postgres", "-c", "config_file=/etc/postgresql/custom.conf"]
```

| Line | What It Does |
|------|-------------|
| `FROM postgres:16` | Start from the official PostgreSQL 16 image (like starting from a base OS install) |
| `RUN apt-get ...` | Install additional packages (like running `dnf install` on CentOS) |
| `COPY` | Copy files from your Mac into the image |
| `CMD` | The command to run when the container starts |

Now create the custom config:

```bash
vi postgresql.conf
```

```
listen_addresses = '*'
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 768MB
work_mem = 4MB
maintenance_work_mem = 128MB
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_statement = 'ddl'
shared_preload_libraries = 'pg_stat_statements'
```

Create the initialization SQL:

```bash
vi init.sql
```

```sql
-- This runs automatically on first container startup
CREATE DATABASE appdb;
\c appdb

CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO app.config (key, value) VALUES
    ('version', '1.0.0'),
    ('environment', 'docker-lab');
```

Build the image:

```bash
docker build -t pg16-custom:latest /tmp/pg-custom/
```

The `-t` flag tags (names) the image. Think of it as naming a `pg_basebackup` snapshot.

Expected output (yours will differ):
```
[+] Building 45.2s (9/9) FINISHED
 => [1/4] FROM docker.io/library/postgres:16
 => [2/4] RUN apt-get update && apt-get install -y ...
 => [3/4] COPY postgresql.conf /etc/postgresql/custom.conf
 => [4/4] COPY init.sql /docker-entrypoint-initdb.d/
 => exporting to image
...
=> => naming to docker.io/library/pg16-custom:latest
```

Stop the old container, then run your custom image:

```bash
docker stop pg16-new && docker rm pg16-new
```

```bash
docker run --name pg16-custom \
  -e POSTGRES_PASSWORD=dbalab123 \
  -p 5432:5432 \
  -d pg16-custom:latest
```

Wait a few seconds for initialization, then verify:

```bash
psql -h localhost -U postgres -p 5432 -d appdb -c "SELECT * FROM app.config;"
```

Expected output (yours will differ):
```
    key     |  value     |          updated_at
------------+------------+-------------------------------
 version    | 1.0.0      | 2026-06-09 14:30:00.123456+00
 environment| docker-lab | 2026-06-09 14:30:00.123456+00
(2 rows)
```

---

## Step 11: Docker Compose - Primary + Replica Together

Docker Compose lets you define and run multiple containers together in a single YAML file. Think of it as a deployment manifest for a multi-node database setup.

**On your Mac, in Terminal:**

```bash
mkdir -p /tmp/pg-compose && cd /tmp/pg-compose
```

```bash
vi docker-compose.yml
```

```yaml
services:
  pg-primary:
    image: postgres:16
    container_name: pg-primary
    environment:
      POSTGRES_PASSWORD: dbalab123
      POSTGRES_USER: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata-primary:/var/lib/postgresql/data
      - ./init-primary.sh:/docker-entrypoint-initdb.d/init-primary.sh
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=3
      -c max_replication_slots=3
      -c hot_standby=on

  pg-replica:
    image: postgres:16
    container_name: pg-replica
    environment:
      POSTGRES_PASSWORD: dbalab123
      PGUSER: postgres
      PGPASSWORD: dbalab123
    ports:
      - "5433:5432"
    volumes:
      - pgdata-replica:/var/lib/postgresql/data
    depends_on:
      pg-primary:
        condition: service_started

volumes:
  pgdata-primary:
  pgdata-replica:
```

Create the primary initialization script:

```bash
vi init-primary.sh
```

```bash
#!/bin/bash
set -e

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'dbalab123';
EOSQL

# Allow replication connections
echo "host replication replicator all md5" >> "$PGDATA/pg_hba.conf"

# Reload to pick up pg_hba.conf changes
pg_ctl reload -D "$PGDATA"
```

```bash
chmod +x init-primary.sh
```

Start the primary:

```bash
docker compose up -d pg-primary
```

Expected output (yours will differ):
```
[+] Running 2/2
 ✓ Volume "pg-compose_pgdata-primary"  Created
 ✓ Container pg-primary                Started
```

Wait 5 seconds for the primary to finish initialization, then set up the replica manually. First, remove the replica volume if it exists, then use `pg_basebackup` to clone the primary:

```bash
docker compose run --rm -e PGPASSWORD=dbalab123 pg-replica bash -c "\
  rm -rf /var/lib/postgresql/data/* && \
  pg_basebackup -h pg-primary -U replicator -D /var/lib/postgresql/data -Fp -Xs -R -P"
```

The `-R` flag writes `standby.signal` and sets `primary_conninfo` automatically - just like you would do on bare metal.

Expected output (yours will differ):
```
24563/24563 kB (100%), 1/1 tablespace
```

Now start the replica:

```bash
docker compose up -d pg-replica
```

Verify replication is working - connect to the primary:

```bash
psql -h localhost -U postgres -p 5432 -c "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"
```

Expected output (yours will differ):
```
 client_addr |   state   |  sent_lsn   | replay_lsn
-------------+-----------+-------------+------------
 172.18.0.3  | streaming | 0/3000148   | 0/3000148
(1 row)
```

Verify the replica is in recovery mode:

```bash
psql -h localhost -U postgres -p 5433 -c "SELECT pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 t
(1 row)
```

You now have a streaming replication pair running in containers.

---

## Step 12: Essential Docker Commands Reference

Clean up everything before moving on:

```bash
docker compose -f /tmp/pg-compose/docker-compose.yml down -v
docker stop pg16-custom 2>/dev/null; docker rm pg16-custom 2>/dev/null
docker volume rm pgdata16 2>/dev/null
```

Here is a reference of every command you used, with DBA analogies:

| Docker Command | What It Does | DBA Analogy |
|---------------|-------------|-------------|
| `docker run` | Create and start a container | `pg_ctl start` with a fresh instance |
| `docker ps` | List running containers | `pg_lsclusters` or `systemctl list-units` |
| `docker stop <name>` | Stop a container gracefully | `pg_ctl stop -m fast` |
| `docker rm <name>` | Delete a stopped container | Removing the instance entirely |
| `docker logs <name>` | View container logs | `tail /var/log/postgresql/*.log` |
| `docker exec -it <name> bash` | Shell into a container | SSH into a database server |
| `docker images` | List downloaded images | List available RPM packages |
| `docker build -t <tag> .` | Build an image from Dockerfile | Creating a pg_basebackup template |
| `docker volume create` | Create persistent storage | `mkdir /opt/pgsql/data` |
| `docker compose up -d` | Start all services in background | Starting a multi-node cluster |
| `docker compose down -v` | Stop all services and delete volumes | Full teardown |

---

## Step 13: Why Containers Matter for DBAs

As a DBA who has provisioned hundreds of servers, consider these advantages:

1. **Consistent environments** - No more "works on my server but not yours." Every container built from the same image is identical.

2. **Quick provisioning** - Spin up a PostgreSQL 16 instance in 3 seconds instead of 30 minutes of package installation and configuration.

3. **Version testing** - Run PostgreSQL 14, 15, and 16 side by side on the same machine to test upgrades.

4. **Disposable test environments** - Need to test a migration? Spin up a container, run the migration, throw it away. No cleanup needed.

5. **CI/CD pipelines** - Automated testing against real PostgreSQL instances, not mocked databases.

6. **Reproducible bugs** - Share a Dockerfile that reproduces the exact environment where a bug occurs.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Containers | Lightweight, isolated instances that package an application with its dependencies |
| Docker Desktop | The runtime that makes containers work on your Mac |
| `docker run` | Creates and starts containers from images |
| Port mapping (`-p`) | Exposes container ports to your host machine |
| Volumes (`-v`) | Persistent storage that survives container deletion - critical for databases |
| `docker exec` | Get a shell inside a running container |
| Dockerfile | A script to build custom images with your configuration |
| Docker Compose | Define and run multi-container setups from a single YAML file |
| Streaming replication | Works the same in containers as on bare metal - same `pg_basebackup`, same `pg_stat_replication` |
