# Concepts: understand the Patroni system

You are the database engineer for a company that uses Mattermost. People must be
able to post messages even when an expected database server fails. Before touching
a server, build the mental model you will use to construct and troubleshoot the
system.

There are no terminal commands in Concepts. BUILD introduces them one at a time.

## 1. Why high availability exists

**Definition:** High availability is a system's ability to keep providing its
required service when an expected component fails.

The service here is safe PostgreSQL reads and writes for Mattermost. A prepared
replica can replace a failed primary. High availability does not prevent every
outage and does not replace backups.

Check yourself: what service must remain available when one database server fails?

## 2. Meet the eight roles

**Definition:** A role is the responsibility assigned to a server.

| Roles | Responsibility |
|---|---|
| `dcs-1`, `dcs-2`, `dcs-3` | Maintain shared coordination state in etcd |
| `pg-ha-1`, `pg-ha-2`, `pg-ha-3` | Run PostgreSQL under Patroni |
| `db-router-1` | Provide one stable HAProxy writer endpoint |
| `mattermost-1` | Run the application workload |

Stable role names remain meaningful when cloud addresses change. A role name does
not prove its service is healthy.

Check yourself: name the four groups and the job of each group.

## 3. Failure versus outage

**Definition:** A failure is a component that stops working. An outage is loss of
the required service.

One failed replica reduces redundancy but may not stop Mattermost. The DBA still
repairs it because another failure could cause an outage.

Check yourself: why repair a replica when users see no outage?

## 4. The distributed configuration store

**Definition:** A distributed configuration store, or **DCS**, keeps small pieces
of shared coordination state consistently across several members.

Patroni uses etcd as its DCS. etcd records facts such as the current leader lock.
It does not contain Mattermost tables, copy PostgreSQL rows, or replace backups.

Check yourself: what does etcd store, and what does it not store?

## 5. Quorum protects one shared truth

**Definition:** Quorum is the minimum majority of voting members required to
approve a change.

The majority of three is two. Two reachable etcd members can approve an update
when the third fails. One isolated member cannot safely create another truth.

```text
2 of 3 votes = quorum       1 of 3 votes = no quorum
```

Check yourself: how many failures can a three-member etcd cluster tolerate?

## 6. Patroni leadership is a renewable lease

**Definition:** A leader lease is time-limited DCS state granting one Patroni
member leadership while that member continues renewing it.

Only one member owns the lease. If renewal stops, it can expire and eligible
members can hold an election. Faster timing is not automatically safer.

Check yourself: why use a renewable lease instead of a permanent leader flag?

## 7. PostgreSQL copies changes through WAL

**Definition:** Write-ahead log, or **WAL**, is PostgreSQL's ordered record of
changes written before changed data pages. Streaming replication sends WAL from a
primary to replicas, where it is replayed.

```text
Mattermost write → primary WAL ─┬→ replica 1 replays it
                                └→ replica 2 replays it
```

Replication prepares a replacement writer but is not an independent backup.

Check yourself: trace one committed change from primary to replica using WAL.

## 8. Asynchronous and synchronous replication

**Definition:** Asynchronous replication may acknowledge a commit before a replica
confirms it. Synchronous replication waits for the configured replica
acknowledgment before acknowledging the commit.

Asynchronous operation usually adds less latency but may lose the newest
acknowledged changes after failure. Synchronous operation strengthens durability
but can block writes when no eligible synchronous replica exists.

Check yourself: what latency-versus-durability trade-off changes between the modes?

## 9. What Patroni manages

**Definition:** Patroni is a PostgreSQL high-availability manager that uses a DCS
to coordinate leadership, configure PostgreSQL, and manage promotion and replicas.

Patroni repeatedly observes PostgreSQL and DCS state, then applies the safe local
role. It cannot coordinate safely without suitable DCS access and configuration.

Check yourself: what does Patroni manage, and which service does it depend on?

## 10. Patroni reports role-aware health

**Definition:** Patroni's REST application programming interface is an HTTP
interface that answers health questions about a member's current role and state.

All three PostgreSQL ports might accept connections, but only one node may receive
writes. `/primary` succeeds only for the current primary. It does not prove the
whole application is healthy.

Check yourself: why is an open PostgreSQL port weaker evidence than `/primary`?

## 11. HAProxy provides the stable writer address

**Definition:** HAProxy is a proxy that accepts a client connection and selects an
eligible backend using health checks.

Mattermost connects to one frontend. HAProxy lists all PostgreSQL nodes as backends
but routes writes only to the backend whose Patroni `/primary` check succeeds.

```text
Mattermost → HAProxy → current primary
```

The application address stays stable during switchover. This lab's single HAProxy
server remains a single point of failure.

Check yourself: what stays stable, and what changes behind HAProxy?

## 12. Trace one Mattermost message

**Definition:** An application path is the complete chain of components required
to serve one user action.

```text
User → Mattermost → HAProxy → PostgreSQL primary → WAL → replicas
```

A database-only check can miss a broken Mattermost process, credential, or router.

Check yourself: trace a posted message through every component.

## 13. State the honest availability boundary

**Definition:** An availability boundary states which service and failure set a
design is proven to tolerate.

This lab protects the PostgreSQL writer against selected database-node failures.
The single HAProxy and Mattermost nodes remain unprotected. It demonstrates
database HA with a workload, not whole-application HA.

Check yourself: which part is HA, and which roles remain single points of failure?

## 14. Build in dependency order

**Definition:** Dependency order arranges work so every required input exists
before the dependent component starts.

```text
etcd → PostgreSQL → Patroni → HAProxy → Mattermost
```

Starting everything at once hides which unfinished layer caused a failure. BUILD
validates each boundary before adding the next one.

Final check: explain one dependency between each adjacent pair.
