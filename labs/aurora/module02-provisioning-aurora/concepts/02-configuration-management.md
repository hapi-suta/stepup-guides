# Concepts: Configuration Management
## Module 02 - Provisioning Aurora (CLI + Console)

This document explains how Aurora PostgreSQL handles configuration. If you have experience managing `postgresql.conf` on a self-managed PostgreSQL server, this will show you how the same concepts translate to Aurora.

---

## How Parameter Groups Replace postgresql.conf

On a self-managed PostgreSQL server, you edit `postgresql.conf` directly:

```
# /etc/postgresql/16/main/postgresql.conf
shared_buffers = 256MB
work_mem = 64MB
log_statement = 'all'
```

On Aurora, you cannot SSH into the server. You cannot edit `postgresql.conf`. Instead, AWS provides parameter groups - a web and CLI interface for changing the same settings.

```
Self-managed PostgreSQL:
  You -> vi postgresql.conf -> reload or restart PostgreSQL

Aurora PostgreSQL:
  You -> aws rds modify-db-cluster-parameter-group -> Aurora applies changes
```

The parameter names are identical. `work_mem` is still `work_mem`. `log_statement` is still `log_statement`. The only difference is how you change them.

### Where Do Parameters Live in Aurora?

Aurora has two levels of parameter groups:

```
Cluster Parameter Group (most settings go here)
  |
  +-- log_statement = 'all'
  +-- work_mem = 65536
  +-- timezone = 'UTC'
  +-- rds.force_ssl = 1
  |
  +-- Instance A: DB Parameter Group (overrides, if any)
  |     +-- (usually no overrides)
  |
  +-- Instance B: DB Parameter Group (overrides, if any)
        +-- (usually no overrides)
```

Most settings belong in the cluster parameter group. Instance-level parameter groups are for rare cases where one instance needs a different setting (e.g., a reader dedicated to analytics might have a higher `work_mem`).

---

## Static vs Dynamic Parameters

Every parameter has an `ApplyType` that controls when changes take effect.

### Dynamic Parameters

Dynamic parameters take effect immediately (or within a few seconds) after you change them. No reboot required.

Examples of dynamic parameters:
| Parameter | What It Controls | Default |
|-----------|-----------------|---------|
| `work_mem` | Memory per sort/hash operation | 4 MB |
| `log_statement` | Which SQL statements to log | `none` |
| `log_min_duration_statement` | Log queries slower than N ms | `-1` (off) |
| `statement_timeout` | Kill queries longer than N ms | `0` (off) |
| `idle_in_transaction_session_timeout` | Kill idle-in-transaction sessions | `0` (off) |

When you change a dynamic parameter, Aurora applies it to new sessions immediately. Existing sessions may or may not see the change depending on the specific parameter.

### Static Parameters

Static parameters require a reboot to take effect. These are settings that PostgreSQL reads only at startup.

Examples of static parameters:
| Parameter | What It Controls | Default |
|-----------|-----------------|---------|
| `shared_buffers` | Main memory cache for data pages | Formula based on instance memory |
| `shared_preload_libraries` | Extensions loaded at startup | `pg_stat_statements` (Aurora default) |
| `max_connections` | Maximum concurrent connections | Formula based on instance memory |
| `max_worker_processes` | Maximum background worker processes | `8` |

When you change a static parameter, the status changes to `pending-reboot`. The old value stays active until you reboot the instance.

```
Change work_mem (dynamic):
  modify-db-cluster-parameter-group -> takes effect in seconds -> done

Change shared_preload_libraries (static):
  modify-db-cluster-parameter-group -> status: pending-reboot -> reboot instance -> takes effect
```

### How to Check if a Parameter is Static or Dynamic

**In your terminal** (local machine):

```
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name default.aurora-postgresql16 \
  --query "Parameters[?ParameterName=='work_mem'].{Name:ParameterName,ApplyType:ApplyType}" \
  --output table
```

The `ApplyType` field shows `static` or `dynamic`.

---

## Default Parameter Group vs Custom

### The Default Parameter Group

Every Aurora cluster starts with a default parameter group:

- Cluster level: `default.aurora-postgresql16`
- Instance level: `default.aurora-postgresql16`

The default parameter group has two important limitations:

1. **You cannot modify it.** If you try to change any parameter in the default group, AWS returns an error.
2. **All clusters using the same engine version share it.** Changing it (if you could) would affect every cluster.

### Why You Need a Custom Parameter Group

To tune any setting, you must:

1. Create a custom parameter group
2. Modify the parameters you want
3. Attach the custom group to your cluster (or instance)
4. Reboot if you changed any static parameters

```
Default group (read-only):
  default.aurora-postgresql16
    work_mem = 4096 (cannot change)

Custom group (your group):
  devops-lab-cluster-params
    work_mem = 65536 (you set this)
    log_statement = 'all' (you set this)
    everything else = inherited from engine defaults
```

Parameters you do not explicitly set in your custom group use the engine default values. You only need to set the parameters you want to change.

---

## Common Parameters to Tune

### max_connections

Controls how many clients can connect simultaneously.

- **Default:** Aurora calculates this based on instance memory. For db.t3.medium, it is around 420.
- **When to change:** When your application needs more connections, or when you want to limit connections to protect the database.
- **Apply type:** Static (requires reboot)
- **Warning:** Setting this too high wastes memory. Each connection uses about 5-10 MB of RAM. 1000 connections on a db.t3.medium (4 GB RAM) will cause memory pressure.

```
Instance class    Default max_connections (approximate)
db.t3.medium      420
db.r6g.large      830
db.r6g.xlarge     1660
db.r6g.2xlarge    3320
```

> **Best practice:** Use a connection pooler (like PgBouncer or RDS Proxy) instead of increasing max_connections. A pooler lets thousands of application threads share a small number of database connections.

### shared_buffers

The main memory cache for PostgreSQL data pages.

- **Default:** Aurora calculates this as a fraction of instance memory (typically 75% of available memory, which is higher than the standard PostgreSQL recommendation of 25%)
- **When to change:** Almost never on Aurora. AWS has tuned this formula for Aurora's storage architecture. Changing it can hurt performance.
- **Apply type:** Static (requires reboot)

> **Important:** On Aurora, shared_buffers behaves differently than on self-managed PostgreSQL. Aurora's storage layer has its own caching, so the shared_buffers formula is optimized for that architecture. Trust the default unless you have Aurora-specific tuning guidance from AWS.

### work_mem

Memory allocated per sort or hash operation within a query.

- **Default:** 4 MB (4096 KB)
- **When to change:** When queries with ORDER BY, GROUP BY, DISTINCT, or hash joins are slow and using disk-based sorts
- **Apply type:** Dynamic (no reboot needed)
- **Warning:** This is per-operation, not per-connection. A complex query with 5 sorts uses 5 x work_mem. With 100 connections running such queries, that is 500 x work_mem.

```
Conservative: 16 MB  (16384)
Moderate:     64 MB  (65536)
Aggressive:   256 MB (262144)  <- only on memory-optimized instances
```

### log_statement

Controls which SQL statements are written to the PostgreSQL log.

- **Default:** `none` (nothing logged)
- **Options:** `none`, `ddl`, `mod`, `all`
- **Apply type:** Dynamic
- **Recommendation:** Use `ddl` or `mod` in production. Use `all` only for debugging (it generates a lot of log data).

| Value | What Gets Logged |
|-------|-----------------|
| `none` | Nothing |
| `ddl` | CREATE, ALTER, DROP statements |
| `mod` | DDL + INSERT, UPDATE, DELETE |
| `all` | Every SQL statement including SELECT |

### log_min_duration_statement

Logs any query that takes longer than the specified number of milliseconds.

- **Default:** `-1` (disabled)
- **Recommended:** `1000` (log queries taking more than 1 second)
- **Apply type:** Dynamic
- **Use case:** Finding slow queries without logging everything

This is one of the most useful parameters for performance troubleshooting. Set it to 1000 in development and 5000 in production.

### rds.force_ssl

Forces all connections to use SSL encryption.

- **Default:** `0` (SSL optional)
- **Recommended:** `1` (SSL required)
- **Apply type:** Dynamic
- **Where:** Cluster parameter group

When set to `1`, any connection attempt without SSL is rejected with: `FATAL: no pg_hba.conf entry for host ... SSL off`.

### timezone

Sets the default timezone for the database.

- **Default:** `UTC`
- **Apply type:** Dynamic
- **Recommendation:** Keep it as UTC. Convert to local time in your application, not the database.

---

## How to View Current Settings

You have three ways to check what values are actually active on a running cluster.

### Method 1 - SHOW Command in psql

**In psql** (connected to any endpoint):

```sql
SHOW work_mem;
```

Output:
```
 work_mem
----------
 4MB
(1 row)
```

This shows the current session value. If you changed the parameter but have not reconnected, you may see the old value.

### Method 2 - pg_settings System View

**In psql** (connected to any endpoint):

```sql
SELECT name, setting, unit, source, context
FROM pg_settings
WHERE name = 'work_mem';
```

Output:
```
   name   | setting | unit |       source       | context
----------+---------+------+--------------------+---------
 work_mem | 4096    | kB   | configuration file | user
(1 row)
```

The columns tell you:
- `setting` - the current value (in the unit shown)
- `unit` - the unit (kB, MB, ms, s, etc.)
- `source` - where this value came from (`configuration file` means parameter group, `default` means engine default)
- `context` - when changes take effect (`user` = dynamic, `postmaster` = requires restart)

### Method 3 - Query Multiple Parameters at Once

**In psql** (connected to any endpoint):

```sql
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'max_connections',
    'shared_buffers',
    'work_mem',
    'log_statement',
    'log_min_duration_statement',
    'timezone'
)
ORDER BY name;
```

This gives you a quick overview of the most important settings.

### Method 4 - AWS CLI

**In your terminal** (local machine):

```
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --source user \
  --query "Parameters[*].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}" \
  --output table
```

The `--source user` flag shows only parameters you have explicitly changed. Without it, you see hundreds of engine defaults.

---

## Parameter Change Workflow

Here is the complete workflow for changing a parameter on an Aurora cluster:

```
1. Decide which parameter to change
   |
2. Check if it is static or dynamic
   |
   +-- Dynamic: proceed, no reboot needed
   +-- Static: plan a maintenance window for the reboot
   |
3. Check if it belongs in the cluster or instance parameter group
   |
   +-- Most settings: cluster parameter group
   +-- Instance-specific overrides: DB parameter group
   |
4. Modify the parameter group
   aws rds modify-db-cluster-parameter-group ...
   |
5. Verify the change
   +-- Dynamic: connect with psql and run SHOW
   +-- Static: check parameter group status (pending-reboot)
   |
6. If static: reboot the instance
   aws rds reboot-db-instance ...
   |
7. Verify after reboot
   Connect with psql and run SHOW
```

---

## Common Mistakes

1. **Modifying the default parameter group.** You cannot. Create a custom one instead.

2. **Forgetting to reboot after changing a static parameter.** The console shows `pending-reboot` as a warning, but CLI users often miss this. Always check the parameter group status after changes.

3. **Setting shared_buffers manually on Aurora.** The default formula is tuned for Aurora's architecture. Overriding it usually makes things worse.

4. **Setting work_mem too high without calculating total memory usage.** If you set work_mem to 256 MB and have 200 connections each running complex queries, that is potentially 50+ GB of RAM just for sorts.

5. **Using log_statement = 'all' in production.** This generates enormous log volumes and can impact performance. Use `log_min_duration_statement` instead to capture only slow queries.

6. **Changing cluster parameter group but checking the instance parameter group** (or vice versa). Make sure you are looking at the right level.

---

## Summary

| Concept | Key Point |
|---------|-----------|
| Parameter groups replace postgresql.conf | Same parameter names, different management interface |
| Cluster parameter group | Applies to all instances - put most settings here |
| DB parameter group | Per-instance overrides - rarely needed |
| Dynamic parameters | Take effect immediately, no reboot |
| Static parameters | Require instance reboot to take effect |
| Default parameter group | Read-only - you must create a custom group to tune settings |
| SHOW command | Check current session value in psql |
| pg_settings view | Check value, unit, source, and context |
| --source user | CLI flag to see only parameters you changed |

**Next:** Start [Build 01 - Create Aurora Cluster (Console)](../build/01-create-aurora-cluster-console.md).
