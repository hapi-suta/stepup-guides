# Concepts: Cloud Database Services

**Module 03 - Cloud Database Services**
**Quick reference for the concepts covered in BUILD 01 through BUILD 04.**

---

## RDS vs Aurora vs Self-Managed Comparison

| Feature | Self-Managed (EC2) | RDS PostgreSQL | Aurora PostgreSQL |
|---|---|---|---|
| **OS access** | Full root/SSH | None | None |
| **Custom extensions** | Any | AWS-supported list | AWS-supported list |
| **pg_cron** | Yes | No (standard RDS) | Yes |
| **HA setup** | Manual (repmgr, Patroni) | Multi-AZ checkbox | Built-in (shared storage) |
| **Failover time** | Minutes | 60-120 seconds | ~30 seconds |
| **Max read replicas** | Unlimited (you manage) | 5 | 15 |
| **Replica lag** | Depends on network/load | Seconds to minutes | < 20 ms |
| **Auto backups** | You configure | Included | Included |
| **PITR** | You configure WAL archiving | Included (1-35 days) | Included + Backtrack |
| **Storage auto-grow** | No (manual resize) | Yes (with autoscaling) | Yes (automatic, 10 GB increments) |
| **Max storage** | EBS limits (64 TB) | 64 TB | 128 TB |
| **Encryption at rest** | You configure | Checkbox at creation | Checkbox at creation |
| **Minor version upgrades** | You do it | Automatic (optional) | Automatic (optional) |
| **Major version upgrades** | pg_upgrade or dump/restore | In-place with downtime | In-place with downtime |
| **Relative cost** | Lowest | Medium (+20-30%) | Highest (+40-50%) |
| **DBA effort** | Highest | Low | Lowest |

---

## Instance Type Guide for DBAs

### Development and Testing

| Instance | vCPU | RAM | Use Case | Cost (on-demand, us-east-1) |
|---|---|---|---|---|
| db.t3.micro | 2 | 1 GB | Experimentation, tutorials | ~$0.018/hr |
| db.t3.small | 2 | 2 GB | Small dev databases | ~$0.036/hr |
| db.t3.medium | 2 | 4 GB | Dev/test, Aurora minimum | ~$0.073/hr |
| db.t4g.medium | 2 | 4 GB | Dev/test (Graviton/ARM) | ~$0.065/hr |

**Note:** `t3` and `t4g` instances are "burstable" - they accumulate CPU credits when idle and spend them during spikes. Good for intermittent workloads. Bad for sustained high CPU.

### Production

| Instance | vCPU | RAM | Use Case | Cost (on-demand, us-east-1) |
|---|---|---|---|---|
| db.r6g.large | 2 | 16 GB | Small production | ~$0.26/hr |
| db.r6g.xlarge | 4 | 32 GB | Medium production | ~$0.48/hr |
| db.r6g.2xlarge | 8 | 64 GB | Large production | ~$0.96/hr |
| db.r6g.4xlarge | 16 | 128 GB | Heavy OLTP | ~$1.92/hr |
| db.r6g.8xlarge | 32 | 256 GB | Very large databases | ~$3.84/hr |

**Why `r6g` for production:** The "r" family is memory-optimized. PostgreSQL performance is heavily influenced by how much data fits in `shared_buffers` and OS page cache. More RAM = fewer disk reads = faster queries.

**Graviton (ARM) instances** (`g` suffix) are 10-20% cheaper than Intel equivalents with comparable performance. Use them unless you have a specific reason not to.

---

## Storage Type Comparison

| Storage Type | Base IOPS | Max IOPS | Throughput | Cost per GB | IOPS Cost | Best For |
|---|---|---|---|---|---|---|
| **gp2** | 3 IOPS/GB (min 100) | 16,000 | 250 MB/s | $0.115 | Included | Legacy (do not use) |
| **gp3** | 3,000 (baseline) | 16,000 | 125 MB/s (up to 1,000) | $0.08 | $0.005/IOPS above 3,000 | Default choice |
| **io1** | Provisioned | 64,000 | 1,000 MB/s | $0.125 | $0.065/IOPS | High-IOPS OLTP |
| **io2** | Provisioned | 256,000 | 4,000 MB/s | $0.125 | $0.065/IOPS | Extreme performance |
| **Aurora** | Automatic | Automatic | Automatic | $0.10 | $0.20/million I/O | Aurora only |

**Decision guide:**
- **gp3** for 90% of workloads. It replaced gp2 - cheaper with more baseline IOPS.
- **io1/io2** only when you need more than 16,000 IOPS consistently.
- **Aurora storage** is automatic - you do not choose a type.

---

## Backup Strategy Decision Matrix

| Scenario | Strategy | Retention | Cost Impact |
|---|---|---|---|
| Development database | Automated backups, 1-day retention | 1 day | Minimal |
| Standard production | Automated backups, 14-day retention | 14 days | Moderate |
| Regulated production | Automated 35-day + monthly manual snapshots | 35 days + yearly | Higher |
| Cross-region DR | Automated + cross-region snapshot copy | Per policy | Significant |
| Pre-migration safety | Manual snapshot before change | Keep until verified | One-time |
| Long-term archival | Export snapshot to S3 (Parquet) | Years | S3 storage cost |

**Recovery time expectations:**

| Recovery Method | Time Estimate | Creates New Instance? |
|---|---|---|
| RDS PITR | 30-60 minutes | Yes |
| Snapshot restore | 20-45 minutes | Yes |
| Aurora Backtrack | Seconds to minutes | No |
| Aurora PITR | 15-30 minutes | Yes |
| Cross-region restore | 45-90 minutes | Yes |

---

## Cost Estimation Formulas

### RDS PostgreSQL Monthly Cost

```
Instance Cost = hourly_rate x 730 hours
Storage Cost  = allocated_GB x $0.08 (gp3)
Backup Cost   = max(0, backup_GB - allocated_GB) x $0.095
Multi-AZ      = Instance Cost x 2 (doubles instance cost)
Read Replicas = Instance Cost x number_of_replicas
PITR Storage  = included in backup cost
------
Total = Instance + Storage + Backup + Multi-AZ + Replicas
```

**Example: Production RDS (db.r6g.xlarge, 500 GB, Multi-AZ, 1 replica)**

```
Instance:  $0.48/hr x 730 = $350.40
Multi-AZ:  $350.40 (doubles instance)
Replica:   $350.40
Storage:   500 GB x $0.08 = $40.00
Backup:    Free (under 500 GB)
------
Total: ~$1,091.20/month
```

### Aurora PostgreSQL Monthly Cost

```
Instance Cost = hourly_rate x 730 hours (writer + readers)
Storage Cost  = used_GB x $0.10
I/O Cost      = total_IO_requests / 1,000,000 x $0.20
Backup Cost   = max(0, backup_GB - cluster_volume_GB) x $0.021
------
Total = Instance + Storage + I/O + Backup
```

**Example: Production Aurora (db.r6g.xlarge writer + 1 reader, 500 GB, 10M I/Os/month)**

```
Writer:    $0.58/hr x 730 = $423.40
Reader:    $0.58/hr x 730 = $423.40
Storage:   500 GB x $0.10 = $50.00
I/O:       10M / 1M x $0.20 = $2.00
Backup:    Free (under 500 GB)
------
Total: ~$898.80/month
```

**Key insight:** Aurora with HA (writer + reader) is cheaper than RDS with Multi-AZ + read replica because Aurora does not charge double for HA.

---

## AWS CLI Cheat Sheet for RDS/Aurora

### Instance Management

```bash
# List all RDS instances
aws rds describe-db-instances \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus,MultiAZ:MultiAZ}" \
  --output table

# List all Aurora clusters
aws rds describe-db-clusters \
  --query "DBClusters[*].{ID:DBClusterIdentifier,Engine:Engine,Status:Status,Writer:Endpoint,Reader:ReaderEndpoint}" \
  --output table

# Get instance endpoint
aws rds describe-db-instances \
  --db-instance-identifier INSTANCE_NAME \
  --query "DBInstances[0].Endpoint.Address" \
  --output text

# Reboot instance
aws rds reboot-db-instance --db-instance-identifier INSTANCE_NAME

# Stop instance (saves cost - max 7 days, then auto-restarts)
aws rds stop-db-instance --db-instance-identifier INSTANCE_NAME

# Start instance
aws rds start-db-instance --db-instance-identifier INSTANCE_NAME
```

### Backup and Recovery

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier INSTANCE_NAME \
  --db-snapshot-identifier SNAPSHOT_NAME

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier INSTANCE_NAME \
  --output table

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier NEW_INSTANCE_NAME \
  --db-snapshot-identifier SNAPSHOT_NAME

# Point-in-time restore
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier SOURCE_NAME \
  --target-db-instance-identifier TARGET_NAME \
  --restore-time "2026-06-09T15:00:00Z"

# Delete snapshot
aws rds delete-db-snapshot --db-snapshot-identifier SNAPSHOT_NAME
```

### Monitoring

```bash
# Get CPU metric
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time START_TIME --end-time END_TIME \
  --period 300 --statistics Average

# List CloudWatch alarms for RDS
aws cloudwatch describe-alarms \
  --alarm-name-prefix "rds-" \
  --output table

# Check RDS events (last 24 hours)
aws rds describe-events \
  --source-identifier INSTANCE_NAME \
  --source-type db-instance \
  --duration 1440
```

### Parameter Groups

```bash
# List parameter groups
aws rds describe-db-parameter-groups

# Show parameters in a group
aws rds describe-db-parameters \
  --db-parameter-group-name GROUP_NAME \
  --query "Parameters[?ParameterValue!=null].{Name:ParameterName,Value:ParameterValue,Apply:ApplyMethod}"

# Modify a parameter
aws rds modify-db-parameter-group \
  --db-parameter-group-name GROUP_NAME \
  --parameters "ParameterName=PARAM,ParameterValue=VALUE,ApplyMethod=immediate"
```
