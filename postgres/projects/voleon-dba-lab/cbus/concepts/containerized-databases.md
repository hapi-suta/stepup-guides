# Containerized Databases

## Why Run Databases in Containers

The default answer for production databases has long been: bare metal or dedicated VMs, not containers. That is still true for primary production databases. But containers solve real problems in specific contexts, and understanding when to use them - and when not to - is a key skill at a shop like Voleon.

### Good Use Cases for Containerized Databases

**Development and test environments** - Every developer can run a local PostgreSQL instance matching production's major version with no installation required. `docker run -e POSTGRES_PASSWORD=dev postgres:16` is faster and cleaner than installing PostgreSQL locally.

**CI/CD pipelines** - Tests that require a real database (not mocks) spin up a container, run migrations, execute tests, and tear down. No shared test database state. No schema collisions between parallel test runs.

**Microservice sidecars** - A service that owns its data exclusively and has low throughput may be fine with a containerized database. The key word is "owns" - no cross-service joins, no shared schema.

**Staging environments** - A containerized staging database can be snapshotted, cloned, and reset quickly. Developers can test destructive migrations safely.

**Non-critical internal tooling** - Monitoring databases, job schedulers, internal dashboards - these have modest throughput requirements and benefit from the operational simplicity of containers.

### Where Containers Are Not Appropriate

**Production primary databases for critical systems** - At Voleon, the PostgreSQL instances holding market data, positions, and ML feature tables run on bare metal or dedicated VMs. The reasons:
- Container networking adds latency
- Resource limits in containers interact poorly with PostgreSQL's buffer management
- Data persistence requires careful volume management - mistakes cause data loss
- High availability (failover, streaming replication) is significantly more complex in containers
- PostgreSQL uses `fsync` extensively - container storage stacks add overhead

---

## Docker vs Podman

### Docker

Docker is the most widely used container runtime. It uses a daemon (`dockerd`) running as root, which containers communicate with via a socket. Images are pulled from Docker Hub or private registries.

Key components:
- `docker` CLI - user-facing commands
- `dockerd` - daemon that manages containers
- containerd - low-level container runtime
- Docker Engine - the full stack

### Podman

Podman is a daemonless, rootless container runtime developed by Red Hat. It is the default on RHEL/CentOS Stream 9, which is the OS Voleon and this lab use.

Key differences from Docker:
- **No daemon** - each `podman` command is a direct fork/exec, not a call to a long-running daemon
- **Rootless** - containers can run as a regular user with no root privileges required (improved security)
- **Systemd integration** - Podman can generate systemd unit files with `podman generate systemd`, making container lifecycle management consistent with other services
- **Drop-in compatible** - `alias docker=podman` works for most use cases

```bash
# These are equivalent in most cases
docker run -d --name mydb postgres:16
podman run -d --name mydb postgres:16
```

At Voleon, Podman is the container runtime on RHEL/CentOS nodes. Docker may appear on older infrastructure or developer laptops.

---

## Volume Management

Containers are ephemeral by default. When a container is removed, its filesystem is gone. For databases, you must use persistent storage.

### Named Volumes

Docker/Podman manages the storage location. The runtime creates a directory under `/var/lib/docker/volumes/` (or equivalent for Podman).

```bash
# Create a named volume
docker volume create pg-data

# Mount it into a PostgreSQL container
docker run -d \
  --name postgres-dev \
  -v pg-data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=devpass \
  postgres:16
```

Named volumes persist across container restarts and survive `docker stop` / `docker rm`. They are removed only by `docker volume rm`.

### Bind Mounts

A specific directory on the host is mounted into the container. More explicit, easier to inspect, but tied to host paths.

```bash
# Mount /opt/pgdata from the host into the container
docker run -d \
  --name postgres-dev \
  -v /opt/pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=devpass \
  postgres:16
```

Bind mounts are useful when you need the storage to integrate with host-level backup tools, or when you want to inspect the data directory directly on the host.

### Ownership and Permissions

PostgreSQL runs as the `postgres` user inside the container (UID 999 by default in the official image). The host directory or volume must be owned by that UID:

```bash
mkdir -p /opt/pgdata
chown 999:999 /opt/pgdata
```

Getting this wrong produces the common error: `initdb: error: could not create directory "/var/lib/postgresql/data": Permission denied`

---

## Networking

### Port Mapping

PostgreSQL listens on port 5432 inside the container. To access it from the host or external clients, map a host port to the container port:

```bash
docker run -d \
  -p 5432:5432 \          # host_port:container_port
  --name postgres-dev \
  postgres:16
```

For multiple PostgreSQL containers on the same host, use different host ports:

```bash
docker run -d -p 5433:5432 --name pg-staging postgres:16
docker run -d -p 5434:5432 --name pg-test postgres:16
```

### Docker Bridge Network

By default, containers run on a bridge network with private IPs. Containers on the same bridge network can reach each other by container name (Docker provides internal DNS).

```bash
# Create a network
docker network create app-net

# Connect both containers to it
docker run -d --network app-net --name postgres postgres:16 -e POSTGRES_PASSWORD=pass
docker run -d --network app-net --name app myapp:latest

# The app container can connect to postgres:5432 by name
```

This is how Docker Compose works - it creates a default network and all services in the compose file can reach each other by service name.

---

## Resource Limits

Resource limits are critical for database containers. Without limits, a runaway query can consume all host memory and kill the container or crash the host.

### Memory

```bash
docker run -d \
  --name postgres-dev \
  --memory=4g \          # hard limit: container killed if exceeded
  --memory-swap=4g \     # disable swap (same as memory = no swap)
  postgres:16
```

Important: PostgreSQL's `shared_buffers` and `work_mem` settings must be sized to fit within the container's memory limit. A common mistake is running PostgreSQL with default settings (shared_buffers = 128MB) inside a 4GB container - the database will be severely under-tuned.

Rule of thumb for containerized PostgreSQL:
- `shared_buffers` = 25% of container memory limit
- `work_mem` = conservative (2-8MB) to avoid per-connection memory accumulation
- `max_connections` = reduced compared to bare metal (no point in 100 connections if the app only uses 10)

### CPU

```bash
docker run -d \
  --name postgres-dev \
  --cpus=4 \             # limit to 4 CPU cores
  postgres:16
```

CPU limits affect PostgreSQL parallel query execution. If `max_parallel_workers_per_gather` is set to 4 but the container only has 2 CPUs, parallel queries will be throttled.

### Storage I/O

Docker supports block device I/O limits via `--blkio-weight` and `--device-read-bps`. These are useful in shared environments to prevent one database container from saturating disk I/O.

---

## Kubernetes for Databases

### StatefulSets

Kubernetes `Deployment` objects are for stateless workloads - any pod can be replaced with any other. `StatefulSet` is for stateful workloads like databases. It provides:
- Stable, persistent network identifiers (`postgres-0`, `postgres-1`)
- Ordered startup and shutdown (primary starts before replicas)
- PersistentVolumeClaims (PVCs) that are not deleted when pods are deleted

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:16
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: pg-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: ceph-rbd
      resources:
        requests:
          storage: 100Gi
```

### PersistentVolumes and StorageClasses

A `StorageClass` defines how storage is provisioned. At Voleon, there is a Ceph RBD StorageClass that dynamically creates RBD images when a PVC is created. The DBA does not create RBD volumes manually - Kubernetes handles it.

PVCs survive pod deletion. Even if the `postgres-0` pod crashes and is recreated, the PVC with the actual data remains and is reattached to the new pod.

### Operators

A Kubernetes Operator is a custom controller that knows how to manage a specific stateful application. The CloudNativePG operator, for example, knows how to:
- Bootstrap a PostgreSQL primary
- Add streaming replicas
- Perform failover when the primary fails
- Manage pgBackRest for backups

Operators reduce the operational burden of running databases on Kubernetes, but they also add a layer of abstraction that can be confusing during incidents. The DBA needs to understand both the operator abstraction and the PostgreSQL internals underneath it.

---

## Backup in Containers

### The Problem

`pg_dump` and `pgBackRest` need to run inside or with access to the container's network. Options:
- Run backup tooling as a sidecar container in the same pod
- Use `docker exec` to run `pg_dump` inside the running container
- Mount the data volume into a separate backup container

```bash
# pg_dump via docker exec
docker exec postgres-dev pg_dump -U postgres mydb > /backup/mydb.sql

# pgBackRest sidecar - both containers share the data volume
docker run -d \
  --name pgbackrest \
  -v pg-data:/var/lib/postgresql/data:ro \
  -v /backup:/backup \
  pgbackrest:latest stanza-create
```

### Volume Snapshots in Kubernetes

Kubernetes supports VolumeSnapshots (backed by Ceph RBD snapshots at the storage layer). This provides point-in-time consistent backups at the storage level, avoiding the overhead of logical dumps.

---

## Docker Compose for Multi-Container Stacks

Docker Compose defines multi-container applications in a single YAML file. This is the standard way to run a local dev environment with PostgreSQL, Redis, and an application together.

```yaml
version: "3.9"

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: devpass
      POSTGRES_DB: voleon_dev
    volumes:
      - pg-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"

  app:
    image: myapp:latest
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://postgres:devpass@postgres:5432/voleon_dev
      REDIS_URL: redis://redis:6379

volumes:
  pg-data:
```

Key points:
- `healthcheck` on PostgreSQL ensures `app` does not start until PostgreSQL is ready
- `depends_on` with `condition: service_healthy` is the correct way to handle startup ordering
- Named volume `pg-data` persists data across `docker compose down` (but not `docker compose down -v`)

---

## Monitoring Containerized Databases

### docker stats

```bash
docker stats postgres-dev    # live CPU, memory, network, block I/O
```

Useful for a quick check. Not a substitute for proper monitoring.

### cAdvisor

Google's Container Advisor exposes container resource metrics as Prometheus metrics. Deploy it as a container alongside your database containers:

```bash
docker run -d \
  --name cadvisor \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:latest
```

cAdvisor + Prometheus + Grafana gives full visibility into container resource usage.

### postgres_exporter Inside a Container

The `postgres_exporter` connects to PostgreSQL via the network (or Unix socket). Run it as a sidecar:

```bash
docker run -d \
  --name pg-exporter \
  --network app-net \
  -e DATA_SOURCE_NAME="postgresql://postgres:devpass@postgres:5432/postgres?sslmode=disable" \
  prometheuscommunity/postgres-exporter
```

Prometheus scrapes the exporter, and Grafana displays the same dashboards you use for bare metal PostgreSQL.

---

## When to Containerize vs. Bare Metal

| Scenario                          | Recommendation      | Reason                                              |
|-----------------------------------|---------------------|-----------------------------------------------------|
| Production primary (financial data) | Bare metal         | Lowest latency, simplest failure domain             |
| Production streaming replica      | Bare metal or VM    | Replica should match primary's performance profile  |
| Staging environment               | Container or VM     | Convenience outweighs performance need              |
| Developer local environment       | Container           | Fast setup, no host pollution                       |
| CI database (test runs)           | Container           | Ephemeral, fast spin-up, isolated                   |
| Internal tooling (Grafana DB, etc)| Container           | Low stakes, easy upgrade                            |
| Redis cache (production)          | Container or VM     | Stateless-ish, easy failover, operators exist       |
