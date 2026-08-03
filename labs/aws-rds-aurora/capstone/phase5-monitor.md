# Phase 5: Monitor

## Objective

Set up observability so you can detect and diagnose issues before users notice. This draws on skills from Tier 6 (Performance and Monitoring).

## Requirements

1. **Performance Insights**
   - Enable Performance Insights on the writer instance
   - Default 7-day retention (free tier) is fine

2. **CloudWatch alarm**
   - Create at least one CloudWatch alarm for your cluster
   - Suggested: CPU utilization > 80% for 5 minutes
   - Alarm name should be discoverable (validate.sh searches for alarms on your cluster)

3. **Enhanced Monitoring**
   - Enable Enhanced Monitoring on the writer instance
   - Granularity: 60 seconds (minimum)
   - Requires an IAM role for monitoring (create or use existing `rds-monitoring-role`)

## Validation Criteria

- `PerformanceInsightsEnabled = true` on writer instance
- At least one CloudWatch alarm exists with dimension `DBClusterIdentifier = your-cluster`
- `MonitoringInterval > 0` on writer instance (Enhanced Monitoring active)

## Hints

- Enable PI: `aws rds modify-db-instance --enable-performance-insights`
- For Enhanced Monitoring, you need a role with `AmazonRDSEnhancedMonitoringRole` policy
- CloudWatch alarm dimension must reference your cluster ID for validate.sh to find it
- If you need a refresher on Performance Insights, see T6 Build 03
- For CloudWatch alarms, see T6 Build 05
- For Enhanced Monitoring, see T6 Build 04

## Reference

If you get stuck, review: T6 Build 03-06.
