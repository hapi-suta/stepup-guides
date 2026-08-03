# USE: Kubernetes for Databases - Exercises

**Module:** Kubernetes for Databases
**Prerequisites:** All 4 BUILD guides completed
**Time:** 90-120 minutes total

Each exercise builds on the previous one. Complete them in order.

---

## Exercise 1: Containerize PostgreSQL

**Objective:** Write a Dockerfile, build a custom PostgreSQL image, and run it with persistent storage.

### Requirements

1. Create a directory `/tmp/pg-exercise/`
2. Write a `Dockerfile` that:
   - Uses `postgres:16` as the base image
   - Installs `pg_stat_statements` and `pg_trgm` extensions
   - Copies a custom `postgresql.conf` that sets:
     - `shared_buffers = 256MB`
     - `max_connections = 150`
     - `log_statement = 'all'`
     - `shared_preload_libraries = 'pg_stat_statements'`
   - Copies an `init.sql` that:
     - Creates a database called `exercisedb`
     - Creates a table `exercise.logs` with columns: `id serial`, `event text`, `created_at timestamptz default now()`
     - Inserts 5 sample rows
3. Build the image with the tag `pg16-exercise:v1`
4. Create a Docker volume named `exercise-data`
5. Run the container with:
   - Name: `pg-exercise`
   - Port mapping: 5433:5432 (use 5433 on host to avoid conflicts)
   - The volume mounted at `/var/lib/postgresql/data`
   - Password: `exercise123`

### Verification

Run these commands and confirm the output:

```bash
psql -h localhost -U postgres -p 5433 -d exercisedb -c "SELECT count(*) FROM exercise.logs;"
# Expected: count = 5

psql -h localhost -U postgres -p 5433 -d exercisedb -c "SHOW shared_buffers;"
# Expected: 256MB

psql -h localhost -U postgres -p 5433 -d exercisedb -c "SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';"
# Expected: pg_stat_statements should appear
```

### Clean Up

```bash
docker stop pg-exercise && docker rm pg-exercise
# Keep the volume for now
```

---

## Exercise 2: Deploy on Kubernetes

**Objective:** Write YAML manifests for a Pod, Service, and PVC, then deploy PostgreSQL to minikube.

### Requirements

Start minikube if it is not running:

```bash
minikube start
```

1. Create a namespace called `exercise`
2. Create a Secret called `pg-exercise-secret` in the `exercise` namespace with:
   - Key `POSTGRES_PASSWORD`, value `exercise123`
3. Write a YAML file `/tmp/pg-exercise-k8s.yaml` that defines THREE resources (separated by `---`):
   - A **PersistentVolumeClaim** named `pg-exercise-pvc`:
     - 1Gi storage
     - `ReadWriteOnce` access mode
   - A **Pod** named `pg-exercise`:
     - Image: `postgres:16`
     - Port: 5432
     - Environment variable `POSTGRES_PASSWORD` from the Secret
     - Environment variable `PGDATA` set to `/var/lib/postgresql/data/pgdata`
     - Volume mount: the PVC at `/var/lib/postgresql/data`
     - Resource requests: 128Mi memory, 100m CPU
     - Resource limits: 256Mi memory, 250m CPU
   - A **Service** named `pg-exercise-svc`:
     - Type: `NodePort`
     - Port: 5432
     - NodePort: 30433
     - Selector matching the Pod labels
4. Apply the YAML file

### Verification

```bash
kubectl get pods,pvc,svc -n exercise
# All should show Running/Bound/active

kubectl exec -it pg-exercise -n exercise -- psql -U postgres -c "SELECT 'Exercise 2 complete' AS status;"
# Expected: Exercise 2 complete

psql -h $(minikube ip) -U postgres -p 30433 -c "SELECT version();"
# Expected: PostgreSQL 16.x
```

### Clean Up

Do NOT delete the `exercise` namespace yet - Exercise 3 uses it.

```bash
kubectl delete pod pg-exercise -n exercise
kubectl delete svc pg-exercise-svc -n exercise
# Keep the PVC
```

---

## Exercise 3: StatefulSet Cluster

**Objective:** Deploy a 3-node PostgreSQL StatefulSet with persistent storage and headless Service.

### Requirements

1. Write a YAML file `/tmp/pg-statefulset-exercise.yaml` that defines:
   - A **headless Service** named `pg-sts-headless`:
     - `clusterIP: None`
     - Port: 5432
     - Selector: `app: pg-sts`
   - A **StatefulSet** named `pg-sts`:
     - 3 replicas
     - Service name: `pg-sts-headless`
     - Image: `postgres:16`
     - Environment variable `POSTGRES_PASSWORD` set to `exercise123` (for simplicity, hardcode it)
     - Environment variable `PGDATA` set to `/var/lib/postgresql/data/pgdata`
     - Volume claim template: 1Gi per pod
     - Resource limits: 256Mi memory, 250m CPU

2. Apply the YAML file to the `exercise` namespace

### Verification

```bash
kubectl get pods -n exercise
# Expected: pg-sts-0, pg-sts-1, pg-sts-2 all Running

kubectl get pvc -n exercise
# Expected: 3 PVCs, one per pod

# Verify each pod is an independent PostgreSQL instance
kubectl exec -it pg-sts-0 -n exercise -- psql -U postgres -c "CREATE DATABASE fromnode0;"
kubectl exec -it pg-sts-1 -n exercise -- psql -U postgres -c "\l" | grep fromnode0
# Expected: fromnode0 should NOT appear on pg-sts-1 (no replication configured)

# Verify DNS resolution from inside a pod
kubectl exec -it pg-sts-0 -n exercise -- bash -c "apt-get update > /dev/null 2>&1 && apt-get install -y dnsutils > /dev/null 2>&1 && nslookup pg-sts-1.pg-sts-headless.exercise.svc.cluster.local"
# Expected: resolves to an IP address
```

### Clean Up

```bash
kubectl delete statefulset pg-sts -n exercise
kubectl delete service pg-sts-headless -n exercise
kubectl delete pvc -l app=pg-sts -n exercise
```

---

## Exercise 4: CloudNativePG Cluster

**Objective:** Deploy a production-grade PostgreSQL cluster using CloudNativePG with custom configuration.

### Requirements

Ensure CloudNativePG operator is installed (from BUILD 04). If not:

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.1.yaml
kubectl wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=120s
```

1. Create a Secret in the `exercise` namespace:
   - Name: `cnpg-exercise-creds`
   - Keys: `username=appuser`, `password=exercise123`

2. Write a YAML file `/tmp/cnpg-exercise.yaml` that defines a CloudNativePG `Cluster`:
   - Name: `pg-exercise-cluster`
   - Namespace: `exercise`
   - 3 instances
   - Image: `ghcr.io/cloudnative-pg/postgresql:16`
   - PostgreSQL parameters:
     - `max_connections: "100"`
     - `shared_buffers: "128MB"`
     - `log_statement: "ddl"`
   - Bootstrap: initdb with database `exercisedb`, owner `appuser`
   - Storage: 1Gi
   - Resource limits: 512Mi memory, 500m CPU

3. Apply the YAML file
4. Wait for all 3 instances to be Running

### Verification

```bash
kubectl cnpg status pg-exercise-cluster -n exercise
# Expected: 3 instances, 1 primary + 2 standbys, Cluster in healthy state

kubectl get svc -n exercise | grep pg-exercise-cluster
# Expected: -rw, -ro, -r services

# Connect to primary and create test data
kubectl exec -it pg-exercise-cluster-1 -n exercise -- psql -U appuser -d exercisedb -c "CREATE TABLE test (id serial, val text); INSERT INTO test (val) VALUES ('from primary');"

# Verify replication to a standby
kubectl exec -it pg-exercise-cluster-2 -n exercise -- psql -U appuser -d exercisedb -c "SELECT * FROM test;"
# Expected: row from primary appears on standby
```

### Clean Up

Do NOT delete yet - Exercise 5 uses this cluster.

---

## Exercise 5: Failover Test

**Objective:** Kill the primary pod and verify automatic failover with zero data loss.

### Requirements

Using the cluster from Exercise 4:

1. Identify the current primary:
   ```bash
   kubectl cnpg status pg-exercise-cluster -n exercise | grep "Primary instance"
   ```

2. Insert a row with a known value:
   ```bash
   kubectl exec -it <primary-pod> -n exercise -- psql -U appuser -d exercisedb -c "INSERT INTO test (val) VALUES ('pre-failover-marker');"
   ```

3. Open a second terminal and watch pods:
   ```bash
   kubectl get pods -n exercise -w
   ```

4. Delete the primary pod:
   ```bash
   kubectl delete pod <primary-pod> -n exercise
   ```

5. Wait for failover to complete (watch the second terminal)

6. Verify:
   - A new primary was elected
   - The `pre-failover-marker` row exists on the new primary
   - All 3 instances are eventually Running and healthy
   - The `pg-exercise-cluster-rw` service points to the new primary

### Verification

```bash
kubectl cnpg status pg-exercise-cluster -n exercise
# Expected: Different primary than before, all 3 instances healthy

# Find the new primary
NEW_PRIMARY=$(kubectl cnpg status pg-exercise-cluster -n exercise | grep "Primary instance" | awk '{print $NF}')
kubectl exec -it $NEW_PRIMARY -n exercise -- psql -U appuser -d exercisedb -c "SELECT * FROM test WHERE val = 'pre-failover-marker';"
# Expected: 1 row returned - zero data loss
```

### Final Clean Up

```bash
kubectl delete cluster pg-exercise-cluster -n exercise
kubectl delete namespace exercise
```

If you are completely done with all modules:

```bash
minikube stop
minikube delete
```

---

## Scoring

| Exercise | Points | Criteria |
|----------|--------|----------|
| 1. Containerize PostgreSQL | 20 | Dockerfile builds, volume persists data, config applied |
| 2. Deploy on Kubernetes | 20 | Pod, Service, PVC all working, connectable via NodePort |
| 3. StatefulSet Cluster | 20 | 3 pods with stable names, individual PVCs, DNS resolution |
| 4. CloudNativePG Cluster | 20 | 3-instance cluster with replication working |
| 5. Failover Test | 20 | Automatic failover, zero data loss, cluster recovers |
| **Total** | **100** | |
