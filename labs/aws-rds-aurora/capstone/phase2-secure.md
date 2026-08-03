# Phase 2: Secure the Cluster

## Objective

Lock down your Aurora cluster following AWS security best practices. This draws on skills from Tier 2 (Security and Access).

## Requirements

1. **Encryption at rest**
   - Storage encryption must be enabled (this is set at creation time - if you missed it in Phase 1, you'll need to recreate)

2. **Encryption in transit (SSL/TLS)**
   - Force SSL connections via cluster parameter group
   - Set `rds.force_ssl = 1` in your custom parameter group

3. **Network isolation**
   - No instance should have `PubliclyAccessible = true`
   - Security group should only allow your IP on port 5432

4. **IAM authentication**
   - Enable IAM database authentication on the cluster

## Validation Criteria

- `StorageEncrypted` is `true`
- `rds.force_ssl` is `1` in the attached parameter group
- All instances have `PubliclyAccessible = false`
- `IAMDatabaseAuthenticationEnabled` is `true`

## Hints

- Storage encryption cannot be added after creation. If yours isn't encrypted, delete and recreate with `--storage-encrypted`
- To enable IAM auth: `aws rds modify-db-cluster --enable-iam-database-authentication`
- If you need a refresher on SSL enforcement, see T2 Build 03
- For IAM authentication setup, see T2 Build 04

## Reference

If you get stuck, review: T2 Build 01-06.
