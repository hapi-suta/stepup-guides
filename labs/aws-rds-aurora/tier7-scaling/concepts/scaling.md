# Tier 7 - Scaling, Integration, and Modern Patterns: Concepts

Read this before working through the BUILD guides. These concepts underpin every lab in Tier 7.

---

## T7.1 Vertical Scaling and Storage Autoscaling

### What Vertical Scaling Means for RDS

Vertical scaling means changing the instance class - swapping from a smaller instance (db.t3.medium) to a larger one (db.r6g.2xlarge). You are getting more CPU, more RAM, and more network bandwidth on a single node.

This is the most common first response when an RDS database is under resource pressure. It is quick to execute and requires no application changes. The tradeoff is downtime: instance class changes require a reboot, which causes a brief interruption (typically 20-90 seconds for Multi-AZ instances, longer for single-AZ).

**Multi-AZ behavior during scaling:**
With Multi-AZ enabled, AWS performs the instance class change on the standby first, promotes the standby to primary (the failover causes the brief interruption), then upgrades the old primary. This minimizes downtime compared to a cold resize, but you will still see a connection drop during failover.

**When to scale up vs. when to scale out:**
- Scale up when the bottleneck is CPU or memory on the primary writer.
- Scale out (read replicas) when the bottleneck is read volume.
- Scale up alone does not help read-heavy workloads if the writer is not the bottleneck.

### Storage Autoscaling

RDS storage autoscaling monitors your used storage and automatically increases the allocated size when free space drops below a threshold. AWS scales storage in increments - typically the larger of 5 GiB or 10% of current allocated storage.

**Key facts:**
- Storage can only grow, never shrink. Once you scale storage up, you cannot reduce it.
- The autoscaling threshold is: free space < 10% of allocated storage AND that condition persists for at least 5 minutes.
- You set a Maximum Storage Threshold. AWS will not scale beyond that value.
- Storage scaling happens online with no downtime for gp2 and gp3 volumes.

**Storage types:**
- `gp3`: General purpose SSD. Baseline 3,000 IOPS and 125 MB/s throughput at no extra cost. You can provision additional IOPS and throughput independently. Recommended default.
- `gp2`: Older general purpose SSD. IOPS tied to size (3 IOPS/GiB). Baseline 100 IOPS minimum, bursts up to 3,000 IOPS. Avoid for new databases.
- `io1` / `io2`: Provisioned IOPS SSD. Use when you need predictable, high IOPS above what gp3 can deliver. More expensive.

**Storage autoscaling limitations:**
- Does not help if you hit IOPS limits - that requires changing the storage type or provisioning more IOPS.
- The 6-hour cooldown between autoscaling events can leave you in a gap if storage fills faster than the cooldown clears.
- Aurora manages storage differently - it allocates in 10 GiB chunks automatically and scales to 128 TiB. Storage autoscaling settings on Aurora instances have less meaning.

### Monitoring Scaling Events

Key CloudWatch metrics for scaling decisions:
- `FreeStorageSpace` - Watch for trends, not just point-in-time values.
- `CPUUtilization` - Sustained >70% is a signal to investigate.
- `DatabaseConnections` - High connection counts can indicate memory pressure.
- `FreeableMemory` - Less than 10% of instance RAM is a warning sign.
- `ReadIOPS` / `WriteIOPS` - Compare against your provisioned IOPS limit.

RDS events (in the console under Events) log storage scaling actions. Use EventBridge to trigger alerts when storage scaling occurs.

---

## T7.2 Aurora Serverless v2 Capacity Design and Troubleshooting

### What Aurora Serverless v2 Is

Aurora Serverless v2 (ASv2) replaces fixed-size instances with capacity that scales automatically between a minimum and maximum you define. Capacity is measured in Aurora Capacity Units (ACUs).

1 ACU = approximately 2 GiB of memory, proportional CPU, and network.

Unlike Aurora Serverless v1 (which had cold-start delays and limitations), v2 scales in fine-grained increments (0.5 ACU steps), responds in seconds, and supports most Aurora features including Multi-AZ, read replicas, and Global Database.

### ACU Range Design

Choosing the right ACU range is the primary capacity planning task for ASv2.

**Minimum ACU:**
- The lowest ACU value ASv2 will scale down to during idle periods.
- Setting minimum to 0.5 ACU allows the instance to pause (charge only for storage) when there is no activity. This is only appropriate for development or sporadic workloads.
- For production databases that must be responsive at all times, set minimum to at least 2 ACUs. Scaling from near-zero adds latency to the first queries after a quiet period.
- Rule of thumb: minimum should handle your baseline, non-peak load with headroom.

**Maximum ACU:**
- The ceiling. ASv2 will not exceed this.
- If your workload hits the maximum, behavior resembles a traditional instance - you will see CPU and memory pressure, queries will queue.
- Set maximum based on your peak load analysis plus a 20-30% buffer.
- Maximum ACU also acts as a cost ceiling - you know the worst case hourly cost.

**Example ranges:**
- Dev/test: 0.5 min, 4 max
- Low-traffic production: 2 min, 16 max
- High-traffic production: 4 min, 64 max
- Data warehouse / analytics: 8 min, 128 max

### Scaling Behavior and Cooldowns

ASv2 scales up quickly - within seconds of detecting load. Scaling down is more conservative. ASv2 waits for connections to drain and CPU to drop before reducing capacity. This protects against premature scale-down during brief lulls in traffic.

Scale-down happens in steps and can take several minutes. Do not expect ASv2 to hit minimum ACU instantly after load ends.

### Troubleshooting ASv2 Scaling Issues

**Symptom: Queries are slow during traffic spikes**
Check `ServerlessDatabaseCapacity` metric. If it is pegged at your Maximum ACU during spikes, you have hit the ceiling. Either raise the max or investigate why the workload needs more capacity (missing indexes, inefficient queries).

**Symptom: Database is slow to respond after an idle period**
The instance scaled down toward minimum ACU. The first queries after an idle period pay a "warm-up" cost. Solutions: raise the minimum ACU so the instance never drops below a responsive level, or send a keepalive query periodically.

**Symptom: Costs are higher than expected**
ASv2 charges per ACU-hour. If your workload sustains high capacity for long periods, ASv2 may cost more than a fixed instance. Check the `ServerlessDatabaseCapacity` metric over time. If average capacity is consistently near your max, a fixed instance may be cheaper.

**Break-even analysis:**
- Calculate average ACU consumed per hour from CloudWatch.
- Provisioned instance cost = fixed hourly rate.
- ASv2 cost = average ACUs * $0.12 per ACU-hour (varies by region).
- If average ACU cost >= provisioned instance cost, consider switching to provisioned.

### Cost Analysis: Provisioned vs Serverless

Serverless v2 wins when: workload is highly variable (overnight dips, weekend drops), you have many databases that are often idle, you want to avoid over-provisioning for rare peaks.

Provisioned wins when: workload is steady and predictable, you need the absolute lowest latency (no scaling lag), you have high sustained throughput.

---

## T7.3 Zero-ETL to Redshift and RDS Data API

### Zero-ETL Integration

Zero-ETL is an AWS feature that replicates data from Aurora (PostgreSQL or MySQL) into Amazon Redshift automatically - without building and maintaining a traditional ETL pipeline.

The integration works using transaction logs. Aurora captures row-level changes and streams them into Redshift in near-real-time. From the Redshift side, your tables appear as if they are local.

**What it solves:**
Traditional analytics pipelines require: a data extraction job, transformation logic, loading into Redshift, schema management, and scheduling. Zero-ETL eliminates most of this. Schema changes (DDL) in Aurora propagate automatically.

**What it does not solve:**
- Complex transformations (you still need dbt or SQL views for that)
- Data from non-Aurora sources
- Full historical loads from before the integration was created (you need to seed initial data separately)

**Requirements:**
- Aurora PostgreSQL 16.6+ or Aurora MySQL 3.05+
- The Aurora cluster and Redshift cluster must be in the same AWS account and region
- The Aurora cluster must have `aurora_enhanced_binlog` parameter enabled (Aurora MySQL) or logical replication configured (Aurora PostgreSQL)
- Redshift must be a provisioned cluster or Redshift Serverless

**Limitations:**
- Tables must have primary keys. Tables without primary keys are not replicated.
- Some data types are not supported (e.g., geometric types, large objects).
- Replication lag varies - typically seconds to minutes depending on load.

### RDS Data API

The RDS Data API provides HTTP-based access to Aurora Serverless databases without requiring a persistent TCP connection. You call an HTTPS endpoint, pass SQL, and get JSON back.

**Why this exists:**
Traditional database connections require: a persistent TCP connection, a connection pool, and a driver running in your application environment. Lambda functions, API Gateway integrations, and other serverless architectures struggle with persistent connections because they scale horizontally and each new invocation may need a new connection.

The Data API solves this by decoupling query execution from connection management. The API maintains a connection pool internally.

**Trade-offs:**

| Factor | Data API | Direct Connection |
|--------|----------|-------------------|
| Connection overhead | None per request | Pool required |
| Latency | Higher (HTTP overhead) | Lower |
| Throughput | Lower | Higher |
| VPC requirement | No (can call from outside VPC) | Yes |
| Long transactions | Not supported | Supported |
| Binary protocols | No | Yes |

**When to use Data API:**
- Lambda functions querying Aurora infrequently
- API Gateway backends with stateless query patterns
- Quick administrative scripts that do not warrant a full connection setup

**When NOT to use Data API:**
- High-throughput transactional workloads
- Long-running transactions (the API has a 45-second query timeout)
- Bulk data operations
- Applications that already have a connection pool

---

## T7.4 Lambda from RDS PostgreSQL; S3 Import and Export

### Calling Lambda from PostgreSQL

Aurora PostgreSQL can invoke AWS Lambda functions directly using the `aws_lambda` extension. This allows you to trigger Lambda from a PostgreSQL trigger, function, or query.

**Use cases:**
- Send a notification (SNS, SES) when a row is inserted
- Call an external API when data changes
- Trigger a downstream data processing workflow from a database event
- Audit logging to an external system

**How it works:**
The `aws_lambda` extension uses the IAM role attached to the Aurora cluster to call Lambda. The call is synchronous by default - the PostgreSQL function waits for Lambda to return before completing. You can call Lambda asynchronously (fire and forget) using the `invocation_type` parameter.

**Important constraints:**
- The Lambda function must be in the same region as the Aurora cluster (or peered if using VPC Lambda).
- The Aurora cluster's IAM role needs `lambda:InvokeFunction` permission.
- Synchronous Lambda calls from triggers can fail in ways that roll back transactions if not handled carefully.
- Lambda has a 15-minute maximum execution time. Do not call long-running Lambdas from synchronous triggers.

### S3 Import and Export

The `aws_s3` extension enables importing data from S3 into RDS/Aurora and exporting query results to S3.

**S3 Import:**
Used to bulk-load CSV or other delimited files from S3 into a table. This is faster than inserting rows one at a time through an application.

The function `aws_s3.table_import_from_s3()` wraps PostgreSQL's `COPY FROM` command, pulling data directly from an S3 object.

**S3 Export:**
Used to write the results of a SELECT query to S3 as a CSV or other format.

The function `aws_s3.query_export_to_s3()` runs your query and streams results to an S3 object.

**IAM requirement:**
Both import and export require the RDS instance to have an IAM role with `s3:GetObject` (for import) and `s3:PutObject` (for export) permissions. The role must be associated with the RDS instance.

**Performance notes:**
- S3 import reads the entire file sequentially. Split large files into multiple objects and use parallel imports for speed.
- S3 export writes row by row. For very large result sets, the export can be slow.
- Neither import nor export replaces a proper ETL pipeline for complex transformations.

---

## T7.5 Logical Replication and CDC Patterns

### How Logical Replication Works in PostgreSQL

Physical replication (streaming replication) replicates at the block level - it copies the exact WAL bytes from primary to replica. The replica must be on the same PostgreSQL major version.

Logical replication decodes WAL changes into row-level events (INSERT, UPDATE, DELETE) and ships those events to a subscriber. Because the events are logical (not physical bytes), the subscriber can be on a different PostgreSQL major version, a different schema layout, or a completely different system.

**Components:**
- **Publication**: Defined on the source. Specifies which tables (or all tables) to publish. `CREATE PUBLICATION my_pub FOR TABLE orders, customers;`
- **Subscription**: Defined on the destination. Points to the source connection string and publication name. `CREATE SUBSCRIPTION my_sub CONNECTION '...' PUBLICATION my_pub;`
- **Replication slot**: Created automatically on the source. Tracks how far the subscriber has consumed WAL. The source retains WAL until the subscriber acknowledges receipt.

**Replication slots are critical to understand:**
If a subscriber goes offline or falls behind, the replication slot prevents WAL cleanup on the source. WAL accumulates. If the slot is not consumed, the source disk fills. This is the most common operational failure mode with logical replication on RDS.

### Publications and Subscriptions in RDS

RDS imposes some constraints on logical replication:

- You cannot use superuser for replication. Use the `rds_replication` role.
- The parameter `rds.logical_replication` must be set to `1` in the parameter group.
- Setting this parameter to 1 sets `wal_level = logical` automatically.
- Changing `wal_level` requires an instance reboot.

**Replication identity:**
For logical replication, each replicated table needs a replication identity so PostgreSQL can identify which rows to UPDATE or DELETE on the subscriber.

- `FULL` identity: PostgreSQL logs the entire old row in WAL. Allows replication even without a primary key, but WAL is larger.
- `DEFAULT` (primary key): Uses the primary key to identify rows. Most efficient.
- Tables without a primary key and without `REPLICA IDENTITY FULL` set will cause replication errors on UPDATE and DELETE.

### CDC Patterns for Event-Driven Architecture

Change Data Capture (CDC) reads the WAL stream and converts database changes into events that downstream systems can consume. CDC is the foundation of event-driven architectures built on top of relational databases.

**Common CDC tools for RDS/Aurora PostgreSQL:**
- **Debezium**: Open-source CDC platform. Reads PostgreSQL WAL via a replication slot, publishes events to Kafka topics. Each table change becomes a Kafka message.
- **AWS Database Migration Service (DMS)**: Can be configured as a CDC-only task. Reads WAL changes and writes to a target (S3, Kinesis, another database).
- **Logical replication to a consumer app**: Your application subscribes to a replication slot using `pg_logical` or `pgoutput` plugin and processes changes directly.

**Event schema patterns:**
CDC events typically include:
- Operation type (INSERT, UPDATE, DELETE)
- Before image (for UPDATE/DELETE, what the row looked like before)
- After image (what the row looks like after)
- Metadata: transaction ID, LSN (log sequence number), timestamp

**Operational discipline for logical replication:**
- Monitor replication slot lag. Use CloudWatch metric `OldestReplicationSlotLag` for RDS.
- Set an alert when lag exceeds a threshold (e.g., 5 GiB of WAL retained).
- Drop unused replication slots immediately. An unconsumed slot is a ticking clock on your disk.
- If a subscriber will be offline for an extended period, drop the slot and recreate it when the subscriber returns (accept data loss) or provision enough storage for the expected lag.

---

## T7.6 Migration Into RDS/Aurora: DMS, Blue/Green, Dump/Restore

### Choosing the Right Migration Strategy

There is no single migration strategy. The right choice depends on:

| Factor | Considerations |
|--------|---------------|
| Downtime tolerance | How long can the application be offline? |
| Database size | Small (<50 GiB) vs. large (>500 GiB) |
| Source database | On-premise, EC2, different cloud, different engine |
| Same engine migration | PostgreSQL to PostgreSQL, or cross-engine (Oracle to PostgreSQL) |
| Major version jump | PostgreSQL 12 to 16 requires logical replication or dump/restore |
| Reversibility | Can you roll back if the migration fails? |

### pg_dump / pg_restore

The simplest migration method. Stop writes, dump the source database, restore to the target, restart writes.

**When to use:**
- Migrating from on-premises PostgreSQL to RDS
- Migrating to a new major version when downtime is acceptable
- Database size < 100 GiB (larger is possible but slow)
- You need a clean, simple, reversible migration

**Process:**
1. Take a `pg_dump` in custom format (`-Fc`).
2. Transfer the dump to a location accessible to the target.
3. Run `pg_restore` on the target.
4. Validate row counts and data.
5. Cut over DNS or application config.

**Downtime:** However long the dump and restore takes. For 50 GiB databases, typically 30-90 minutes depending on hardware. Not suitable for very large databases or low-downtime requirements.

### AWS Database Migration Service (DMS)

DMS is a managed service that handles both full-load migration and ongoing replication (CDC mode). It can migrate between different database engines (Oracle to PostgreSQL, MySQL to PostgreSQL, etc.).

**DMS components:**
- **Replication instance**: An EC2 instance that runs the migration tasks. Size this appropriately - it is the bottleneck for large migrations.
- **Source endpoint**: Connection details for where data comes from.
- **Target endpoint**: Connection details for where data goes.
- **Migration task**: Defines what to migrate (full load, CDC, or both) and mapping rules.

**Task types:**
- `Full load`: Copy all existing data. No ongoing replication.
- `Full load + CDC`: Copy existing data, then continue replicating new changes. Used for minimal-downtime migrations.
- `CDC only`: Assume the target already has data (seeded via another method). Only replicate changes.

**DMS limitations for PostgreSQL:**
- DDL replication is limited. Schema changes during migration may not replicate correctly.
- Large objects (BLOBs) may not migrate correctly.
- Sequences are not migrated automatically - they must be set on the target after migration.
- DMS does not replicate all PostgreSQL-specific features (partial indexes, complex defaults, custom types).
- Always run a schema migration (using `pg_dump --schema-only`) separately before running DMS data migration.

### Blue/Green Deployments

AWS RDS Blue/Green Deployments create a staging copy (green) of your production database (blue), keep it in sync using logical replication, and then switch traffic from blue to green with minimal downtime.

**Primary use case:** Major version upgrades. Going from PostgreSQL 14 to 16 with less than 60 seconds of downtime.

**How it works:**
1. AWS creates a green environment - a copy of your blue (production) database running the new version.
2. Logical replication keeps green synchronized with blue during the cutover period.
3. When you initiate switchover, RDS stops writes to blue, waits for green to catch up, then promotes green. Downtime is typically under 60 seconds.
4. After switchover, blue exists for a rollback window. If problems appear, you can roll back.

**Blue/Green limitations:**
- Requires logical replication to be possible (tables need primary keys or replica identity set).
- The green environment costs money during the preparation period (you run two databases).
- Some RDS features cannot be changed as part of a Blue/Green switchover (e.g., changing storage type requires a separate operation).
- Externally managed read replicas are not included in Blue/Green automatically.

### Decision Matrix

| Scenario | Recommended Strategy |
|----------|---------------------|
| Same engine, same version, small DB, downtime OK | pg_dump / pg_restore |
| Same engine, major version upgrade, production | Blue/Green Deployment |
| Cross-engine migration (Oracle/MySQL to PostgreSQL) | DMS full load + CDC |
| Very large database (>500 GiB), minimal downtime | DMS full load + CDC, then cutover |
| On-premises to RDS, large, some downtime OK | pg_dump to S3, then aws_s3 import or pg_restore via bastion |
| Ongoing sync (not a one-time migration) | Logical replication or DMS CDC-only |
| Disaster recovery / standby setup | Read replica promotion (not really a migration) |
