# BUILD 02: Kubernetes Core Concepts for DBAs

**Module:** Kubernetes for Databases
**Prerequisites:** BUILD 01 (Docker Fundamentals) completed, Docker Desktop running
**Time:** 60-75 minutes

---

## What You Will Build

By the end of this guide, you will have a local Kubernetes cluster running on your Mac with minikube, understand every core Kubernetes concept through DBA analogies, and deploy a PostgreSQL Pod manually using YAML manifests.

---

## Step 1: Understand What Kubernetes Is

You already know **Patroni** - it monitors PostgreSQL, handles failover, manages replication. Kubernetes does the same thing, but for **every service in your infrastructure**, not just PostgreSQL.

**DBA Analogy:** Kubernetes is like Patroni on steroids. Patroni says "if the primary dies, promote the standby." Kubernetes says "if ANY container dies, restart it. If a server dies, move all its containers to a healthy server. If traffic increases, add more containers."

| Patroni Concept | Kubernetes Equivalent |
|----------------|----------------------|
| Patroni cluster | Kubernetes cluster |
| etcd (stores cluster state) | etcd (literally the same technology) |
| Patroni agent on each node | kubelet agent on each node |
| patronictl | kubectl |
| DCS (Distributed Configuration Store) | Control Plane |
| PostgreSQL instance | Pod |

Kubernetes is often abbreviated as **K8s** (K + 8 letters + s). You will see both terms used interchangeably.

---

## Step 2: Install minikube on Mac

minikube runs a single-node Kubernetes cluster inside a container on your Mac. It is perfect for learning - you get a real K8s cluster without needing cloud servers.

**On your Mac, in Terminal:**

```bash
brew install minikube
```

Expected output (yours will differ):
```
==> Downloading https://ghcr.io/v2/homebrew/core/minikube/...
==> Installing minikube
==> Pouring minikube--1.34.0.arm64_sonoma.bottle.tar.gz
...
==> Summary
/opt/homebrew/Cellar/minikube/1.34.0: 9 files, 97.5MB
```

Verify the installation:

```bash
minikube version
```

Expected output (yours will differ):
```
minikube version: v1.34.0
commit: 210b148df93a80eb872ecbeb7e35281b3c582c61
```

Also install `kubectl` - the command-line tool for Kubernetes:

```bash
brew install kubectl
```

Expected output (yours will differ):
```
==> Downloading https://ghcr.io/v2/homebrew/core/kubernetes-cli/...
==> Installing kubernetes-cli
...
```

---

## Step 3: Start Your First Kubernetes Cluster

**On your Mac, in Terminal:**

```bash
minikube start
```

This takes 1-3 minutes. minikube downloads a Kubernetes distribution and runs it inside Docker.

Expected output (yours will differ):
```
* minikube v1.34.0 on Darwin 14.6 (arm64)
* Automatically selected the docker driver
* Using Docker Desktop driver with root privileges
* Starting "minikube" primary control-plane node in "minikube" cluster
* Pulling base image v0.0.45 ...
* Creating docker container (CPUs=2, Memory=4000MB) ...
* Preparing Kubernetes v1.31.0 on Docker 27.2.0 ...
* Configuring bridge CNI (Container Networking Interface) ...
* Verifying Kubernetes components...
* Enabled addons: storage-provisioner, default-storageclass
* Done! kubectl is now configured to use "minikube" cluster
```

Verify the cluster is running:

```bash
kubectl cluster-info
```

Expected output (yours will differ):
```
Kubernetes control plane is running at https://127.0.0.1:55000
CoreDNS is running at https://127.0.0.1:55000/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

```bash
kubectl get nodes
```

Expected output (yours will differ):
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   45s   v1.31.0
```

You now have a single-node Kubernetes cluster. In production, you would have multiple nodes (servers), but for learning, one node is enough.

---

## Step 4: kubectl - The psql of Kubernetes

`kubectl` is your primary tool for interacting with Kubernetes. Just as you use `psql` to query PostgreSQL, you use `kubectl` to query and manage your K8s cluster.

**DBA Analogy:**

| psql Command | kubectl Equivalent | What It Does |
|-------------|-------------------|-------------|
| `\l` | `kubectl get namespaces` | List logical groupings |
| `\dt` | `kubectl get pods` | List running things |
| `\d+ tablename` | `kubectl describe pod <name>` | Detailed info about one thing |
| `tail -f pg.log` | `kubectl logs <pod>` | View logs |
| `psql -c "SELECT ..."` | `kubectl exec -it <pod> -- psql` | Run a command inside |

Try it:

```bash
kubectl get namespaces
```

Expected output (yours will differ):
```
NAME              STATUS   AGE
default           Active   2m
kube-node-lease   Active   2m
kube-public       Active   2m
kube-system       Active   2m
```

These are the built-in namespaces. `default` is where your Pods will go unless you specify otherwise.

---

## Step 5: Pods - The Running Database Instance

A **Pod** is the smallest deployable unit in Kubernetes. It wraps one or more containers and gives them a shared network and storage context.

**DBA Analogy:** A Pod is a running database instance. Just as you think of "the PostgreSQL instance on pg-primary," in K8s you think of "the PostgreSQL Pod."

Let's deploy your first Pod. Rather than writing YAML yet, use a quick imperative command:

**On your Mac, in Terminal:**

```bash
kubectl run pg-test --image=postgres:16 --env="POSTGRES_PASSWORD=dbalab123"
```

Expected output (yours will differ):
```
pod/pg-test created
```

Check the Pod status:

```bash
kubectl get pods
```

Expected output (yours will differ):
```
NAME      READY   STATUS    RESTARTS   AGE
pg-test   1/1     Running   0          15s
```

| Column | Meaning |
|--------|---------|
| `READY 1/1` | 1 out of 1 containers in the Pod are ready |
| `STATUS Running` | The Pod is healthy and running |
| `RESTARTS 0` | It has not crashed and restarted |

Get detailed information about the Pod:

```bash
kubectl describe pod pg-test
```

This outputs a lot of information. Key sections to look at:

- **Events** (at the bottom) - shows the Pod lifecycle: Scheduled, Pulled, Created, Started
- **Containers** - shows the image, ports, environment variables
- **Conditions** - shows Ready, Initialized, ContainersReady

---

## Step 6: kubectl logs and kubectl exec

**View PostgreSQL logs from the Pod:**

```bash
kubectl logs pg-test
```

Expected output (yours will differ):
```
PostgreSQL init process complete; ready for start up.
...
LOG:  database system is ready to accept connections
LOG:  listening on IPv4 address "0.0.0.0", port 5432
```

**Get a shell inside the Pod:**

```bash
kubectl exec -it pg-test -- bash
```

Expected output (yours will differ):
```
root@pg-test:/#
```

You are now inside the container running in the Pod. Connect to PostgreSQL:

```bash
psql -U postgres -c "SELECT version();"
```

Expected output (yours will differ):
```
                                                  version
------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.4 (Debian 16.4-1.pgdg120+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 12.2.0-14)
(1 row)
```

Exit the Pod:

```bash
exit
```

---

## Step 7: Deployments - A Fleet of Identical Instances

A **Deployment** tells Kubernetes "I want N copies of this container running at all times." If one dies, K8s automatically creates a replacement.

**DBA Analogy:** Think of a Deployment as managing a fleet of identical stateless application servers - like running 3 copies of PgBouncer. If one crashes, a new one takes its place. Deployments are great for stateless services, but NOT ideal for databases (we will cover that in BUILD 03).

Delete the test Pod first:

```bash
kubectl delete pod pg-test
```

Create a simple Deployment using nginx (a web server) to illustrate the concept:

```bash
vi /tmp/nginx-deployment.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
```

| Field | What It Does | DBA Analogy |
|-------|-------------|-------------|
| `replicas: 3` | Run 3 copies of this container | 3 PgBouncer instances behind a load balancer |
| `selector.matchLabels` | How the Deployment finds its Pods | Like a `WHERE` clause - identifies which Pods belong to this Deployment |
| `template` | The Pod template - what each copy looks like | A CREATE TABLE template that gets used 3 times |

Apply it:

```bash
kubectl apply -f /tmp/nginx-deployment.yaml
```

Expected output (yours will differ):
```
deployment.apps/web-app created
```

```bash
kubectl get pods
```

Expected output (yours will differ):
```
NAME                       READY   STATUS    RESTARTS   AGE
web-app-6d4f5b7c8d-abc12   1/1     Running   0          10s
web-app-6d4f5b7c8d-def34   1/1     Running   0          10s
web-app-6d4f5b7c8d-ghi56   1/1     Running   0          10s
```

Three Pods, all running. Now delete one and watch Kubernetes recreate it:

```bash
kubectl delete pod web-app-6d4f5b7c8d-abc12
```

```bash
kubectl get pods
```

Expected output (yours will differ):
```
NAME                       READY   STATUS    RESTARTS   AGE
web-app-6d4f5b7c8d-def34   1/1     Running   0          45s
web-app-6d4f5b7c8d-ghi56   1/1     Running   0          45s
web-app-6d4f5b7c8d-jkl78   1/1     Running   0          3s
```

A new Pod (`jkl78`) replaced the deleted one. Kubernetes ensures the desired state (3 replicas) is always maintained. This is called **self-healing**.

Clean up:

```bash
kubectl delete deployment web-app
```

---

## Step 8: Services - DNS Names and Load Balancing

A **Service** gives a stable network endpoint to a set of Pods. Pods come and go (they get new IPs when recreated), but a Service provides a permanent DNS name and IP.

**DBA Analogy:** A Service is like PgBouncer or a VIP (Virtual IP) in front of your database. Clients connect to the Service, and the Service routes traffic to the right Pod. Even if the Pod restarts and gets a new IP, the Service name stays the same.

| Service Type | What It Does | DBA Analogy |
|-------------|-------------|-------------|
| `ClusterIP` (default) | Internal-only DNS name | A hostname in `/etc/hosts` visible only inside the cluster |
| `NodePort` | Exposes on a port on every node | Like `listen_addresses = '*'` with a specific port |
| `LoadBalancer` | Provisions an external load balancer (cloud only) | An AWS NLB in front of your database |

You will create a Service in Step 13 when you deploy PostgreSQL with a YAML manifest.

---

## Step 9: Namespaces - Schemas for Your Cluster

A **Namespace** is a logical partition within a Kubernetes cluster.

**DBA Analogy:** Namespaces are like PostgreSQL schemas. Just as you use schemas to separate `app.users` from `audit.users`, namespaces separate resources by team, environment, or project.

```bash
kubectl create namespace databases
```

Expected output (yours will differ):
```
namespace/databases created
```

```bash
kubectl get namespaces
```

Expected output (yours will differ):
```
NAME              STATUS   AGE
databases         Active   5s
default           Active   10m
kube-node-lease   Active   10m
kube-public       Active   10m
kube-system       Active   10m
```

You can deploy resources into a specific namespace with `-n databases`. Resources in different namespaces are isolated from each other by default.

---

## Step 10: ConfigMaps - postgresql.conf in Kubernetes

A **ConfigMap** stores configuration data as key-value pairs. Instead of editing `postgresql.conf` on a server, you store it in a ConfigMap and mount it into your Pod.

**DBA Analogy:** A ConfigMap is `postgresql.conf` stored in Kubernetes instead of on disk. You can update it centrally and roll it out to all your database Pods.

```bash
vi /tmp/pg-configmap.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pg-config
  namespace: databases
data:
  postgresql.conf: |
    listen_addresses = '*'
    max_connections = 200
    shared_buffers = 256MB
    effective_cache_size = 768MB
    work_mem = 4MB
    maintenance_work_mem = 128MB
    log_statement = 'ddl'
    log_min_duration_statement = 1000
```

```bash
kubectl apply -f /tmp/pg-configmap.yaml
```

Expected output (yours will differ):
```
configmap/pg-config created
```

```bash
kubectl get configmap -n databases
```

Expected output (yours will differ):
```
NAME               DATA   AGE
kube-root-ca.crt   1      2m
pg-config          1      5s
```

---

## Step 11: Secrets - Credentials in Kubernetes

A **Secret** stores sensitive data like passwords. Kubernetes Secrets are base64 encoded (not encrypted by default - we will discuss this).

**DBA Analogy:** A Secret is like the password entries in `pg_hba.conf` or `.pgpass` - credentials that should not be in plain text in your YAML files.

```bash
kubectl create secret generic pg-credentials \
  --from-literal=POSTGRES_PASSWORD=dbalab123 \
  --from-literal=REPLICATION_PASSWORD=replpass123 \
  -n databases
```

Expected output (yours will differ):
```
secret/pg-credentials created
```

```bash
kubectl get secrets -n databases
```

Expected output (yours will differ):
```
NAME              TYPE     DATA   AGE
pg-credentials    Opaque   2      5s
```

**Important security note:** base64 is NOT encryption. Anyone with cluster access can decode Secrets. In production, you would use something like HashiCorp Vault or enable encryption at rest for etcd. For this lab, base64 is fine.

---

## Step 12: YAML Manifests - DDL Scripts for Infrastructure

Everything in Kubernetes is defined in YAML files called **manifests**. You `kubectl apply` them just like you run DDL scripts against a database.

**DBA Analogy:**

| SQL DDL | Kubernetes YAML |
|---------|----------------|
| `CREATE TABLE ...` | Define a Pod/Deployment in YAML |
| `psql -f schema.sql` | `kubectl apply -f manifest.yaml` |
| `ALTER TABLE ...` | Edit the YAML and `kubectl apply` again |
| `DROP TABLE ...` | `kubectl delete -f manifest.yaml` |
| `pg_dump --schema-only` | `kubectl get pod <name> -o yaml` (export current state) |

Every YAML manifest has four required fields:

```yaml
apiVersion: v1          # Which API version to use
kind: Pod               # What type of resource
metadata:               # Name, labels, namespace
  name: my-pod
spec:                   # The actual specification
  containers:
  - name: my-container
    image: postgres:16
```

---

## Step 13: Deploy PostgreSQL with a Full YAML Manifest

Now put it all together. You will create a PostgreSQL Pod with a Service, using the ConfigMap and Secret you already created.

**On your Mac, in Terminal:**

```bash
vi /tmp/pg-pod.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pg-manual
  namespace: databases
  labels:
    app: postgresql
    role: primary
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
          name: pg-credentials
          key: POSTGRES_PASSWORD
    - name: PGDATA
      value: /var/lib/postgresql/data/pgdata
    volumeMounts:
    - name: pg-data
      mountPath: /var/lib/postgresql/data
    - name: pg-config
      mountPath: /etc/postgresql/custom
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  volumes:
  - name: pg-data
    emptyDir: {}
  - name: pg-config
    configMap:
      name: pg-config
```

Let's break down the new concepts:

| Field | What It Does | DBA Analogy |
|-------|-------------|-------------|
| `labels` | Key-value tags on the Pod | Like instance tags in AWS |
| `env[].valueFrom.secretKeyRef` | Reads password from the Secret | Like reading from `.pgpass` |
| `volumeMounts` | Mounts volumes into the container filesystem | Like mount points for tablespace directories |
| `resources.requests` | Minimum resources guaranteed | Reserved memory/CPU for the instance |
| `resources.limits` | Maximum resources allowed | `cgroup` limits - prevents runaway queries from consuming all resources |
| `emptyDir` | Temporary storage (lost when Pod is deleted) | `/tmp` - fine for testing, NOT for production data |

Apply the Pod:

```bash
kubectl apply -f /tmp/pg-pod.yaml
```

Expected output (yours will differ):
```
pod/pg-manual created
```

Now create a Service to expose it:

```bash
vi /tmp/pg-service.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pg-manual-svc
  namespace: databases
spec:
  type: NodePort
  selector:
    app: postgresql
    role: primary
  ports:
  - port: 5432
    targetPort: 5432
    nodePort: 30432
```

| Field | What It Does | DBA Analogy |
|-------|-------------|-------------|
| `selector` | Routes traffic to Pods matching these labels | `WHERE app='postgresql' AND role='primary'` |
| `port: 5432` | The port the Service listens on inside the cluster | The port PgBouncer listens on |
| `targetPort: 5432` | The port on the Pod to forward to | The port PostgreSQL listens on |
| `nodePort: 30432` | The port exposed on the node (your Mac can reach this) | External port for client connections |

```bash
kubectl apply -f /tmp/pg-service.yaml
```

Expected output (yours will differ):
```
service/pg-manual-svc created
```

Check everything is running:

```bash
kubectl get pods,svc -n databases
```

Expected output (yours will differ):
```
NAME            READY   STATUS    RESTARTS   AGE
pod/pg-manual   1/1     Running   0          30s

NAME                    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/pg-manual-svc   NodePort   10.96.123.456   <none>        5432:30432/TCP   10s
```

Connect to PostgreSQL through minikube:

```bash
minikube service pg-manual-svc -n databases --url
```

This prints a URL like `http://192.168.49.2:30432`. Use that IP and port to connect:

```bash
psql -h $(minikube ip) -U postgres -p 30432
```

Enter password `dbalab123` when prompted.

Expected output (yours will differ):
```
Password for user postgres:
psql (16.4)
Type "help" for help.

postgres=#
```

Run a query to confirm:

```sql
SELECT 'Hello from Kubernetes!' AS message;
```

Expected output (yours will differ):
```
        message
------------------------
 Hello from Kubernetes!
(1 row)
```

```sql
\q
```

---

## Step 14: Clean Up

Leave the `databases` namespace and its resources for the next BUILD guide. Clean up only the temporary files:

```bash
kubectl delete pod pg-manual -n databases
kubectl delete service pg-manual-svc -n databases
```

Do NOT run `minikube stop` - you will need the cluster in BUILD 03.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Kubernetes | An orchestration platform that manages containers across servers - like Patroni for everything |
| minikube | A local K8s cluster running on your Mac for learning and development |
| kubectl | The CLI for K8s - equivalent to psql for PostgreSQL |
| Pod | The smallest deployable unit - wraps one or more containers |
| Deployment | Manages a fleet of identical stateless Pods with self-healing |
| Service | A stable DNS name and IP that routes traffic to Pods - like a VIP or PgBouncer |
| Namespace | Logical separation within a cluster - like PostgreSQL schemas |
| ConfigMap | Configuration data stored in K8s - like postgresql.conf |
| Secret | Sensitive data (passwords) stored in K8s - like .pgpass |
| YAML Manifests | Infrastructure as code - DDL scripts for K8s resources |
| Labels and Selectors | How K8s resources find each other - like WHERE clauses |
