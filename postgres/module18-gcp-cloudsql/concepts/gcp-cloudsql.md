# Concepts: Google Cloud SQL for PostgreSQL

## What Is Cloud SQL?

Cloud SQL is Google Cloud's fully managed relational database service. It runs PostgreSQL (also MySQL and SQL Server) on Google infrastructure. Google handles patching, backups, replication, failover, and hardware. You manage the database contents, schemas, users, and query performance.

Cloud SQL is NOT a re-engineered database (like Spanner or AlloyDB). It runs standard PostgreSQL with some restrictions. Your existing PostgreSQL knowledge transfers directly.

---

## Cloud SQL Architecture

### Under the Hood

```
┌─────────────────────────────────────────────────┐
│                  Google Cloud                     │
│                                                   │
│   ┌─────────────────────────────────────────┐    │
│   │           Cloud SQL Instance             │    │
│   │                                          │    │
│   │   ┌──────────┐    ┌──────────────────┐  │    │
│   │   │PostgreSQL │    │ Regional         │  │    │
│   │   │ Process   │───▶│ Persistent Disk  │  │    │
│   │   │ (Primary) │    │ (SSD/HDD)       │  │    │
│   │   └──────────┘    └──────────────────┘  │    │
│   │                           │              │    │
│   │                    ┌──────┴──────┐       │    │
│   │                    │  Standby    │       │    │
│   │                    │  (Zone B)   │       │    │
│   │                    └─────────────┘       │    │
│   └─────────────────────────────────────────┘    │
│                                                   │
│   ┌───────────────┐  ┌───────────────────────┐   │
│   │ Cloud Storage  │  │ Cloud Monitoring      │   │
│   │ (Backups)      │  │ (Metrics & Alerts)    │   │
│   └───────────────┘  └───────────────────────┘   │
└─────────────────────────────────────────────────┘
```

Key components:
- **Compute**: A VM running PostgreSQL, managed by Google
- **Storage**: Persistent disk (SSD or HDD) with automatic encryption
- **Networking**: VPC peering for private IP, firewall rules for public IP
- **Backups**: Stored in Cloud Storage, retained per your policy
- **Monitoring**: Automatic metrics sent to Cloud Monitoring

### What Google Manages

- OS patches and security updates
- PostgreSQL minor version upgrades
- Disk encryption at rest (AES-256)
- Network encryption in transit
- Automated backups
- Failover (if HA enabled)
- Hardware failures and replacement

### What You Manage

- PostgreSQL major version (choose at creation, upgrade manually)
- Database schemas, tables, indexes
- Users and permissions
- Database flags (postgresql.conf subset)
- Query performance and optimization
- Connection management
- Backup retention policy
- HA and read replica configuration

---

## High Availability and Failover

### How HA Works

Cloud SQL HA uses a **regional** configuration, not streaming replication.

1. The primary runs in Zone A
2. A standby instance runs in Zone B (same region)
3. Both share a **regional persistent disk** that replicates synchronously across zones
4. If the primary fails, the standby attaches to the same regional disk and becomes the new primary

This is fundamentally different from standard PostgreSQL HA:
- No WAL shipping between primary and standby
- No replication lag (it is the same disk)
- Zero data loss on failover (RPO = 0)
- Failover takes 30-120 seconds (RTO)

### Failover Triggers

Automatic failover happens when:
- The primary VM becomes unresponsive (heartbeat failure)
- The primary zone has a Google infrastructure outage
- A maintenance event requires it

Manual failover: `gcloud sql instances failover [INSTANCE]`

### What Happens During Failover

1. Google detects primary failure (~60 seconds of health checks)
2. Standby VM starts PostgreSQL using the regional disk
3. The IP address stays the same
4. All existing connections are dropped
5. Applications must reconnect (the Auth Proxy does this automatically)

### Cost Impact

HA doubles compute costs. The standby is the same machine tier as the primary. Storage is NOT doubled because both zones share a regional disk.

---

## Cloud SQL Auth Proxy

### Why It Exists

The Auth Proxy solves three problems:
1. **Encryption**: Provides TLS without managing certificates
2. **Authentication**: Uses IAM instead of database passwords
3. **Authorization**: Checks IAM roles before allowing connection
4. **Network**: No need to whitelist IPs or manage firewall rules

### How It Works

```
Application  ──▶  Auth Proxy (localhost:5432)  ──▶  Cloud SQL Instance
                       │
                       ├── Gets IAM token from metadata/ADC
                       ├── Opens TLS tunnel to Cloud SQL
                       └── Forwards PostgreSQL traffic
```

1. The proxy runs on the same machine as your application
2. Your application connects to `localhost:5432` (no encryption needed - it is local)
3. The proxy authenticates with IAM (Application Default Credentials or service account key)
4. The proxy opens an encrypted tunnel to Cloud SQL
5. PostgreSQL traffic flows through the tunnel

### When to Use It

| Scenario | Use Proxy? | Why |
|---|---|---|
| GKE/Cloud Run | Yes | Sidecar container, uses Workload Identity |
| GCE VM | Yes | Uses VM service account automatically |
| Local development | Yes | Uses gcloud auth credentials |
| VPC with Private IP | Optional | Private IP is already secure within VPC |
| Non-GCP environments | Yes | Safest way to connect from outside GCP |

---

## IAM Authentication

### How It Differs from Password Auth

| Aspect | Password Auth | IAM Auth |
|---|---|---|
| Credential | Password stored in PostgreSQL | IAM token (short-lived, auto-rotated) |
| Management | DBA manages passwords | IAM manages identities |
| Rotation | Manual | Automatic (tokens expire in 1 hour) |
| Audit | Database logs only | Cloud Audit Logs + database logs |
| Revocation | Must change password | Revoke IAM role - instant |

### IAM Auth Flow

1. User or service account has `roles/cloudsql.instanceUser` IAM role
2. A database user is created mapping to the IAM identity
3. The Auth Proxy (with `--auto-iam-authn`) generates a short-lived token
4. PostgreSQL receives the token as the password
5. Cloud SQL validates the token against IAM

### User Types

- `CLOUD_IAM_USER`: Maps to a GCP user account (person)
- `CLOUD_IAM_SERVICE_ACCOUNT`: Maps to a service account (application)
- `BUILT_IN`: Traditional PostgreSQL password auth

---

## Backup and Point-in-Time Recovery

### Backup Architecture

```
Automated Backups                    WAL Archiving (PITR)
┌─────────────┐                     ┌──────────────────┐
│ Daily full   │                     │ Continuous WAL    │
│ backup at    │                     │ stream to Cloud   │
│ scheduled    │                     │ Storage           │
│ window       │                     │                   │
│              │                     │ Retention: 1-7    │
│ Retention:   │                     │ days              │
│ 1-365 days   │                     │                   │
└──────┬───────┘                     └────────┬──────────┘
       │                                      │
       ▼                                      ▼
  Restore to                            Restore to ANY
  backup time                           second within
  only                                  retention window
```

### Automated Backups

- Run daily during your configured backup window
- Incremental (only changed blocks after the first full backup)
- Stored in Cloud Storage in the same region (or cross-region if configured)
- Retained by count (1-365 backups) or by age

### Point-in-Time Recovery (PITR)

- Requires automated backups to also be enabled
- Continuously archives WAL segments to Cloud Storage
- You can clone to any second within the retention window (1-7 days)
- PITR creates a NEW instance (does not overwrite the original)
- Uses `gcloud sql instances clone --point-in-time=TIMESTAMP`

### On-Demand Backups

- Triggered manually with `gcloud sql backups create`
- Persist until you delete them (no automatic retention)
- Use before risky changes (schema migrations, bulk deletes)

### Recovery Options

| Method | RPO | Creates New Instance? | Speed |
|---|---|---|---|
| Restore from backup | Last backup time | No (overwrites) | Minutes |
| PITR clone | Any second (1-7 day window) | Yes | Minutes |
| Export/Import | Export time | N/A | Varies |

---

## Query Insights

### What It Tracks

Query Insights captures:
- Query execution time (total, average, min, max)
- Query frequency (calls per minute)
- Rows scanned and returned
- Wait events
- Client IP and application name (if enabled)
- Query text (up to configured length)

### How It Differs from pg_stat_statements

| Feature | pg_stat_statements | Query Insights |
|---|---|---|
| Setup | CREATE EXTENSION | gcloud flag |
| Storage | Shared memory (limited) | Cloud Monitoring (unlimited history) |
| Visualization | SQL queries only | Cloud Console dashboard |
| Historical data | Lost on restart | Retained in Cloud Monitoring |
| Cross-instance | No | Yes (via Cloud Console) |

Use both together. Query Insights for dashboards and alerts. pg_stat_statements for detailed in-database analysis.

---

## Networking

### Private IP

Private IP uses VPC peering to connect your VPC to the Cloud SQL VPC.

```
Your VPC (10.0.0.0/16)  ──VPC Peering──  Cloud SQL VPC (10.x.x.x/20)
       │                                          │
  Your GCE VM                              Cloud SQL Instance
  10.0.1.5                                 10.20.30.40
```

- Traffic stays within Google's network
- No public internet exposure
- Requires a VPC peering connection (one-time setup)
- Private IP cannot be removed once assigned (you can add public IP alongside it)

### Authorized Networks

- Whitelist specific IP addresses or CIDR ranges for public IP access
- Each entry allows that IP to reach the Cloud SQL public IP on port 5432
- Maximum 256 authorized networks per instance
- Setting authorized networks REPLACES all existing entries
- Use 0.0.0.0/0 NEVER (allows the entire internet)

### Auth Proxy Networking

The Auth Proxy connects outbound from your machine to Cloud SQL. It does not require any inbound firewall rules. This makes it work from almost any network.

---

## Cost Optimization

### Pricing Components

| Component | How Charged | Optimization |
|---|---|---|
| vCPU | Per hour | Right-size the tier, use committed use discounts |
| RAM | Per hour | Included in tier, choose appropriate tier |
| Storage | Per GB per month | Enable auto-resize with limit, clean up bloat |
| Network egress | Per GB | Use same-region for replicas when possible |
| Backups | Per GB per month (beyond free) | Tune retention count and PITR days |
| HA standby | Same as primary | Use zonal for non-prod |
| Read replicas | Same pricing as primary | Scale down replica tier if lower traffic |

### Cost Reduction Strategies

1. **Right-size the tier**: Start small, scale up based on metrics
2. **Use zonal for non-prod**: HA costs 2x compute - skip it for dev/test
3. **Committed use discounts**: 1-year or 3-year commitments for 25-52% savings
4. **Stop idle instances**: Development instances can be stopped when not in use
5. **Tune backup retention**: 7-day PITR and 14 backups is plenty for most workloads
6. **Use HDD for cold data**: SSD is 2x the cost of HDD
7. **Cross-region replicas cost more**: Same-region replicas avoid cross-region egress

### Free Tier

Cloud SQL has no free tier. The smallest instance (db-f1-micro) costs approximately $10/month. Use it for development and delete when done.

---

## Database Migration Service (DMS)

### Migrating to Cloud SQL

Google provides the Database Migration Service for migrating from:
- On-premises PostgreSQL
- AWS RDS PostgreSQL
- Azure Database for PostgreSQL
- Self-managed PostgreSQL (any cloud or VM)

### Migration Flow

1. **Create a migration job** in DMS
2. **Configure the source** (connection details, SSL)
3. **Create a destination** Cloud SQL instance
4. **Initial full dump**: DMS copies all data
5. **Continuous replication**: DMS uses logical replication to keep in sync
6. **Cutover**: When ready, promote the Cloud SQL instance and switch application traffic

### Requirements for Source Database

- PostgreSQL 9.6 or later
- `wal_level = logical` on the source
- A user with replication privileges
- Network connectivity between source and GCP (VPN, interconnect, or public IP)
- Enough storage on Cloud SQL for the full dataset

### DMS vs pg_dump/pg_restore

| Feature | DMS | pg_dump/pg_restore |
|---|---|---|
| Downtime | Minutes (cutover only) | Hours (full dump/restore) |
| Continuous sync | Yes (logical replication) | No |
| Schema + data | Yes | Yes |
| Large databases | Better (streaming) | Slower (full dump) |
| Complexity | Higher (setup + monitoring) | Lower (one command) |

Use DMS for production migrations where downtime must be minimized. Use pg_dump for small databases or development environments.

---

## Cloud SQL vs AlloyDB vs Cloud Spanner

| Feature | Cloud SQL | AlloyDB | Cloud Spanner |
|---|---|---|---|
| Engine | Standard PostgreSQL | PostgreSQL-compatible | Google-proprietary |
| Scaling | Vertical (bigger instance) | Vertical + read pools | Horizontal (auto) |
| HA | Regional (zone failover) | Regional (zone failover) | Multi-region |
| Max storage | 64 TB | 64 TB | Unlimited |
| HTAP | No | Yes (columnar engine) | No |
| PostgreSQL compatibility | 100% | ~99% | Not PostgreSQL |
| Cost | Lowest | 2-3x Cloud SQL | Highest |
| Best for | Standard OLTP | High-perf OLTP + analytics | Global scale |

Choose Cloud SQL when:
- Standard PostgreSQL is sufficient
- Budget is a concern
- Workload fits on a single instance (up to 96 vCPUs, 624 GB RAM)
- You want the simplest managed PostgreSQL option

---

## Key Differences from Self-Managed PostgreSQL

| Aspect | Self-Managed | Cloud SQL |
|---|---|---|
| OS access | Full root/SSH | None |
| postgresql.conf | All parameters | ~105 exposed as flags |
| Extensions | All available | Supported subset only |
| pg_hba.conf | Direct edit | Authorized networks + IAM |
| WAL management | Your responsibility | Managed (PITR) |
| Replication setup | Manual | One command |
| Failover | Manual or Patroni/repmgr | Automatic |
| Backups | pg_basebackup/pgBackRest | Managed (daily + PITR) |
| Monitoring | Set up yourself | Built-in Cloud Monitoring |
| pg_upgrade | Run it yourself | Managed major version upgrade |
| Custom background workers | Yes | No |
| COPY from local file | Yes | No (use Cloud Storage) |

The biggest trade-off: you give up OS access and full parameter control in exchange for operational simplicity.
