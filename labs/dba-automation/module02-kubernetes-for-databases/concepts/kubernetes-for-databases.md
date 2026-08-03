# Concepts: Kubernetes for Databases

**Module:** Kubernetes for Databases
**Reference document** - use alongside BUILD guides 01-04.

---

## Container vs VM Comparison

| Aspect | Virtual Machine | Container |
|--------|----------------|-----------|
| **Boot time** | Minutes | Seconds |
| **Size** | Gigabytes (full OS) | Megabytes (app + dependencies only) |
| **Isolation** | Full hardware-level (hypervisor) | Process-level (shared kernel) |
| **Resource overhead** | High - each VM runs its own OS kernel | Low - containers share the host kernel |
| **Density** | 10-20 VMs per server | 100+ containers per server |
| **Portability** | Tied to hypervisor format (VMware, KVM) | Runs anywhere Docker/containerd runs |
| **Network** | Full network stack per VM | Virtual network overlay |
| **Storage** | Virtual disks (VMDK, qcow2) | Volumes, bind mounts |
| **Security** | Strong isolation (separate kernels) | Weaker isolation (shared kernel - use with caution for multi-tenant databases) |
| **DBA use case** | Production databases needing strong isolation | Dev/test, CI/CD, microservices, operator-managed databases |

**Key insight for DBAs:** Containers are not less secure than VMs by default, but the isolation model is different. For multi-tenant databases where complete isolation is critical, VMs are still preferred. For databases managed by an operator within a trusted cluster, containers are excellent.

---

## Kubernetes Architecture Diagram

```
+------------------------------------------------------------------+
|                     KUBERNETES CLUSTER                             |
|                                                                    |
|  +---------------------------+                                     |
|  |      CONTROL PLANE        |                                     |
|  |                           |                                     |
|  |  +----------+  +-------+  |                                     |
|  |  | API      |  | etcd  |  |  etcd = cluster state database     |
|  |  | Server   |  | (K/V) |  |  (like Patroni's DCS)             |
|  |  +----------+  +-------+  |                                     |
|  |                           |                                     |
|  |  +----------+  +-------+  |                                     |
|  |  | Scheduler|  |Control|  |  Scheduler = decides WHERE to      |
|  |  |          |  |Manager|  |  run pods (like picking a server)   |
|  |  +----------+  +-------+  |                                     |
|  +---------------------------+                                     |
|                                                                    |
|  +---------------------------+  +---------------------------+      |
|  |      WORKER NODE 1        |  |      WORKER NODE 2        |      |
|  |                           |  |                           |      |
|  |  +--------+  +--------+  |  |  +--------+  +--------+  |      |
|  |  | Pod    |  | Pod    |  |  |  | Pod    |  | Pod    |  |      |
|  |  | pg-0   |  | app-1  |  |  |  | pg-1   |  | app-2  |  |      |
|  |  +--------+  +--------+  |  |  +--------+  +--------+  |      |
|  |                           |  |                           |      |
|  |  +--------+               |  |  +--------+               |      |
|  |  | kubelet| (agent)       |  |  | kubelet| (agent)       |      |
|  |  +--------+               |  |  +--------+               |      |
|  |                           |  |                           |      |
|  |  +--------+               |  |  +--------+               |      |
|  |  | kube-  | (networking)  |  |  | kube-  | (networking)  |      |
|  |  | proxy  |               |  |  | proxy  |               |      |
|  |  +--------+               |  |  +--------+               |      |
|  +---------------------------+  +---------------------------+      |
+------------------------------------------------------------------+
```

**DBA translation:**
- **API Server** - The front door. All `kubectl` commands go through here. Like the PostgreSQL `postmaster` accepting connections.
- **etcd** - The cluster state database. Stores what should be running and where. Like Patroni's DCS (etcd/ZooKeeper/Consul).
- **Scheduler** - Decides which worker node gets a new pod. Like a load balancer deciding which server handles a new connection.
- **Controller Manager** - Ensures desired state matches actual state. Like Patroni checking if the primary is healthy.
- **kubelet** - Agent on each worker node. Starts/stops pods. Like the Patroni agent on each PostgreSQL server.
- **kube-proxy** - Handles networking. Like iptables rules that route traffic to the right pod.

---

## K8s Resource Hierarchy

```
Cluster
  |
  +-- Namespace (databases)
  |     |
  |     +-- StatefulSet (pg)
  |     |     |
  |     |     +-- Pod (pg-0)
  |     |     |     |
  |     |     |     +-- Container (postgres:16)
  |     |     |
  |     |     +-- Pod (pg-1)
  |     |           |
  |     |           +-- Container (postgres:16)
  |     |
  |     +-- Service (pg-rw)
  |     +-- Service (pg-ro)
  |     +-- ConfigMap (pg-config)
  |     +-- Secret (pg-credentials)
  |     +-- PVC (pg-data-pg-0)
  |     +-- PVC (pg-data-pg-1)
  |
  +-- Namespace (kube-system)
        |
        +-- (K8s internal components)
```

**DBA translation:**
- Cluster = your entire infrastructure
- Namespace = a PostgreSQL schema (logical separation)
- StatefulSet = a managed set of database instances
- Pod = a single database instance
- Container = the PostgreSQL process inside the instance
- Service = a DNS name/VIP for routing connections
- ConfigMap = `postgresql.conf`
- Secret = `.pgpass` / password storage
- PVC = the disk holding PGDATA

---

## StatefulSet vs Deployment Decision Table

| Question | If Yes, Use | If No, Use |
|----------|------------|------------|
| Does the application store data that must survive restarts? | StatefulSet | Deployment |
| Does each instance need a unique, stable identity? | StatefulSet | Deployment |
| Does startup/shutdown order matter? | StatefulSet | Deployment |
| Do instances need stable DNS names? | StatefulSet | Deployment |
| Are all instances interchangeable? | Deployment | StatefulSet |
| Can you lose an instance and replace it with a fresh one? | Deployment | StatefulSet |

**Summary:** If it is a database, message queue, or any stateful service - use a StatefulSet. If it is a web server, API, or stateless worker - use a Deployment.

---

## CloudNativePG CRD Reference

### Cluster Resource

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <cluster-name>           # Name of the PostgreSQL cluster
  namespace: <namespace>          # Kubernetes namespace
spec:
  instances: <number>             # Total instances (primary + standbys)
  imageName: <image>              # PostgreSQL container image

  postgresql:
    parameters:                   # postgresql.conf parameters
      <key>: "<value>"
    pg_hba:                       # pg_hba.conf rules
      - "<hba-rule>"

  bootstrap:
    initdb:                       # Initialize a new cluster
      database: <dbname>
      owner: <username>
    recovery:                     # Restore from backup (PITR)
      source: <cluster-name>
      recoveryTarget:
        targetTime: "<timestamp>"

  storage:
    size: <size>                  # PGDATA disk size (e.g., "10Gi")
    storageClass: <class>         # Storage class name

  walStorage:                     # Separate WAL storage (recommended)
    size: <size>
    storageClass: <class>

  resources:
    requests:
      memory: "<size>"
      cpu: "<cores>"
    limits:
      memory: "<size>"
      cpu: "<cores>"

  backup:
    barmanObjectStore:
      destinationPath: "<s3-path>"
      s3Credentials:
        accessKeyId:
          name: <secret-name>
          key: <key>
        secretAccessKey:
          name: <secret-name>
          key: <key>
    retentionPolicy: "<duration>" # e.g., "30d"

  monitoring:
    enablePodMonitor: <bool>      # Enable Prometheus PodMonitor
```

### Key Commands

| Command | What It Does |
|---------|-------------|
| `kubectl cnpg status <cluster>` | Show cluster health, roles, LSN positions |
| `kubectl cnpg promote <cluster> <pod>` | Manual promotion of a standby |
| `kubectl cnpg certificates <cluster>` | Show TLS certificate status |
| `kubectl cnpg restart <cluster>` | Rolling restart of all instances |
| `kubectl cnpg reload <cluster>` | Reload PostgreSQL configuration |
| `kubectl cnpg maintenance set <cluster> --reusePVC` | Enable maintenance mode |

---

## kubectl Cheat Sheet for DBAs

### Cluster Information

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl cluster-info` | "What cluster am I connected to?" |
| `kubectl get nodes` | "What servers are in this cluster?" |
| `kubectl top nodes` | "How loaded are my servers?" |

### Namespace Operations

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl get namespaces` | `\dn` (list schemas) |
| `kubectl create namespace <name>` | `CREATE SCHEMA <name>` |
| `kubectl config set-context --current --namespace=<name>` | `SET search_path TO <name>` |

### Pod Operations

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl get pods -n <ns>` | `pg_lsclusters` / `systemctl list-units` |
| `kubectl describe pod <name> -n <ns>` | `pg_controldata` + system info |
| `kubectl logs <pod> -n <ns>` | `tail /var/log/postgresql/*.log` |
| `kubectl logs <pod> -n <ns> --previous` | Check logs of a crashed instance |
| `kubectl exec -it <pod> -n <ns> -- psql -U postgres` | SSH + psql |
| `kubectl delete pod <pod> -n <ns>` | Kill the process (K8s will restart it) |
| `kubectl top pod -n <ns>` | `top` / `htop` for resource usage |

### Storage Operations

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl get pvc -n <ns>` | `df -h` (show disk usage) |
| `kubectl get pv` | Show all physical volumes in the cluster |
| `kubectl get storageclass` | Show available disk types |

### Debugging

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl get events -n <ns> --sort-by=.lastTimestamp` | System event log |
| `kubectl describe pod <pod> -n <ns>` | Detailed pod info (look at Events section) |
| `kubectl get pod <pod> -n <ns> -o yaml` | Full YAML dump of pod state |
| `kubectl port-forward pod/<pod> 5432:5432 -n <ns>` | SSH tunnel to PostgreSQL |

### Resource Management

| Command | DBA Equivalent |
|---------|---------------|
| `kubectl apply -f <file.yaml>` | `psql -f schema.sql` |
| `kubectl delete -f <file.yaml>` | Drop all resources defined in the file |
| `kubectl get all -n <ns>` | Show everything in a namespace |
| `kubectl diff -f <file.yaml>` | Preview changes before applying |

---

## When to Use K8s vs RDS vs Bare Metal

| Factor | Kubernetes | RDS / Cloud Managed | Bare Metal / VM |
|--------|-----------|-------------------|----------------|
| **Setup time** | Hours (with operator) | Minutes | Days |
| **Operational overhead** | Medium (operator handles most) | Low (cloud handles most) | High (you handle everything) |
| **Control** | High | Low | Full |
| **Cost at scale** | Lowest | Highest | Medium |
| **Cost at small scale** | Medium | Lowest | Highest |
| **Extension support** | Any extension | Limited list | Any extension |
| **Multi-cloud** | Yes (runs anywhere) | No (vendor lock-in) | Yes (but manual) |
| **HA/Failover** | Operator-managed (seconds) | Cloud-managed (minutes) | Manual or Patroni |
| **Backup/PITR** | Operator + Barman/pgBackRest | Built-in | Manual setup |
| **Major upgrades** | Operator-assisted | Blue/green or in-place | Manual pg_upgrade |
| **Team skills needed** | DBA + K8s | DBA only | DBA + Sysadmin |
| **Best for** | Platform teams, multi-cloud, advanced extensions | Small teams, single cloud, standard workloads | Legacy apps, maximum control, compliance |

### Decision Flowchart

1. **Do you need extensions not available on RDS?** - Yes: K8s or Bare Metal
2. **Do you run on multiple clouds?** - Yes: K8s
3. **Does your team know Kubernetes?** - No: RDS or Bare Metal
4. **Is cost optimization critical at 50+ instances?** - Yes: K8s
5. **Do you need to be up and running in a day?** - Yes: RDS
6. **Do you need full OS-level control?** - Yes: Bare Metal
7. **Default choice for most teams:** RDS until you outgrow it
