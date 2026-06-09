# Lab: PostgreSQL Logical Replication

Table-level replication using the publish/subscribe model. You set up logical
replication between two independent PostgreSQL servers, learn to manage
publications and subscriptions, then survive production incidents unique to
logical replication.

## Objectives

By the end of this lab you can:

- Explain the difference between physical and logical replication
- Configure wal_level = logical and create publications
- Create subscriptions and verify initial data sync
- Add/remove tables, use row filters, and column lists
- Monitor logical replication with pg_stat_subscription and pg_stat_replication
- Diagnose stuck subscriptions and sequence gaps after cutover

## Prerequisites

- `module11-streaming-replication` (or equivalent understanding of WAL and replication slots)
- SSH access to 2 servers (provided by Happy)

## Infrastructure

See `infrastructure.yml` for server specs.

| Node | Role | Default port |
| ---- | ---- | ------------ |
| pg-suta-labs-1 | Publisher | 5432 |
| pg-suta-labs-2 | Subscriber | 5432 |

## Phases

### Phase 1 - BUILD IT (~40 min)

Follow `build/01-setup-publication.md`. At the end you will have a working
publication and subscription with live data flowing between the two nodes.

### Phase 2 - USE IT (~20 min)

Work through `use/01-logical-rep-exercises.md`. Covers adding/removing tables
from publications, row filtering (PG 15+), and column lists (PG 15+).

### Phase 3 - SURVIVE IT (~15 min per scenario)

Two chaos scenarios that hit every logical replication deployment:

1. `survive/01-subscription-stuck/` - Subscription stuck in initializing state
2. `survive/02-sequence-gap/` - Sequences not synced after cutover

## Estimated total time

2-3 hours in one session. BUILD and USE back-to-back, SURVIVE after a break.
