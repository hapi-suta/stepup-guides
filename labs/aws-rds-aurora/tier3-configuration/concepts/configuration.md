# Tier 3 Concepts - Configuration and Extensions

**Read this before the BUILD guides.** These concepts explain the "why" behind each configuration decision.

---

## T3.1 Parameter Groups

### What Is a Parameter Group?

A parameter group is a named collection of PostgreSQL configuration settings. Instead of editing `postgresql.conf` directly (which you cannot do on RDS), you attach a parameter group to your instance and AWS applies those settings.

```
Your RDS Instance
        |
        | attached to
        v
+---------------------------+
|   DB Parameter Group      |
|  (custom or default)      |
|---------------------------|
|  work_mem = 64MB          |
|  max_connections = 200    |
|  log_min_duration = 1000  |
+---------------------------+
        |
        | reads at startup / dynamically
        v
  PostgreSQL Engine
```

### Default vs Custom Parameter Groups

| | Default Parameter Group | Custom Parameter Group |
|---|---|---|
| Name | `default.postgres16` | you choose |
| Editable | No | Yes |
| Shareable | Yes (across instances) | Yes |
| Best for | Quick tests | Any production use |

> **Rule:** Never use the default parameter group in production. Always create a custom one, even if you don't change anything yet. This gives you a safe place to make changes later.

### DB Parameter Groups vs Cluster Parameter Groups

For **RDS PostgreSQL** (single instance), you use a **DB Parameter Group**.

For **Aurora PostgreSQL**, there are two levels:

```
Aurora Cluster
    |
    +-- Cluster Parameter Group   <-- cluster-wide settings
    |   (applies to all instances in the cluster)
    |
    +-- Writer Instance
    |       |
    |       +-- DB Parameter Group  <-- instance-specific settings
    |
    +-- Reader Instance 1
    |       |
    |       +-- DB Parameter Group
    |
    +-- Reader Instance 2
            |
            +-- DB Parameter Group
```

Settings in the **cluster parameter group** affect all instances. Settings in a **DB parameter group** override at the instance level. Most PostgreSQL settings live in the cluster parameter group for Aurora.

### Static vs Dynamic Parameters

This is one of the most important distinctions in RDS parameter management.

| Type | Description | Apply Timing | Example Parameters |
|---|---|---|---|
| **Dynamic** | Can change without restart | `apply-immediately` works | `work_mem`, `log_min_duration_statement`, `enable_hashjoin` |
| **Static** | Requires instance reboot | Must reboot to take effect | `shared_buffers`, `max_connections`, `shared_preload_libraries` |

How to identify which type a parameter is:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [GROUP-NAME] \
  --query 'Parameters[?ParameterName==`shared_buffers`].{Name:ParameterName,ApplyType:ApplyType}'
```

The `ApplyType` field will be either `static` or `dynamic`.

### Apply Timing Options

When you modify a parameter group, you choose when the change takes effect:

| Option | Meaning | Safe? |
|---|---|---|
| `apply-immediately` | Dynamic params apply now. Static params wait for next reboot. | Yes for dynamic params |
| `pending-reboot` | Change is saved, applied on next reboot | Safest option |

**Pending changes** show up in the RDS console as "pending reboot" status. The instance keeps running with old values until you reboot.

### The Pending Reboot Warning

If you change a static parameter and don't reboot, your instance runs with the OLD value. The console shows a yellow warning icon. New DBAs miss this constantly.

```
Instance Status: available (pending-reboot)
                              ^
                              This means static params have not applied yet
```

---

## T3.2 Option Groups

Option groups predate Aurora and are primarily used for other engines (Oracle, SQL Server, MySQL). For PostgreSQL on RDS/Aurora, option groups have **very limited use** - they are mostly a placeholder.

```
Option Group Support by Engine:
  Oracle:     Full featured (many options)
  SQL Server: Full featured (many options)
  MySQL:      Some options
  PostgreSQL: Minimal (not commonly used)
```

PostgreSQL uses **extensions** (installed with `CREATE EXTENSION`) instead of option groups for additional features. You will still create an option group when provisioning - just accept the defaults.

---

## T3.3 Extensions

Extensions are add-on modules that extend PostgreSQL's capabilities. On RDS/Aurora, AWS controls which extensions are available and which versions of each.

### How Extensions Work

```
PostgreSQL Core
      |
      | CREATE EXTENSION foo;
      v
+-----------------+
|   Extensions    |
|-----------------|
|  pg_stat_statements  <- query performance stats
|  pgaudit             <- audit logging
|  pg_repack           <- online table maintenance
|  postgis             <- geospatial data
|  pgvector            <- vector similarity search
|  pg_tle              <- trusted language extensions
|  postgres_fdw        <- foreign data wrappers
+-----------------+
```

### shared_preload_libraries

Some extensions must be loaded at PostgreSQL startup. They go in `shared_preload_libraries` - a **static parameter** that requires a reboot.

```
shared_preload_libraries = 'pg_stat_statements,pgaudit,pg_tle'
                            ^                  ^       ^
                            Must list ALL extensions that need preload
                            Order matters for some extensions
```

After changing `shared_preload_libraries`:
1. Reboot the instance
2. Then run `CREATE EXTENSION [name];` in the database

### pg_stat_statements

Tracks execution statistics for all SQL statements. Essential for finding slow queries.

```sql
-- After enabling, query the view:
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Key columns:
| Column | Meaning |
|---|---|
| `query` | Normalized SQL text (literals replaced with $1, $2) |
| `calls` | How many times executed |
| `mean_exec_time` | Average milliseconds per call |
| `total_exec_time` | Total ms spent in this query |
| `rows` | Total rows returned |

### pgaudit

Provides detailed audit logging. Required for compliance (SOC 2, PCI-DSS, HIPAA).

```
Without pgaudit:         With pgaudit:
log_statement = 'ddl'   Logs: WHO ran WHAT on WHICH object
  -> basic logging       at WHAT TIME from WHERE
                         -> granular audit trail
```

Two logging modes:
- **Session auditing** - logs all statements for a session
- **Object auditing** - logs statements on specific tables/functions

### pg_repack

Reclaims dead space from tables and indexes without a full table lock. Use it instead of `VACUUM FULL` when you can't afford downtime.

```
VACUUM FULL:            pg_repack:
- Exclusive lock        - No exclusive lock (brief lock at the end)
- Table offline         - Table stays online
- Fast for small tables - Better for large production tables
```

### PostGIS

Adds geospatial types and functions. Used for location-based queries.

```sql
SELECT ST_Distance(
  ST_MakePoint(-73.9857, 40.7484),  -- Times Square
  ST_MakePoint(-87.6298, 41.8781)   -- Chicago
) AS distance_degrees;
```

### Extension Version Policy

AWS controls which extension versions are available on each PostgreSQL engine version. You cannot install an arbitrary extension version. Check availability:

```sql
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
WHERE name = 'pgvector';
```

---

## T3.4 pgvector for AI/ML Workloads

pgvector adds a `vector` data type to PostgreSQL. This lets you store and search mathematical representations (embeddings) of text, images, and other data.

### Why Vectors?

AI/ML models convert data into arrays of numbers called embeddings. Similar items have embeddings that are "close" in mathematical space.

```
"cat"  -> [0.21, -0.45, 0.83, ...]  (1536 numbers)
"dog"  -> [0.19, -0.41, 0.79, ...]  (close to cat)
"car"  -> [0.92,  0.13, -0.55, ...] (far from cat)
```

Similarity search finds records whose embeddings are closest to a query embedding.

### Distance Metrics

| Operator | Metric | Best for |
|---|---|---|
| `<->` | L2 (Euclidean) distance | General similarity |
| `<=>` | Cosine distance | Text similarity (OpenAI embeddings) |
| `<#>` | Negative inner product | Dot product similarity |

### Index Types

| Index | Algorithm | Build Time | Query Speed | Memory |
|---|---|---|---|---|
| None (exact) | Sequential scan | None | Slowest (exact) | None |
| IVFFlat | Inverted file | Fast | Fast (approximate) | Low |
| HNSW | Hierarchical Navigable Small World | Slow | Fastest (approximate) | High |

**When to use each:**
- No index: small tables (< 100K rows), need exact results
- IVFFlat: medium tables, memory-constrained, can afford approximate results
- HNSW: large tables, speed is critical, have memory budget

### RDS vs Aurora for pgvector

| Feature | RDS PostgreSQL | Aurora PostgreSQL |
|---|---|---|
| pgvector available | Yes | Yes |
| Optimized storage | No | Aurora Optimized Reads (io2) |
| Read replicas for search | Manual | Automatic with Aurora |
| Cost | Lower | Higher |

---

## T3.5 Trusted Language Extensions (TLE)

### The Problem TLE Solves

Standard PostgreSQL lets you write extensions in C. C extensions can crash the server, access the filesystem, and create security holes. AWS does not allow arbitrary C extensions on RDS.

TLE (pg_tle) provides a safe sandbox where you can write custom extensions in:
- SQL
- PL/pgSQL
- PL/Perl
- PL/v8 (JavaScript)

```
Standard C Extension           TLE Extension
+-------------------+          +-------------------+
| Written in C      |          | Written in SQL    |
| Can crash server  |          | Sandboxed         |
| Access filesystem |          | No OS access      |
| NOT allowed on RDS|          | ALLOWED on RDS    |
+-------------------+          +-------------------+
```

### TLE Lifecycle

```
1. Enable pg_tle in shared_preload_libraries
2. CREATE EXTENSION pg_tle;
3. SELECT pgtle.install_extension(...);   <- install your TLE
4. CREATE EXTENSION [your-tle-name];      <- activate in a database
5. Use your extension's functions
6. DROP EXTENSION [your-tle-name];        <- deactivate
7. SELECT pgtle.uninstall_extension(...); <- remove from pg_tle registry
```

---

## T3.6 Foreign Data Wrappers (FDW)

FDW lets you query a remote database as if it were a local table. The remote server can be another PostgreSQL, MySQL, S3, or any supported system.

### How FDW Works

```
Local RDS Instance                    Remote RDS Instance
+-------------------+                 +-------------------+
|                   |                 |                   |
| Foreign Table     | --- network --> | Real Table        |
| (local proxy)     |   SQL query     | (actual data)     |
|                   |                 |                   |
| postgres_fdw      |                 |                   |
+-------------------+                 +-------------------+
        ^
        |
  your application
  queries here
```

### Key Objects

| Object | What It Is | SQL Command |
|---|---|---|
| Extension | Enables FDW functionality | `CREATE EXTENSION postgres_fdw;` |
| Foreign Server | Defines the remote connection | `CREATE SERVER` |
| User Mapping | Maps local user to remote credentials | `CREATE USER MAPPING` |
| Foreign Table | Local proxy for a remote table | `CREATE FOREIGN TABLE` or `IMPORT FOREIGN SCHEMA` |

### Performance Considerations

FDW pushes down some operations to the remote server (predicate pushdown) but not all. Be aware:

- `WHERE` clauses on indexed columns often push down - efficient
- JOINs between local and foreign tables pull all foreign data first - can be slow
- Large result sets cross the network - watch bandwidth
- Each query to a foreign table opens a connection to the remote server

---

## T3.7 Engine Versions, Release Process, and Preview Environment

### Version Numbering

PostgreSQL uses major.minor versioning:

```
PostgreSQL 16.3
           ^  ^
           |  +-- Minor version (bug fixes, security patches)
           +-- Major version (new features, may break compatibility)
```

AWS RDS supports several major versions at any time. Minor versions lag slightly behind community releases (AWS tests them first).

### Release Process on RDS

```
Community PostgreSQL releases new version
         |
         | AWS tests compatibility (weeks to months)
         |
         v
AWS makes available on RDS (minor) or Preview Environment (major)
         |
         v
GA (Generally Available) on RDS
         |
         | Deprecated versions: AWS gives 12 months notice
         v
Auto-upgrade or instance termination
```

### Major vs Minor Upgrades

| | Minor Upgrade | Major Upgrade |
|---|---|---|
| Example | 16.2 -> 16.3 | 15 -> 16 |
| Downtime | Brief restart | Longer (minutes to hours) |
| Data compatibility | Always compatible | May need changes |
| Automatic | AWS can do it | You must initiate |
| Risk | Very low | Medium - test first |

### Aurora Version Tracks

Aurora has its own version track separate from RDS PostgreSQL:

```
Community PostgreSQL 16.x
         |
         +-- RDS PostgreSQL 16.x (community-aligned)
         |
         +-- Aurora PostgreSQL 16.x (Aurora-specific features added)
                  |
                  +-- Aurora Serverless v2 (autoscaling compute)
```

### Preview Environment

AWS runs a Preview Environment where you can test new major PostgreSQL versions before they reach GA. Use it to:
- Test your application against the next major version
- Validate extension compatibility
- Find breaking changes before they affect production

Preview environment databases are **not for production** - they may be deleted when the version reaches GA.

### End of Life Timeline

Each PostgreSQL major version has a community end-of-life date. AWS typically extends support beyond the community date through their Extended Support program (at additional cost).

```
PostgreSQL 12 Community EOL: Nov 2024
AWS Extended Support:        Available (extra $/month)

Check your instance versions now:
SELECT version();
```

| Version | Community EOL | AWS Standard Support End |
|---|---|---|
| PostgreSQL 13 | Nov 2025 | Jan 2026 |
| PostgreSQL 14 | Nov 2026 | Feb 2027 |
| PostgreSQL 15 | Nov 2027 | Feb 2028 |
| PostgreSQL 16 | Nov 2028 | Feb 2029 |
| PostgreSQL 17 | Nov 2029 | Feb 2030 |

> **Concept:** Always know your PostgreSQL version's EOL date. Upgrading on a deadline is stressful. Plan upgrades 6-12 months before EOL.
