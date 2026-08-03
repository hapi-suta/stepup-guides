# BUILD 03: StatefulSets and Persistent Storage

**Module:** Kubernetes for Databases
**Prerequisites:** BUILD 02 (Kubernetes Fundamentals) completed, minikube running
**Time:** 60-75 minutes

---

## What You Will Build

By the end of this guide, you will understand why Deployments are wrong for databases, deploy a PostgreSQL StatefulSet with persistent storage, scale it, and prove that data survives pod restarts.

---

## Step 1: Why Deployments Do Not Work for Databases

In BUILD 02, you learned that a Deployment creates identical, interchangeable Pods. If one dies, K8s creates a brand new replacement with a new name and new storage.

This is exactly what you want for stateless web servers. It is exactly what you do NOT want for databases.

**DBA Analogy:** Imagine you have a 3-node PostgreSQL cluster: `pg-primary`, `pg-standby-1`, `pg-standby-2`. Now imagine someone deletes `pg-primary` and the system creates a brand new empty server called `pg-random-hash-xyz` with no data. That is what a Deployment does. The new Pod has:

- A random name (no stable identity)
- No data (fresh empty disk)
- No concept of "I was the primary" or "I was standby-1"

Databases need:
- **Stable names** - `pg-0` is always `pg-0`, even after restart
- **Stable storage** - each instance keeps its own data across restarts
- **Ordered startup** - the primary starts first, then standbys
- **Ordered shutdown** - standbys stop first, then the primary

This is exactly what a **StatefulSet** provides.

---

## Step 2: StatefulSets - Named Replicas with Stable Identity

A **StatefulSet** is the Kubernetes resource designed for stateful applications like databases.

**DBA Analogy:**

| Deployment Behavior | StatefulSet Behavior | DBA Perspective |
|---------------------|---------------------|----------------|
| Random pod names (`web-6d4f-abc12`) | Sequential names (`pg-0`, `pg-1`, `pg-2`) | Named replicas like `pg-primary`, `pg-standby-1` |
| Shared or no storage | Each pod gets its own persistent volume | Each instance has its own PGDATA |
| All pods start simultaneously | Pods start in order (0, then 1, then 2) | Primary first, then standbys |
| Random pod replacement | Same pod name reattached to same storage | After restart, `pg-0` reconnects to its data |
| Pods are interchangeable | Each pod has a unique, stable identity | Each replica has a distinct role |

---

## Step 3: Persistent Volumes (PV) and Persistent Volume Claims (PVC)

Before creating a StatefulSet, you need to understand how storage works in Kubernetes.

**DBA Analogy:**

| Kubernetes Concept | DBA Equivalent |
|-------------------|---------------|
| Persistent Volume (PV) | A physical disk or partition (`/dev/sda1`) |
| Persistent Volume Claim (PVC) | A request for disk space - like asking your sysadmin "I need a 100GB SSD for PGDATA" |
| Storage Class | The type of disk - SSD, HDD, network-attached, local (like choosing tablespace storage type) |

The flow works like this:

1. A **Storage Class** defines what type of storage is available (SSD, HDD, etc.)
2. A **PVC** is a request: "I need 10Gi of SSD storage"
3. Kubernetes finds or creates a **PV** that satisfies the claim
4. The PV is mounted into the Pod

In minikube, a default Storage Class is already configured. Check it:

**On your Mac, in Terminal:**

```bash
kubectl get storageclass
```

Expected output (yours will differ):
```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           false                  30m
```

The `standard` Storage Class uses minikube's local disk. Notice `RECLAIMPOLICY: Delete` - this means when a PVC is deleted, the underlying data is also deleted. We will discuss this in the SURVIVE exercise.

---

## Step 4: Create a PostgreSQL StatefulSet

Ensure you still have the `databases` namespace and ConfigMap/Secret from BUILD 02. If not, recreate them:

```bash
kubectl get namespace databases 2>/dev/null || kubectl create namespace databases
kubectl get configmap pg-config -n databases 2>/dev/null || kubectl apply -f /tmp/pg-configmap.yaml
kubectl get secret pg-credentials -n databases 2>/dev/null || kubectl create secret generic pg-credentials --from-literal=POSTGRES_PASSWORD=dbalab123 --from-literal=REPLICATION_PASSWORD=replpass123 -n databases
```

Now create the StatefulSet manifest:

**On your Mac, in Terminal:**

```bash
vi /tmp/pg-statefulset.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pg-headless
  namespace: databases
  labels:
    app: postgresql
spec:
  ports:
  - port: 5432
    name: postgres
  clusterIP: None
  selector:
    app: postgresql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg
  namespace: databases
spec:
  serviceName: pg-headless
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pg-credentials
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
  volumeClaimTemplates:
  - metadata:
      name: pg-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Let's break down the new parts:

| Field | What It Does | DBA Analogy |
|-------|-------------|-------------|
| `serviceName: pg-headless` | Links to a headless Service for DNS | Each pod gets its own DNS name |
| `clusterIP: None` | Makes this a headless Service | No single VIP - each pod is individually addressable |
| `volumeClaimTemplates` | Each pod automatically gets its own PVC | Each instance gets its own dedicated PGDATA disk |
| `accessModes: ReadWriteOnce` | Only one pod can mount this volume at a time | A PGDATA directory should only be owned by one instance |
| `storage: 1Gi` | Request 1 gigabyte of storage | Size of the PGDATA partition |

The **headless Service** (`clusterIP: None`) is critical. Instead of one shared IP, each pod gets its own DNS entry:
- `pg-0.pg-headless.databases.svc.cluster.local`
- `pg-1.pg-headless.databases.svc.cluster.local`

**DBA Analogy:** This is like having individual DNS records for each replica: `pg-primary.db.internal`, `pg-standby-1.db.internal`. You can connect to a specific replica by name, not just "whatever is behind the load balancer."

Apply the manifest:

```bash
kubectl apply -f /tmp/pg-statefulset.yaml
```

Expected output (yours will differ):
```
service/pg-headless created
statefulset.apps/pg created
```

Watch the pod come up:

```bash
kubectl get pods -n databases -w
```

Expected output (yours will differ):
```
NAME   READY   STATUS    RESTARTS   AGE
pg-0   0/1     Pending   0          2s
pg-0   0/1     ContainerCreating   0   3s
pg-0   1/1     Running   0          8s
```

Press `Ctrl+C` to stop watching.

Notice the pod name is `pg-0` - not `pg-random-hash`. This is a stable, predictable name.

Check the PVC that was automatically created:

```bash
kubectl get pvc -n databases
```

Expected output (yours will differ):
```
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pg-data-pg-0   Bound    pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   1Gi        RWO            standard       30s
```

The PVC is named `pg-data-pg-0` - the template name (`pg-data`) combined with the pod name (`pg-0`). Each pod gets its own PVC.

---

## Step 5: Verify Data Persistence Across Pod Restarts

This is the most important test for a DBA. Does data survive when the pod is deleted and recreated?

**On your Mac, in Terminal:**

Connect to the PostgreSQL pod:

```bash
kubectl exec -it pg-0 -n databases -- psql -U postgres
```

Create test data:

```sql
CREATE DATABASE persistdb;
\c persistdb
CREATE TABLE survive_test (id serial PRIMARY KEY, message text, created_at timestamptz DEFAULT now());
INSERT INTO survive_test (message) VALUES ('I must survive pod deletion');
INSERT INTO survive_test (message) VALUES ('Persistent storage is critical for DBAs');
INSERT INTO survive_test (message) VALUES ('This data lives on a PVC, not in the container');
SELECT * FROM survive_test;
```

Expected output (yours will differ):
```
 id |                     message                      |          created_at
----+--------------------------------------------------+-------------------------------
  1 | I must survive pod deletion                      | 2026-06-09 15:30:00.123456+00
  2 | Persistent storage is critical for DBAs          | 2026-06-09 15:30:00.234567+00
  3 | This data lives on a PVC, not in the container   | 2026-06-09 15:30:00.345678+00
(3 rows)
```

```sql
\q
```

Now delete the pod - simulate a crash:

```bash
kubectl delete pod pg-0 -n databases
```

Watch the StatefulSet recreate it:

```bash
kubectl get pods -n databases -w
```

Expected output (yours will differ):
```
NAME   READY   STATUS              RESTARTS   AGE
pg-0   0/1     ContainerCreating   0          2s
pg-0   1/1     Running             0          6s
```

Press `Ctrl+C` to stop watching.

The new `pg-0` pod automatically reattached to the **same PVC** (`pg-data-pg-0`). Verify the data is still there:

```bash
kubectl exec -it pg-0 -n databases -- psql -U postgres -d persistdb -c "SELECT * FROM survive_test;"
```

Expected output (yours will differ):
```
 id |                     message                      |          created_at
----+--------------------------------------------------+-------------------------------
  1 | I must survive pod deletion                      | 2026-06-09 15:30:00.123456+00
  2 | Persistent storage is critical for DBAs          | 2026-06-09 15:30:00.234567+00
  3 | This data lives on a PVC, not in the container   | 2026-06-09 15:30:00.345678+00
(3 rows)
```

All three rows survived. The pod was deleted and recreated, but the data on the PVC was untouched. This is exactly how it should work - the container is disposable, the storage is not.

---

## Step 6: Scale the StatefulSet - Add Replicas

Scale from 1 to 3 pods:

**On your Mac, in Terminal:**

```bash
kubectl scale statefulset pg -n databases --replicas=3
```

Expected output (yours will differ):
```
statefulset.apps/pg scaled
```

Watch the pods come up **in order**:

```bash
kubectl get pods -n databases -w
```

Expected output (yours will differ):
```
NAME   READY   STATUS    RESTARTS   AGE
pg-0   1/1     Running   0          5m
pg-1   0/1     Pending   0          2s
pg-1   0/1     ContainerCreating   0   3s
pg-1   1/1     Running   0          8s
pg-2   0/1     Pending   0          1s
pg-2   0/1     ContainerCreating   0   2s
pg-2   1/1     Running   0          7s
```

Press `Ctrl+C` to stop watching.

Notice the ordering: `pg-1` starts only after `pg-0` is fully Running. `pg-2` starts only after `pg-1` is Running. This is StatefulSet's ordered deployment guarantee.

**DBA Analogy:** This is like saying "start the primary first, wait until it is accepting connections, then start standby-1, then standby-2." Exactly the startup order a DBA would enforce.

Check the PVCs:

```bash
kubectl get pvc -n databases
```

Expected output (yours will differ):
```
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pg-data-pg-0   Bound    pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   1Gi        RWO            standard       6m
pg-data-pg-1   Bound    pvc-b2c3d4e5-f6a7-8901-bcde-f12345678901   1Gi        RWO            standard       30s
pg-data-pg-2   Bound    pvc-c3d4e5f6-a7b8-9012-cdef-012345678901   1Gi        RWO            standard       20s
```

Each pod has its own PVC. `pg-0` has its original data. `pg-1` and `pg-2` have fresh, empty PostgreSQL instances.

**Important note:** Scaling a StatefulSet adds independent PostgreSQL instances - it does NOT automatically set up streaming replication. Each new pod is its own standalone primary. To set up replication, you would need additional configuration (init scripts, Patroni, or an operator like CloudNativePG which we cover in BUILD 04).

---

## Step 7: Headless Service DNS - Addressing Individual Pods

Each pod in a StatefulSet gets a predictable DNS name. Let's verify this from inside the cluster.

**On your Mac, in Terminal:**

```bash
kubectl exec -it pg-0 -n databases -- bash
```

Inside the `pg-0` pod, test DNS resolution:

```bash
apt-get update > /dev/null 2>&1 && apt-get install -y dnsutils > /dev/null 2>&1
```

```bash
nslookup pg-0.pg-headless.databases.svc.cluster.local
```

Expected output (yours will differ):
```
Server:         10.96.0.10
Address:        10.96.0.10#53

Name:   pg-0.pg-headless.databases.svc.cluster.local
Address: 10.244.0.15
```

```bash
nslookup pg-1.pg-headless.databases.svc.cluster.local
```

Expected output (yours will differ):
```
Server:         10.96.0.10
Address:        10.96.0.10#53

Name:   pg-1.pg-headless.databases.svc.cluster.local
Address: 10.244.0.16
```

Each pod has its own DNS entry. The naming pattern is:

```
<pod-name>.<headless-service>.<namespace>.svc.cluster.local
```

**DBA Analogy:** This is like having DNS records in `/etc/hosts` for each replica:
- `pg-0` = primary (address: 10.244.0.15)
- `pg-1` = standby-1 (address: 10.244.0.16)
- `pg-2` = standby-2 (address: 10.244.0.17)

If you were setting up streaming replication, `pg-1` would use `primary_conninfo = 'host=pg-0.pg-headless.databases.svc.cluster.local'` - a stable DNS name that does not change even if `pg-0` restarts.

Exit the pod:

```bash
exit
```

---

## Step 8: Pod Identity and Ordering

StatefulSet pods have guarantees that matter deeply for databases:

| Guarantee | What It Means | DBA Impact |
|-----------|--------------|-----------|
| **Stable name** | `pg-0` is always `pg-0` | You can always reference the primary by name |
| **Stable storage** | `pg-0` always mounts `pg-data-pg-0` | PGDATA survives restarts |
| **Ordered creation** | `pg-0` before `pg-1` before `pg-2` | Primary starts before standbys |
| **Ordered deletion** | `pg-2` before `pg-1` before `pg-0` | Standbys stop before primary |
| **Stable DNS** | `pg-0.pg-headless...` always resolves to `pg-0` | Connection strings don't change |

Scale down to see ordered deletion:

```bash
kubectl scale statefulset pg -n databases --replicas=1
```

```bash
kubectl get pods -n databases -w
```

Expected output (yours will differ):
```
NAME   READY   STATUS        RESTARTS   AGE
pg-0   1/1     Running       0          10m
pg-1   1/1     Running       0          5m
pg-2   1/1     Terminating   0          5m
pg-2   0/1     Terminating   0          5m
pg-1   1/1     Terminating   0          5m
pg-1   0/1     Terminating   0          5m
```

Press `Ctrl+C` to stop watching.

`pg-2` is terminated first, then `pg-1`. `pg-0` remains. Reverse order - highest ordinal deleted first.

**Critical detail:** When you scale down, the PVCs for `pg-1` and `pg-2` are **NOT deleted**. They are retained so that if you scale back up, the pods reattach to their existing data.

Verify:

```bash
kubectl get pvc -n databases
```

Expected output (yours will differ):
```
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pg-data-pg-0   Bound    pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   1Gi        RWO            standard       12m
pg-data-pg-1   Bound    pvc-b2c3d4e5-f6a7-8901-bcde-f12345678901   1Gi        RWO            standard       6m
pg-data-pg-2   Bound    pvc-c3d4e5f6-a7b8-9012-cdef-012345678901   1Gi        RWO            standard       6m
```

All three PVCs still exist even though only `pg-0` is running.

---

## Step 9: Resource Limits - Preventing Noisy Neighbors

In the StatefulSet manifest, you set resource requests and limits:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**DBA Analogy:**

| K8s Resource Concept | DBA Equivalent |
|---------------------|---------------|
| `requests.memory: 256Mi` | Guaranteed minimum - like setting `shared_buffers`. This memory is reserved. |
| `limits.memory: 512Mi` | Maximum allowed - like the OS cgroup limit. If PostgreSQL tries to use more, the pod is OOMKilled (killed by the Out of Memory killer). |
| `requests.cpu: 250m` | 250 millicores = 0.25 CPU guaranteed | Like setting `cpu_weight` in a resource group |
| `limits.cpu: 500m` | 500 millicores = 0.5 CPU maximum | Like a hard CPU cap |

If the PostgreSQL process inside the pod tries to use more than 512Mi of memory, Kubernetes will kill the pod with an `OOMKilled` status. This is the most common cause of `CrashLoopBackOff` for database pods - we will debug this in the SURVIVE exercises.

Check the current resource usage:

```bash
kubectl top pod -n databases
```

If `metrics-server` is not enabled, run:

```bash
minikube addons enable metrics-server
```

Then wait 60 seconds and retry:

```bash
kubectl top pod -n databases
```

Expected output (yours will differ):
```
NAME   CPU(cores)   MEMORY(bytes)
pg-0   3m           28Mi
```

PostgreSQL at idle uses very little resources. Under load, you would see these numbers increase toward the limits.

---

## Step 10: Storage Classes - Choosing Your Disk Type

In production, you would have multiple Storage Classes for different performance tiers.

**DBA Analogy:**

| Storage Class | DBA Equivalent |
|--------------|---------------|
| `fast-ssd` | NVMe/SSD for PGDATA - low latency reads and writes |
| `standard-hdd` | HDD for WAL archives and backups - high capacity, lower cost |
| `replicated-ssd` | SSD with replication across availability zones - for the most critical data |

In minikube, you only have `standard`. In production (AWS EKS, for example), you would see:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Retain        # CRITICAL: Keep the data when PVC is deleted
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true   # Allow resizing without downtime
```

The `reclaimPolicy` is critical for databases:
- `Delete` (default) - when the PVC is deleted, the underlying data is also deleted. Dangerous for production.
- `Retain` - when the PVC is deleted, the data is preserved. A DBA must manually clean it up. Safe for production.

---

## Step 11: Clean Up

Scale back to 1 replica (keep it for BUILD 04):

```bash
kubectl scale statefulset pg -n databases --replicas=1
```

Delete the unused PVCs from scaled-down pods:

```bash
kubectl delete pvc pg-data-pg-1 pg-data-pg-2 -n databases
```

Do NOT delete the StatefulSet, `pg-0`, or the `databases` namespace - you will build on these in BUILD 04.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Deployments vs StatefulSets | Deployments are for stateless apps. StatefulSets are for databases - they provide stable names, stable storage, and ordered operations. |
| Persistent Volume (PV) | A piece of storage in the cluster - like a physical disk |
| Persistent Volume Claim (PVC) | A request for storage - like asking for a 100GB SSD for PGDATA |
| Storage Classes | Different types of storage (SSD, HDD) - like choosing tablespace storage |
| Headless Services | Give each pod its own DNS name - essential for connecting to specific replicas |
| Pod identity | `pg-0` is always `pg-0`, always gets the same PVC, always starts first |
| Ordered operations | Pods start in order (0, 1, 2) and stop in reverse (2, 1, 0) |
| Data persistence | Data on a PVC survives pod deletion and recreation |
| Resource limits | Prevent pods from consuming too much memory/CPU - OOMKilled is the K8s equivalent of the Linux OOM killer |
| Reclaim policies | `Retain` for production databases - never let K8s auto-delete your data |
