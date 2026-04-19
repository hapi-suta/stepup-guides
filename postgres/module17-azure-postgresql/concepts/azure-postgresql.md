# Concepts - Azure Database for PostgreSQL Flexible Server

## What is Flexible Server?

Azure Database for PostgreSQL - Flexible Server is a fully managed PostgreSQL service on Microsoft Azure. "Fully managed" means Azure handles patching, backups, high availability, and infrastructure - you focus on your database design, queries, and application logic.

Flexible Server replaced the older "Single Server" deployment option (retired March 2025). All new deployments use Flexible Server.

---

## Architecture

### How It Works Internally

A Flexible Server consists of:

1. **Compute VM** - A virtual machine running PostgreSQL. You pick the size (SKU) and tier.
2. **Premium SSD storage** - Attached block storage for data, WAL, and temp files.
3. **Backup storage** - Automatic snapshots stored in zone-redundant or geo-redundant storage.
4. **Networking layer** - Either a public endpoint with firewall rules, a VNet-integrated private endpoint, or a Private Link.

Azure manages the underlying OS (Linux), the PostgreSQL binary, and the infrastructure. You interact with it through the Azure CLI, Azure Portal, REST API, or Terraform.

### FQDN and DNS

Every server gets a fully qualified domain name:

```
[server-name].postgres.database.azure.com
```

This DNS name resolves to the server's current IP. During failover, Azure updates DNS to point to the new primary. Applications should always connect using the FQDN, never a hardcoded IP.

---

## Compute Tiers

### Burstable

- **vCPUs**: 1-20
- **Memory**: 2-80 GB
- **Use case**: Development, testing, low-traffic applications
- **Key feature**: Can burst above baseline CPU temporarily
- **Limitation**: Does not support HA, limited IOPS
- **Example SKU**: Standard_B1ms (1 vCPU, 2 GB RAM)

### General Purpose

- **vCPUs**: 2-96
- **Memory**: 8-384 GB
- **Use case**: Production workloads with balanced compute and memory
- **Key feature**: Consistent CPU performance, supports HA
- **Example SKU**: Standard_D2ds_v4 (2 vCPU, 8 GB RAM)

### Memory Optimized

- **vCPUs**: 2-96
- **Memory**: 16-672 GB
- **Use case**: In-memory caching, complex analytics, large working sets
- **Key feature**: Higher memory-to-vCPU ratio
- **Example SKU**: Standard_E2ds_v4 (2 vCPU, 16 GB RAM)

### Cost Optimization Tips

- Use Burstable for non-production environments
- Right-size based on actual CPU/memory utilization (check Azure Monitor metrics)
- Use Reserved Instances (1-year or 3-year commitment) for 30-60% savings on production servers
- Stop the server when not in use (dev/test) - you pay only for storage while stopped

---

## High Availability

### Zone-Redundant HA

The primary and standby run in different availability zones within the same region. Azure uses synchronous streaming replication.

```
Zone 1                    Zone 2
+------------------+      +------------------+
| Primary Server   | ---> | Standby Server   |
| (compute + data) |      | (compute + data) |
+------------------+      +------------------+
```

- **RPO**: 0 (zero data loss - synchronous replication)
- **RTO**: 60-120 seconds
- **Protects against**: Zone failures, VM failures, storage failures
- **Cost**: Approximately 2x compute (you pay for both VMs)

### Same-Zone HA

Both primary and standby run in the same availability zone.

- **RPO**: 0
- **RTO**: 60-120 seconds
- **Protects against**: VM failures, storage failures
- **Does NOT protect against**: Zone failures
- **Cost**: Same as zone-redundant

### Failover Process

1. Azure detects the primary is unhealthy (or you trigger a planned failover)
2. Existing connections are dropped
3. The standby replays any remaining WAL
4. The standby promotes to primary
5. DNS updates to point to the new primary
6. A new standby is provisioned in the background

Applications must handle reconnection. Use connection pooling (PgBouncer) and retry logic.

### HA vs Read Replicas

| Feature | HA Standby | Read Replica |
|---------|-----------|--------------|
| Replication | Synchronous | Asynchronous |
| Readable | No | Yes |
| Automatic failover | Yes | No (manual promote) |
| Cross-region | No (same region) | Yes |
| Purpose | Availability | Read scaling, DR |

---

## Networking

### Public Access

The server gets a public IP address. You control access through firewall rules that whitelist specific IP addresses or ranges.

- Simple to set up
- Suitable for development and small deployments
- Must manage firewall rules carefully
- Each rule allows a start IP to end IP range

### VNet Integration

The server is placed directly into a delegated subnet within your virtual network. No public IP is assigned.

- Most secure option for production
- All traffic stays within the Azure backbone
- Must be configured at server creation (cannot change later)
- The subnet must be delegated to `Microsoft.DBforPostgreSQL/flexibleServers`
- Requires DNS configuration (Private DNS zone)

### Private Link

Creates a private endpoint in your VNet that maps to the server.

- Works with public access servers (adds a private path)
- Supports cross-VNet and cross-subscription access
- Uses Azure Private DNS for name resolution
- More flexible than VNet integration for hub-spoke topologies

### Choosing a Networking Mode

- **Dev/test**: Public access with firewall rules
- **Simple production**: VNet integration
- **Complex production (multi-VNet, hub-spoke)**: Private Link

---

## Azure AD (Entra ID) Authentication

### How It Works

1. An Azure AD administrator is assigned to the server
2. The admin creates PostgreSQL roles mapped to Azure AD identities using `pgaadauth_create_principal()`
3. Users authenticate by getting an Azure AD access token
4. The token is used as the password in the PostgreSQL connection

### Token Flow

```
User -> Azure AD -> Access Token -> PostgreSQL (validates token) -> Session
```

Tokens expire after approximately 1 hour. Applications should refresh tokens before expiry.

### Types of Identities

- **User** - An Azure AD user (human)
- **Service Principal** - An application identity (for automated systems)
- **Managed Identity** - An Azure resource identity (for VMs, App Service, etc.)

### Advantages Over Password Auth

- Centralized identity management
- Multi-factor authentication
- Conditional access policies
- No password rotation needed (tokens expire automatically)
- Audit trail in Azure AD

---

## Backup and PITR

### How Automated Backups Work

Azure takes backups automatically:

1. **First backup**: Full snapshot when the server is created
2. **Daily full backups**: A full snapshot every 24 hours
3. **Transaction log backups**: Every 5 minutes

This enables point-in-time restore to any second within your retention window.

### Backup Storage

- Backup storage equal to 100% of your provisioned storage is free
- Beyond that, you pay per GB per month
- Storage is zone-redundant by default (in regions with availability zones)
- Geo-redundant backup replicates to the paired region

### Point-in-Time Restore (PITR)

PITR restores your database to a specific second in time. It works by:

1. Restoring the most recent full backup before your target time
2. Replaying transaction logs up to the exact target timestamp

Important: PITR always creates a **new server**. You cannot restore in-place. You must update your application connection string to point to the new server.

### Restore Window

```
|<---------- Retention Period (7-35 days) ---------->|
|                                                     |
Earliest Restore ---------------------------------> Now
```

You can restore to any point between `EarliestRestore` and now.

---

## Intelligent Performance

### Query Store

Query Store captures query execution statistics within PostgreSQL. It tracks:

- **Runtime statistics**: Execution count, total time, rows returned
- **Wait statistics**: What queries wait on (I/O, locks, CPU)

Enable it with: `pg_qs.query_capture_mode = top`

### Query Performance Insight

A portal-based view that shows:

- Top 5 queries by execution time
- Top 5 queries by call count
- Wait event breakdown

This helps identify the queries that consume the most resources.

### Index Tuning

Azure can recommend indexes based on Query Store data:

- **report mode**: Shows recommendations only
- **apply mode**: Automatically creates recommended indexes

Enable with: `index_tuning.mode = report` (or `apply`)

Recommendations appear after 24-48 hours of query data collection.

---

## Migration from On-Premises

### Azure Database Migration Service (DMS)

DMS handles online (minimal downtime) migrations from:

- On-premises PostgreSQL
- AWS RDS for PostgreSQL
- Other cloud providers

The migration process:
1. Full initial data copy
2. Continuous change data capture (CDC) using logical replication
3. Cutover when the target catches up

### pg_dump / pg_restore

For smaller databases or offline migrations:

1. Export with `pg_dump --format=custom`
2. Create the target Flexible Server
3. Import with `pg_restore --host=target.postgres.database.azure.com`

### Key Migration Considerations

- Check PostgreSQL version compatibility
- Verify extension support on Flexible Server
- Test application connectivity with the new FQDN
- Plan for DNS cutover
- Test SSL connectivity (Azure enforces SSL by default)
- Migrate users and roles separately (they are not in pg_dump by default)

---

## Extensions

Flexible Server supports a subset of PostgreSQL extensions. Common ones include:

| Extension | Purpose |
|-----------|---------|
| pgcrypto | Cryptographic functions |
| uuid-ossp | UUID generation |
| postgis | Geospatial data |
| pg_stat_statements | Query statistics |
| pgaudit | Audit logging |
| pg_trgm | Trigram matching (fuzzy search) |
| hstore | Key-value store |
| pg_partman | Partition management |

Check available extensions:

```sql
SELECT name, default_version FROM pg_available_extensions ORDER BY name;
```

---

## Security Layers

A properly secured Flexible Server uses multiple layers:

1. **Network** - VNet integration or Private Link (no public exposure)
2. **Authentication** - Azure AD with MFA and conditional access
3. **Encryption in transit** - SSL/TLS required (TLSv1.2 minimum)
4. **Encryption at rest** - AES-256 (Microsoft-managed or customer-managed keys)
5. **Audit** - pgaudit for DML/DDL tracking
6. **Threat detection** - Microsoft Defender for anomaly detection
7. **Access control** - PostgreSQL GRANT/REVOKE for fine-grained permissions

---

## Cost Components

| Component | Billing |
|-----------|---------|
| Compute | Per hour, based on SKU |
| Storage | Per GB per month (Premium SSD) |
| Backup storage | Free up to 100% of provisioned storage |
| HA standby | Same as primary compute cost |
| Read replicas | Same as primary compute + storage cost per replica |
| Network egress | Per GB for cross-region traffic |

### Cost Estimation Example (Monthly)

For a General Purpose D2ds_v4 (2 vCPU, 8 GB) with 64 GB storage:
- Compute: ~$125/month
- Storage: ~$7.50/month
- With HA: ~$250/month compute + $7.50 storage
- Total without HA: ~$133/month
- Total with HA: ~$258/month

Prices vary by region. Check the Azure Pricing Calculator for current rates.

---

## Key Differences from Self-Managed PostgreSQL

| Feature | Self-Managed | Flexible Server |
|---------|-------------|-----------------|
| OS access | Full root access | None |
| postgresql.conf | Direct file edit | Azure CLI parameter set |
| pg_hba.conf | Direct file edit | Firewall rules / VNet |
| Backups | You manage | Automated |
| HA | You configure (Patroni, repmgr) | Built-in toggle |
| Patching | You apply | Azure applies (with maintenance window) |
| Extensions | Install any | Supported subset only |
| Superuser | Yes | No (azure_pg_admin role) |
| WAL management | Full control | Azure managed |
| Custom data directory | Yes | No |

The biggest adjustment for DBAs moving to Flexible Server: you do not have superuser or OS access. Everything is managed through the Azure API and the `azure_pg_admin` role.
