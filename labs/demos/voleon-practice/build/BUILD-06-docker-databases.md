# Build Guide 06: Docker Databases Setup

| | |
|---|---|
| **Time** | 50 minutes |
| **Server** | pg-container (34.235.89.112) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- Why quant funds like Voleon run databases in containers alongside bare-metal PostgreSQL
- How to install Docker CE on CentOS Stream 9
- How to run PostgreSQL 17, MySQL 9, and Redis inside Docker containers
- How to manage running containers and read their logs
- How to install Python data tools (pyarrow and duckdb)
- The difference between Docker and Podman

## Prerequisites

- SSH access to pg-container
- No PostgreSQL installation required on this server - it is a dedicated container host

---

## Step 1: Understand Containerized Databases at Voleon

Voleon's infrastructure spans bare-metal PostgreSQL clusters for production data and containerized databases for surrounding services. Understanding why helps you make the right architectural decisions.

**Kubernetes and sidecars** - Voleon's model training and backtesting jobs run on Kubernetes. Many pods include a sidecar database container - a small database that lives next to the application container in the same pod, storing job-specific state without needing to connect to the main production cluster.

**Isolated development environments** - Quant researchers need fresh database instances to test schema changes or load experimental datasets without touching production. A `docker run` command gives them a clean database in under 30 seconds.

**Multi-database support** - The core time-series and factor data lives in PostgreSQL. Some legacy risk systems at acquired firms use MySQL. Running both in Docker means engineers do not need to maintain two separate bare-metal installations for non-critical workloads.

**Docker vs bare-metal** - Bare-metal PostgreSQL (what you set up on pg-primary) is appropriate for production: full control over kernel parameters, WAL settings, and storage layout. Docker is appropriate for development, testing, and short-lived workloads where isolation matters more than raw performance.

---

## Step 2: Install Docker CE

SSH into pg-container as ec2-user.

```
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

On **pg-container**, as **ec2-user**, install the `yum-utils` package first. This provides the `dnf config-manager` command used to add the Docker repository.

```
sudo dnf install -y yum-utils
```

Expected output (yours will differ):
```
Installed:
  yum-utils-4.3.0-11.el9.noarch

Complete!
```

Add the official Docker CE repository for CentOS. This tells `dnf` where to download Docker packages from.

```
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

Expected output (yours will differ):
```
Adding repo from: https://download.docker.com/linux/centos/docker-ce.repo
```

Install Docker CE and its dependencies. The four packages are:
- `docker-ce` - the Docker daemon
- `docker-ce-cli` - the `docker` command-line client
- `containerd.io` - the container runtime that Docker uses under the hood
- `docker-compose-plugin` - adds `docker compose` subcommand support

```
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

Expected output (yours will differ):
```
Installed:
  containerd.io-1.7.x  docker-ce-26.x  docker-ce-cli-26.x  docker-compose-plugin-2.x ...

Complete!
```

Start the Docker service.

```
sudo systemctl start docker
```

Enable Docker to start on every reboot.

```
sudo systemctl enable docker
```

Verify Docker is running.

```
sudo systemctl status docker
```

Expected output (yours will differ):
```
● docker.service - Docker Application Container Engine
     Loaded: loaded (/usr/lib/systemd/system/docker.service; enabled; ...)
     Active: active (running) since Sun 2026-06-15 10:30:00 UTC; 5s ago
...
```

---

## Step 3: Add ec2-user to the Docker Group

By default, only root can run Docker commands. Adding `ec2-user` to the `docker` group lets you run `docker` without `sudo`. The `-aG` flags mean: `-a` append (do not remove from other groups), `-G` add to this group.

On **pg-container**, as **ec2-user**:

```
sudo usermod -aG docker ec2-user
```

For this change to take effect, you need to either log out and log back in, or activate the new group membership in the current session.

```
newgrp docker
```

`newgrp docker` starts a new shell session with the docker group active. You stay logged in but the group is now applied.

Verify you can run Docker without sudo.

```
docker version
```

Expected output (yours will differ):
```
Client: Docker Engine - Community
 Version:           26.1.x
...
Server: Docker Engine - Community
 Engine:
  Version:          26.1.x
...
```

---

## Step 4: Install Podman

Podman is an alternative container runtime that ships with CentOS 9. It is daemonless (no background service required) and can run containers as a non-root user. Voleon's security team prefers Podman for workloads where running a root-level daemon is undesirable.

On **pg-container**, as **ec2-user**:

```
sudo dnf install -y podman
```

Expected output (yours will differ):
```
Installed:
  podman-4.x.x-1.el9.x86_64

Complete!
```

Verify Podman installed.

```
podman --version
```

Expected output (yours will differ):
```
podman version 4.x.x
```

---

## Step 5: Run PostgreSQL 17 in Docker

On **pg-container**, as **ec2-user**, run a PostgreSQL 17 container. Read the full command before running it - each flag is explained below.

```
docker run -d \
  --name voleon-pg \
  --restart unless-stopped \
  -e POSTGRES_PASSWORD=docker_pg_2026 \
  -p 5433:5432 \
  -v pg_docker_data:/var/lib/postgresql/data \
  postgres:17
```

**What each flag does:**
- `-d` - Detached mode. The container runs in the background and you get your shell prompt back immediately.
- `--name voleon-pg` - Gives the container a human-readable name instead of a random string. Used in later commands like `docker logs voleon-pg`.
- `--restart unless-stopped` - Docker automatically restarts this container if it crashes or if the server reboots, unless you explicitly stop it with `docker stop`.
- `-e POSTGRES_PASSWORD=docker_pg_2026` - Sets an environment variable inside the container. The official PostgreSQL image reads this to set the `postgres` superuser password.
- `-p 5433:5432` - Maps port 5433 on the host to port 5432 inside the container. Format is `host_port:container_port`. We use 5433 to avoid conflicting with any local PostgreSQL.
- `-v pg_docker_data:/var/lib/postgresql/data` - Mounts a named Docker volume at the path where PostgreSQL stores its data files. Named volumes persist even if you remove the container.
- `postgres:17` - The image name and tag. Docker pulls this from Docker Hub if not already cached locally.

Expected output (yours will differ):
```
Unable to find image 'postgres:17' locally
17: Pulling from library/postgres
...
Status: Downloaded newer image for postgres:17
a1b2c3d4e5f6...
```

The long string at the end is the container ID.

---

## Step 6: Verify the PostgreSQL Container

On **pg-container**, as **ec2-user**, check that the container is running.

```
docker ps
```

Expected output (yours will differ):
```
CONTAINER ID   IMAGE         COMMAND                  CREATED         STATUS         PORTS                    NAMES
a1b2c3d4e5f6   postgres:17   "docker-entrypoint.s..."   30 seconds ago  Up 29 seconds  0.0.0.0:5433->5432/tcp   voleon-pg
```

Wait about 10 seconds for the PostgreSQL server inside the container to finish initializing, then connect to it.

```
psql -h 127.0.0.1 -U postgres -p 5433 -c "SELECT version();"
```

When prompted for a password, enter: `docker_pg_2026`

Expected output (yours will differ):
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 17.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

---

## Step 7: Run MySQL 9 in Docker

On **pg-container**, as **ec2-user**, start a MySQL container. This is the same pattern as PostgreSQL - a detached container with a named volume and an environment variable for the root password.

```
docker run -d \
  --name voleon-mysql \
  --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD=docker_mysql_2026 \
  -p 3306:3306 \
  -v mysql_docker_data:/var/lib/mysql \
  mysql:latest
```

- `-e MYSQL_ROOT_PASSWORD=docker_mysql_2026` - The MySQL image reads this variable to set the root password on first start.
- `-p 3306:3306` - Maps MySQL's default port on the host to the container. No offset needed since we have no local MySQL installation.
- `-v mysql_docker_data:/var/lib/mysql` - Named volume for MySQL data files.

Expected output (yours will differ):
```
Unable to find image 'mysql:latest' locally
latest: Pulling from library/mysql
...
b2c3d4e5f6a7...
```

---

## Step 8: Verify the MySQL Container

On **pg-container**, as **ec2-user**, wait about 20 seconds for MySQL to initialize, then run a query inside the container using `docker exec`.

```
docker exec -it voleon-mysql mysql -u root -pdocker_mysql_2026 -e "SELECT VERSION();"
```

- `docker exec` - Runs a command inside an already-running container.
- `-it` - Interactive terminal mode. `-i` keeps stdin open, `-t` allocates a pseudo-TTY. Together they let the command behave like an interactive session.
- `voleon-mysql` - The name of the container to run the command inside.
- `mysql -u root -pdocker_mysql_2026` - The command to run: start the MySQL client as root with the password (no space between `-p` and the password is intentional).
- `-e "SELECT VERSION();"` - Execute this SQL and exit.

Expected output (yours will differ):
```
mysql: [Warning] Using a password on the command line interface can be insecure.
+-----------+
| VERSION() |
+-----------+
| 9.x.x     |
+-----------+
```

---

## Step 9: Run Redis in Docker

On **pg-container**, as **ec2-user**, start a Redis container. This one uses port 6380 on the host so it does not conflict with the Redis running on pg-primary (6379).

```
docker run -d \
  --name voleon-redis \
  --restart unless-stopped \
  -p 6380:6379 \
  redis:7 redis-server --requirepass redis_docker_2026
```

- `-p 6380:6379` - Host port 6380 maps to Redis's default port 6379 inside the container.
- `redis:7` - Use the Redis 7 image.
- `redis-server --requirepass redis_docker_2026` - This overrides the container's default start command. Instead of starting Redis with no password, it starts Redis with authentication required.

Expected output (yours will differ):
```
Unable to find image 'redis:7' locally
7: Pulling from library/redis
...
c3d4e5f6a7b8...
```

---

## Step 10: Verify the Redis Container

On **pg-container**, as **ec2-user**, run a ping command inside the Redis container.

```
docker exec -it voleon-redis redis-cli -a redis_docker_2026 ping
```

Expected output:
```
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
PONG
```

The warning is expected - it is telling you that passing passwords on the command line is visible in process lists. In production, you would use a secrets manager. For this lab, it is fine.

Set and get a test key.

```
docker exec -it voleon-redis redis-cli -a redis_docker_2026 SET test:key "hello"
```

```
docker exec -it voleon-redis redis-cli -a redis_docker_2026 GET test:key
```

Expected output:
```
"hello"
```

---

## Step 11: Install Python Data Tools

On **pg-container**, as **ec2-user**, install Python 3 and pip. These are needed for pyarrow and duckdb.

```
sudo dnf install -y python3 python3-pip
```

Expected output (yours will differ):
```
Installed:
  python3-3.11.x  python3-pip-22.x ...

Complete!
```

Install `pyarrow` using pip. The `--user` flag installs into `~/.local/` so you do not need sudo. pyarrow is the Python library for Apache Arrow - a columnar in-memory data format used heavily in quant workflows for fast bulk data transfers between systems.

```
pip3 install pyarrow --user
```

Expected output (yours will differ):
```
Successfully installed pyarrow-16.x.x
```

Install `duckdb`. DuckDB is an in-process analytical SQL engine - think SQLite but optimized for running analytical queries on large datasets directly from Python, without needing a separate database server.

```
pip3 install duckdb --user
```

Expected output (yours will differ):
```
Successfully installed duckdb-1.x.x
```

---

## Step 12: Verify Python Tools

On **pg-container**, as **ec2-user**, verify pyarrow is importable and check its version.

```
python3 -c "import pyarrow; print(pyarrow.__version__)"
```

Expected output (yours will differ):
```
16.x.x
```

Verify duckdb.

```
python3 -c "import duckdb; print(duckdb.__version__)"
```

Expected output (yours will differ):
```
1.x.x
```

Run a quick duckdb query to confirm it works end to end. This runs an in-memory SQL query with no external database required.

```
python3 -c "import duckdb; print(duckdb.sql('SELECT 42 AS answer').fetchone())"
```

Expected output:
```
(42,)
```

---

## Step 13: Docker Management Commands

These are the commands you will use daily when working with containers.

On **pg-container**, as **ec2-user**:

**List running containers:**
```
docker ps
```

**List all containers (including stopped):**
```
docker ps -a
```

**View logs from a container** (useful when a container fails to start):
```
docker logs voleon-pg
```

**Follow logs in real-time** (like `tail -f`):
```
docker logs -f voleon-pg
```

Press `Ctrl+C` to stop following.

**Show resource usage** (CPU, memory, network per container):
```
docker stats --no-stream
```

`--no-stream` prints one snapshot and exits instead of continuously refreshing.

Expected output (yours will differ):
```
CONTAINER ID   NAME            CPU %   MEM USAGE / LIMIT    MEM %   NET I/O       BLOCK I/O
a1b2c3d4e5f6   voleon-pg       0.01%   42MiB / 7.5GiB       0.55%   1.2kB / 0B    ...
b2c3d4e5f6a7   voleon-mysql    0.02%   380MiB / 7.5GiB      4.94%   648B / 0B     ...
c3d4e5f6a7b8   voleon-redis    0.12%   8.2MiB / 7.5GiB      0.11%   1.5kB / 0B    ...
```

**Run an interactive shell inside a container:**
```
docker exec -it voleon-pg bash
```

Type `exit` to leave the container shell. You return to the ec2-user shell on pg-container.

**Stop a container** (graceful shutdown):
```
docker stop voleon-pg
```

**Start a stopped container:**
```
docker start voleon-pg
```

**List Docker volumes** (where persistent data lives):
```
docker volume ls
```

Expected output (yours will differ):
```
DRIVER    VOLUME NAME
local     mysql_docker_data
local     pg_docker_data
```

---

## Step 14: Docker vs Podman - Run the Same PostgreSQL with Podman

On **pg-container**, as **ec2-user**, run a PostgreSQL container using Podman instead of Docker. The command syntax is nearly identical.

```
podman run -d \
  --name podman-pg \
  -e POSTGRES_PASSWORD=podman_pg_2026 \
  -p 5434:5432 \
  postgres:17
```

Key differences from Docker:
- No `--restart unless-stopped` flag - Podman handles restarts differently (through systemd units). Omitting it here is intentional for simplicity.
- No daemon required - Podman runs the container directly as your user process.
- Same image name (`postgres:17`) - Podman also pulls from Docker Hub by default.

Check the running Podman container.

```
podman ps
```

Expected output (yours will differ):
```
CONTAINER ID  IMAGE                            COMMAND               CREATED        STATUS        PORTS                   NAMES
d4e5f6a7b8c9  docker.io/library/postgres:17    docker-entrypoint...  10 seconds ago Up 9 seconds  0.0.0.0:5434->5432/tcp  podman-pg
```

Test the connection (port 5434 this time).

```
psql -h 127.0.0.1 -U postgres -p 5434 -c "SELECT version();"
```

When prompted, enter: `podman_pg_2026`

Stop the Podman container when done - you do not need it running for the rest of the lab.

```
podman stop podman-pg
```

**Docker vs Podman summary:**

| | Docker | Podman |
|---|---|---|
| Daemon | Requires dockerd running as root | Daemonless |
| Root | Daemon runs as root | Can run fully rootless |
| Syntax | `docker run ...` | `podman run ...` (nearly identical) |
| Compose | `docker compose` plugin | `podman-compose` (separate package) |
| Kubernetes | Good for dev, needs conversion for k8s | Generates k8s YAML natively |
| CentOS 9 | Needs external repo | Ships with OS |

For most day-to-day container work at Voleon, Docker is used on container hosts. Podman is used in CI pipelines and for security-sensitive workloads where a root daemon is not acceptable.

---

## Step 15: Final Verification - All Containers Running

On **pg-container**, as **ec2-user**, do a final status check on all three Docker containers.

```
docker ps
```

Expected output (yours will differ):
```
CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS          PORTS                    NAMES
a1b2c3d4e5f6   postgres:17   "docker-entrypoint.s..."  25 minutes ago   Up 25 minutes   0.0.0.0:5433->5432/tcp   voleon-pg
b2c3d4e5f6a7   mysql:latest  "docker-entrypoint.s..."  20 minutes ago   Up 20 minutes   0.0.0.0:3306->3306/tcp   voleon-mysql
c3d4e5f6a7b8   redis:7       "docker-entrypoint.s..."  15 minutes ago   Up 15 minutes   0.0.0.0:6380->6379/tcp   voleon-redis
```

All three containers should show `Up` in the STATUS column.

---

## Summary

You now have a container host running:

- **PostgreSQL 17** in Docker on port 5433 with data persisted to a named volume `pg_docker_data`
- **MySQL 9** in Docker on port 3306 with data persisted to a named volume `mysql_docker_data`
- **Redis 7** in Docker on port 6380 with password authentication
- **Python data tools** - pyarrow and duckdb installed and verified
- **Podman** installed as an alternative container runtime

Port summary across the Voleon lab:

| Service | Server | Port |
|---|---|---|
| PostgreSQL (bare-metal) | pg-primary | 5432 |
| PgBouncer | pg-primary | 6432 |
| Redis (bare-metal) | pg-primary | 6379 |
| PostgreSQL (Docker) | pg-container | 5433 |
| MySQL (Docker) | pg-container | 3306 |
| Redis (Docker) | pg-container | 6380 |

This separation - bare-metal PostgreSQL for production, Docker containers for auxiliary services and development - reflects how modern quant infrastructure is organized.
