# Concepts - Instance Management

Reference documents that explain the theory and architecture behind PostgreSQL
instance creation, configuration, authentication, and lifecycle management.
Read these before or alongside the build guides to understand the WHY behind
each configuration choice.

## Documents

| Document | Topic | Description |
| -------- | ----- | ----------- |
| [instance-management.md](instance-management.md) | Instance Management | Cluster architecture, PGDATA internals, initdb deep dive, configuration hierarchy (postgresql.conf / conf.d / postgresql.auto.conf), pg_hba.conf authentication, server lifecycle (startup/shutdown/reload/restart), production best practices, and troubleshooting |

## Planned

The following concept documents will be added as the lab expands:

| Document | Topic |
| -------- | ----- |
| `connection-pooling.md` | PgBouncer architecture, pooling modes, sizing, monitoring |
| `ssl-tls.md` | Certificate management, TLS configuration, client certificate authentication |
| `roles-privileges.md` | Role hierarchy, GRANT/REVOKE patterns, least-privilege design, row-level security |
| `tablespaces.md` | When and how to use tablespaces, I/O isolation strategies |
