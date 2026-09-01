# Concepts: how the Patroni HA system works

This is the mental model behind the lab. SutaBot teaches it as a conversation,
one useful idea at a time. It can slow down, use an analogy, draw the request path,
or revisit a concept when the learner is stuck later. This chapter is tutor context
and a learner reference; it is not fourteen questions that must be repeated back.

There are no server commands in Concepts. In BUILD, the learner constructs each
layer on eight clean servers and proves it with independent validation.

## The workplace problem

Your company uses Mattermost. A message is useful only if Mattermost can store it
and read it again. Its durable data lives in PostgreSQL, so a failed PostgreSQL
writer can stop the workday even while the Mattermost web process is still running.

The goal is not “keep every server alive.” Servers fail. The goal is to keep a safe
database writer available after an expected database-node failure, then prove that
Mattermost can still use the same database endpoint.

- **Healthy:** the service works and the expected redundancy is present.
- **Degraded:** the service works, but a failure removed some protection.
- **Outage:** the required service is unavailable or unsafe.

A failed replica can leave users unaffected while making the system degraded. A
DBA still repairs it because the next failure may become an outage.

## Picture the complete system

```text
                         coordination
              ┌────────── etcd quorum ──────────┐
              │        dcs-1 dcs-2 dcs-3        │
              └──────────────┬──────────────────┘
                             │ leader lease / state
                             ▼
Mattermost ──► HAProxy ──► PostgreSQL + Patroni writer
mattermost-1  db-router-1       pg-ha-1/2/3
                                   │
                                   └── WAL ──► two replicas
```

The eight stable roles describe responsibility, not current health:

| Role | Responsibility |
|---|---|
| `dcs-1`, `dcs-2`, `dcs-3` | Form the etcd distributed configuration store |
| `pg-ha-1`, `pg-ha-2`, `pg-ha-3` | Run PostgreSQL under Patroni management |
| `db-router-1` | Give clients one HAProxy address for the current writer |
| `mattermost-1` | Exercise the database through a real application workload |

Addresses can change when infrastructure is replaced. Stable role names keep the
same instruction and validator tied to the intended job.

## etcd: agreement before leadership

Patroni nodes need one shared answer to a critical question: **which member holds
permission to lead?** etcd is the distributed configuration store, or DCS, that
holds this coordination state. It does not store Mattermost tables or replicate
PostgreSQL rows.

Three etcd members use majority agreement. A majority of three is two:

```text
3 available → can agree
2 available → can still agree
1 available → cannot safely change shared truth
```

Three members therefore tolerate one unavailable member, not two. Refusing a new
decision without quorum is safer than letting separated minorities create competing
leaders.

Each member needs a unique name and data directory. Peer and client traffic uses
TLS. A certificate is valid only for names and IP addresses in its subject
alternative names. Connecting to `127.0.0.1` with a certificate issued only for a
private node IP must fail; use a covered endpoint or issue the correct certificate,
never disable verification.

An etcd snapshot protects DCS state, but recovery is a deliberate cluster operation.
Restored members must not reuse identities or accidentally join stale state.

## PostgreSQL: data movement and durability

PostgreSQL records changes in the write-ahead log, or **WAL**, before changed data
pages are written. A primary streams WAL to standby servers; each standby replays
those records to reproduce the primary's changes.

```text
client commit → primary WAL → standby receives WAL → standby replays WAL
```

**Received**, **replayed**, and **committed** are not interchangeable. Replication
lag shows how far a standby is behind, and a failover candidate must be current
enough for the durability promise the business expects.

Streaming replication is asynchronous by default. A commit can be acknowledged
before a standby confirms it, usually reducing latency but risking the newest
acknowledged changes after primary failure. Synchronous replication waits for the
configured standby acknowledgment, improving durability while adding response time
and potentially blocking writes when no suitable synchronous standby is reachable.

Replication is not a backup: a mistaken delete can be replicated perfectly.
Backups, WAL retention, and restore testing solve different problems.

After failover, the old primary has a divergent history. It cannot simply resume as
writer. Patroni can use `pg_rewind` when data checksums or `wal_log_hints` prepared
the cluster; otherwise a new base backup may be required.

## Patroni: safe role management

Patroni is the HA manager around PostgreSQL. Every member repeatedly:

1. observes local PostgreSQL state;
2. reads shared DCS state;
3. renews or competes for a time-limited leader lease;
4. starts, follows, promotes, demotes, or rewinds PostgreSQL under cluster rules.

Leadership is a renewable lease, not a permanent flag. If renewal stops, the lease
can expire and an eligible replica can be promoted. TTL, loop wait, and retry
timeout trade detection speed against sensitivity to brief delays.

Patroni coordinates promotion; it does not remove the need for fencing. “A new
leader exists” and “the old leader cannot write” are separate facts to prove.

Patroni's role-aware REST endpoints distinguish the current primary from replicas.
An open PostgreSQL port only proves a listener answered. A successful `/primary`
response means Patroni currently considers that member primary. Neither alone
proves Mattermost continuity.

Bootstrap DCS values seed the cluster during initialization. Editing them after the
cluster exists does not automatically change live dynamic configuration. Daily
changes use Patroni's supported dynamic-configuration path and must be observed on
the members.

## HAProxy: one stable writer address

Mattermost connects to one HAProxy frontend instead of discovering the primary.
HAProxy checks each Patroni `/primary` endpoint and makes only the current writer
eligible in the writer backend.

```text
before: Mattermost → HAProxy → pg-ha-1 (primary)
after:  Mattermost → HAProxy → pg-ha-3 (new primary)
```

Role-aware HTTP checks are stronger than “port 5432 is open,” because replicas may
accept read-only connections while remaining ineligible for application writes.
Check intervals and rise/fall thresholds affect how quickly routing changes.

Existing connections do not teleport during failover. They break, then the
application or pool reconnects through HAProxy. The stable address helps new
connections find the new writer.

This lab has one HAProxy node. Losing `db-router-1` still breaks the application
database path even when PostgreSQL is healthy.

## Mattermost: prove the user path

Mattermost proves the path the business actually uses:

```text
person → Mattermost → connection pool → HAProxy → PostgreSQL writer
                                      ← result / committed message
```

A continuity proof records a message before failure, confirms it remains readable
after failover, and commits another message through the unchanged HAProxy endpoint.
This distinguishes database topology health from application usefulness.

The single `mattermost-1` node is also a single point of failure. This lab teaches
database HA with a Mattermost workload, not Mattermost application HA.

## Failure, outage and degraded service

Think in impact and evidence, not merely process status:

| Event | Likely state | What must be proved |
|---|---|---|
| One replica stops | Degraded | Writer works; another replica is current; redundancy returns |
| Current primary stops | Interruption, then recovery or outage | New writer; old writer fenced; app writes recover |
| One etcd member stops | Degraded | Two-member quorum still commits; member safely returns |
| Two etcd members stop | Coordination unavailable | No competing leader; DCS recovery follows runbook |
| HAProxy stops | Application DB-path outage | Database may be healthy; router recovers |
| Mattermost stops | Application outage | Database health is separate; application recovers |
| Replica falls far behind | Degraded / unsafe candidate | Cause, WAL availability, recovery, eligibility |

A planned **switchover** moves leadership while leader and target are healthy. An
unplanned **failover** responds to losing the leader. Switchover can check readiness
and choose a safe target; failover is incident recovery with greater uncertainty.

## Build order

```text
infrastructure handoff
  → etcd identity, TLS and quorum
  → PostgreSQL filesystems and replication prerequisites
  → Patroni configuration and cluster bootstrap
  → replicas and rewind readiness
  → HAProxy role-aware writer routing
  → Mattermost database and application path
```

BUILD gives one role, one user, one action, and one expected observation at a time.
When a dependency fails, SutaBot diagnoses actual server evidence and gives
progressive help; it does not perform the assessed configuration.

## What you will prove

By the end of CBUSI, the learner can:

- explain the responsibility and boundary of all five products;
- construct the stack from eight clean, connected servers;
- prove three-member etcd health and majority behavior;
- prove exactly one PostgreSQL writer and two usable replicas;
- explain WAL, lag, async/sync trade-offs, and rewind readiness;
- perform switchover, dynamic configuration, restart, replica maintenance, snapshot,
  and application continuity checks;
- diagnose injected primary, replica, DCS, routing, lag, and application failures;
- recover without creating two writers or hiding lost redundancy;
- defend RPO, RTO, fencing, backup, routing, and single-point-of-failure decisions.

When the learner is ready, BUILD begins with the infrastructure handoff and first
etcd member. Understanding is revisited through decisions and evidence; it is not
certified by repeating this chapter back to the tutor.

## Official source map

- PostgreSQL 16: [warm standby and streaming replication](https://www.postgresql.org/docs/16/warm-standby.html), [replication settings](https://www.postgresql.org/docs/16/runtime-config-replication.html), and [`pg_rewind`](https://www.postgresql.org/docs/16/app-pgrewind.html).
- Patroni: [configuration](https://patroni.readthedocs.io/en/latest/yaml_configuration.html), [dynamic configuration](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html), and [REST API](https://patroni.readthedocs.io/en/latest/rest_api.html).
- etcd 3.6: [transport security](https://etcd.io/docs/v3.6/op-guide/security/) and [operations/disaster recovery](https://etcd.io/docs/v3.6/op-guide/).
- HAProxy: [active HTTP and TCP health checks](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/reliability/health-checks/).
