# repmgr and High Availability

## Why This Module Matters

Streaming replication keeps a standby in sync with the primary. But it does not watch
for failures. It does not decide when to promote. It does not reconfigure other nodes
to follow the new primary. By itself, replication is just data movement - not high
availability.

repmgr is the tool that fills that gap. It adds the management layer on top of streaming
replication: it monitors, it decides, it acts. This module is about understanding what
repmgr does, why it makes the decisions it makes, and where it can be trusted to act
automatically versus where you still need a human involved.

---

## What repmgr Is

repmgr (Replication Manager) is an open-source PostgreSQL extension and daemon that
manages replication clusters. It does three things:

1. **Tracks cluster state** - knows which nodes exist, their roles, and their status,
   stored in metadata tables inside PostgreSQL itself.

2. **Automates administrative tasks** - clone a standby, register nodes, perform
   controlled switchovers, rebuild failed nodes.

3. **Detects and responds to failures** - via the `repmgrd` daemon, it monitors the
   primary and can promote a standby automatically when the primary fails.

repmgr does not replace streaming replication. It sits on top of it. The WAL still
flows the same way - repmgr just adds the brain that watches what is happening and
coordinates responses.

---

## Why Manual Failover Is Dangerous

Imagine it is 3am. Your primary just crashed. Without automation, here is what has
to happen:

1. Someone gets paged and wakes up.
2. They verify the primary is actually dead (not just a network blip).
3. They decide which standby to promote (is the standby caught up? how much lag?).
4. They promote the standby manually.
5. They update your application's connection string to point at the new primary.
6. They reconfigure any other standbys to follow the new primary.
7. They document what happened.

Step 2 alone can take 5-10 minutes while a sleepy engineer rules out false positives.
Step 4 and 5 introduce human error risk. Step 6 is easy to forget. Total downtime:
15-30 minutes on a good night.

With automated failover, steps 2 through 6 happen in under 30 seconds. repmgrd watches
continuously, applies a consistent decision algorithm, and acts immediately.

The tradeoff is that automation can be wrong. An automated system can promote when it
should not. That is what the split-brain discussion below is about.

---

## repmgr Architecture

```
  pg-primary                    pg-standby                   pg-witness
  ----------                    ----------                   ----------
  repmgrd daemon                repmgrd daemon               repmgrd daemon
  |                             |                            |
  +-- monitors standby          +-- monitors primary         +-- no PostgreSQL data
  +-- repmgr metadata tables    +-- ready to promote         +-- just votes in elections
       (repmgr.nodes, etc.)     +-- follows election result
```

**repmgrd** - The daemon process. Runs on every node (primary, standbys, witnesses).
It performs heartbeat checks, monitors replication status, and coordinates failover
decisions.

**repmgr metadata** - Stored in a dedicated schema (`repmgr`) in a PostgreSQL database.
Tables include `repmgr.nodes` (all known nodes and their roles), `repmgr.events`
(history of repmgr actions), and `repmgr.monitoring_history` (lag history).

**witness node** - A lightweight node that runs PostgreSQL but holds no replica data.
It exists only to provide a vote in failover elections. More on this below.

---

## Node Types

| Type | Role | Can take writes | Holds data |
|---|---|---|---|
| Primary | Receives all writes, source of WAL | Yes | Yes |
| Standby | Replays WAL from primary | No | Yes (replica) |
| Witness | Votes in elections | No | No |

You register each node with repmgr when you set it up:

```bash
repmgr primary register
repmgr standby register
repmgr witness register
```

After registration, `repmgr cluster show` shows every node and its current status.

---

## How repmgrd Detects Failure

repmgrd on the standby performs periodic connection checks against the primary. The
check is simple: can I connect to the primary's PostgreSQL port?

```
  Every N seconds (reconnect_attempts * reconnect_interval):
  +-- Try to connect to primary
  +-- Success -> all good, continue monitoring
  +-- Failure -> retry N times over M seconds
  +-- Still failing -> primary is declared dead, trigger election
```

The key settings controlling this behavior:

```
connection_check_type   = 'ping'     # how to check (ping, query, or connection)
reconnect_attempts      = 6          # how many times to retry before declaring failure
reconnect_interval      = 10         # seconds between retries
```

With `reconnect_attempts = 6` and `reconnect_interval = 10`, repmgrd waits a full
60 seconds of failed checks before acting. This prevents a brief network blip from
triggering a failover.

---

## Automatic Failover Flow

When repmgrd on the standby decides the primary is dead:

```
  1. DETECTION
     repmgrd on standby: cannot reach primary after N retries
                         |
  2. QUORUM CHECK
     Can I reach the witness node?
     - If YES: I have quorum, proceed
     - If NO:  I cannot safely promote (risk of split-brain), wait
                         |
  3. ELECTION
     If multiple standbys: which one is most up-to-date?
     Compare LSN (WAL position). Most advanced standby wins.
                         |
  4. PROMOTION
     Winning standby runs: repmgr standby promote
     PostgreSQL standby becomes writable primary.
                         |
  5. FOLLOW
     Other standbys: repmgr standby follow
     They reconnect to the new primary and continue replicating.
                         |
  6. NOTIFICATION
     repmgrd runs any configured event notification scripts
     (send alerts, update load balancers, etc.)
```

The whole flow from failed check to promotion takes 30-90 seconds depending on your
retry settings.

---

## Split-Brain - What It Is and How repmgr Prevents It

Split-brain is the failure mode where two nodes both believe they are the primary and
both accept writes. The result is two diverging datasets. When you try to reconcile
them, you have lost data and possibly corrupted business logic.

```
  Network partition:

  pg-primary  ---- network cuts ----  pg-standby

  pg-primary: "I'm still the primary! Taking writes!"
  pg-standby: "I can't see the primary! I'll promote!"

  -> Both accepting writes -> split-brain
```

repmgr uses the witness node to prevent this. The witness sits in a third network
location (or at minimum, a separate failure domain from both primary and standby).

The standby applies a quorum rule: only promote if I can reach the witness node. If
I cannot reach the witness, I do not know if the primary is dead or if it is just
my network that is broken. Stay a standby.

```
  Scenario 1 (primary dead, real failure):
  standby -> cannot reach primary
  standby -> CAN reach witness
  => Promote. This is a real failure.

  Scenario 2 (network partition, standby isolated):
  standby -> cannot reach primary
  standby -> CANNOT reach witness either
  => Do not promote. I might be the isolated one.
```

Without a witness node, a two-node cluster (primary + one standby) has no way to
distinguish these two scenarios and is vulnerable to split-brain.

---

## Switchover vs Failover

These are different operations and easy to confuse.

**Failover** - Unplanned. The primary crashed or became unreachable. You are promoting
a standby to recover service. This is what repmgrd automates.

**Switchover** - Planned. The primary is still running. You want to promote a standby
and demote the primary to a standby role - for example, during a maintenance window
or to move the primary to different hardware.

```bash
# Planned switchover (run from the target standby)
repmgr standby switchover --siblings-follow

# This gracefully:
# 1. Checks the standby is fully caught up
# 2. Stops the primary
# 3. Promotes the standby
# 4. Reconfigures the old primary as a standby following the new primary
# 5. Reconfigures other standbys to follow the new primary
```

Switchover is safe. Failover has risk. Do planned switchovers for maintenance.
Let repmgrd handle unplanned failovers.

---

## repmgr.conf Key Settings

The repmgr configuration file lives at `/etc/repmgr.conf` (or wherever you specify).

```ini
node_id   = 1
node_name = 'pg-primary'
conninfo  = 'host=pg-primary dbname=repmgr user=repmgr connect_timeout=2'
data_directory = '/var/lib/pgsql/16/data'

# The repmgr database
repmgr_db = 'repmgr'

# Failover behavior
failover                    = automatic
promote_command             = 'repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command              = 'repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

# Detection thresholds
reconnect_attempts          = 6
reconnect_interval          = 10
monitoring_history          = yes

# Notifications (optional but recommended)
event_notification_command  = '/opt/repmgr/notify.sh %n %e %s "%t" "%d"'
```

**node_id** - A unique integer for this node. Use 1, 2, 3... Do not reuse IDs.

**conninfo** - The connection string repmgr uses to connect to this node. Must be
reachable from all other nodes.

**failover = automatic** - Without this, repmgrd monitors but does not promote
automatically. It just logs the failure and waits for manual intervention.

**promote_command / follow_command** - What repmgrd actually runs when it decides to
promote or when a standby needs to follow a new primary.

---

## Fencing - Keeping the Old Primary Out

After a failover, the old primary eventually comes back. If it restarts PostgreSQL
and starts accepting writes before you reconnect it as a standby, you have split-brain.

Fencing is the practice of preventing the old primary from acting as a primary after
a failover. repmgr does not have built-in fencing (unlike Patroni). You implement it
through external mechanisms:

**Power fencing (STONITH)** - A script that powers off or reboots the old primary node
via IPMI, AWS EC2 API, or similar. The most reliable approach.

**Network fencing** - Block the old primary's network access so it cannot receive
application connections even if PostgreSQL starts.

**pg_hba fencing** - A notification script that updates pg_hba.conf on all nodes to
reject connections from the old primary's IP. Less reliable - depends on PostgreSQL
being able to reload.

For lab environments you can use a simpler approach: just stop PostgreSQL on the old
primary before it restarts, or use the `standby_disconnect_on_failover` setting which
makes the standby terminate its replication connection before promoting (prevents
the primary from continuing to think it has an active standby).

---

## When to Use repmgr vs Patroni

Both solve the same problem (automated PostgreSQL HA) but with different tradeoffs.

**Use repmgr when:**
- Your team is already comfortable with PostgreSQL internals
- You want something lightweight with minimal infrastructure dependencies
- You are managing 2-4 node clusters
- You do not need DCS (distributed consensus store) integration
- You want a simple tool with a small operational surface area

**Use Patroni when:**
- You need strong split-brain protection without manual fencing setup
- You are managing many clusters at scale
- You want integration with etcd, Consul, or ZooKeeper for consensus
- You want template-based configuration management (Patroni manages postgresql.conf)
- You need cloud-native deployment patterns (Kubernetes, etc.)

repmgr is approachable for a DBA who knows PostgreSQL well. Patroni requires more
infrastructure (you need to run etcd or similar) but is more robust against split-brain
by design.

For this course, we use repmgr because it teaches you to think about the HA problem
at the PostgreSQL layer first, without hiding it behind distributed systems abstractions.

---

## What to Watch For in the Lab

You will set up a three-node cluster (primary, standby, witness) and configure repmgrd
for automatic failover. Watch for:

- The repmgr schema and tables created in the repmgr database
- `repmgr cluster show` output before and after failover
- The sequence of events in repmgrd logs during failover (detection, election, promotion)
- What happens to the old primary's timeline after you bring it back
- How to safely rejoin a failed primary as a standby (`repmgr node rejoin`)

The most common lab mistakes: pg_hba.conf not allowing the repmgr user to connect with
replication privilege, and forgetting that repmgrd must be running on all nodes
(not just the primary) for failover to work.
