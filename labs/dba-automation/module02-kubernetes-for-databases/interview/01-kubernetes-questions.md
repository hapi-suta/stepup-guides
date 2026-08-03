# Interview Questions: Kubernetes for Databases

**Module:** Kubernetes for Databases
**Purpose:** Practice answering DBA interview questions about running PostgreSQL on Kubernetes. Each question includes what the interviewer is looking for and a strong answer framework.

---

## Question 1: Why is a StatefulSet needed for databases instead of a Deployment?

### What the interviewer is looking for:
- Understanding of stateful vs stateless workloads
- Knowledge of how Kubernetes manages pod identity and storage
- Awareness of database-specific requirements

### Strong answer framework:

Deployments treat all pods as interchangeable. When a pod dies, Kubernetes creates a brand new replacement with a random name and no connection to the previous pod's storage. This works for stateless web servers but is catastrophic for databases.

Databases need four things Deployments cannot provide:

1. **Stable identity** - A database pod named `pg-0` must always be `pg-0`, even after restarts. Deployments give random names like `pg-6d4f5b7c8d-abc12`. Stable names are essential for replication configuration - `primary_conninfo` points to a specific hostname.

2. **Stable storage** - Each database pod must reconnect to its own persistent volume after restart. With a Deployment, a new pod gets fresh storage or fights for the old volume. StatefulSets use `volumeClaimTemplates` to give each pod a dedicated PVC that persists independently.

3. **Ordered startup and shutdown** - In a database cluster, the primary must start before standbys (standbys need the primary to replicate from). Standbys should shut down before the primary to avoid data loss. StatefulSets enforce this ordering (pod-0 first, then pod-1, then pod-2).

4. **Stable DNS** - Each pod in a StatefulSet gets a predictable DNS name through a headless Service (e.g., `pg-0.pg-headless.databases.svc.cluster.local`). This is critical for replication and application connection strings.

In practice, most teams use a Kubernetes operator (like CloudNativePG) that manages StatefulSets internally, but understanding why StatefulSets exist is fundamental.

---

## Question 2: Explain Persistent Volumes and why they matter for database workloads.

### What the interviewer is looking for:
- Understanding of the Kubernetes storage model
- Knowledge of PV, PVC, and Storage Class relationships
- Awareness of reclaim policies and their impact on data safety

### Strong answer framework:

Kubernetes separates storage into three layers:

- **Persistent Volume (PV)** - The actual storage resource. Think of it as a physical disk or an EBS volume in AWS. It exists independently of any pod.

- **Persistent Volume Claim (PVC)** - A request for storage from a pod. The PVC says "I need 100Gi of SSD storage" and Kubernetes finds or dynamically provisions a PV to satisfy it.

- **Storage Class** - Defines what type of storage is available and how it is provisioned. Like choosing between gp3 (SSD), io2 (high-IOPS SSD), and st1 (HDD) in AWS.

For databases, PVs are critical because:

1. **Data persistence** - Without a PV, all data in a container is ephemeral. When the container stops, everything is gone. A PV ensures PGDATA survives pod restarts, node failures, and even cluster upgrades.

2. **Reclaim policies** - The `reclaimPolicy` on a Storage Class controls what happens when a PVC is deleted. `Delete` (the default) destroys the data. `Retain` preserves it. Production databases should ALWAYS use `Retain`. I have seen incidents where `Delete` policy caused permanent data loss.

3. **Performance characteristics** - Different Storage Classes provide different IOPS and throughput. For a database primary, you want high-IOPS SSD. For WAL archives, high-throughput is more important. For backups, cost-efficient HDD may be fine.

4. **Volume expansion** - Production databases grow. The Storage Class should have `allowVolumeExpansion: true` so you can resize PVCs without downtime.

5. **Access modes** - Database volumes should be `ReadWriteOnce` (RWO) - only one pod mounts them at a time. This matches PostgreSQL's requirement that only one process should own PGDATA.

---

## Question 3: What happens when a Kubernetes node running your database pod goes down?

### What the interviewer is looking for:
- Understanding of node failure scenarios
- Knowledge of pod rescheduling behavior
- Awareness of the difference between managed operators and raw StatefulSets
- Practical incident response knowledge

### Strong answer framework:

The answer depends on whether you are using a raw StatefulSet or an operator like CloudNativePG.

**With a raw StatefulSet:**

1. The kubelet on the failed node stops sending heartbeats to the control plane.
2. After the `node-monitor-grace-period` (default 40 seconds), the node is marked `NotReady`.
3. After the `pod-eviction-timeout` (default 5 minutes), the control plane marks the pod for eviction.
4. The StatefulSet controller creates a new pod on a healthy node.
5. The new pod attempts to mount the PVC. If the storage is network-attached (EBS, Ceph, etc.), it can be detached from the failed node and reattached to the new node. If it is local storage, this fails.
6. Total downtime: 5-7 minutes minimum due to the eviction timeout.

**With CloudNativePG operator:**

1. The operator detects the primary is unreachable much faster than the default K8s timeouts.
2. If the failed pod was the primary, the operator promotes the healthiest standby (lowest replication lag) within seconds.
3. The `-rw` Service is updated to route to the new primary.
4. A replacement standby pod is scheduled on a healthy node.
5. Total downtime for writes: seconds (comparable to Patroni failover).

**Key considerations:**
- Storage type matters. Cloud block storage (EBS, Persistent Disk) can be reattached to another node. Local NVMe storage cannot - the data is stranded on the failed node until it recovers.
- Pod Disruption Budgets (PDBs) prevent Kubernetes from evicting too many database pods at once during planned maintenance.
- Topology spread constraints can ensure database pods run on different nodes, so a single node failure does not take down the entire cluster.

---

## Question 4: When would you choose RDS over running PostgreSQL on Kubernetes?

### What the interviewer is looking for:
- Practical decision-making ability, not religious preference for one approach
- Understanding of tradeoffs (cost, control, operational burden)
- Awareness of team capabilities and organizational context

### Strong answer framework:

I choose RDS (or any managed database service) when:

1. **The team lacks Kubernetes expertise.** Running databases on K8s requires understanding StatefulSets, PVCs, operators, resource limits, and storage classes. If the team does not already use Kubernetes for other workloads, introducing it just for the database adds unnecessary risk.

2. **Speed to production matters more than control.** RDS gives you a production-ready, HA database in minutes. Kubernetes takes hours to set up properly, even with an operator. For startups or new projects, RDS eliminates operational overhead.

3. **The managed service supports all required extensions.** If you only need standard PostgreSQL with extensions like PostGIS, pg_stat_statements, and pgvector, RDS covers it. There is no advantage to self-managing.

4. **Single cloud provider.** If you are committed to AWS (or GCP/Azure), vendor lock-in is already accepted. RDS optimizes for that environment.

5. **Small database count.** Managing 1-5 databases on K8s has high overhead per instance. RDS has a flat operational cost regardless of count.

I choose Kubernetes when:

1. **I need extensions not available on managed services** (custom C extensions, TimescaleDB, Citus, etc.).
2. **Multi-cloud or hybrid deployments** where the same PostgreSQL setup must run on AWS, GCP, and on-prem.
3. **Cost optimization at scale** - running 50+ databases on K8s is significantly cheaper than 50 RDS instances.
4. **Fine-grained control** over configuration, kernel parameters, or PostgreSQL source builds is required.
5. **The team already runs everything on Kubernetes** and has the operational maturity to manage databases there too.

The honest answer is that most teams should start with RDS and migrate to Kubernetes only when they hit a specific limitation.

---

## Question 5: How does CloudNativePG handle automated failover?

### What the interviewer is looking for:
- Understanding of operator-based failover mechanics
- Knowledge of how CloudNativePG differs from Patroni-style failover
- Awareness of the service routing mechanism
- Practical understanding of what happens during failover

### Strong answer framework:

CloudNativePG handles failover differently from Patroni. Instead of using a Distributed Configuration Store (DCS) like etcd or Consul for leader election, it leverages Kubernetes itself as the coordination layer.

**The failover process:**

1. **Health monitoring** - The CNPG controller continuously monitors all PostgreSQL instances by checking:
   - Pod readiness (Kubernetes-level)
   - PostgreSQL connectivity (can it accept connections?)
   - Replication status (`pg_stat_replication` and `pg_stat_wal_receiver`)
   - WAL receiver lag

2. **Failure detection** - When the primary pod becomes unresponsive (deleted, OOMKilled, node failure), the controller detects it through the Kubernetes API. There is no separate consensus protocol - the controller trusts Kubernetes pod status.

3. **Target selection** - The controller selects the best failover target by comparing:
   - `pg_last_wal_replay_lsn()` on each standby
   - The standby closest to the primary's last known LSN is chosen
   - This minimizes data loss (similar to `pg_rewind` target selection)

4. **Promotion** - The selected standby is promoted using `pg_promote()`. The operator:
   - Removes the `standby.signal` file
   - Calls `pg_promote()`
   - Waits for the instance to accept writes
   - Updates the pod labels to reflect the new role

5. **Reconfiguration** - The remaining standbys are reconfigured:
   - Their `primary_conninfo` is updated to point to the new primary
   - They restart replication from the new primary

6. **Service update** - The `-rw` (read-write) Service selector is updated to match the new primary pod. Applications using the `-rw` Service endpoint reconnect automatically to the new primary. The `-ro` (read-only) Service is updated to exclude the new primary.

7. **Fencing** - If the old primary comes back online, it is fenced (prevented from accepting writes) and reconfigured as a standby. CNPG uses `pg_rewind` if necessary to align the old primary's timeline with the new primary.

**Failover timing:**
- Detection: 1-5 seconds (depends on Kubernetes API response time)
- Promotion: 2-5 seconds
- Service update: 1-2 seconds
- Total: typically under 10 seconds for the new primary to be ready

**Key difference from Patroni:** Patroni uses a DCS for leader election, which requires a quorum vote. CloudNativePG uses a single controller that makes the decision, trusting Kubernetes for pod state. This is simpler but means the CNPG controller itself is a single point of failure - in production, the controller runs with multiple replicas for its own HA.
