# Build 01: Agent Architecture

## What Is an Agent?

An agent is a program that can:
1. Receive input (a task or observation)
2. Decide what to do (using logic or an AI model)
3. Use tools (functions) to take action
4. Remember things (memory) across steps

**DBA analogy:** Think of an agent like a database role. The role has a name, a purpose (like `reporting_role` or `backup_role`), a set of permissions (which tools it can use), and it maintains state (session variables, temp tables).

---

## Step 1: Basic Agent Class

### The Concept

Every agent needs four things:
- `name` - who the agent is
- `role` - what it is responsible for
- `tools` - a list of functions it is allowed to call (like GRANTs on stored procedures)
- `memory` - a dictionary to store information between steps (like a session-level config table)
- `process` method - the function that handles incoming input

**DBA analogy:** This is like a `CREATE ROLE` statement with GRANTs. The role has a name, it owns certain objects, and it can only execute specific procedures.

```sql
-- SQL equivalent of what we are modeling in Python
CREATE ROLE monitor_agent;
GRANT EXECUTE ON FUNCTION check_metric(text) TO monitor_agent;
GRANT EXECUTE ON FUNCTION send_alert(text) TO monitor_agent;
```

### The Code

Run this as a standalone script. Paste the entire block into your Mac terminal.

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Defines a basic Agent class and creates one instance.
#   The agent receives a task string and decides how to respond.
# ---------------------------------------------------------

# "class" is Python's way of defining a blueprint for an object.
# Think of it like a CREATE TYPE or a table definition -- it describes
# the structure, not the data itself.
class Agent:

    # "__init__" is the constructor. It runs when you create a new agent.
    # It is like the INSERT that populates the row for the first time.
    # "self" refers to the specific instance being created -- like SELF in PL/pgSQL.
    def __init__(self, name, role, tools):
        self.name = name          # the agent's identifier -- like a role name
        self.role = role          # a description of its job -- like a COMMENT ON ROLE
        self.tools = tools        # list of tool names this agent can use -- like its GRANTs
        self.memory = {}          # empty dict to start -- like an empty session config table

    # "process" is the main method. It receives input and returns a response.
    # Think of it like a stored procedure: you call it with input, it does work, it returns output.
    def process(self, input_text):
        # Log that this agent received input -- like an audit log INSERT
        print(f"[{self.name}] Received task: {input_text}")

        # Store the last task in memory -- like UPDATE session_config SET last_task = ...
        self.memory["last_task"] = input_text

        # Return a simple acknowledgment
        return f"[{self.name}] Task acknowledged. Role: {self.role}"


# ---------------------------------------------------------
# Create two agents -- like creating two database roles
# ---------------------------------------------------------

# This agent monitors database metrics
monitor = Agent(
    name="MonitorAgent",
    role="Watch database metrics and detect anomalies",
    tools=["check_metric", "send_alert"]   # list of tool names -- actual functions come in Step 2
)

# This agent handles diagnostics
diagnostics = Agent(
    name="DiagnosticsAgent",
    role="Investigate root cause of detected problems",
    tools=["run_query", "read_logs"]
)

# ---------------------------------------------------------
# Run both agents with sample input
# ---------------------------------------------------------

result1 = monitor.process("CPU is at 95%")
print(result1)

result2 = diagnostics.process("High CPU detected on pg-primary")
print(result2)

# Print memory state -- like SELECT * FROM pg_stat_activity for the agent
print(f"\n[{monitor.name}] Memory: {monitor.memory}")
print(f"[{diagnostics.name}] Memory: {diagnostics.memory}")

EOF
```

Expected output (yours will differ):
```
[MonitorAgent] Received task: CPU is at 95%
[MonitorAgent] Task acknowledged. Role: Watch database metrics and detect anomalies
[DiagnosticsAgent] Received task: High CPU detected on pg-primary
[DiagnosticsAgent] Task acknowledged. Role: Investigate root cause of detected problems

[MonitorAgent] Memory: {'last_task': 'CPU is at 95%'}
[DiagnosticsAgent] Memory: {'last_task': 'High CPU detected on pg-primary'}
```

---

## Step 2: Agent With Tools

### The Concept

Tools are real Python functions that the agent can call. The agent checks its `tools` list, picks the right one based on keywords in the input, and executes it.

**DBA analogy:** Tools are like stored procedures. The agent (role) has EXECUTE permission on specific functions. When a task comes in, the agent decides which procedure to call - just like application code deciding whether to call `sp_check_replication_lag()` or `sp_kill_idle_connections()`.

```sql
-- The agent's toolset is like a role's procedure grants
GRANT EXECUTE ON FUNCTION check_metric(text)  TO monitor_agent;
GRANT EXECUTE ON FUNCTION run_query(text)     TO monitor_agent;
GRANT EXECUTE ON FUNCTION send_alert(text)    TO monitor_agent;
```

### The Code

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Defines tool functions (like stored procedures).
#   The agent selects and calls the right tool based on input.
# ---------------------------------------------------------

import datetime   # Python's built-in module for timestamps -- like now() in SQL


# ---------------------------------------------------------
# Tool functions -- these are the "stored procedures"
# ---------------------------------------------------------

# Each function takes a value and returns a result string.
# "def" defines a function -- like CREATE FUNCTION in SQL.

def check_metric(metric_name):
    # Simulates checking a system metric -- like querying pg_stat_bgwriter
    # In production this would call Prometheus, CloudWatch, etc.
    fake_values = {
        "cpu":        "92%",
        "connections": "487 / 500",
        "replication_lag": "4.2 seconds"
    }
    # ".get()" is like COALESCE -- returns a default if the key is not found
    value = fake_values.get(metric_name, "metric not found")
    return f"check_metric({metric_name}) => {value}"


def run_query(sql):
    # Simulates running a diagnostic query -- like calling dblink or a monitoring function
    return f"run_query result: [simulated rows for: {sql}]"


def send_alert(message):
    # Simulates sending an alert -- like pg_notify() sending a channel message
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"ALERT SENT at {timestamp}: {message}"


# ---------------------------------------------------------
# Agent class with tool dispatch
# ---------------------------------------------------------

class Agent:

    def __init__(self, name, role, tools):
        self.name   = name
        self.role   = role
        # "tools" is now a dict: tool_name -> function
        # Think of it like a lookup table: tool_name | function_pointer
        self.tools  = tools
        self.memory = {}

    def process(self, input_text):
        print(f"\n[{self.name}] Processing: {input_text}")
        self.memory["last_task"] = input_text

        # Decide which tool to use based on keywords in the input.
        # This is simple keyword matching -- like a CASE statement.
        # Real agents use an LLM to make this decision.

        if "cpu" in input_text.lower():
            # "self.tools['check_metric']" retrieves the function from the dict
            # "(...)('cpu')" immediately calls it -- like EXECUTE stored_proc('cpu')
            result = self.tools["check_metric"]("cpu")

        elif "connection" in input_text.lower():
            result = self.tools["check_metric"]("connections")

        elif "lag" in input_text.lower():
            result = self.tools["check_metric"]("replication_lag")

        elif "alert" in input_text.lower():
            result = self.tools["send_alert"](input_text)

        elif "query" in input_text.lower():
            result = self.tools["run_query"]("SELECT * FROM pg_stat_activity WHERE state = 'active'")

        else:
            # "f-string" is Python's way of embedding variables in strings
            # Think of it like FORMAT() in PL/pgSQL
            result = f"No matching tool found for: {input_text}"

        # Store the result in memory -- like updating a status table
        self.memory["last_result"] = result
        print(f"[{self.name}] Tool result: {result}")
        return result


# ---------------------------------------------------------
# Build the monitor agent with real tool functions
# ---------------------------------------------------------

monitor = Agent(
    name="MonitorAgent",
    role="Watch database metrics and detect anomalies",
    # Pass actual functions as values in the dict -- not strings, real callables
    tools={
        "check_metric": check_metric,
        "run_query":    run_query,
        "send_alert":   send_alert
    }
)

# ---------------------------------------------------------
# Test the agent with different inputs
# ---------------------------------------------------------

monitor.process("Check CPU usage now")
monitor.process("How many connections are active?")
monitor.process("Is there replication lag?")
monitor.process("Send alert: disk at 88%")
monitor.process("Run diagnostic query on active sessions")

# Show what the agent remembers after all tasks
print(f"\n[{monitor.name}] Final memory state:")
# ".items()" returns key-value pairs -- like SELECT key, value FROM hstore
for key, value in monitor.memory.items():
    print(f"  {key}: {value}")

EOF
```

Expected output (yours will differ):
```
[MonitorAgent] Processing: Check CPU usage now
[MonitorAgent] Tool result: check_metric(cpu) => 92%

[MonitorAgent] Processing: How many connections are active?
[MonitorAgent] Tool result: check_metric(connections) => 487 / 500

[MonitorAgent] Processing: Is there replication lag?
[MonitorAgent] Tool result: check_metric(replication_lag) => 4.2 seconds

[MonitorAgent] Processing: Send alert: disk at 88%
[MonitorAgent] Tool result: ALERT SENT at 2026-06-09 ...: Send alert: disk at 88%

[MonitorAgent] Processing: Run diagnostic query on active sessions
[MonitorAgent] Tool result: run_query result: [simulated rows for: SELECT * FROM pg_stat_activity WHERE state = 'active']

[MonitorAgent] Final memory state:
  last_task: Run diagnostic query on active sessions
  last_result: run_query result: [simulated rows for: ...]
```

---

## Step 3: Agent Memory

### The Concept

Agents have two types of memory:

| Memory Type | What It Stores | SQL Analogy |
|---|---|---|
| Short-term | Current task context - what is happening right now | Session-level GUCs (`SET work_mem`) |
| Long-term | Patterns learned from past tasks - what has happened before | `pg_stat_statements` - persists across sessions |

Short-term memory is reset when the agent starts a new task context. Long-term memory persists across tasks and grows over time.

**DBA analogy:** `pg_stat_statements` is a perfect model. It tracks every query that has ever run, counts executions, accumulates timing, and lets you query patterns. An agent's long-term memory does the same thing for its own actions.

### The Code

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Adds both short-term and long-term memory to an agent.
#   Shows how past patterns influence current behavior.
# ---------------------------------------------------------

import datetime


# --- Tool functions (same as Step 2, abbreviated) ---

def check_metric(metric_name):
    fake_values = {"cpu": "88%", "connections": "312 / 500", "disk": "71%"}
    return fake_values.get(metric_name, "unknown")

def send_alert(message):
    return f"ALERT: {message}"


# ---------------------------------------------------------
# Agent with short-term AND long-term memory
# ---------------------------------------------------------

class Agent:

    def __init__(self, name, role, tools):
        self.name  = name
        self.role  = role
        self.tools = tools

        # SHORT-TERM memory: wiped at the start of each new task context.
        # Like session-level settings -- gone when the session ends.
        self.short_term = {}

        # LONG-TERM memory: persists across all tasks.
        # Stores a history list -- like a table that keeps growing.
        # "history" will be a list of past task records.
        self.long_term = {
            "history": [],          # list of past task dicts -- like rows in pg_stat_statements
            "alert_count": 0,       # how many alerts have been sent -- like calls_total in pg_stat_statements
            "known_issues": {}      # recurring issues -- like queries with high total_time
        }

    def _record_to_long_term(self, task, result, tool_used):
        # "_" prefix means this is an internal helper -- like a private function in a package
        # This appends a record to the history list.
        # Think of it like INSERT INTO agent_history (task, result, tool_used, ts)
        record = {
            "task":      task,
            "result":    result,
            "tool_used": tool_used,
            "timestamp": datetime.datetime.now().strftime("%H:%M:%S")
        }
        # ".append()" adds an item to a list -- like INSERT without a WHERE
        self.long_term["history"].append(record)

        # Track recurring issues -- like incrementing a counter in pg_stat_statements
        if tool_used == "send_alert":
            self.long_term["alert_count"] += 1   # "+=" means add and assign -- like count = count + 1

        # If this task has been seen before, note it as a known issue
        if task in self.long_term["known_issues"]:
            self.long_term["known_issues"][task] += 1
        else:
            # First time seeing this task -- INSERT a new row with count 1
            self.long_term["known_issues"][task] = 1

    def process(self, input_text):
        # Reset short-term memory for this task -- like SET LOCAL (resets at transaction end)
        self.short_term = {
            "current_task":   input_text,
            "started_at":     datetime.datetime.now().strftime("%H:%M:%S"),
            "status":         "in_progress"
        }

        print(f"\n[{self.name}] Task: {input_text}")

        # Check long-term memory for known recurring issues -- like querying pg_stat_statements
        task_seen_before = self.long_term["known_issues"].get(input_text, 0)
        if task_seen_before > 0:
            print(f"  [MEMORY] Seen this task {task_seen_before} time(s) before -- pattern detected")

        # Dispatch to tools
        tool_used = "none"
        if "cpu" in input_text.lower():
            result    = self.tools["check_metric"]("cpu")
            tool_used = "check_metric"
        elif "disk" in input_text.lower():
            result    = self.tools["check_metric"]("disk")
            tool_used = "check_metric"
        elif "alert" in input_text.lower():
            result    = self.tools["send_alert"](input_text)
            tool_used = "send_alert"
        else:
            result    = f"No tool matched for: {input_text}"

        # Update short-term memory with result
        self.short_term["status"] = "complete"
        self.short_term["result"] = result

        # Write to long-term memory
        self._record_to_long_term(input_text, result, tool_used)

        print(f"  Result:    {result}")
        print(f"  Short-term memory: {self.short_term}")
        return result

    def show_memory_report(self):
        # Like running: SELECT * FROM pg_stat_statements ORDER BY calls DESC
        print(f"\n--- [{self.name}] Long-Term Memory Report ---")
        print(f"  Total tasks processed: {len(self.long_term['history'])}")
        print(f"  Total alerts sent:     {self.long_term['alert_count']}")
        print(f"  Known issues (task -> seen count):")
        for task, count in self.long_term["known_issues"].items():
            # "ljust(40)" pads the string to 40 chars -- like column alignment in psql \x
            print(f"    {task.ljust(40)} x{count}")
        print(f"\n  Full history (most recent last):")
        for row in self.long_term["history"]:
            print(f"    [{row['timestamp']}] tool={row['tool_used']} | {row['task'][:50]}")


# ---------------------------------------------------------
# Create the agent and run it through several tasks
# Some tasks repeat to show pattern detection
# ---------------------------------------------------------

monitor = Agent(
    name="MonitorAgent",
    role="Watch database metrics and detect anomalies",
    tools={
        "check_metric": check_metric,
        "send_alert":   send_alert
    }
)

monitor.process("Check CPU usage now")
monitor.process("Send alert: disk at 88%")
monitor.process("Check CPU usage now")          # repeated -- memory will note this
monitor.process("Send alert: high connections")
monitor.process("Check CPU usage now")          # repeated again

# Print the memory report -- like EXPLAIN ANALYZE for agent behavior
monitor.show_memory_report()

EOF
```

Expected output (yours will differ):
```
[MonitorAgent] Task: Check CPU usage now
  Result:    88%
  Short-term memory: {'current_task': 'Check CPU usage now', 'started_at': '...', 'status': 'complete', 'result': '88%'}

[MonitorAgent] Task: Send alert: disk at 88%
  Result:    ALERT: Send alert: disk at 88%
  ...

[MonitorAgent] Task: Check CPU usage now
  [MEMORY] Seen this task 1 time(s) before -- pattern detected
  ...

[MonitorAgent] Task: Check CPU usage now
  [MEMORY] Seen this task 2 time(s) before -- pattern detected
  ...

--- [MonitorAgent] Long-Term Memory Report ---
  Total tasks processed: 5
  Total alerts sent:     2
  Known issues (task -> seen count):
    Check CPU usage now                      x3
    Send alert: disk at 88%                  x1
    Send alert: high connections             x1

  Full history (most recent last):
    [HH:MM:SS] tool=check_metric | Check CPU usage now
    ...
```

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| Agent identity | `name` and `role` attributes on the class | `CREATE ROLE` with a `COMMENT` |
| Available tools | `tools` dict mapping name to function | `GRANT EXECUTE ON FUNCTION` to a role |
| Tool dispatch | `if/elif` keyword matching in `process()` | `CASE` statement routing to a stored procedure |
| Short-term memory | `self.short_term = {}` reset each task | `SET LOCAL` - scoped to the current transaction |
| Long-term memory | `self.long_term["history"]` grows over time | `pg_stat_statements` accumulating across sessions |
| Pattern detection | Checking `known_issues` count before acting | Querying `pg_stat_statements` for high-call queries |
| Memory report | `show_memory_report()` method | `SELECT * FROM pg_stat_statements ORDER BY calls DESC` |

**Next:** Build 02 covers how agents communicate with each other using a message bus.
