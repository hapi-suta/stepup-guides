# Lab: PostgreSQL Streaming Replication

The foundational PostgreSQL lab. You build a primary + standby from scratch,
learn every operational command, then survive production incidents on the cluster
you built.

## Objectives

By the end of this lab you can:

- Install PostgreSQL 16 from the PGDG repo on Debian/Ubuntu
- Configure streaming replication between two nodes
- Verify replication status using `pg_stat_replication` and `pg_stat_wal_receiver`
- Manually promote a standby and understand timeline implications
- Rejoin an old primary as a standby using `pg_rewind`
- Measure and interpret replication lag
- Survive 5 production incidents on the cluster you built

## Prerequisites

- `linux/fundamentals` (or equivalent comfort with SSH, systemctl, file editing)
- SSH access to 2 servers (provided by Happy)

## Infrastructure

See `infrastructure.yml` for server specs.

| Node | Role | Default port |
| ---- | ---- | ------------ |
| NODE1 | Primary | 5432 |
| NODE2 | Standby | 5432 |

## Phases

### Phase 1 - BUILD IT (~2 hours)

Follow the guides in `build/` in order (01 through 05). At the end, run
`build/verify.sh` to confirm your cluster is correctly set up. Do not proceed
to Phase 2 until verify passes.

### Phase 2 - USE IT (~1-2 hours)

Work through the exercises in `use/` in order. Complete the self-assessment
`checklist.md` when done. If you cannot answer every question confidently,
re-read the relevant BUILD guide.

### Phase 3 - SURVIVE IT (~3-5 hours across multiple sessions)

Tell Happy you are ready. He fires chaos scenarios against your cluster. You
get paged, diagnose, fix, and call for validation. 5 scenarios, each harder
than the last.

## Estimated total time

6-9 hours spread across 1-2 weeks. BUILD and USE in one session. SURVIVE across
multiple on-call windows.
