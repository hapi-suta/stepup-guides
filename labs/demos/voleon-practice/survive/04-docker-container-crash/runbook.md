# Runbook 04: Docker Container Crash

## Alert
> "Docker PostgreSQL container voleon-pg on pg-container is not responding. Port 5433 connection
> refused."

The `voleon-pg` Docker container on the container server (34.235.89.112) has stopped. Applications
that connect to port 5433 on that host are receiving `Connection refused`. The container may have
been OOM killed, crashed on startup, experienced a volume issue, or exited due to a failed
health check.

---

## Layer 1 - Junior DBA: Assess and Contain

**Goal:** Confirm the container is down, collect all available diagnostic information, and check
host-level resources before anything is restarted.

### Step 1: SSH into the container server

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

### Step 2: Check all container statuses

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker ps -a
```

Expected output (when container is down):

```
CONTAINER ID   IMAGE            COMMAND                  CREATED        STATUS                     PORTS     NAMES
a3f1d8c29e10   postgres:17      "docker-entrypoint.s..."  2 hours ago   Exited (137) 14 min ago              voleon-pg
8b2c4e91fa30   mysql:8.0        "docker-entrypoint.s..."  2 hours ago   Up 2 hours                 3306/tcp  voleon-mysql
d9e7a2c03b11   redis:7.2        "docker-entrypoint.s..."  2 hours ago   Up 2 hours                 6379/tcp  voleon-redis
```

Key things to note in the `STATUS` column for `voleon-pg`:
- `Exited (137)` - exit code 137 means the container was killed by signal 9 (SIGKILL), usually OOM
- `Exited (1)` - the process inside the container crashed (check logs for the reason)
- `Exited (0)` - the container stopped cleanly (someone ran `docker stop`)
- `OOMKilled` - the Docker daemon killed the container due to memory exhaustion

### Step 3: Check the container logs

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker logs voleon-pg --tail 100
```

Expected output (OOM scenario - truncated):

```
2024-08-14 09:41:22.134 UTC [1] LOG:  starting PostgreSQL 17.1 on x86_64-pc-linux-gnu
2024-08-14 09:41:22.201 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2024-08-14 09:41:22.891 UTC [1] LOG:  database system was interrupted; last known up at 2024-08-14 09:30:00 UTC
...
Killed
```

`Killed` at the end confirms OOM kill. For a crash, you will see a PANIC or FATAL log line. For
a disk issue, you will see `could not write to file` errors.

### Step 4: Check if the container was OOM killed

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker inspect voleon-pg | grep -i oom
```

Expected output when OOM killed:

```
            "OOMKilled": true,
```

Also check the host-level OOM log:

```bash
sudo dmesg | grep -i "oom\|kill" | tail -20
```

Expected output:

```
[123456.789] Out of memory: Kill process 18432 (postgres) score 820 or sacrifice child
[123456.812] Killed process 18432 (postgres) total-vm:2048000kB, anon-rss:1843200kB
```

### Step 5: Check host memory and disk

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
free -h
```

Expected output (after OOM event, memory appears available because the process was killed):

```
               total        used        free      shared  buff/cache   available
Mem:            3.8Gi       3.1Gi       201Mi        12Mi       531Mi       612Mi
Swap:              0B          0B          0B
```

Note: 0B swap means there is no swap configured. PostgreSQL had nowhere to go when RAM was
exhausted.

Also check disk:

```bash
df -h
```

Look for any filesystem at 100%. If `/var/lib/docker` is full, the container cannot write and may
have crashed for a different reason.

### Step 6: Check Docker volume integrity

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker volume inspect pg_data
```

Expected output:

```json
[
    {
        "CreatedAt": "2024-08-14T02:00:00Z",
        "Driver": "local",
        "Mountpoint": "/var/lib/docker/volumes/pg_data/_data",
        "Name": "pg_data",
        "Scope": "local"
    }
]
```

Confirm the mountpoint exists and has data:

```bash
sudo ls -lh /var/lib/docker/volumes/pg_data/_data/
```

You should see the standard PostgreSQL data directory structure: `PG_VERSION`, `base/`, `global/`,
`pg_wal/`. If the directory is empty, you have a data volume problem - escalate to the senior DBA
immediately.

### Step 7: Notify the team

Document:
- Container exit status (Exited code, OOMKilled true/false)
- Last 10 lines of container logs
- Current host memory and disk state
- Whether the data volume appears intact

Post to the incident channel. Do not restart the container if OOMKilled = true and you have not
addressed the memory limit. It will just crash again.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

**Goal:** Safely restart the container, verify data integrity after recovery, and apply an
immediate memory limit to prevent another crash loop.

### Step 8: Set a memory limit before restarting

If the container had no memory limit, it competed with the entire host and won too much RAM. Set
a limit now so Docker will OOM kill only the container (not the host) at the threshold.

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker update --memory 1g --memory-swap 1g voleon-pg
```

Expected output:

```
voleon-pg
```

Confirm the limit was applied:

```bash
sudo docker inspect voleon-pg | grep -i '"Memory"'
```

Expected output:

```
            "Memory": 1073741824,
```

`1073741824` bytes = 1 GB. The container will now be OOM killed before it can take down the host.

### Step 9: Start the container

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker start voleon-pg
```

Watch the startup logs in real time:

```bash
sudo docker logs voleon-pg -f --tail 30
```

Expected output during normal startup:

```
2024-08-14 10:02:11.001 UTC [1] LOG:  starting PostgreSQL 17.1 on x86_64-pc-linux-gnu
2024-08-14 10:02:11.003 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2024-08-14 10:02:11.122 UTC [1] LOG:  database system was shut down at 2024-08-14 09:41:22 UTC
2024-08-14 10:02:11.210 UTC [1] LOG:  database system is ready to accept connections
```

`database system is ready to accept connections` confirms successful startup. Press `Ctrl+C` to
exit the log stream.

If you see `PANIC: could not locate a valid checkpoint record`, the database files were corrupted.
Stop here and escalate to the senior DBA - do not force-restart.

### Step 10: Verify the container is running and the port is open

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker ps | grep voleon-pg
```

Expected output:

```
a3f1d8c29e10   postgres:17   "docker-entrypoint.s..."   Up 2 minutes   0.0.0.0:5433->5432/tcp   voleon-pg
```

Test the port directly:

```bash
/usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5433
```

Expected output:

```
127.0.0.1:5433 - accepting connections
```

### Step 11: Verify data integrity inside the container

Connect to the container's PostgreSQL and run basic integrity checks.

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker exec -it voleon-pg psql -U postgres -d quantdb
```

Once inside psql, check the table count:

```sql
SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('quant', 'ops') ORDER BY schemaname, tablename;
```

Check for any tables flagged for recovery after the crash:

```sql
SELECT relname, relfrozenxid FROM pg_class WHERE relkind = 'r' AND relpages = 0 AND reltuples > 0;
```

If the above query returns rows (tables with 0 pages but non-zero tuple count), run VACUUM on
those tables:

```sql
VACUUM ANALYZE quant.signals;
VACUUM ANALYZE ops.runs;
```

Exit psql:

```sql
\q
```

### Step 12: Check the other containers are still healthy

The OOM event on the host may have degraded the other containers as well.

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker ps
```

Confirm `voleon-mysql` and `voleon-redis` show `Up` status. If any show `Exited`, investigate and
restart them:

```bash
sudo docker start voleon-mysql
sudo docker start voleon-redis
```

### Step 13: Check what triggered the memory spike

Use Docker stats to see the current memory usage:

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker stats --no-stream
```

Expected output:

```
CONTAINER ID   NAME           CPU %   MEM USAGE / LIMIT   MEM %   NET I/O       BLOCK I/O
a3f1d8c29e10   voleon-pg      0.5%    312MiB / 1GiB       30.5%   1.2MB/980kB   45MB/12MB
8b2c4e91fa30   voleon-mysql   0.3%    280MiB / 500MiB     56.0%   800kB/1.1MB   20MB/5MB
d9e7a2c03b11   voleon-redis   0.1%    18MiB / 200MiB      9.0%    500kB/300kB   1MB/200kB
```

If `voleon-pg` is approaching its new 1 GB limit, investigate what workload is driving memory.
Connect to the container and check `pg_stat_activity` for large queries:

```bash
sudo docker exec -it voleon-pg psql -U postgres -d quantdb -c "SELECT pid, query_start, state, left(query, 80) AS query FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;"
```

---

## Layer 3 - Senior DBA: Root Cause and Prevent

**Goal:** Understand the root cause of the OOM event, configure proper resource limits for all
containers, add health checks, and set up persistent monitoring.

### Step 14: Analyze what caused the memory spike

Check if `shared_buffers` or `work_mem` in the PostgreSQL container config was set too high for
the host's available RAM.

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker exec -it voleon-pg psql -U postgres -c "SHOW shared_buffers; SHOW work_mem; SHOW effective_cache_size;"
```

Expected output:

```
 shared_buffers
----------------
 1GB
(1 row)

 work_mem
----------
 256MB
(1 row)
```

If `shared_buffers = 1GB` and the container had no memory limit, a single sort operation with
`work_mem = 256MB` could cause PostgreSQL to allocate 1GB + (workers * 256MB) at once, exceeding
available RAM. Reduce these settings.

Create or edit the container's PostgreSQL config. The container uses an environment variable or
a mounted config file. Check how the container was originally started:

```bash
sudo docker inspect voleon-pg | grep -A 20 '"Env"'
```

If you see `POSTGRES_SHARED_BUFFERS=1GB`, you need to update the container run command or compose
file to reduce it.

### Step 15: Rebuild the container with proper PostgreSQL memory settings

Stop the running container:

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker stop voleon-pg
```

Remove only the container, not the volume (never remove the volume without backing up first):

```bash
sudo docker rm voleon-pg
```

Re-create the container with:
- Memory limit: `--memory 1g`
- Swap limit equal to memory: `--memory-swap 1g` (no extra swap)
- Restart policy: `--restart unless-stopped`
- Reduced `shared_buffers` appropriate for 1 GB container limit (256 MB is a safe value)
- A health check that verifies PostgreSQL is accepting connections

```bash
sudo docker run -d \
  --name voleon-pg \
  --memory 1g \
  --memory-swap 1g \
  --restart unless-stopped \
  -p 5433:5432 \
  -v pg_data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=changeme \
  -e POSTGRES_DB=quantdb \
  --health-cmd="pg_isready -U postgres" \
  --health-interval=10s \
  --health-timeout=5s \
  --health-retries=3 \
  --health-start-period=30s \
  postgres:17 \
  -c shared_buffers=256MB \
  -c work_mem=32MB \
  -c effective_cache_size=512MB \
  -c max_connections=100
```

Verify the container starts healthy:

```bash
sudo docker ps | grep voleon-pg
```

Expected output (after health check period):

```
a3f1d8c29e10   postgres:17   "docker-entrypoint.s..."   Up 2 minutes (healthy)   0.0.0.0:5433->5432/tcp   voleon-pg
```

`(healthy)` confirms the health check is passing.

### Step 16: Set limits on voleon-mysql and voleon-redis too

While you are here, apply sensible limits to the other containers to prevent them from competing
for memory.

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker update --memory 512m --memory-swap 512m voleon-mysql
```

```bash
sudo docker update --memory 256m --memory-swap 256m voleon-redis
```

Confirm limits are applied:

```bash
sudo docker stats --no-stream
```

### Step 17: Set up Docker stats export to a monitoring system

Docker's native `docker stats` is manual. For production-level alerting, export metrics to
Prometheus using `cAdvisor`:

On **pg-container (34.235.89.112)**, as **ec2-user**:

```bash
sudo docker run -d \
  --name cadvisor \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest
```

Verify cAdvisor is running:

```bash
sudo docker ps | grep cadvisor
```

cAdvisor exposes metrics on `http://34.235.89.112:8080/metrics`. Add this endpoint to your
Prometheus scrape config and alert on:

```
container_memory_usage_bytes{name="voleon-pg"} / container_spec_memory_limit_bytes{name="voleon-pg"} > 0.85
```

This fires at 85% memory usage - before the container is OOM killed.

### Step 18: Consider Podman as an alternative

Docker requires a root daemon. A crash in the Docker daemon can take all containers down together.
Podman runs containers as individual systemd services (rootless), which means each container has its
own restart policy managed by systemd rather than a single daemon.

Benefits for this setup:
- `systemctl status voleon-pg` works like any other service
- `journalctl -u voleon-pg` gives structured logs integrated with the OS
- No single daemon failure can kill all containers at once
- Rootless mode reduces the blast radius of container escapes

This is a medium-term architecture decision. Queue it for the next infrastructure review with the
platform team.

### Step 19: Document the container run parameters in version control

The `docker run` command from Step 15 must be stored somewhere reproducible. If the host is
terminated and rebuilt, you need to recreate the containers exactly. Options:

1. A Docker Compose file in the lab's git repo
2. A shell script `start-containers.sh` stored in the repo
3. A systemd unit file if switching to Podman

Create the compose file at `/opt/voleon/docker-compose.yml` with the settings from Step 15, and
commit it to the repo. This ensures any future rebuild is consistent and the memory limits are
not forgotten.

---

## Summary

### Root Cause
The `voleon-pg` container had no memory limit set. A workload (large sort or hash join) caused
PostgreSQL to allocate more RAM than was available on the host. The Linux OOM killer sent SIGKILL
(signal 9) to the PostgreSQL process inside the container, causing an unclean shutdown. Exit
code 137 (128 + 9) confirmed this.

### Resolution
1. Confirmed OOM kill via `docker inspect` (`OOMKilled: true`) and `dmesg`
2. Applied a 1 GB memory limit with `docker update` before restarting
3. Started the container and confirmed `(healthy)` status via health check
4. Verified data integrity inside the container with `pg_stat_activity` and table checks
5. Confirmed other containers (voleon-mysql, voleon-redis) were unaffected

### Prevention
- Set memory limits on all containers - never run without `--memory`
- Add `--health-cmd` health checks so Docker knows when PostgreSQL is actually ready
- Set `--restart unless-stopped` so containers recover from host reboots
- Tune `shared_buffers` and `work_mem` to fit within the container memory limit
- Export Docker metrics to Prometheus via cAdvisor and alert at 85% memory usage
- Store all container run parameters in version control for reproducible rebuilds
- Evaluate Podman + systemd as a longer-term alternative to Docker daemon
