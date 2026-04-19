# Runbook 03 - Performance Degradation Cascade

**Severity:** High - Application slow, multiple root causes
**Time to resolve:** 20-30 minutes
**Skills tested:** Performance tuning (Module 12), configuration (Module 04), MVCC/vacuum (Module 08), connection management (Module 06)

---

## Fix Path

### Triage: Identify all issues first

Before fixing anything, assess the full scope. In a cascade, fixing one thing without finding the others wastes time.

```bash
su - postgres
```

#### Check 1: Configuration

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW work_mem;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW random_page_cost;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW effective_cache_size;"
```

If shared_buffers is 32MB on a 4GB server, that is critically wrong. Note it.

#### Check 2: Connections

```bash
/usr/pgsql-16/bin/psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count DESC;"
```

If you see 50+ `idle in transaction` connections, that is a leak.

#### Check 3: Missing indexes

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname, relname, seq_scan, idx_scan FROM pg_stat_user_tables WHERE schemaname = 'app' ORDER BY seq_scan DESC;"
```

High seq_scan on large tables with low idx_scan means missing indexes.

#### Check 4: Table bloat

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT relname, n_live_tup, n_dead_tup, round(n_dead_tup::numeric / greatest(n_live_tup, 1) * 100, 1) AS dead_pct, last_autovacuum FROM pg_stat_user_tables WHERE schemaname = 'app' ORDER BY dead_pct DESC;"
```

High dead_pct with no recent autovacuum means vacuum is disabled or blocked.

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT relname, reloptions FROM pg_class WHERE relname = 'orders';"
```

If you see `autovacuum_enabled=false`, that is the problem.

### Fix 1 (Highest Priority): Kill the connection leak

Idle-in-transaction connections hold locks and prevent vacuum. Fix this first.

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND pid != pg_backend_pid();"
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"
```

The idle-in-transaction count should be 0 or near 0.

### Fix 2: Restore configuration

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET shared_buffers = '1GB';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET work_mem = '16MB';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET random_page_cost = 1.1;"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET effective_cache_size = '3GB';"
```

```bash
exit
```

Restart to apply shared_buffers:

```bash
systemctl restart postgresql-16
```

```bash
su - postgres
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

Expected: `1GB`

### Fix 3: Recreate missing indexes

```bash
/usr/pgsql-16/bin/psql -d appdb -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_id ON app.orders (customer_id);"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_status ON app.orders (status) WHERE status NOT IN ('delivered', 'cancelled');"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_order_items_order_id ON app.order_items (order_id);"
```

Always use `CONCURRENTLY` in production. It takes longer but does not lock the table.

### Fix 4: Fix table bloat

Re-enable autovacuum:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "ALTER TABLE app.orders RESET (autovacuum_enabled);"
```

Run vacuum manually since the table is already bloated:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "VACUUM ANALYZE app.orders;"
```

Verify dead tuples are cleaned:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'orders';"
```

Expected: n_dead_tup close to 0.

### Fix 5: Verify all fixes

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW work_mem;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT indexname FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'orders';"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction';"
```

```bash
exit
```

---

## Revision Concepts

**Q: In what order should you triage multiple issues?**
A: Fix blocking issues first: (1) connection leak (holds locks, blocks vacuum, consumes slots), (2) configuration (requires restart), (3) missing indexes (causes immediate performance impact), (4) table bloat (causes gradual degradation). The principle is: fix what blocks other fixes first.

**Q: Why use ALTER SYSTEM instead of editing postgresql.conf?**
A: ALTER SYSTEM writes to `postgresql.auto.conf`, which overrides `postgresql.conf`. This is safer during emergencies because you do not need to find and edit the correct line in a large config file. After the emergency, you should update `postgresql.conf` to match and reset `postgresql.auto.conf`.

**Q: Why CONCURRENTLY for index creation?**
A: Without CONCURRENTLY, CREATE INDEX takes a SHARE lock on the table, blocking all writes for the duration. On a large table, that could be minutes or hours. CONCURRENTLY builds the index in the background, only briefly locking at the start and end.
