# Phase 7: Operate

## Objective

Set up audit logging and log exports for compliance and operational visibility. This draws on skills from Tier 8 (Operations at Scale).

## Requirements

1. **pgaudit extension**
   - Add `pgaudit` to `shared_preload_libraries` in your custom parameter group
   - Set `pgaudit.log = 'ddl,role'` (at minimum)
   - Reboot the cluster for changes to take effect

2. **CloudWatch Logs export**
   - Enable PostgreSQL log export to CloudWatch Logs
   - At minimum, export the `postgresql` log type
   - Modify the cluster: `--enable-cloudwatch-logs-exports '["postgresql"]'`

## Validation Criteria

- `shared_preload_libraries` includes `pgaudit`
- `pgaudit.log` parameter is set (not empty/default)
- Cluster has `postgresql` in `EnabledCloudwatchLogsExports`

## Hints

- `shared_preload_libraries` should now contain both `pg_stat_statements` AND `pgaudit`
- After modifying the parameter group, reboot: `aws rds reboot-db-instance`
- Wait for "available" before running validate.sh
- If you need a refresher on pgaudit, see T8 Build 02
- For CloudWatch log exports, see T8 Build 03

## Reference

If you get stuck, review: T8 Build 01-04.
