# SURVIVE 01: The Lost Volume

**Scenario:** A PVC is accidentally deleted and PostgreSQL data is gone.

**Module:** Kubernetes for Databases
**Difficulty:** Medium
**Time:** 30-45 minutes

---

## The Story

It is 3 AM. You get paged. The `pg-production` cluster in namespace `production` is down. A junior developer ran `kubectl delete pvc --all -n production` thinking they were cleaning up a test namespace. The PVC for the primary was deleted. PostgreSQL has no data directory.

Your mission: understand what happened, recover the service, and implement safeguards so this never happens again.

---

## Part 1: The Injection

Set up the broken environment.

**On your Mac, in Terminal:**

Ensure minikube is running:

```bash
minikube start
```

Create the scenario:

```bash
vi /tmp/survive-pv-setup.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-creds
  namespace: production
type: Opaque
stringData:
  POSTGRES_PASSWORD: survive123
---
apiVersion: v1
kind: Service
metadata:
  name: pg-headless
  namespace: production
spec:
  clusterIP: None
  ports:
  - port: 5432
  selector:
    app: pg-production
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg-production
  namespace: production
spec:
  serviceName: pg-headless
  replicas: 1
  selector:
    matchLabels:
      app: pg-production
  template:
    metadata:
      labels:
        app: pg-production
    spec:
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pg-creds
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
        resources:
          limits:
            memory: "256Mi"
            cpu: "250m"
  volumeClaimTemplates:
  - metadata:
      name: pg-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Apply and wait for the pod:

```bash
kubectl apply -f /tmp/survive-pv-setup.yaml
kubectl wait --for=condition=Ready pod/pg-production-0 -n production --timeout=120s
```

Insert critical data:

```bash
kubectl exec -it pg-production-0 -n production -- psql -U postgres -c "
CREATE DATABASE critical_app;
"
kubectl exec -it pg-production-0 -n production -- psql -U postgres -d critical_app -c "
CREATE TABLE customers (id serial PRIMARY KEY, name text, email text);
INSERT INTO customers (name, email) VALUES
  ('Alice', 'alice@example.com'),
  ('Bob', 'bob@example.com'),
  ('Charlie', 'charlie@example.com');
"
```

Now simulate the disaster - delete the PVC:

```bash
kubectl delete statefulset pg-production -n production --cascade=foreground
kubectl delete pvc pg-data-pg-production-0 -n production
```

The data is gone. The pod is gone. The PVC is gone.

---

## Part 2: The Runbook

Now investigate and recover. Work through these steps:

### Step 1: Assess the Damage

Answer these questions:
1. What resources still exist in the `production` namespace?
2. Is the Persistent Volume (PV) still available, or was it deleted too?
3. What was the reclaim policy on the Storage Class?

**Hints:**
```bash
kubectl get all -n production
kubectl get pvc -n production
kubectl get pv
kubectl get storageclass
```

### Step 2: Understand Reclaim Policies

The Storage Class `standard` in minikube uses `reclaimPolicy: Delete`. This means when the PVC was deleted, the underlying PV and its data were also deleted.

Research and answer:
- What are the three reclaim policies: `Delete`, `Retain`, `Recycle`?
- Which policy should a DBA ALWAYS use for production databases?
- How do you change a PV's reclaim policy after creation?

### Step 3: Recreate the Database (Recovery)

Since the data is gone (no backup configured - that is the real lesson), recreate the StatefulSet:

```bash
kubectl apply -f /tmp/survive-pv-setup.yaml
kubectl wait --for=condition=Ready pod/pg-production-0 -n production --timeout=120s
```

Verify it is running but empty:

```bash
kubectl exec -it pg-production-0 -n production -- psql -U postgres -c "\l"
```

The `critical_app` database is gone. In a real scenario, you would restore from your latest backup. Since we have no backup, the data is permanently lost.

### Step 4: Implement Safeguards

Now implement three safeguards to prevent this from happening again:

**Safeguard 1: Change the reclaim policy on the PV**

```bash
PV_NAME=$(kubectl get pvc pg-data-pg-production-0 -n production -o jsonpath='{.spec.volumeName}')
kubectl patch pv $PV_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Verify:

```bash
kubectl get pv $PV_NAME -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
```

Expected output:
```
Retain
```

**Safeguard 2: Create a Storage Class with Retain policy**

```bash
vi /tmp/retain-storageclass.yaml
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: retain-standard
provisioner: k8s.io/minikube-hostpath
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

```bash
kubectl apply -f /tmp/retain-storageclass.yaml
```

**Safeguard 3: Add RBAC to prevent PVC deletion**

In production, restrict who can delete PVCs:

```bash
vi /tmp/pvc-protect-role.yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pvc-reader
  namespace: production
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch"]
  # Note: no "delete" verb - users with this role cannot delete PVCs
```

```bash
kubectl apply -f /tmp/pvc-protect-role.yaml
```

---

## Part 3: Validation

Run these checks to confirm your safeguards are in place:

```bash
# Check 1: PV reclaim policy is Retain
PV_NAME=$(kubectl get pvc pg-data-pg-production-0 -n production -o jsonpath='{.spec.volumeName}')
POLICY=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
echo "Reclaim policy: $POLICY"
# Expected: Retain

# Check 2: retain-standard Storage Class exists
kubectl get storageclass retain-standard -o jsonpath='{.reclaimPolicy}'
# Expected: Retain

# Check 3: RBAC role exists with no delete permission
kubectl get role pvc-reader -n production -o jsonpath='{.rules[0].verbs}'
# Expected: ["get","list","watch"] - no "delete"

# Check 4: PostgreSQL is running
kubectl exec -it pg-production-0 -n production -- psql -U postgres -c "SELECT 'recovered' AS status;"
# Expected: recovered
```

---

## Clean Up

```bash
kubectl delete namespace production
kubectl delete storageclass retain-standard
```

---

## Lessons Learned

| Lesson | Action |
|--------|--------|
| Default reclaim policy is `Delete` | ALWAYS change to `Retain` for production database PVs |
| PVC deletion destroys data | Restrict PVC delete permissions with RBAC |
| No backup means no recovery | Configure backups BEFORE you need them (CloudNativePG + Barman) |
| `kubectl delete --all` is dangerous | Never use wildcard deletes in production namespaces |
| Storage Class matters | Create a dedicated Storage Class for databases with `Retain` policy |
