# USE Exercise 06: Container Database Operations

| | |
|---|---|
| **Time** | 50 minutes |
| **Server** | pg-container (34.235.89.112) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice

- Checking the health and resource usage of running Docker containers
- Connecting to a containerized PostgreSQL instance and creating a database
- Importing a dataset into Docker MySQL
- Comparing a Docker PostgreSQL install against the native PostgreSQL on pg-primary
- Managing Docker volumes and understanding persistent storage
- Reading container log output
- Adjusting container resource limits at runtime
- Backing up a Docker PostgreSQL database and restoring it to a new container
- Running a quick Podman container comparison
- Using Redis inside a container for key-value operations

---

## Exercise 1: Check Container Health

SSH into pg-container. On **pg-container**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

List all running containers with their status. On **pg-container**, as **ec2-user**:

```bash
docker ps
```

Expected output (yours will differ):

```
CONTAINER ID   IMAGE         COMMAND                  CREATED        STATUS                    PORTS                    NAMES
a1b2c3d4e5f6   postgres:17   "docker-entrypoint.s…"   2 days ago     Up 2 days (healthy)       0.0.0.0:5433->5432/tcp   voleon-pg
b2c3d4e5f6a7   mysql:8.0     "docker-entrypoint.s…"   2 days ago     Up 2 days (healthy)       0.0.0.0:3306->3306/tcp   voleon-mysql
c3d4e5f6a7b8   redis:7       "docker-entrypoint.s…"   2 days ago     Up 2 days (healthy)       0.0.0.0:6380->6379/tcp   voleon-redis
```

Note the port mappings. `voleon-pg` maps host port 5433 to container port 5432. This means you connect to PostgreSQL inside the container by using port 5433 on the host.

Check live CPU and memory usage across all containers. On **pg-container**, as **ec2-user**:

```bash
docker stats --no-stream
```

Expected output (yours will differ):

```
CONTAINER ID   NAME           CPU %     MEM USAGE / LIMIT     MEM %     NET I/O       BLOCK I/O
a1b2c3d4e5f6   voleon-pg      0.12%     48.3MiB / 3.84GiB     1.23%     1.2MB / 800kB 10MB / 5MB
b2c3d4e5f6a7   voleon-mysql   0.08%     180MiB / 3.84GiB      4.58%     500kB / 200kB 30MB / 10MB
c3d4e5f6a7b8   voleon-redis   0.02%     8.5MiB / 3.84GiB      0.22%     100kB / 50kB  1MB / 0B
```

The `--no-stream` flag prints one snapshot and exits. Without it, `docker stats` streams continuously until you press Ctrl+C.

---

## Exercise 2: Connect to Docker PostgreSQL and Create a Test Database

The `voleon-pg` container runs PostgreSQL on host port 5433. You connect to it from the pg-container host using `docker exec`, which runs a command directly inside the container.

On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-pg psql -U postgres
```

You are now inside the container's psql session. The prompt will show `postgres=#`.

Check what databases exist inside the container. Inside the **voleon-pg container**, as **postgres**:

```sql
\l
```

Create a test database. Inside the **voleon-pg container**, as **postgres**:

```sql
CREATE DATABASE container_test;
```

Connect to the new database. Inside the **voleon-pg container**, as **postgres**:

```sql
\c container_test
```

Create a simple table to confirm write access works. Inside the **voleon-pg container**, as **postgres**:

```sql
CREATE TABLE test_run (
    id SERIAL PRIMARY KEY,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO test_run (note) VALUES ('first container insert');

SELECT * FROM test_run;
```

Expected output (yours will differ):

```
 id |         note          |          created_at
----+-----------------------+-------------------------------
  1 | first container insert | 2026-06-15 14:22:31.456789+00
(1 row)
```

Exit psql and return to the host. Inside the **voleon-pg container**, as **postgres**:

```sql
\q
```

---

## Exercise 3: Import a Small Dataset into Docker MySQL

You will create a small SQL file and import it into the `voleon-mysql` container.

On **pg-container**, as **ec2-user**:

```bash
cat > /tmp/test_import.sql << 'EOF'
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

CREATE TABLE IF NOT EXISTS instruments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    asset_class VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO instruments (symbol, asset_class) VALUES
    ('AAPL', 'equity'),
    ('BTC-USD', 'crypto'),
    ('ES1!', 'futures'),
    ('EUR/USD', 'fx');
EOF
```

Import the file into the MySQL container. On **pg-container**, as **ec2-user**:

```bash
docker exec -i voleon-mysql mysql -u root -pvoleon_root_pass < /tmp/test_import.sql
```

Verify the import worked. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-mysql mysql -u root -pvoleon_root_pass \
  -e "SELECT * FROM test_db.instruments;"
```

Expected output (yours will differ):

```
+----+---------+-------------+---------------------+
| id | symbol  | asset_class | created_at          |
+----+---------+-------------+---------------------+
|  1 | AAPL    | equity      | 2026-06-15 14:25:00 |
|  2 | BTC-USD | crypto      | 2026-06-15 14:25:00 |
|  3 | ES1!    | futures     | 2026-06-15 14:25:00 |
|  4 | EUR/USD | fx          | 2026-06-15 14:25:00 |
+----+---------+-------------+---------------------+
```

---

## Exercise 4: Compare Docker PG vs Native PG

This shows you what is identical between the two environments and what differs.

Check the version inside the Docker container. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-pg psql -U postgres -c "SELECT version();"
```

Now check the version on the native pg-primary. On **pg-container**, as **ec2-user**:

```bash
psql -h 3.90.199.62 -U quant_readonly -d quantdb -c "SELECT version();"
```

Both should return PostgreSQL 17. The minor version may differ.

Compare installed extensions. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-pg psql -U postgres -c "SELECT name, default_version FROM pg_available_extensions ORDER BY name LIMIT 20;"
```

Compare against native. On **pg-container**, as **ec2-user**:

```bash
psql -h 3.90.199.62 -U quant_readonly -d quantdb \
  -c "SELECT name, default_version FROM pg_available_extensions ORDER BY name LIMIT 20;"
```

The Docker image typically ships with fewer extensions than a package-managed install because it uses only what is bundled in the official Docker image. The native install on pg-primary has additional extensions installed via dnf.

Compare `max_connections`. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-pg psql -U postgres -c "SHOW max_connections;"
psql -h 3.90.199.62 -U quant_readonly -d quantdb -c "SHOW max_connections;"
```

Note any differences and think about why they exist. Container defaults are set in the Docker image. Native defaults are set in the RPM package.

---

## Exercise 5: Docker Volume Management

PostgreSQL data inside a container is stored on a Docker volume. If you delete the container but keep the volume, the data survives.

List all Docker volumes. On **pg-container**, as **ec2-user**:

```bash
docker volume ls
```

Expected output (yours will differ):

```
DRIVER    VOLUME NAME
local     pg_data
local     mysql_data
local     redis_data
```

Inspect the `pg_data` volume to see where it lives on disk. On **pg-container**, as **ec2-user**:

```bash
docker volume inspect pg_data
```

Expected output (yours will differ):

```json
[
    {
        "CreatedAt": "2026-06-12T10:00:00Z",
        "Driver": "local",
        "Labels": {},
        "Mountpoint": "/var/lib/docker/volumes/pg_data/_data",
        "Name": "pg_data",
        "Options": {},
        "Scope": "local"
    }
]
```

The `Mountpoint` field shows the actual path on the host where PostgreSQL data files are written. You can look at them directly. On **pg-container**, as **ec2-user**:

```bash
sudo ls /var/lib/docker/volumes/pg_data/_data
```

You will see the standard PostgreSQL data directory layout: `base/`, `global/`, `pg_wal/`, `PG_VERSION`, etc.

---

## Exercise 6: Read Container Logs

Container logs capture everything written to stdout and stderr inside the container. For PostgreSQL, this includes startup messages, connection events, and errors.

Tail the last 50 lines of the voleon-pg log. On **pg-container**, as **ec2-user**:

```bash
docker logs voleon-pg --tail 50
```

Expected output (yours will differ):

```
2026-06-15 14:00:01.234 UTC [1] LOG:  starting PostgreSQL 17.x on x86_64-pc-linux-gnu
2026-06-15 14:00:01.456 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2026-06-15 14:00:01.789 UTC [1] LOG:  database system is ready to accept connections
2026-06-15 14:22:31.001 UTC [45] LOG:  connection received: host=172.17.0.1 port=52310
...
```

Follow logs in real time (press Ctrl+C to stop). On **pg-container**, as **ec2-user**:

```bash
docker logs voleon-pg --follow
```

Open a second terminal, connect to the container PG, and run a query. Switch back to the first terminal and watch the connection event appear in the logs.

---

## Exercise 7: Adjust Container Resource Limits

Docker lets you update resource limits on a running container without stopping it.

Set a memory limit of 512MB on voleon-pg. On **pg-container**, as **ec2-user**:

```bash
docker update --memory 512m --memory-swap 512m voleon-pg
```

Verify the new limit was applied. On **pg-container**, as **ec2-user**:

```bash
docker inspect voleon-pg | grep -A 3 '"Memory"'
```

Expected output (yours will differ):

```
            "Memory": 536870912,
            "MemorySwap": 536870912,
            "MemoryReservation": 0,
```

`536870912` bytes is exactly 512MB. The container is still running with the new limit applied.

Check that the container survived the update. On **pg-container**, as **ec2-user**:

```bash
docker ps --filter name=voleon-pg
```

Reset the memory limit to unrestricted (0 = no limit). On **pg-container**, as **ec2-user**:

```bash
docker update --memory 0 --memory-swap 0 voleon-pg
```

---

## Exercise 8: Backup a Docker PostgreSQL Database

`pg_dump` can run inside the container using `docker exec`. The output is piped through to the host filesystem.

On **pg-container**, as **ec2-user**:

```bash
docker exec -t voleon-pg pg_dump -U postgres container_test \
  > /tmp/container_test_backup.sql
```

Verify the backup file has content. On **pg-container**, as **ec2-user**:

```bash
wc -l /tmp/container_test_backup.sql
head -20 /tmp/container_test_backup.sql
```

Expected output (yours will differ):

```
42 /tmp/container_test_backup.sql
--
-- PostgreSQL database dump
--
-- Dumped from database version 17.x
...
```

Now restore that backup to a new, temporary container. Pull the same image and start a temporary container. On **pg-container**, as **ec2-user**:

```bash
docker run --rm -d \
  --name voleon-pg-restore \
  -e POSTGRES_PASSWORD=restore_pass \
  -p 5434:5432 \
  postgres:17
```

Wait 5 seconds for it to start, then create the target database. On **pg-container**, as **ec2-user**:

```bash
sleep 5
docker exec -it voleon-pg-restore psql -U postgres \
  -c "CREATE DATABASE container_test_restored;"
```

Restore the backup. On **pg-container**, as **ec2-user**:

```bash
cat /tmp/container_test_backup.sql | \
  docker exec -i voleon-pg-restore psql -U postgres -d container_test_restored
```

Verify the data is there. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-pg-restore psql -U postgres -d container_test_restored \
  -c "SELECT * FROM test_run;"
```

You should see the row you inserted earlier. Stop and remove the restore container when done. On **pg-container**, as **ec2-user**:

```bash
docker stop voleon-pg-restore
```

Because you used `--rm` when starting it, Docker automatically removes the container once it stops.

---

## Exercise 9: Podman Quick Comparison

Podman is an alternative to Docker that runs containers without a daemon. CentOS Stream 9 ships with Podman by default.

Check what is running under Podman. On **pg-container**, as **ec2-user**:

```bash
podman ps
```

If nothing is running, that is fine. Run a quick Alpine container to verify Podman works. On **pg-container**, as **ec2-user**:

```bash
podman run --rm alpine echo "podman works"
```

Expected output:

```
podman works
```

Compare the version numbers. On **pg-container**, as **ec2-user**:

```bash
docker --version
podman --version
```

The key difference: Docker has a background daemon (`dockerd`). Podman is daemonless - each container runs as a direct child process. Both are OCI-compliant, so container images are interchangeable.

---

## Exercise 10: Redis Container Operations

The `voleon-redis` container runs Redis on host port 6380.

Connect to Redis inside the container. On **pg-container**, as **ec2-user**:

```bash
docker exec -it voleon-redis redis-cli -p 6379
```

You are now at the Redis prompt `127.0.0.1:6379>`.

Set a key. Inside the **voleon-redis container**:

```
SET last_sync_time "2026-06-15T14:30:00Z"
```

Expected output:

```
OK
```

Retrieve the key. Inside the **voleon-redis container**:

```
GET last_sync_time
```

Expected output:

```
"2026-06-15T14:30:00Z"
```

Set a key with a TTL (time to live) of 60 seconds. Inside the **voleon-redis container**:

```
SET temp_flag "processing" EX 60
TTL temp_flag
```

The `TTL` command returns the remaining seconds before the key expires.

Check server info and memory usage. Inside the **voleon-redis container**:

```
INFO server
INFO memory
```

Look for `redis_version`, `used_memory_human`, and `maxmemory_human` in the output.

Exit the Redis CLI. Inside the **voleon-redis container**:

```
quit
```

---

## Summary

In this exercise you:
- Confirmed all three containers are healthy using `docker ps` and `docker stats`
- Connected to Docker PostgreSQL via `docker exec` and created a database and table
- Imported a SQL dataset into Docker MySQL using file redirection
- Compared the Docker PostgreSQL instance against the native install on pg-primary
- Explored Docker volume storage and found the actual data directory on the host
- Read container logs and tailed them in real time
- Updated a memory limit on a running container without stopping it
- Backed up a Docker PostgreSQL database to a SQL file and restored it to a new container
- Ran a Podman container and compared it against Docker
- Used Redis inside a container to set, get, and expire keys

The core skill here is understanding that `docker exec` is your entry point into any running container, and that port mappings connect the outside world to services inside.
