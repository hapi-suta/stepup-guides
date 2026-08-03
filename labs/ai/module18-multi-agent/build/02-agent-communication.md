# Build 02: Agent Communication

## Why Agents Need to Communicate

A single agent handles one job. Real systems need multiple agents to collaborate - one monitors, one diagnoses, one remediates. For that to work, agents must pass structured messages to each other through a shared channel.

**DBA analogy:** This is exactly what PostgreSQL LISTEN/NOTIFY does. One session sends a notification on a channel. Any session listening on that channel receives it. The agents here work the same way - one sends, one (or many) receives.

```sql
-- Producer session
NOTIFY dba_alerts, 'cpu_high:pg-primary:92%';

-- Consumer session (monitoring agent listening)
LISTEN dba_alerts;
```

---

## Step 1: Message Passing Between Agents

### The Concept

Every message has a standard structure:
- `sender` - which agent sent it
- `receiver` - which agent should handle it
- `type` - what kind of message (`alert`, `task`, `result`, `status`)
- `content` - the actual payload
- `timestamp` - when it was created

A message bus class holds a queue (list) of messages and routes them to the right agent.

**DBA analogy:** The message bus is like a `pg_notify()` dispatcher. Messages land in a queue (like a channel), and the bus delivers them to whatever agent is registered to handle that channel.

### The Code

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Defines a Message class and a MessageBus class.
#   Two agents pass a message through the bus.
# ---------------------------------------------------------

import datetime


# ---------------------------------------------------------
# Message class -- defines the envelope for every message
# Like a standard table schema that all agents must use
# ---------------------------------------------------------

class Message:
    # Every column in this "table": sender, receiver, type, content, timestamp
    def __init__(self, sender, receiver, msg_type, content):
        self.sender    = sender
        self.receiver  = receiver
        self.msg_type  = msg_type    # "alert", "task", "result", "status"
        self.content   = content
        # "datetime.datetime.now().isoformat()" gives ISO-8601 timestamp -- like CURRENT_TIMESTAMP
        self.timestamp = datetime.datetime.now().isoformat(timespec="seconds")

    def __repr__(self):
        # "__repr__" controls how the object prints -- like \pset format aligned in psql
        return (
            f"Message("
            f"from={self.sender}, "
            f"to={self.receiver}, "
            f"type={self.msg_type}, "
            f"content='{self.content}', "
            f"ts={self.timestamp})"
        )


# ---------------------------------------------------------
# MessageBus class -- routes messages between agents
# Like a pg_notify dispatcher: messages arrive, get routed to listeners
# ---------------------------------------------------------

class MessageBus:

    def __init__(self):
        # "queue" is a list acting as a message queue -- like a FIFO unlogged table
        self.queue = []
        # "subscribers" maps receiver_name -> agent object -- like a listener registry
        # Think of it as: SELECT * FROM pg_listening_channels()
        self.subscribers = {}

    def subscribe(self, agent_name, agent_obj):
        # Register an agent as a listener on its own name channel
        # Like: LISTEN agent_name  (but the bus keeps track, not Postgres)
        self.subscribers[agent_name] = agent_obj
        print(f"[BUS] {agent_name} subscribed (now listening)")

    def send(self, message):
        # Enqueue the message -- like INSERT INTO message_queue VALUES (...)
        self.queue.append(message)
        print(f"[BUS] Queued: {message}")

    def deliver_all(self):
        # Process every message in the queue -- like a pgq consumer draining a queue
        # "while self.queue" means "keep going while the list is not empty"
        # Like: LOOP EXIT WHEN NOT FOUND; FETCH FROM cursor; ... END LOOP;
        while self.queue:
            # ".pop(0)" removes and returns the first item -- like DEQUEUE / FETCH NEXT
            msg = self.queue.pop(0)
            # Look up the target agent in subscribers
            target = self.subscribers.get(msg.receiver)
            if target:
                # Call the agent's receive() method with the message
                target.receive(msg)
            else:
                print(f"[BUS] WARNING: No subscriber for '{msg.receiver}' -- message dropped")


# ---------------------------------------------------------
# A simple agent that can both send and receive messages
# ---------------------------------------------------------

class Agent:

    def __init__(self, name, role):
        self.name   = name
        self.role   = role
        self.memory = {}
        # "bus" will be set after creation -- like a foreign key set after INSERT
        self.bus    = None

    def attach_bus(self, bus):
        # Connect this agent to the message bus and register as a listener
        self.bus = bus
        bus.subscribe(self.name, self)

    def receive(self, message):
        # Called by the bus when a message arrives for this agent
        # Like a NOTIFY arriving at a LISTEN session -- the handler fires
        print(f"\n[{self.name}] Received message:")
        print(f"  From:    {message.sender}")
        print(f"  Type:    {message.msg_type}")
        print(f"  Content: {message.content}")
        self.memory["last_received"] = message.content

    def send(self, receiver_name, msg_type, content):
        # Create a Message and put it on the bus
        # Like calling pg_notify('channel', 'payload') from inside a function
        if not self.bus:
            print(f"[{self.name}] ERROR: Not connected to a bus")
            return
        msg = Message(
            sender   = self.name,
            receiver = receiver_name,
            msg_type = msg_type,
            content  = content
        )
        self.bus.send(msg)


# ---------------------------------------------------------
# Wire it all together
# ---------------------------------------------------------

# Create the bus -- shared channel infrastructure
bus = MessageBus()

# Create two agents
monitor     = Agent("MonitorAgent",     "Watch metrics and send alerts")
diagnostics = Agent("DiagnosticsAgent", "Investigate root cause of issues")

# Attach both agents to the bus -- like each running LISTEN in its session
monitor.attach_bus(bus)
diagnostics.attach_bus(bus)

print("\n--- Sending messages ---")

# MonitorAgent detects a problem and sends a task to DiagnosticsAgent
monitor.send("DiagnosticsAgent", "task",  "Investigate high CPU on pg-primary (92%)")
monitor.send("DiagnosticsAgent", "alert", "Replication lag exceeded 5 seconds")

# DiagnosticsAgent sends its result back to MonitorAgent
diagnostics.send("MonitorAgent", "result", "Root cause: long-running VACUUM on orders table")

print("\n--- Delivering all queued messages ---")
bus.deliver_all()

print("\n--- Agent memory after delivery ---")
print(f"  MonitorAgent last_received:     {monitor.memory.get('last_received')}")
print(f"  DiagnosticsAgent last_received: {diagnostics.memory.get('last_received')}")

EOF
```

Expected output (yours will differ):
```
[BUS] MonitorAgent subscribed (now listening)
[BUS] DiagnosticsAgent subscribed (now listening)

--- Sending messages ---
[BUS] Queued: Message(from=MonitorAgent, to=DiagnosticsAgent, type=task, content='Investigate high CPU...')
[BUS] Queued: Message(from=MonitorAgent, to=DiagnosticsAgent, type=alert, content='Replication lag exceeded 5 seconds')
[BUS] Queued: Message(from=DiagnosticsAgent, to=MonitorAgent, type=result, content='Root cause: long-running VACUUM...')

--- Delivering all queued messages ---
[DiagnosticsAgent] Received message:
  From:    MonitorAgent
  Type:    task
  Content: Investigate high CPU on pg-primary (92%)
...

--- Agent memory after delivery ---
  MonitorAgent last_received:     Root cause: long-running VACUUM on orders table
  DiagnosticsAgent last_received: Replication lag exceeded 5 seconds
```

---

## Step 2: Sequential Pipeline (Agent Chain)

### The Concept

A pipeline is a fixed sequence: each agent does its job, then passes the result to the next agent in the chain. No agent skips ahead and no agent works out of order.

Pipeline for a database incident:
```
MonitorAgent -> ClassifierAgent -> DiagnosticsAgent -> RemediationAgent
```

Each agent adds its findings to a shared "context" dict and passes the whole thing to the next stage.

**DBA analogy:** This is like a stored procedure calling other stored procedures in sequence - `sp_detect()` calls `sp_classify()` calls `sp_diagnose()` calls `sp_remediate()`. Each one gets the output of the previous one as input.

```sql
-- Sequential stored procedure chain
CREATE FUNCTION sp_handle_incident(incident TEXT) RETURNS TEXT AS $$
DECLARE
    classified TEXT;
    diagnosis  TEXT;
    fix        TEXT;
BEGIN
    classified := sp_classify(incident);
    diagnosis  := sp_diagnose(classified);
    fix        := sp_remediate(diagnosis);
    RETURN fix;
END;
$$ LANGUAGE plpgsql;
```

### The Code

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a 4-agent sequential pipeline.
#   Each agent receives a context dict, adds to it, passes it forward.
#   Context dict grows with each stage -- like a pipeline accumulating columns.
# ---------------------------------------------------------

import datetime


# ---------------------------------------------------------
# Pipeline agent -- designed for sequential processing
# ---------------------------------------------------------

class PipelineAgent:

    def __init__(self, name, role, handler_fn):
        self.name       = name
        self.role       = role
        # "handler_fn" is the function this agent runs on the context
        # Like the stored procedure body -- the actual business logic
        self.handler_fn = handler_fn
        self.next_agent = None    # pointer to the next stage -- like a linked list

    def set_next(self, agent):
        # Chain this agent to the next one
        # Returns self so you can chain calls: a.set_next(b).set_next(c) -- fluent interface
        self.next_agent = agent
        return agent

    def run(self, context):
        # "context" is a dict passed down the chain -- each agent adds its output to it
        # Like a RECORD type in PL/pgSQL that accumulates values across procedure calls
        print(f"\n[{self.name}] Starting... (stage: {context.get('stage', 'unknown')})")

        # Run this agent's logic -- modifies context in place
        self.handler_fn(context)

        # Record which stage just ran and when
        context["stage"] = self.name
        context.setdefault("trace", []).append({
            "agent": self.name,
            "ts":    datetime.datetime.now().strftime("%H:%M:%S")
        })
        # ".setdefault(key, default)" is like INSERT ... ON CONFLICT DO NOTHING
        # If "trace" already exists, return it. If not, set it to [] first, then return it.

        print(f"[{self.name}] Done. Context so far: {list(context.keys())}")

        # If there is a next agent in the chain, pass the context along
        # Like CALL next_procedure(context_var)
        if self.next_agent:
            self.next_agent.run(context)


# ---------------------------------------------------------
# Handler functions -- the business logic for each stage
# Each one receives the shared context dict and adds keys to it
# ---------------------------------------------------------

def monitor_handler(ctx):
    # Stage 1: Detect the raw incident
    ctx["incident"]  = "CPU at 94% on pg-primary"
    ctx["server"]    = "pg-primary"
    ctx["cpu_pct"]   = 94
    ctx["detected_at"] = datetime.datetime.now().isoformat(timespec="seconds")
    print(f"  Detected: {ctx['incident']}")


def classify_handler(ctx):
    # Stage 2: Classify severity and category
    # Uses data written by Stage 1 -- like a pipeline stage reading upstream output
    cpu = ctx.get("cpu_pct", 0)
    if cpu >= 90:
        ctx["severity"] = "CRITICAL"
    elif cpu >= 70:
        ctx["severity"] = "WARNING"
    else:
        ctx["severity"] = "INFO"
    ctx["category"] = "resource_exhaustion"
    print(f"  Classified as: {ctx['severity']} / {ctx['category']}")


def diagnose_handler(ctx):
    # Stage 3: Investigate root cause
    # In production this would run real queries against the database
    ctx["root_cause"]    = "VACUUM FULL on orders table holding ExclusiveLock"
    ctx["blocking_pid"]  = 28471
    ctx["lock_type"]     = "ExclusiveLock"
    ctx["recommended_action"] = "Terminate PID 28471 if vacuum has been running > 30 minutes"
    print(f"  Root cause: {ctx['root_cause']}")
    print(f"  Blocking PID: {ctx['blocking_pid']}")


def remediate_handler(ctx):
    # Stage 4: Take corrective action
    # Reads everything the previous stages built up in context
    if ctx.get("severity") == "CRITICAL":
        action = f"SELECT pg_terminate_backend({ctx.get('blocking_pid', 'unknown')})"
        ctx["action_taken"] = action
        ctx["outcome"]      = "SIMULATED: backend terminated"
        print(f"  Action taken: {action}")
        print(f"  Outcome: {ctx['outcome']}")
    else:
        ctx["action_taken"] = "none -- severity below threshold"
        print(f"  No action required at this severity level")


# ---------------------------------------------------------
# Build the pipeline chain
# ---------------------------------------------------------

monitor     = PipelineAgent("MonitorAgent",     "Detect incidents",           monitor_handler)
classifier  = PipelineAgent("ClassifierAgent",  "Classify severity",          classify_handler)
diagnostics = PipelineAgent("DiagnosticsAgent", "Investigate root cause",     diagnose_handler)
remediation = PipelineAgent("RemediationAgent", "Execute corrective action",  remediate_handler)

# Chain them together: monitor -> classifier -> diagnostics -> remediation
# Like: A CALLS B CALLS C CALLS D
monitor.set_next(classifier).set_next(diagnostics).set_next(remediation)

# ---------------------------------------------------------
# Run the pipeline with an empty context dict
# The context grows as it passes through each stage
# ---------------------------------------------------------

context = {"stage": "start"}   # initial state -- like initializing a PL/pgSQL RECORD

print("=== Starting incident pipeline ===")
monitor.run(context)

# ---------------------------------------------------------
# Print the final context -- the accumulated result of all 4 stages
# ---------------------------------------------------------

print("\n=== Final context (full pipeline output) ===")
# Excluding "trace" for readability -- print it separately
for key, value in context.items():
    if key != "trace":
        print(f"  {key:<22}: {value}")

print("\n=== Execution trace ===")
# "trace" is the audit trail -- like pg_audit log entries
for entry in context.get("trace", []):
    print(f"  [{entry['ts']}] {entry['agent']}")

EOF
```

Expected output (yours will differ):
```
=== Starting incident pipeline ===

[MonitorAgent] Starting... (stage: start)
  Detected: CPU at 94% on pg-primary
[MonitorAgent] Done. Context so far: ['stage', 'incident', 'server', ...]

[ClassifierAgent] Starting... (stage: MonitorAgent)
  Classified as: CRITICAL / resource_exhaustion
...

[RemediationAgent] Starting... (stage: DiagnosticsAgent)
  Action taken: SELECT pg_terminate_backend(28471)
  Outcome: SIMULATED: backend terminated

=== Final context (full pipeline output) ===
  stage                  : RemediationAgent
  incident               : CPU at 94% on pg-primary
  severity               : CRITICAL
  root_cause             : VACUUM FULL on orders table holding ExclusiveLock
  blocking_pid           : 28471
  action_taken           : SELECT pg_terminate_backend(28471)
  outcome                : SIMULATED: backend terminated

=== Execution trace ===
  [HH:MM:SS] MonitorAgent
  [HH:MM:SS] ClassifierAgent
  [HH:MM:SS] DiagnosticsAgent
  [HH:MM:SS] RemediationAgent
```

---

## Step 3: Parallel Execution

### The Concept

Sometimes multiple agents should work at the same time - each investigating a different aspect of a problem. When all are done, their results are combined into a single report.

**DBA analogy:** This is like PostgreSQL parallel query execution. Postgres splits a large scan across multiple workers, each scans a chunk, and the gather node combines the results. Here, each agent is a worker, and the coordinator is the gather node.

```sql
-- Postgres parallel query: workers run concurrently, gather combines results
SET max_parallel_workers_per_gather = 4;
SELECT count(*), avg(duration_ms)
FROM query_log
WHERE server = 'pg-primary';
-- Workers scan partitions in parallel; Gather combines their partial counts
```

In Python, `threading` is the built-in way to run code concurrently. Each agent runs in its own thread - like a parallel worker process.

### The Code

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Runs three diagnostic agents in parallel (simultaneously).
#   Each writes results to a shared results dict.
#   A coordinator waits for all to finish, then combines the report.
# ---------------------------------------------------------

import threading   # Python's built-in concurrency module -- like Postgres parallel workers
import time        # For simulating work with sleep() -- like pg_sleep() in SQL
import datetime


# ---------------------------------------------------------
# Shared results store
# Each agent writes its output here -- like workers writing to a shared temp table
# "threading.Lock()" prevents two agents from writing at the exact same moment
# Like an advisory lock or a row-level lock on the shared table
# ---------------------------------------------------------

results      = {}
results_lock = threading.Lock()   # The "lock" ensures only one writer at a time


# ---------------------------------------------------------
# Parallel agent function
# Each call to this function runs as an independent thread (parallel worker)
# ---------------------------------------------------------

def run_agent(agent_name, task_fn, task_args):
    # This entire function runs in a separate thread -- like a parallel worker process
    print(f"[{agent_name}] Started at {datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]}")

    # Run the task -- simulates doing real work (queries, checks, etc.)
    result = task_fn(*task_args)
    # "*task_args" unpacks the list as individual arguments -- like VARIADIC in PL/pgSQL

    # Write result to shared dict -- must acquire the lock first
    # "with results_lock:" is like: BEGIN; SELECT ... FOR UPDATE; ... COMMIT;
    # It acquires the lock, runs the block, then releases automatically
    with results_lock:
        results[agent_name] = result

    print(f"[{agent_name}] Finished at {datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]}")


# ---------------------------------------------------------
# Task functions -- each agent's actual job
# These simulate real database checks that take varying amounts of time
# ---------------------------------------------------------

def check_cpu_usage(server):
    time.sleep(1.2)   # Simulates a 1.2-second metric API call -- like a slow network query
    return {"server": server, "cpu_pct": 91, "status": "CRITICAL"}

def check_replication_lag(primary, replica):
    time.sleep(0.8)   # Simulates an 0.8-second replication query
    return {"primary": primary, "replica": replica, "lag_seconds": 3.7, "status": "WARNING"}

def check_lock_contention(server):
    time.sleep(1.5)   # Simulates a 1.5-second pg_locks scan
    return {"server": server, "blocking_pids": [28471, 30102], "status": "CRITICAL"}


# ---------------------------------------------------------
# Coordinator: launches all agents in parallel, waits for results
# Like the Gather node in a parallel query plan
# ---------------------------------------------------------

print("=== Coordinator: launching parallel agents ===")
start_time = time.time()   # Record wall-clock start -- like clock_timestamp()

# Define which agents to run and what arguments to pass them
# Each tuple: (agent_name, function_to_run, list_of_args)
agent_specs = [
    ("CPUAgent",         check_cpu_usage,        ["pg-primary"]),
    ("ReplicationAgent", check_replication_lag,  ["pg-primary", "pg-replica-1"]),
    ("LockAgent",        check_lock_contention,  ["pg-primary"]),
]

# Create thread objects -- like spawning parallel worker processes
# "threading.Thread(target=..., args=...)" defines what each thread will run
threads = []
for agent_name, task_fn, task_args in agent_specs:
    # Pack into a single args tuple for run_agent()
    t = threading.Thread(
        target = run_agent,
        args   = (agent_name, task_fn, task_args)
    )
    threads.append(t)

# Start all threads simultaneously -- like Postgres launching parallel workers at once
for t in threads:
    t.start()   # ".start()" fires the thread -- it runs concurrently from this point

# Wait for ALL threads to complete before continuing -- like the Gather node
# ".join()" blocks until that thread finishes -- like WAIT FOR all workers to return
for t in threads:
    t.join()

end_time    = time.time()
elapsed     = end_time - start_time

# If agents ran sequentially: 1.2 + 0.8 + 1.5 = 3.5 seconds
# If agents ran in parallel:  max(1.2, 0.8, 1.5) = ~1.5 seconds
print(f"\n=== All agents finished in {elapsed:.2f}s ===")
print(f"    (Sequential would have taken ~3.5s -- parallel speedup demonstrated)")

# ---------------------------------------------------------
# Combine results -- like the Gather node merging partial results
# ---------------------------------------------------------

print("\n=== Combined diagnostic report ===")

# Determine overall severity -- like rolling up statuses in a monitoring query
# If ANY agent reports CRITICAL, the overall status is CRITICAL
# "values()" returns all values in the dict -- like SELECT value FROM unnest(array)
all_statuses = [r.get("status", "OK") for r in results.values()]
# List comprehension: builds a list by iterating -- like SELECT col FROM table
overall = "CRITICAL" if "CRITICAL" in all_statuses else "WARNING" if "WARNING" in all_statuses else "OK"

print(f"  Overall status: {overall}")
print(f"  Individual findings:")

for agent_name, finding in results.items():
    status = finding.get("status", "unknown")
    # Format each finding as a single line -- like psql \pset format unaligned
    details = {k: v for k, v in finding.items() if k != "status"}
    # Dict comprehension: builds a dict from another dict, filtering keys
    # Like: SELECT key, value FROM hstore WHERE key != 'status'
    print(f"    [{status}] {agent_name}: {details}")

EOF
```

Expected output (yours will differ):
```
=== Coordinator: launching parallel agents ===
[CPUAgent] Started at HH:MM:SS.mmm
[ReplicationAgent] Started at HH:MM:SS.mmm
[LockAgent] Started at HH:MM:SS.mmm
[ReplicationAgent] Finished at HH:MM:SS.mmm
[CPUAgent] Finished at HH:MM:SS.mmm
[LockAgent] Finished at HH:MM:SS.mmm

=== All agents finished in 1.51s ===
    (Sequential would have taken ~3.5s -- parallel speedup demonstrated)

=== Combined diagnostic report ===
  Overall status: CRITICAL
  Individual findings:
    [CRITICAL] CPUAgent: {'server': 'pg-primary', 'cpu_pct': 91}
    [WARNING]  ReplicationAgent: {'primary': 'pg-primary', 'replica': 'pg-replica-1', 'lag_seconds': 3.7}
    [CRITICAL] LockAgent: {'server': 'pg-primary', 'blocking_pids': [28471, 30102]}
```

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| Message format | `Message` class with sender, receiver, type, content, timestamp | A standard table schema all producers must follow |
| Message bus | `MessageBus` class with `queue` list and `subscribers` dict | `pg_notify()` dispatcher routing to `LISTEN` channels |
| Subscribing / listening | `bus.subscribe(name, agent)` + `agent.attach_bus(bus)` | `LISTEN channel_name` in a session |
| Sending a message | `agent.send(receiver, type, content)` -> `bus.queue.append()` | `pg_notify('channel', 'payload')` |
| Delivering messages | `bus.deliver_all()` draining the queue | pgq consumer loop reading from a queue table |
| Sequential pipeline | Each agent calls `next_agent.run(context)` | Stored procedure calling other procedures in sequence |
| Shared context dict | One dict grows as it passes through all pipeline stages | A `RECORD` type accumulating values across procedure calls |
| Parallel execution | `threading.Thread` per agent, all `.start()`, all `.join()` | Postgres parallel query workers + Gather node |
| Parallel result merge | Write to `results` dict under `results_lock` | Parallel workers writing to shared temp table with row locks |
| Speedup measurement | Wall-clock elapsed vs sum of individual task times | `EXPLAIN ANALYZE` comparing parallel vs sequential plan cost |

**Next:** Build 03 covers orchestration - a supervisor agent that dynamically assigns tasks to specialist agents based on the situation.
