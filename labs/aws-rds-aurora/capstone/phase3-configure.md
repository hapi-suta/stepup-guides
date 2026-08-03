# Phase 3: Configure Extensions and Parameters

## Objective

Set up a custom parameter group with production-appropriate settings and enable key extensions. This draws on skills from Tier 3 (Configuration and Extensions).

## Requirements

1. **Custom cluster parameter group**
   - Create a custom Aurora PostgreSQL 16 cluster parameter group
   - Name it something meaningful (e.g., `capstone-aurora-pg16`)
   - Attach it to your cluster (replaces the default)

2. **pg_stat_statements**
   - Add `pg_stat_statements` to `shared_preload_libraries`
   - This requires a cluster reboot to take effect

3. **Production parameters** (recommended but not graded)
   - `log_min_duration_statement = 1000` (log queries > 1 second)
   - `log_connections = 1`
   - `log_disconnections = 1`

## Validation Criteria

- Cluster uses a custom parameter group (not `default.aurora-postgresql16`)
- `shared_preload_libraries` includes `pg_stat_statements`

## Hints

- Modifying `shared_preload_libraries` requires a reboot: `aws rds reboot-db-instance`
- Wait for status "available" after reboot before proceeding
- If you need a refresher on parameter groups, see T3 Build 01
- For extensions management, see T3 Build 02

## Reference

If you get stuck, review: T3 Build 01-03.
