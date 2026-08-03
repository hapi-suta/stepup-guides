# BUILD 04: CloudNativePG - Production PostgreSQL on Kubernetes

**Module:** Kubernetes for Databases
**Prerequisites:** BUILD 03 (StatefulSets and Storage) completed, minikube running
**Time:** 75-90 minutes

---

## What You Will Build

By the end of this guide, you will have CloudNativePG operator installed, a 3-node PostgreSQL cluster with automated failover, and you will have tested failover by killing the primary pod and watching the operator promote a standby automatically.

---

## Step 1: What Is a Kubernetes Operator?

In BUILD 03, you created a StatefulSet that ran PostgreSQL pods. But those pods were independent - no replication, no failover, no backups. To make them a real database cluster, you would need to:

- Set up streaming replication between pods
- Monitor the primary and promote a standby if it fails
- Handle backup scheduling
- Manage connection pooling
- Handle minor version upgrades

That is a lot of manual work. A **Kubernetes Operator** automates all of it.

**DBA Analogy:** An operator is like Patroni on steroids. Patroni handles failover for one PostgreSQL cluster. A Kubernetes operator handles failover, backups, monitoring, pooling, and upgrades for ALL your PostgreSQL clusters in the K8s environment - and it does it by extending Kubernetes itself.

| Manual DBA Task | What the Operator Does Automatically |
|----------------|--------------------------------------|
| `pg_basebackup` to set up a standby | Creates standbys automatically when you say `replicas: 2` |
| Monitor with `pg_stat_replication` | Continuously watches replication lag |
| Promote standby on primary failure | Detects failure and promotes within seconds |
| Schedule `pg_dump` / Barman backups | Runs backups on a schedule to S3/MinIO |
| PITR recovery | One YAML change to restore to a specific timestamp |
| PgBouncer configuration | Built-in connection pooler |

---

## Step 2: Why Operators Exist

Managing databases on Kubernetes is hard because Kubernetes was designed for stateless applications. Operators bridge that gap by encoding DBA knowledge into software.

An operator works by defining a **Custom Resource Definition (CRD)** - a new resource type in Kubernetes. Just as Kubernetes natively understands Pods, Deployments, and Services, an operator teaches Kubernetes to understand a new kind called `Cluster` (in CloudNativePG's case).

When you write:

```yaml
kind: Cluster
spec:
  instances: 3
```

The operator sees this and automatically:
1. Creates 3 pods (1 primary, 2 standbys)
2. Configures streaming replication
3. Monitors health
4. Handles failover

**DBA Analogy:** A CRD is like creating a custom `CREATE TYPE` in PostgreSQL. You are extending the system with a new concept it did not have before.

---

## Step 3: Clean Up Previous Resources

Before installing CloudNativePG, clean up the StatefulSet from BUILD 03 to free resources:

**On your Mac, in Terminal:**

```bash
kubectl delete statefulset pg -n databases
kubectl delete service pg-headless -n databases
kubectl delete pvc pg-data-pg-0 -n databases
```

Expected output (yours will differ):
```
statefulset.apps "pg" deleted
service "pg-headless" deleted
persistentvolumeclaim "pg-data-pg-0" deleted
```

Keep the `databases` namespace, ConfigMap, and Secret.

---

## Step 4: Install CloudNativePG Operator

CloudNativePG is the most popular open-source PostgreSQL operator for Kubernetes. It is a CNCF Sandbox project (Cloud Native Computing Foundation - the same organization that governs Kubernetes).

**On your Mac, in Terminal:**

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.1.yaml
```

This installs the operator into the `cnpg-system` namespace.

Expected output (yours will differ):
```
namespace/cnpg-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backups.postgresql.cnpg.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clusters.postgresql.cnpg.io serverside-applied
...
deployment.apps/cnpg-controller-manager serverside-applied
```

Wait for the operator to be ready:

```bash
kubectl get pods -n cnpg-system -w
```

Expected output (yours will differ):
```
NAME                                       READY   STATUS    RESTARTS   AGE
cnpg-controller-manager-5b4f7c8d9f-abc12   1/1     Running   0          30s
```

Press `Ctrl+C` when you see `Running`.

Verify the CRDs were installed:

```bash
kubectl get crd | grep cnpg
```

Expected output (yours will differ):
```
backups.postgresql.cnpg.io             2026-06-09T15:00:00Z
clusters.postgresql.cnpg.io            2026-06-09T15:00:00Z
poolers.postgresql.cnpg.io             2026-06-09T15:00:00Z
scheduledbackups.postgresql.cnpg.io    2026-06-09T15:00:00Z
```

Kubernetes now understands four new resource types: Cluster, Backup, Pooler, and ScheduledBackup. These are the CRDs that CloudNativePG registered.

---

## Step 5: Install the cnpg kubectl Plugin

CloudNativePG provides a kubectl plugin for easier management:

```bash
brew install kubectl-cnpg
```

Expected output (yours will differ):
```
==> Downloading https://ghcr.io/v2/homebrew/core/kubectl-cnpg/...
==> Installing kubectl-cnpg
...
```

Verify:

```bash
kubectl cnpg version
```

Expected output (yours will differ):
```
Build: {Version:1.25.1 Commit:abc123 Date:2026-05-15}
```

---

## Step 6: Create a PostgreSQL Cluster with CloudNativePG

This is where the operator shines. One YAML file creates a complete PostgreSQL cluster with streaming replication.

**On your Mac, in Terminal:**

```bash
vi /tmp/cnpg-cluster.yaml
```

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-lab
  namespace: databases
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "768MB"
      work_mem: "4MB"
      maintenance_work_mem: "128MB"
      log_statement: "ddl"
      log_min_duration_statement: "1000"

  bootstrap:
    initdb:
      database: appdb
      owner: appuser
      secret:
        name: pg-credentials

  storage:
    size: 2Gi

  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"

  monitoring:
    enablePodMonitor: false
```

Let's break down this manifest:

| Field | What It Does | DBA Analogy |
|-------|-------------|-------------|
| `kind: Cluster` | The CRD type - tells K8s this is a PostgreSQL cluster | Like `CREATE CLUSTER` if SQL had such a command |
| `instances: 3` | 1 primary + 2 standbys | A 3-node HA cluster |
| `imageName` | Which PostgreSQL version to run | Specifying the RPM version to install |
| `postgresql.parameters` | PostgreSQL configuration | Your `postgresql.conf` settings |
| `bootstrap.initdb` | Initial database and owner | `CREATE DATABASE appdb OWNER appuser` |
| `storage.size: 2Gi` | Each instance gets 2GB persistent storage | PGDATA disk size |
| `resources` | CPU/memory limits per pod | Resource governance |

Apply it:

```bash
kubectl apply -f /tmp/cnpg-cluster.yaml
```

Expected output (yours will differ):
```
cluster.postgresql.cnpg.io/pg-lab created
```

Watch the cluster come up:

```bash
kubectl get pods -n databases -w
```

Expected output (yours will differ):
```
NAME       READY   STATUS    RESTARTS   AGE
pg-lab-1   0/1     Pending   0          3s
pg-lab-1   0/1     Init:0/1  0          5s
pg-lab-1   1/1     Running   0          25s
pg-lab-2   0/1     Pending   0          2s
pg-lab-2   0/1     Init:0/1  0          4s
pg-lab-2   1/1     Running   0          30s
pg-lab-3   0/1     Pending   0          2s
pg-lab-3   0/1     Init:0/1  0          4s
pg-lab-3   1/1     Running   0          28s
```

Press `Ctrl+C` when all three are Running.

Notice the ordered startup: `pg-lab-1` (primary) starts first, then `pg-lab-2` and `pg-lab-3` (standbys) are created from a `pg_basebackup` of the primary.

---

## Step 7: Inspect the Cluster

Use the cnpg plugin to see the cluster status:

```bash
kubectl cnpg status pg-lab -n databases
```

Expected output (yours will differ):
```
Cluster Summary
Name:               pg-lab
Namespace:          databases
PostgreSQL Image:   ghcr.io/cloudnative-pg/postgresql:16
Primary instance:   pg-lab-1
Status:             Cluster in healthy state
Instances:          3
Ready instances:    3

Instances status
Name       Database Size  Current LSN  Replication role  Status  QoS
----       -------------  -----------  ----------------  ------  ---
pg-lab-1   29 MB          0/5000060    Primary           OK      BestEffort
pg-lab-2   29 MB          0/5000060    Standby (async)   OK      BestEffort
pg-lab-3   29 MB          0/5000060    Standby (async)   OK      BestEffort
```

This is exactly the information a DBA wants to see: which node is primary, replication status, LSN positions, and database size.

Check the Services that CloudNativePG created automatically:

```bash
kubectl get svc -n databases
```

Expected output (yours will differ):
```
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
pg-lab-r     ClusterIP   10.96.100.1     <none>        5432/TCP   2m
pg-lab-ro    ClusterIP   10.96.100.2     <none>        5432/TCP   2m
pg-lab-rw    ClusterIP   10.96.100.3     <none>        5432/TCP   2m
```

Three services, automatically:

| Service | Routes To | DBA Analogy |
|---------|----------|-------------|
| `pg-lab-rw` | The current primary (read-write) | VIP that always points to the primary |
| `pg-lab-ro` | All standbys (read-only) | Read replica load balancer |
| `pg-lab-r` | All instances (any) | Catch-all for monitoring or tools |

**DBA Analogy:** This is like Patroni's HAProxy configuration or a PgBouncer setup where you have separate pools for read-write and read-only traffic. The operator creates this automatically.

---

## Step 8: Connect to the Cluster

Connect to the primary (read-write service):

**On your Mac, in Terminal:**

```bash
kubectl exec -it pg-lab-1 -n databases -- psql -U postgres -d appdb
```

```sql
CREATE TABLE failover_test (
    id serial PRIMARY KEY,
    node_name text DEFAULT (inet_server_addr()::text),
    written_at timestamptz DEFAULT now()
);

INSERT INTO failover_test (node_name) VALUES ('written-to-primary');
SELECT * FROM failover_test;
```

Expected output (yours will differ):
```
 id |     node_name      |          written_at
----+--------------------+-------------------------------
  1 | written-to-primary | 2026-06-09 16:00:00.123456+00
(1 row)
```

```sql
\q
```

Verify replication is working by checking a standby:

```bash
kubectl exec -it pg-lab-2 -n databases -- psql -U postgres -d appdb -c "SELECT * FROM failover_test;"
```

Expected output (yours will differ):
```
 id |     node_name      |          written_at
----+--------------------+-------------------------------
  1 | written-to-primary | 2026-06-09 16:00:00.123456+00
(1 row)
```

The data replicated to the standby. Streaming replication is working - configured entirely by the operator.

---

## Step 9: Automated Failover - Kill the Primary

This is the moment of truth. Delete the primary pod and watch the operator handle failover automatically.

First, identify which pod is the primary:

```bash
kubectl cnpg status pg-lab -n databases | grep Primary
```

Expected output (yours will differ):
```
Primary instance:   pg-lab-1
```

Open a second terminal window to watch pods. **In Terminal 2:**

```bash
kubectl get pods -n databases -w
```

**Back in Terminal 1**, delete the primary:

```bash
kubectl delete pod pg-lab-1 -n databases
```

**In Terminal 2**, watch the failover:

Expected output (yours will differ):
```
NAME       READY   STATUS        RESTARTS   AGE
pg-lab-1   1/1     Terminating   0          10m
pg-lab-2   1/1     Running       0          9m
pg-lab-3   1/1     Running       0          8m
pg-lab-1   0/1     Terminating   0          10m
pg-lab-1   0/1     Pending       0          1s
pg-lab-1   0/1     Init:0/1      0          2s
pg-lab-1   1/1     Running       0          15s
```

Press `Ctrl+C` in Terminal 2.

**Back in Terminal 1**, check the cluster status:

```bash
kubectl cnpg status pg-lab -n databases
```

Expected output (yours will differ):
```
Cluster Summary
Name:               pg-lab
Namespace:          databases
Primary instance:   pg-lab-2
Status:             Cluster in healthy state
Instances:          3
Ready instances:    3

Instances status
Name       Database Size  Current LSN  Replication role  Status  QoS
----       -------------  -----------  ----------------  ------  ---
pg-lab-2   29 MB          0/6000028    Primary           OK      BestEffort
pg-lab-1   29 MB          0/6000028    Standby (async)   OK      BestEffort
pg-lab-3   29 MB          0/6000028    Standby (async)   OK      BestEffort
```

The primary changed from `pg-lab-1` to `pg-lab-2`. The operator:

1. Detected that `pg-lab-1` was gone
2. Promoted `pg-lab-2` to primary (the standby with the most recent LSN)
3. Reconfigured `pg-lab-3` to replicate from `pg-lab-2`
4. Recreated `pg-lab-1` as a standby of `pg-lab-2`
5. Updated the `pg-lab-rw` Service to route to `pg-lab-2`

All of this happened automatically in seconds. No DBA intervention required.

Verify the data is intact:

```bash
kubectl exec -it pg-lab-2 -n databases -- psql -U postgres -d appdb -c "SELECT * FROM failover_test;"
```

Expected output (yours will differ):
```
 id |     node_name      |          written_at
----+--------------------+-------------------------------
  1 | written-to-primary | 2026-06-09 16:00:00.123456+00
(1 row)
```

Zero data loss. The `pg-lab-rw` service now routes to `pg-lab-2`, so applications using that service name experienced a brief interruption but reconnected automatically to the new primary.

---

## Step 10: Backup Configuration

CloudNativePG integrates with Barman for backups. In production, you would back up to S3, Azure Blob Storage, or Google Cloud Storage. For this lab, we will look at the configuration without actually configuring a cloud provider.

Here is what a production backup configuration looks like in the Cluster manifest:

```yaml
# This is a reference - do NOT apply this in the lab
spec:
  backup:
    barmanObjectStore:
      destinationPath: "s3://my-pg-backups/pg-lab/"
      endpointURL: "https://s3.amazonaws.com"
      s3Credentials:
        accessKeyId:
          name: aws-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-creds
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
        maxParallel: 2
    retentionPolicy: "30d"
```

And a scheduled backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: pg-lab-daily
spec:
  schedule: "0 2 * * *"      # Daily at 2 AM
  backupOwnerReference: self
  cluster:
    name: pg-lab
```

**DBA Analogy:** This is like configuring Barman or pgBackRest with a cron job, but the operator manages the entire lifecycle - takes the backup, monitors completion, enforces retention, and restores from it if needed.

---

## Step 11: Point-in-Time Recovery with CloudNativePG

If you had backups configured, PITR would be a single YAML manifest:

```yaml
# This is a reference - requires backup configuration from Step 10
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-lab-restored
spec:
  instances: 3
  bootstrap:
    recovery:
      source: pg-lab
      recoveryTarget:
        targetTime: "2026-06-09T15:30:00Z"
  externalClusters:
  - name: pg-lab
    barmanObjectStore:
      destinationPath: "s3://my-pg-backups/pg-lab/"
      s3Credentials:
        accessKeyId:
          name: aws-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-creds
          key: SECRET_ACCESS_KEY
```

**DBA Analogy:** This is like running `pg_restore` with `recovery_target_time` in `recovery.conf`, but the operator handles everything - downloads the base backup from S3, replays WAL files up to the target time, starts the cluster, and sets up replication.

---

## Step 12: Connection Pooling with Built-in PgBouncer

CloudNativePG can deploy PgBouncer as a sidecar or standalone pooler:

**On your Mac, in Terminal:**

```bash
vi /tmp/cnpg-pooler.yaml
```

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: pg-lab-pooler
  namespace: databases
spec:
  cluster:
    name: pg-lab
  instances: 2
  type: rw
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "1000"
      default_pool_size: "25"
```

```bash
kubectl apply -f /tmp/cnpg-pooler.yaml
```

Expected output (yours will differ):
```
pooler.postgresql.cnpg.io/pg-lab-pooler created
```

```bash
kubectl get pods -n databases | grep pooler
```

Expected output (yours will differ):
```
pg-lab-pooler-5b7c8d9f-abc12   1/1     Running   0          15s
pg-lab-pooler-5b7c8d9f-def34   1/1     Running   0          15s
```

Two PgBouncer instances running in transaction pooling mode. The operator created a Service for the pooler automatically:

```bash
kubectl get svc -n databases | grep pooler
```

Expected output (yours will differ):
```
pg-lab-pooler   ClusterIP   10.96.100.4   <none>   5432/TCP   30s
```

Applications connect to `pg-lab-pooler:5432` instead of directly to PostgreSQL. The pooler handles connection management, and if the primary fails over, the pooler automatically reconnects to the new primary.

---

## Step 13: Monitoring Integration

CloudNativePG exposes Prometheus metrics on each pod. Check the metrics endpoint:

```bash
kubectl exec -it pg-lab-2 -n databases -- curl -s http://localhost:9187/metrics | head -20
```

Expected output (yours will differ):
```
# HELP cnpg_collector_up 1 if the collector was able to connect to PostgreSQL
# TYPE cnpg_collector_up gauge
cnpg_collector_up 1
# HELP cnpg_pg_database_size_bytes Database size in bytes
# TYPE cnpg_pg_database_size_bytes gauge
cnpg_pg_database_size_bytes{datname="appdb"} 2.9097984e+07
cnpg_pg_database_size_bytes{datname="postgres"} 7.537152e+06
...
```

In production, you would connect Prometheus and Grafana to these metrics. The CloudNativePG project provides pre-built Grafana dashboards.

---

## Step 14: Comparing PostgreSQL Operators

CloudNativePG is not the only option. Here is a brief comparison:

| Feature | CloudNativePG | CrunchyData PGO | Zalando Postgres Operator |
|---------|--------------|-----------------|--------------------------|
| License | Apache 2.0 | Apache 2.0 | MIT |
| CNCF Status | Sandbox | None | None |
| HA Method | Built-in (no Patroni) | Patroni | Patroni |
| Backup Tool | Barman | pgBackRest | WAL-E/WAL-G |
| Connection Pooler | PgBouncer (built-in) | PgBouncer | External |
| Declarative Config | postgresql.parameters | postgresql.parameters | postgresql.parameters |
| PITR | Yes | Yes | Yes |
| Minor Version Upgrades | Rolling update | Rolling update | Rolling update |
| Major Version Upgrades | In-place (pg_upgrade) | pgUpgrade CRD | Limited |
| Community Activity | Very active | Active | Active |

For this lab series, we use CloudNativePG because:
- It has the simplest setup
- It does not require Patroni (less moving parts)
- It is a CNCF project (aligned with K8s ecosystem)
- It has excellent documentation

---

## Step 15: When to Use K8s PostgreSQL vs RDS

This is the most important decision for a DBA evaluating Kubernetes:

| Factor | K8s PostgreSQL | RDS/Cloud Managed |
|--------|---------------|-------------------|
| **Control** | Full control over config, extensions, versions | Limited to what the cloud provider supports |
| **Cost** | Lower compute cost, higher operational cost | Higher compute cost, lower operational cost |
| **Extensions** | Install anything (PostGIS, TimescaleDB, custom) | Limited extension list |
| **Upgrades** | You manage (operator helps) | Cloud provider handles |
| **Multi-cloud** | Runs anywhere K8s runs | Locked to one cloud provider |
| **Team skills** | Requires K8s expertise | Requires only DBA skills |
| **Recovery time** | Depends on your setup (can be faster) | Cloud provider SLA (typically minutes) |
| **Compliance** | Full audit control | Depends on cloud certifications |

**Use K8s PostgreSQL when:**
- You need extensions not available on managed services
- You run multi-cloud or hybrid environments
- You need fine-grained control over configuration
- Your team already knows Kubernetes
- Cost optimization is critical at scale

**Use RDS/Cloud Managed when:**
- You have a small team without K8s expertise
- You want someone else to handle backups, patching, and HA
- You are on a single cloud provider
- Time to market matters more than control
- The managed service supports all your required extensions

---

## Step 16: Clean Up

To preserve minikube resources, scale down the cluster:

```bash
kubectl delete pooler pg-lab-pooler -n databases
kubectl delete cluster pg-lab -n databases
```

Expected output (yours will differ):
```
pooler.postgresql.cnpg.io "pg-lab-pooler" deleted
cluster.postgresql.cnpg.io "pg-lab" deleted
```

Wait for pods to terminate:

```bash
kubectl get pods -n databases -w
```

When all pods are gone, press `Ctrl+C`.

If you are done with all labs, you can stop minikube:

```bash
minikube stop
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Kubernetes Operator | Software that encodes operational knowledge - automates DBA tasks like failover, backup, and scaling |
| Custom Resource Definition (CRD) | Extends Kubernetes with new resource types - `Cluster` instead of raw `StatefulSet` |
| CloudNativePG | The leading open-source PostgreSQL operator for Kubernetes |
| Cluster manifest | One YAML file creates a complete HA PostgreSQL cluster with replication |
| Automated failover | Operator detects primary failure and promotes a standby in seconds - zero DBA intervention |
| Services (rw/ro/r) | Automatic routing to primary (writes) and standbys (reads) |
| Backup/PITR | Declarative backup configuration with Barman to object storage |
| Connection pooling | Built-in PgBouncer managed by the operator |
| Monitoring | Prometheus metrics exported automatically from every pod |
| Operator comparison | CloudNativePG, CrunchyData PGO, and Zalando are the three major options |
| K8s vs RDS | Choose based on control needs, team skills, and extension requirements |
