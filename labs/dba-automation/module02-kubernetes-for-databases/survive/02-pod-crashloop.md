# SURVIVE 02: The CrashLoopBackOff That Won't Stop

**Scenario:** PostgreSQL pod keeps restarting and will not stay up.

**Module:** Kubernetes for Databases
**Difficulty:** Medium
**Time:** 30-45 minutes

---

## The Story

It is Monday morning. The monitoring dashboard shows the `pg-analytics` pod in namespace `analytics` has been in `CrashLoopBackOff` since the weekend deployment. The pod starts, runs for a few seconds, and gets killed. It has restarted 47 times. The analytics team cannot run their reports. No one touched it over the weekend - or so they claim.

Your mission: diagnose why the pod keeps crashing and fix the root cause.

---

## Part 1: The Injection

Set up the broken environment.

**On your Mac, in Terminal:**

Ensure minikube is running:

```bash
minikube start
```

Create the broken scenario:

```bash
vi /tmp/survive-crashloop-setup.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: analytics
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-analytics-creds
  namespace: analytics
type: Opaque
stringData:
  POSTGRES_PASSWORD: analytics123
---
apiVersion: v1
kind: Service
metadata:
  name: pg-analytics-headless
  namespace: analytics
spec:
  clusterIP: None
  ports:
  - port: 5432
  selector:
    app: pg-analytics
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg-analytics
  namespace: analytics
spec:
  serviceName: pg-analytics-headless
  replicas: 1
  selector:
    matchLabels:
      app: pg-analytics
  template:
    metadata:
      labels:
        app: pg-analytics
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
              name: pg-analytics-creds
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        args:
        - postgres
        - -c
        - shared_buffers=2GB
        - -c
        - max_connections=1000
        - -c
        - work_mem=256MB
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
  volumeClaimTemplates:
  - metadata:
      name: pg-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Apply it:

```bash
kubectl apply -f /tmp/survive-crashloop-setup.yaml
```

Wait 30 seconds for the crash loop to start:

```bash
sleep 30
kubectl get pods -n analytics
```

Expected output (yours will differ):
```
NAME               READY   STATUS             RESTARTS      AGE
pg-analytics-0     0/1     CrashLoopBackOff   3 (15s ago)   30s
```

The pod is crashing. Your investigation begins now.

---

## Part 2: The Runbook

### Step 1: Observe the Symptoms

Start by gathering information. Do NOT guess - look at the evidence.

**Check the pod status:**

```bash
kubectl get pods -n analytics
```

Note the `STATUS` column. `CrashLoopBackOff` means the container starts, crashes, and Kubernetes keeps restarting it with increasing delays (backoff).

**Get detailed pod information:**

```bash
kubectl describe pod pg-analytics-0 -n analytics
```

Look at these sections carefully:
- **State** and **Last State** under Containers
- **Reason** - is it `OOMKilled`, `Error`, or something else?
- **Events** at the bottom

Write down what you find before proceeding.

### Step 2: Check the Logs

**View the current (or most recent) container logs:**

```bash
kubectl logs pg-analytics-0 -n analytics
```

If the container crashed too quickly and there are no logs, check the previous container's logs:

```bash
kubectl logs pg-analytics-0 -n analytics --previous
```

Read the logs carefully. Look for:
- PostgreSQL error messages
- Startup failures
- Out of memory errors
- Configuration errors

### Step 3: Analyze the Root Cause

By now you should have found clues. The key evidence is:

1. In `kubectl describe`, the Last State shows `Reason: OOMKilled` - the container was killed by the Out of Memory killer
2. The container has `resources.limits.memory: 128Mi` (128 megabytes)
3. The PostgreSQL configuration requests:
   - `shared_buffers = 2GB` - this alone requires 2 gigabytes
   - `max_connections = 1000`
   - `work_mem = 256MB`

**DBA Analogy:** This is like setting `shared_buffers = 2GB` on a server with only 128MB of RAM. PostgreSQL tries to allocate the shared memory segment, exceeds the cgroup memory limit, and the OS kills the process. In Kubernetes, this manifests as `OOMKilled`.

The root cause is a mismatch between PostgreSQL configuration and container resource limits. Someone configured PostgreSQL for a large server but deployed it in a container with tiny resource limits.

### Step 4: Fix the Problem

There are two approaches:
- **Option A:** Increase the container resource limits to match the PostgreSQL config
- **Option B:** Reduce the PostgreSQL config to fit the container limits

For a lab/analytics workload, Option B is more appropriate. In production, you would do both - right-size the configuration AND set appropriate limits.

**Fix: Adjust PostgreSQL parameters to fit within the resource limits**

Edit the StatefulSet:

```bash
vi /tmp/survive-crashloop-fix.yaml
```

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg-analytics
  namespace: analytics
spec:
  serviceName: pg-analytics-headless
  replicas: 1
  selector:
    matchLabels:
      app: pg-analytics
  template:
    metadata:
      labels:
        app: pg-analytics
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
              name: pg-analytics-creds
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        args:
        - postgres
        - -c
        - shared_buffers=64MB
        - -c
        - max_connections=50
        - -c
        - work_mem=4MB
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
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

Changes made:
- `shared_buffers`: 2GB -> 64MB (fits within 512Mi limit)
- `max_connections`: 1000 -> 50 (reduces memory footprint)
- `work_mem`: 256MB -> 4MB (prevents per-query memory explosion)
- `resources.limits.memory`: 128Mi -> 512Mi (reasonable for PostgreSQL)
- `resources.requests.memory`: 64Mi -> 256Mi (guaranteed minimum)
- `resources.limits.cpu`: 100m -> 250m (quarter of a CPU core)

Apply the fix:

```bash
kubectl apply -f /tmp/survive-crashloop-fix.yaml
```

Since StatefulSets use `RollingUpdate` by default, the pod will be restarted with the new configuration. If the pod is stuck in CrashLoopBackOff, delete it to force an immediate restart:

```bash
kubectl delete pod pg-analytics-0 -n analytics
```

Wait for it to come up:

```bash
kubectl get pods -n analytics -w
```

Expected output (yours will differ):
```
NAME               READY   STATUS    RESTARTS   AGE
pg-analytics-0     0/1     Pending   0          2s
pg-analytics-0     0/1     ContainerCreating   0   3s
pg-analytics-0     1/1     Running   0          10s
```

Press `Ctrl+C` when you see Running with no more restarts.

### Step 5: Verify the Fix

```bash
kubectl exec -it pg-analytics-0 -n analytics -- psql -U postgres -c "SHOW shared_buffers;"
```

Expected output:
```
 shared_buffers
----------------
 64MB
(1 row)
```

```bash
kubectl exec -it pg-analytics-0 -n analytics -- psql -U postgres -c "SHOW max_connections;"
```

Expected output:
```
 max_connections
-----------------
 50
(1 row)
```

```bash
kubectl exec -it pg-analytics-0 -n analytics -- psql -U postgres -c "SELECT 'Analytics DB is back online' AS status;"
```

Expected output:
```
           status
----------------------------
 Analytics DB is back online
(1 row)
```

---

## Part 3: Validation

Run these checks to confirm the fix:

```bash
# Check 1: Pod is Running and not restarting
RESTARTS=$(kubectl get pod pg-analytics-0 -n analytics -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo "Restart count: $RESTARTS"
# Expected: 0 (since the new pod was created)

# Check 2: No OOMKilled in recent events
kubectl describe pod pg-analytics-0 -n analytics | grep -i oom
# Expected: no output (no OOM events)

# Check 3: Resource limits are reasonable
kubectl get pod pg-analytics-0 -n analytics -o jsonpath='{.spec.containers[0].resources.limits.memory}'
# Expected: 512Mi

# Check 4: PostgreSQL is accepting connections
kubectl exec -it pg-analytics-0 -n analytics -- psql -U postgres -c "SELECT 1;"
# Expected: returns 1
```

---

## Clean Up

```bash
kubectl delete namespace analytics
```

---

## Debugging Cheat Sheet: CrashLoopBackOff

When a database pod is in CrashLoopBackOff, follow this checklist:

| Step | Command | What to Look For |
|------|---------|-----------------|
| 1. Check status | `kubectl get pods -n <ns>` | RESTARTS count, STATUS |
| 2. Describe pod | `kubectl describe pod <name> -n <ns>` | Last State Reason (OOMKilled? Error?) |
| 3. Check logs | `kubectl logs <pod> -n <ns> --previous` | PostgreSQL errors, startup failures |
| 4. Check resources | Look at `resources.limits` in the YAML | Is memory too low for PostgreSQL config? |
| 5. Check config | Look at PostgreSQL args or ConfigMap | shared_buffers, max_connections, work_mem |
| 6. Compare | Config memory needs vs container limits | shared_buffers should be ~25% of memory limit |

### Common Root Causes

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `OOMKilled` | PostgreSQL config exceeds memory limit | Reduce shared_buffers or increase memory limit |
| `Error` exit code 1 | Bad configuration parameter | Check logs for the specific error |
| `Error` exit code 137 | SIGKILL (OOM or manual kill) | Check memory limits and usage |
| Pod starts then dies after 30s | Liveness probe failing | Check probe config and PostgreSQL startup time |
| `Init:CrashLoopBackOff` | Init container failing | Check init container logs |
| Permission denied in logs | Volume mount permissions wrong | Check `securityContext` and volume ownership |

### PostgreSQL Memory Rule of Thumb for Containers

```
Container memory limit = shared_buffers + (max_connections * work_mem) + maintenance_work_mem + 256MB overhead

Example:
  shared_buffers = 64MB
  max_connections = 50
  work_mem = 4MB
  maintenance_work_mem = 64MB
  overhead = 256MB

  Minimum limit = 64 + (50 * 4) + 64 + 256 = 584MB

  Set limit to 512Mi-768Mi for safety.
```

---

## Lessons Learned

| Lesson | Action |
|--------|--------|
| PostgreSQL config must match resource limits | Always calculate memory needs before deploying |
| `OOMKilled` is the most common database pod crash | Set `shared_buffers` to ~25% of the memory limit |
| `kubectl logs --previous` shows crashed container output | Always check previous logs for CrashLoopBackOff |
| `kubectl describe` shows the kill reason | Look at Last State -> Reason |
| Resource requests vs limits | Requests = guaranteed minimum, Limits = hard maximum |
| CrashLoopBackOff has increasing delays | K8s waits longer between each restart (10s, 20s, 40s, up to 5min) |
