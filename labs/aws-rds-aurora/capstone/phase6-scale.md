# Phase 6: Scale

## Objective

Demonstrate horizontal read scaling with Aurora reader replicas. This draws on skills from Tier 7 (Scaling, Integration, and Modern Patterns).

## Requirements

1. **Reader replica**
   - At least 1 reader instance in the cluster (you likely created this in Phase 4)
   - Instance identifier: `${CAPSTONE_CLUSTER_ID}-reader-1`

2. **Reader endpoint**
   - Verify the cluster reader endpoint resolves to your reader instance(s)
   - Reader endpoint format: `${CAPSTONE_CLUSTER_ID}.cluster-ro-XXXX.REGION.rds.amazonaws.com`

## Validation Criteria

- At least 1 reader instance exists in the cluster
- Reader endpoint DNS resolves successfully

## Hints

- If you already created a reader in Phase 4, this phase is mostly verification
- Check reader endpoint: `aws rds describe-db-clusters --query "DBClusters[0].ReaderEndpoint"`
- Test DNS: `dig +short YOUR-READER-ENDPOINT`
- If you need a refresher on read replicas, see T7 Build 01
- For load balancing across readers, see T7 Build 02

## Reference

If you get stuck, review: T7 Build 01-02.
