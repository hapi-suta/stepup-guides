# BUILD 03: Chaos Engineering for Databases

**Module 07: Database SRE Practices**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to deliberately inject failures into your PostgreSQL environment to discover weaknesses before they cause real outages.

---

## What is Chaos Engineering?

Chaos engineering is the practice of running controlled experiments on a system to build confidence in its ability to withstand unexpected conditions.

**DBA Analogy:** Think of it as fire drills for your database. A fire drill does not cause a real fire - it tests whether people know what to do when one happens. Chaos experiments do not cause real outages - they reveal whether your systems handle failures correctly.

### The Chaos Engineering Process

1. **Define steady state:** What does "normal" look like? (SLIs within SLO)
2. **Hypothesize:** "If we kill the primary, Patroni will failover within 30 seconds"
3. **Introduce chaos:** Kill the primary
4. **Observe:** Did failover happen? How long? Any data loss?
5. **Learn:** Did the system behave as expected? What needs improvement?

---

## Step 1: Gameday Planning

Before running any chaos experiment, you need a plan. Running chaos without a plan is not engineering - it is just breaking things.

### Gameday Template

```bash
mkdir -p ~/dba-labs/sre-practice/chaos
vi ~/dba-labs/sre-practice/chaos/gameday-template.md
```

```markdown
# Chaos Experiment: [Title]

## Metadata
- **Date:** [Date]
- **Conductor:** [Name]
- **Participants:** [Names]
- **Environment:** [dev / staging / production]
- **Duration:** [Expected time]

## Steady State
What does "normal" look like before the experiment?
- Availability: [X]%
- Latency p95: [X]ms
- Error rate: [X]%
- Replication lag: [X]s
- Connections: [X] / [max]

## Hypothesis
"We believe that when [chaos event] occurs, [expected behavior] will happen
within [time], and [SLI] will remain within [SLO threshold]."

## Blast Radius
- **What will be affected:** [Specific servers/services]
- **What should NOT be affected:** [Other services]
- **Maximum duration:** [Time limit for experiment]

## Rollback Plan
If the experiment causes unexpected damage:
1. [Step to stop the chaos injection]
2. [Step to restore normal state]
3. [Step to verify recovery]

## Experiment Steps
1. Record baseline SLIs
2. [Inject chaos event]
3. Monitor SLIs for [duration]
4. [Remove chaos / wait for recovery]
5. Record post-experiment SLIs

## Results
- **Hypothesis confirmed?** [Yes / No / Partially]
- **Availability during experiment:** [X]%
- **Recovery time:** [Time]
- **Unexpected behaviors:** [List any]
- **Action items:** [List improvements needed]
```

---

## Step 2: Set Up a Test Environment

For these experiments, we will use a local PostgreSQL instance. In a real environment, you would run these against staging first, then (carefully) against production.

**On your Mac terminal:**

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS chaos_lab;"
psql -U postgres -c "CREATE DATABASE chaos_lab;"
```

```bash
psql -U postgres -d chaos_lab -c "
CREATE TABLE transactions (
    txn_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO transactions (account_id, amount)
SELECT
    (random() * 1000)::int + 1,
    (random() * 1000)::numeric(10,2)
FROM generate_series(1, 500000);

CREATE INDEX idx_txn_account ON transactions (account_id);
CREATE INDEX idx_txn_created ON transactions (created_at);

ANALYZE transactions;
"
```

---

## Step 3: Experiment 1 - Saturate Connections

### Hypothesis
"When connections reach max_connections, PgBouncer (or the application's connection pool) will queue requests. Applications will see increased latency but not errors, and recovery will be immediate when connections are freed."

### Steady State

```bash
psql -U postgres -d chaos_lab -c "
SELECT
    (SELECT count(*) FROM pg_stat_activity) AS current_connections,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections;
"
```

### Inject Chaos

Create a script that opens many idle connections:

```bash
vi ~/dba-labs/sre-practice/chaos/flood-connections.sh
```

```bash
#!/bin/bash
# Chaos experiment: saturate connections
# Usage: ./flood-connections.sh [number_of_connections]

NUM_CONNECTIONS=${1:-80}
DB_NAME="chaos_lab"
PIDS=()

echo "Opening ${NUM_CONNECTIONS} connections to ${DB_NAME}..."

for i in $(seq 1 "$NUM_CONNECTIONS"); do
    psql -U postgres -d "$DB_NAME" -c "SELECT pg_sleep(120);" &
    PIDS+=($!)
    if (( i % 10 == 0 )); then
        echo "  Opened $i connections..."
    fi
done

echo "All ${NUM_CONNECTIONS} connections opened."
echo "Press Ctrl+C to release all connections."

# Wait for interrupt
trap 'echo "Killing all connections..."; for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null; done; echo "Done."; exit 0' SIGINT

wait
```

```bash
chmod +x ~/dba-labs/sre-practice/chaos/flood-connections.sh
```

### Run the Experiment

**Terminal 1 - Flood connections:**

```bash
~/dba-labs/sre-practice/chaos/flood-connections.sh 80
```

**Terminal 2 - Monitor:**

```bash
watch -n 2 'psql -U postgres -d chaos_lab -tAc "
SELECT
    count(*) AS total_conn,
    count(*) FILTER (WHERE state = '\''active'\'') AS active,
    count(*) FILTER (WHERE state = '\''idle'\'') AS idle,
    (SELECT setting::int FROM pg_settings WHERE name = '\''max_connections'\'') AS max_conn
FROM pg_stat_activity;
"'
```

**Terminal 3 - Try to connect (this is the SLI test):**

```bash
time psql -U postgres -d chaos_lab -c "SELECT count(*) FROM transactions;"
```

### Observe

- Can you still connect when connections are near max?
- What happens when max_connections is reached?
- How long does it take to recover after Ctrl+C in Terminal 1?

### Record Results

```bash
vi ~/dba-labs/sre-practice/chaos/results-connection-saturation.md
```

Document:
- Max connections before failure
- Error message when connections exhausted
- Recovery time after releasing connections
- Whether application queries succeeded or failed

---

## Step 4: Experiment 2 - CPU Stress Test

### Hypothesis
"Under high CPU load, query latency will increase but queries will still complete. PostgreSQL will continue to function, just slower."

### Install stress-ng

```bash
brew install stress-ng
```

### Inject Chaos

**Terminal 1 - Stress the CPU:**

```bash
# Use 4 CPU workers at 90% utilization for 60 seconds
stress-ng --cpu 4 --cpu-load 90 --timeout 60s --metrics-brief
```

Expected output (yours will differ):
```
stress-ng: info:  [12345] dispatching hogs: 4 cpu
stress-ng: info:  [12345] stressor       bogo ops real time  usr time  sys time   bogo ops/s
stress-ng: info:  [12345] cpu            12345678    60.00s    234.56s     1.23s    205761.30
stress-ng: info:  [12345] successful run completed in 60.01s
```

**Terminal 2 - Run queries and measure latency:**

```bash
# Run a moderately expensive query during CPU stress
for i in $(seq 1 10); do
    time psql -U postgres -d chaos_lab -c "
        SELECT account_id, count(*), sum(amount)
        FROM transactions
        GROUP BY account_id
        ORDER BY sum(amount) DESC
        LIMIT 10;
    " > /dev/null 2>&1
    echo "Query $i complete"
done
```

### Observe and Compare

Run the same 10 queries WITHOUT CPU stress for comparison:

```bash
# Baseline (no stress)
for i in $(seq 1 10); do
    time psql -U postgres -d chaos_lab -c "
        SELECT account_id, count(*), sum(amount)
        FROM transactions
        GROUP BY account_id
        ORDER BY sum(amount) DESC
        LIMIT 10;
    " > /dev/null 2>&1
    echo "Query $i complete"
done
```

### Record Results

| Metric | Baseline | Under CPU Stress | Degradation |
|--------|----------|-----------------|-------------|
| Avg query time | ___ms | ___ms | ___x slower |
| Max query time | ___ms | ___ms | |
| Queries failed | 0 | ___ | |

---

## Step 5: Experiment 3 - Disk I/O Saturation

### Hypothesis
"Under heavy disk I/O, PostgreSQL queries that require disk access will slow down significantly, but queries served from shared_buffers will be minimally affected."

### Inject Chaos

**Terminal 1 - Generate heavy disk I/O:**

```bash
# Write 1GB of data to stress disk I/O
stress-ng --hdd 2 --hdd-bytes 1G --timeout 30s --metrics-brief
```

**Terminal 2 - Run queries that require disk access:**

```bash
# Force a sequential scan (disk-heavy)
psql -U postgres -d chaos_lab -c "SET enable_indexscan = off; SET enable_bitmapscan = off;"

for i in $(seq 1 5); do
    time psql -U postgres -d chaos_lab -c "
        SET enable_indexscan = off;
        SET enable_bitmapscan = off;
        SELECT count(*) FROM transactions WHERE amount > 500;
    " > /dev/null 2>&1
    echo "SeqScan query $i complete"
done
```

**Terminal 3 - Run queries that use indexes (should be in buffer cache):**

```bash
for i in $(seq 1 5); do
    time psql -U postgres -d chaos_lab -c "
        SELECT count(*) FROM transactions WHERE account_id = 42;
    " > /dev/null 2>&1
    echo "Index query $i complete"
done
```

### Observe

- Sequential scan queries should be much slower under I/O stress
- Index scan queries may be less affected (if data is in shared_buffers)
- Check buffer cache hit ratio during the experiment:

```sql
SELECT
    round(
        100.0 * sum(blks_hit) / NULLIF(sum(blks_hit + blks_read), 0),
        2
    ) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'chaos_lab';
```

---

## Step 6: Experiment Design - Advanced Scenarios

These experiments are for staging or production environments with HA:

### Kill the Primary (Failover Test)

```markdown
## Hypothesis
"When the primary is killed, Patroni will promote a standby within 30 seconds.
Application connections will fail for < 30 seconds. No data will be lost."

## Inject
sudo systemctl stop patroni    # On the primary server

## Observe
- Watch Patroni logs on standbys: journalctl -u patroni -f
- Monitor failover time
- Check if PgBouncer reconnects to new primary
- Verify no committed transactions were lost

## Rollback
Restart Patroni on the old primary - it will rejoin as a standby:
sudo systemctl start patroni
```

### Network Latency (Replication Test)

```markdown
## Hypothesis
"With 100ms network latency between primary and standby,
replication lag will increase but stay under 5 seconds."

## Inject (on primary server, requires root)
# Add 100ms delay to traffic to standby
sudo tc qdisc add dev eth0 root netem delay 100ms

## Observe
- Monitor pg_stat_replication on primary
- Check replay_lag on standbys
- Measure application query latency

## Rollback
sudo tc qdisc del dev eth0 root netem
```

### Disk Fill (Monitoring Test)

```markdown
## Hypothesis
"When disk reaches 90%, our monitoring will alert within 60 seconds.
The runbook will be followed, and disk will be freed before reaching 95%."

## Inject
# Create a large file to fill disk (safer than filling actual PG data)
dd if=/dev/zero of=/tmp/disk-fill-test bs=1M count=5000

## Observe
- Monitor alerting system for disk alert
- Time from injection to alert
- Time from alert to response

## Rollback
rm /tmp/disk-fill-test
```

---

## Step 7: Measuring Impact

During every chaos experiment, measure the SLI impact:

### Before the Experiment (Baseline)

```sql
-- Record baseline SLIs
SELECT
    datname,
    xact_commit,
    xact_rollback,
    blk_read_time,
    blk_write_time
FROM pg_stat_database
WHERE datname = 'chaos_lab';
```

### During the Experiment

```bash
# Continuous latency measurement
while true; do
    START=$(date +%s%N)
    psql -U postgres -d chaos_lab -c "SELECT 1;" > /dev/null 2>&1
    END=$(date +%s%N)
    LATENCY=$(( (END - START) / 1000000 ))
    echo "$(date +%T) ${LATENCY}ms"
    sleep 1
done
```

### After the Experiment

```sql
-- Compare to baseline
-- Calculate error rate during experiment window
-- Calculate latency degradation
-- Determine recovery time (when SLIs returned to baseline)
```

---

## Step 8: Documenting Results

After each experiment, write a results document:

```bash
vi ~/dba-labs/sre-practice/chaos/results-template.md
```

```markdown
# Chaos Experiment Results: [Title]

## Summary
| Metric | Expected | Actual |
|--------|----------|--------|
| Recovery time | < 30s | [actual] |
| Availability during | > 99% | [actual] |
| Data loss | None | [actual] |
| SLI degradation | < 2x baseline | [actual] |

## Hypothesis Result
[CONFIRMED / PARTIALLY CONFIRMED / REJECTED]

[Explanation of why]

## Findings
1. [Finding 1]
2. [Finding 2]
3. [Finding 3]

## Action Items
| Action | Priority | Owner |
|--------|----------|-------|
| [Action] | P1/P2 | [Name] |

## Artifacts
- Monitoring dashboard: [link]
- Log files: [path]
- Grafana snapshot: [link]
```

---

## Step 9: Practical - Run 3 Experiments

Run the following three experiments against your local PostgreSQL and document the results:

1. **Connection saturation** (Step 3) - flood connections, measure when queries fail
2. **CPU stress** (Step 4) - stress CPU, measure query latency degradation
3. **Disk I/O saturation** (Step 5) - stress disk, compare index vs sequential scan performance

For each experiment:
- Record baseline measurements first
- Inject the chaos
- Measure SLI impact
- Record recovery time
- Document results using the template

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Chaos engineering | Controlled failure injection to discover weaknesses before real outages |
| Steady state | Define "normal" before breaking things - you need a baseline |
| Hypothesis | State what you expect to happen - experiments test hypotheses |
| Blast radius | Know what will be affected and what should NOT be affected |
| Rollback plan | Always have a way to stop the chaos immediately |
| Gameday | Planned chaos exercise with conductor, participants, and documentation |
| Connection saturation | Test what happens when connections hit max - reveals pooling gaps |
| CPU stress | Queries slow down but PostgreSQL keeps running (usually) |
| Disk I/O stress | Sequential scans degrade, cached queries survive |
| tc netem | Network chaos tool for simulating latency, packet loss |
| stress-ng | CPU, memory, and disk stress testing tool |
| Results documentation | Every experiment produces measurable results and action items |

---

**Next:** BUILD 04 - Eliminating Toil - identify and automate the repetitive manual work that consumes your day.
