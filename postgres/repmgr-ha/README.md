# Lab: PostgreSQL HA with repmgr

Build a 4-node PostgreSQL cluster managed by repmgr, learn every operational
command, then survive production incidents on the cluster you built.

## Objectives

By the end of this lab you can:

- Install and configure repmgr 5.4 alongside PostgreSQL 16
- Register a primary, two standbys, and a witness node in a repmgr cluster
- Perform planned switchovers with `repmgr standby switchover`
- Perform unplanned promotions with `repmgr standby promote`
- Rejoin failed nodes with `repmgr node rejoin --force-rewind`
- Add and remove nodes from a running cluster
- Configure and operate the repmgrd daemon for automatic failover
- Survive 5 production incidents on the cluster you built

## Prerequisites

- `postgres/streaming-replication` lab completed (you understand WAL, replication
  slots, pg_rewind, and manual promotion)
- SSH access to 4 servers (provided by Happy)

## Infrastructure

| Node  | Hostname     | Role      | Default port |
| ----- | ------------ | --------- | ------------ |
| NODE1 | pg-repmgr-1  | Primary   | 5432         |
| NODE2 | pg-repmgr-2  | Standby 1 | 5432         |
| NODE3 | pg-repmgr-3  | Standby 2 | 5432         |
| NODE4 | pg-repmgr-w  | Witness   | 5432         |

## Architecture

```
                         repmgrd
                        monitors
                            |
   NODE1 (primary)          |         NODE2 (standby 1)
  ┌─────────────────┐       |        ┌─────────────────┐
  │  PostgreSQL 16  │       |        │  PostgreSQL 16  │
  │  repmgr 5.4     │  streaming     │  repmgr 5.4     │
  │  repmgrd daemon ├──────WAL──────>│  repmgrd daemon │
  │  repmgr DB      │       |        │  hot_standby=on │
  └────────┬────────┘       |        └─────────────────┘
           │                |
           │  streaming     |         NODE3 (standby 2)
           │                |        ┌─────────────────┐
           │                |        │  PostgreSQL 16  │
           └───────WAL──────|──────>│  repmgr 5.4     │
                            |        │  repmgrd daemon │
                            |        │  hot_standby=on │
                            |        └─────────────────┘
                            |
                            |         NODE4 (witness)
                            |        ┌─────────────────┐
                            |        │  PostgreSQL 16  │
                            └───────>│  repmgr 5.4     │
                                     │  repmgrd daemon │
                                     │  quorum voter   │
                                     └─────────────────┘
```

The witness node does NOT participate in replication. It holds a copy of
the repmgr metadata and votes during failover elections. Its purpose is
to prevent split-brain when an even number of data nodes exist.

## Phases

### Phase 1 - BUILD IT (~3 hours)

Follow the guides in `build/` in order (01 through 07). At the end, run
`build/verify.sh` to confirm your cluster is correctly set up. Do not proceed
to Phase 2 until verify passes.

### Phase 2 - USE IT (~2-3 hours)

Work through the exercises in `use/` in order. Complete the self-assessment
`checklist.md` when done. If you cannot answer every question confidently,
re-read the relevant BUILD guide.

### Phase 3 - SURVIVE IT (~4-6 hours across multiple sessions)

Tell Happy you are ready. He fires chaos scenarios against your cluster. You
get paged, diagnose, fix, and call for validation. 5 scenarios, each harder
than the last.

## Estimated total time

9-12 hours spread across 1-2 weeks. BUILD and USE in one or two sessions.
SURVIVE across multiple on-call windows.
