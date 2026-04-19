# Module 18 - Google Cloud SQL for PostgreSQL

Deploying and managing PostgreSQL on Google Cloud SQL.

## Structure

### BUILD Guides (build/)

| Guide | Title | Duration |
|---|---|---|
| 01 | Cloud SQL Instance Setup | 30 min |
| 02 | High Availability | 20 min |
| 03 | Backup and Recovery | 30 min |
| 04 | Monitoring and Logging | 25 min |
| 05 | Security and Networking | 30 min |

### USE Exercises (use/)

| Exercise | Title | Duration |
|---|---|---|
| 01 | Provision and Connect | 15 min |
| 02 | Database Flags | 15 min |
| 03 | Backup and Restore | 20 min |
| 04 | Read Replicas | 20 min |
| 05 | Query Insights | 20 min |
| 06 | IAM Authentication | 15 min |

### SURVIVE Scenarios (survive/)

| Scenario | Incident | Duration |
|---|---|---|
| 01 | Authorized Networks Lockout | 10 min |
| 02 | Storage Full | 10 min |
| 03 | HA Failover | 10 min |
| 04 | Flag Misconfigured | 10 min |
| 05 | SSL Certificate Expired | 10 min |
| 06 | Connection Exhaustion | 10 min |
| 07 | Backup Disabled | 10 min |
| 08 | Proxy Connection Failure | 10 min |

### Concepts (concepts/)

- `gcp-cloudsql.md` - Architecture, HA, Auth Proxy, IAM, backups, networking, cost, migration

## Prerequisites

- GCP account with billing enabled
- gcloud CLI installed and authenticated
- psql client installed
- Cloud SQL Auth Proxy binary

## Topics Covered

- Cloud SQL instance creation and configuration
- Database flags (postgresql.conf management)
- Regional HA with automatic failover
- Automated backups, PITR, cross-region backup
- Cloud SQL Auth Proxy
- IAM database authentication
- Private IP, authorized networks, SSL/TLS
- CMEK encryption
- Cloud Monitoring, Query Insights, Cloud Logging
- Read replicas (same-region and cross-region)
- pgAudit integration

## Status

Built - ready for testing on live GCP environment.
