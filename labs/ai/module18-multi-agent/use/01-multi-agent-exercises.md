# Use 01: Multi-Agent Exercises

Module 18 - Multi-Agent Systems
Audience: DBAs with no Python background
Prerequisite: Module 17 (single-agent basics), Python3 installed on Mac

---

## How to read this guide

Every Python line is explained. Where a DBA analogy helps, it is used. All scripts run
as standalone heredoc blocks - paste the entire block into your terminal and press Enter.

---

## Exercise 1: Build a Two-Agent Pipeline (Monitor -> Classifier)

### What you are building

A pipeline where Agent 1 (Monitor) reads a database metric and passes its finding to
Agent 2 (Classifier), which decides the severity. This is the same pattern as a
`pg_stat_activity` query feeding an alert rule - one process produces data, another
process consumes it.

### Concepts

- Agent: a function that takes input, calls an LLM, returns output
- Pipeline: the output of one agent becomes the input of the next
- DBA analogy: `pg_stat_activity` -> alert rule -> `notify_table`

### Code

On your **Mac terminal**, paste this entire block and press Enter:

```bash
python3 << 'PYEOF'

# import the openai library so Python can talk to the OpenAI API
# Think of this like loading the pg_stat extension - it gives you new capabilities
import openai

# import os so we can read environment variables (where your API key lives)
import os

# -----------------------------------------------------------------------
# SETUP
# -----------------------------------------------------------------------

# Create a client object that holds your API credentials
# This is like opening a psql connection - you do it once and reuse it
client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])

# -----------------------------------------------------------------------
# AGENT 1: MONITOR AGENT
# -----------------------------------------------------------------------
# This agent receives a raw metric string and returns a plain-English analysis.
# Think of it as a stored procedure that reads pg_stat and returns a summary row.

def monitor_agent(raw_metric: str) -> str:
    # Build a list called "messages" - this is the conversation you send to the LLM
    # It always starts with a "system" message (the agent's job description)
    # and a "user" message (the actual input)
    messages = [
        {
            "role": "system",
            # This tells the LLM what role it is playing
            "content": "You are a database monitor agent. Analyze the metric and report "
                       "what you observe. Be brief - two sentences maximum."
        },
        {
            "role": "user",
            # This is the actual data being passed in - like a parameter to a function
            "content": f"Metric reading: {raw_metric}"
        }
    ]

    # Call the OpenAI API with our messages
    # model="gpt-4o-mini" is like choosing which query planner to use
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages
    )

    # Pull the text out of the response object
    # .choices[0] = first result (like LIMIT 1)
    # .message.content = the actual text the LLM returned
    return response.choices[0].message.content


# -----------------------------------------------------------------------
# AGENT 2: CLASSIFIER AGENT
# -----------------------------------------------------------------------
# This agent receives the monitor's analysis and assigns a severity level.
# Think of it as a CASE WHEN block that converts a description into a code.

def classifier_agent(monitor_output: str) -> str:
    messages = [
        {
            "role": "system",
            # Strict instructions - we want a single word back, not an essay
            "content": "You are a severity classifier. Given a database observation, "
                       "respond with exactly one word: CRITICAL, WARNING, or OK."
        },
        {
            "role": "user",
            "content": f"Observation: {monitor_output}"
        }
    ]

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages
    )

    # .strip() removes any leading/trailing whitespace - like TRIM() in SQL
    return response.choices[0].message.content.strip()


# -----------------------------------------------------------------------
# PIPELINE: WIRE THE TWO AGENTS TOGETHER
# -----------------------------------------------------------------------

# This is the raw metric - in a real system this comes from pg_stat_activity
# or a Prometheus scrape. For this exercise we hardcode it.
raw_metric = "active_connections=198, max_connections=200, wait_events=ClientRead x 45"

print("=== TWO-AGENT PIPELINE ===")
print(f"Input metric : {raw_metric}")

# Step 1: pass the raw metric to the monitor agent
# This is like calling: SELECT monitor_fn(raw_metric)
monitor_result = monitor_agent(raw_metric)
print(f"\nMonitor agent output:\n{monitor_result}")

# Step 2: pass the monitor's output to the classifier agent
# The output of one agent becomes the input of the next - that is a pipeline
# This is like: SELECT classify_fn(monitor_fn(raw_metric))
severity = classifier_agent(monitor_result)
print(f"\nClassifier agent output: {severity}")

print("\nPipeline complete.")

PYEOF
```

### Expected output (yours will differ):

```
=== TWO-AGENT PIPELINE ===
Input metric : active_connections=198, max_connections=200, wait_events=ClientRead x 45

Monitor agent output:
The database is nearly at connection capacity with 198 out of 200 connections in use.
45 connections are in a ClientRead wait state, indicating the application is not
releasing connections promptly.

Classifier agent output: CRITICAL

Pipeline complete.
```

---

## Exercise 2: Add Logging to Agent Communication (Audit Trail)

### What you are building

Add a message log that records every input and output between agents. In database terms
this is an audit trail - the same reason you keep a `pg_audit` log or write to a
`dba_audit` table. When something goes wrong, you need to know exactly what each agent
said to the other.

### Concepts

- Audit trail: a time-stamped record of every action in the system
- Here we log to a Python list (in-memory) - in production you would INSERT into a table
- The structure mirrors a CDC event log: who, what, when

### Code

On your **Mac terminal**, paste this entire block and press Enter:

```bash
python3 << 'PYEOF'

import openai
import os

# datetime gives us timestamps - like PostgreSQL's NOW()
from datetime import datetime

client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])

# -----------------------------------------------------------------------
# AUDIT LOG
# -----------------------------------------------------------------------
# This is a plain Python list. Each item will be a dict (key-value pairs).
# Think of the list as a table and each dict as a row.
# Columns: agent_name (VARCHAR), direction (VARCHAR), content (TEXT), logged_at (TIMESTAMP)
audit_log = []


def log_message(agent_name: str, direction: str, content: str):
    # Create one log row as a Python dict
    # direction is either "INPUT" or "OUTPUT" - like knowing if a value was read or written
    entry = {
        "agent_name": agent_name,
        "direction":  direction,
        "content":    content,
        # datetime.now().isoformat() produces a string like "2026-06-09T14:23:01.123456"
        # Same as PostgreSQL's NOW()::text
        "logged_at":  datetime.now().isoformat()
    }
    # Append the row to our in-memory table
    audit_log.append(entry)


# -----------------------------------------------------------------------
# AGENT 1: MONITOR AGENT (with logging)
# -----------------------------------------------------------------------

def monitor_agent(raw_metric: str) -> str:
    # Log what came IN to this agent before we do anything
    log_message("MonitorAgent", "INPUT", raw_metric)

    messages = [
        {"role": "system", "content": "You are a database monitor agent. Analyze the "
                                      "metric and report what you observe. Two sentences maximum."},
        {"role": "user",   "content": f"Metric reading: {raw_metric}"}
    ]

    response = client.chat.completions.create(model="gpt-4o-mini", messages=messages)
    result = response.choices[0].message.content

    # Log what went OUT of this agent after we get the LLM response
    log_message("MonitorAgent", "OUTPUT", result)

    return result


# -----------------------------------------------------------------------
# AGENT 2: CLASSIFIER AGENT (with logging)
# -----------------------------------------------------------------------

def classifier_agent(monitor_output: str) -> str:
    log_message("ClassifierAgent", "INPUT", monitor_output)

    messages = [
        {"role": "system", "content": "You are a severity classifier. Respond with "
                                      "exactly one word: CRITICAL, WARNING, or OK."},
        {"role": "user",   "content": f"Observation: {monitor_output}"}
    ]

    response = client.chat.completions.create(model="gpt-4o-mini", messages=messages)
    result = response.choices[0].message.content.strip()

    log_message("ClassifierAgent", "OUTPUT", result)

    return result


# -----------------------------------------------------------------------
# RUN THE PIPELINE
# -----------------------------------------------------------------------

raw_metric = "replication_lag_seconds=320, replica_status=streaming, wal_sender_state=catchup"

monitor_result = monitor_agent(raw_metric)
severity       = classifier_agent(monitor_result)

print(f"Final severity: {severity}")

# -----------------------------------------------------------------------
# PRINT THE AUDIT LOG
# -----------------------------------------------------------------------
# Loop over every entry in our list and print it
# This is like: SELECT * FROM dba_audit ORDER BY logged_at
print("\n=== AUDIT TRAIL ===")

# "for entry in audit_log" iterates row by row - like a cursor in PL/pgSQL
for entry in audit_log:
    # f-strings insert variable values into a string - like format() in SQL
    # [:80] truncates to 80 characters so the output stays readable
    print(f"[{entry['logged_at']}] {entry['agent_name']} {entry['direction']}: "
          f"{entry['content'][:80]}...")

PYEOF
```

### Expected output (yours will differ):

```
Final severity: WARNING

=== AUDIT TRAIL ===
[2026-06-09T14:23:01.001234] MonitorAgent INPUT: replication_lag_seconds=320, replica_status=streaming, wal_sender_state=c...
[2026-06-09T14:23:01.882341] MonitorAgent OUTPUT: Replication lag is at 320 seconds, indicating the replica is significan...
[2026-06-09T14:23:02.441233] ClassifierAgent INPUT: Replication lag is at 320 seconds, indicating the replica is signific...
[2026-06-09T14:23:02.991122] ClassifierAgent OUTPUT: WARNING...
```

---

## Exercise 3: Agent Voting System (3 Agents Vote, Majority Wins)

### What you are building

Three independent classifier agents each analyze the same metric and return a severity
vote. The majority vote wins. This is like running the same query on three read replicas
and taking the result that appears most often - it reduces the chance that one confused
LLM response becomes your final answer.

### Concepts

- Quorum: a majority agreement - the same concept behind Patroni/etcd leader election
- In databases, you need 2 of 3 nodes to agree before a failover is promoted
- Here, 2 of 3 agents must agree on severity before it is accepted

### Code

On your **Mac terminal**, paste this entire block and press Enter:

```bash
python3 << 'PYEOF'

import openai
import os

# Counter counts how many times each value appears in a list
# Think of it like: SELECT severity, COUNT(*) FROM votes GROUP BY severity ORDER BY COUNT(*) DESC LIMIT 1
from collections import Counter

client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])

# -----------------------------------------------------------------------
# SINGLE VOTER AGENT
# -----------------------------------------------------------------------
# Each voter gets the same input but is told it is one of three independent reviewers.
# The agent_id parameter lets us label each voter in the output.

def voter_agent(metric_description: str, agent_id: int) -> str:
    messages = [
        {
            "role": "system",
            # We tell the LLM it is one of multiple independent reviewers
            # This encourages it to reason independently rather than hedge
            "content": f"You are database severity reviewer #{agent_id} of 3. "
                       "Classify independently. Respond with exactly one word: "
                       "CRITICAL, WARNING, or OK."
        },
        {
            "role": "user",
            "content": f"Database observation: {metric_description}"
        }
    ]

    response = client.chat.completions.create(model="gpt-4o-mini", messages=messages)

    # .strip() removes whitespace; .upper() normalizes case - like UPPER(TRIM(col)) in SQL
    vote = response.choices[0].message.content.strip().upper()

    # Validate: if the LLM returned something unexpected, default to WARNING
    # This is defensive programming - like a CHECK constraint with a fallback
    if vote not in ("CRITICAL", "WARNING", "OK"):
        vote = "WARNING"

    return vote


# -----------------------------------------------------------------------
# VOTING PIPELINE
# -----------------------------------------------------------------------

def run_vote(metric_description: str) -> str:
    # Start with an empty list to collect votes - like a fresh temp table
    votes = []

    # range(1, 4) produces [1, 2, 3] - we call each agent once
    # This is like running the same query across 3 read replicas
    for agent_id in range(1, 4):
        vote = voter_agent(metric_description, agent_id)
        votes.append(vote)
        print(f"  Agent {agent_id} voted: {vote}")

    # Counter(votes) counts occurrences of each value in the list
    # .most_common(1) returns the single most common item as a list of (value, count) tuples
    # [0][0] gets the value from that tuple
    # SQL equivalent: SELECT severity FROM votes ORDER BY cnt DESC LIMIT 1
    winner = Counter(votes).most_common(1)[0][0]
    return winner


# -----------------------------------------------------------------------
# RUN IT
# -----------------------------------------------------------------------

metric = "table bloat=78%, autovacuum not running, dead_tuples=4200000, table_size=12GB"

print("=== AGENT VOTING SYSTEM ===")
print(f"Metric: {metric}\n")
print("Votes:")

final_verdict = run_vote(metric)

print(f"\nMajority verdict: {final_verdict}")

PYEOF
```

### Expected output (yours will differ):

```
=== AGENT VOTING SYSTEM ===
Metric: table bloat=78%, autovacuum not running, dead_tuples=4200000, table_size=12GB

Votes:
  Agent 1 voted: CRITICAL
  Agent 2 voted: CRITICAL
  Agent 3 voted: WARNING

Majority verdict: CRITICAL
```

---

## Exercise 4: Agent Specialization Test (Measure Accuracy Per-Agent vs Single-Agent)

### What you are building

Four specialized agents each handle one category of database problem (connections,
replication, storage, locks). A single generalist agent handles all categories. You
run both against the same test cases and compare how often each is correct.

This mirrors a design decision you make in databases: a partitioned table with dedicated
indexes per partition vs. one large table with a general-purpose index. Specialization
wins in high-volume predictable workloads.

### Concepts

- Specialist agent: given a focused system prompt for one narrow domain
- Accuracy: (correct answers / total answers) * 100 - the same SLA math you already do
- Baseline: the generalist agent's score is the benchmark everything else is measured against

### Code

On your **Mac terminal**, paste this entire block and press Enter:

```bash
python3 << 'PYEOF'

import openai
import os

client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])

# -----------------------------------------------------------------------
# TEST CASES
# -----------------------------------------------------------------------
# Each test case has:
#   metric   - the raw input
#   category - what domain it belongs to
#   expected - the correct severity answer

test_cases = [
    {"metric": "active_connections=199, max_connections=200", "category": "connections", "expected": "CRITICAL"},
    {"metric": "active_connections=50, max_connections=200",  "category": "connections", "expected": "OK"},
    {"metric": "replication_lag_seconds=600",                  "category": "replication", "expected": "CRITICAL"},
    {"metric": "replication_lag_seconds=5",                    "category": "replication", "expected": "OK"},
    {"metric": "disk_usage_percent=95, tablespace=pg_default", "category": "storage",     "expected": "CRITICAL"},
    {"metric": "disk_usage_percent=40, tablespace=pg_default", "category": "storage",     "expected": "OK"},
    {"metric": "lock_wait_count=22, oldest_lock_age_sec=180",  "category": "locks",       "expected": "CRITICAL"},
    {"metric": "lock_wait_count=0",                            "category": "locks",       "expected": "OK"},
]

# -----------------------------------------------------------------------
# SPECIALIST AGENTS
# -----------------------------------------------------------------------
# Each specialist has a focused system prompt that encodes domain-specific thresholds.
# This is the same knowledge a DBA would write into an alert rule:
# "connection usage > 90% = CRITICAL"

specialist_prompts = {
    "connections": (
        "You are a PostgreSQL connection specialist. "
        "If connections exceed 90% of max_connections, respond CRITICAL. "
        "If between 70-90%, respond WARNING. Below 70%, respond OK. "
        "Respond with exactly one word."
    ),
    "replication": (
        "You are a PostgreSQL replication specialist. "
        "If replication lag exceeds 300 seconds, respond CRITICAL. "
        "If between 60-300 seconds, respond WARNING. Below 60 seconds, respond OK. "
        "Respond with exactly one word."
    ),
    "storage": (
        "You are a PostgreSQL storage specialist. "
        "If disk usage exceeds 90%, respond CRITICAL. "
        "If between 75-90%, respond WARNING. Below 75%, respond OK. "
        "Respond with exactly one word."
    ),
    "locks": (
        "You are a PostgreSQL lock contention specialist. "
        "If lock_wait_count exceeds 10 or oldest lock exceeds 120 seconds, respond CRITICAL. "
        "If lock_wait_count is 1-10, respond WARNING. Otherwise respond OK. "
        "Respond with exactly one word."
    ),
}

# -----------------------------------------------------------------------
# GENERALIST AGENT
# -----------------------------------------------------------------------

generalist_prompt = (
    "You are a general database health classifier. "
    "Given any database metric, respond with exactly one word: CRITICAL, WARNING, or OK."
)


def call_agent(system_prompt: str, metric: str) -> str:
    # Single reusable function - both specialist and generalist use the same call pattern
    # This is like a generic execute_query() wrapper that accepts different SQL strings
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": f"Metric: {metric}"}
        ]
    )
    result = response.choices[0].message.content.strip().upper()
    # Clamp unexpected responses to WARNING so scoring stays clean
    if result not in ("CRITICAL", "WARNING", "OK"):
        result = "WARNING"
    return result


# -----------------------------------------------------------------------
# RUN THE TEST
# -----------------------------------------------------------------------

specialist_correct = 0
generalist_correct = 0
total = len(test_cases)

print("=== SPECIALIZATION ACCURACY TEST ===\n")
print(f"{'Metric':<45} {'Cat':<12} {'Expected':<10} {'Specialist':<12} {'Generalist'}")
print("-" * 100)

for tc in test_cases:
    metric   = tc["metric"]
    category = tc["category"]
    expected = tc["expected"]

    # Route to the matching specialist based on the category key
    # This is like a partition-routing function: which node handles this row?
    specialist_prompt  = specialist_prompts[category]
    specialist_answer  = call_agent(specialist_prompt, metric)
    generalist_answer  = call_agent(generalist_prompt, metric)

    # Score: add 1 if the answer matches expected - like a CHECK constraint passing
    if specialist_answer == expected:
        specialist_correct += 1
    if generalist_answer == expected:
        generalist_correct += 1

    # ljust pads a string to a fixed width - keeps columns aligned
    print(f"{metric[:44]:<45} {category:<12} {expected:<10} {specialist_answer:<12} {generalist_answer}")

# Calculate accuracy as a percentage
# round(value, 1) = same as ROUND(value, 1) in SQL
specialist_accuracy = round((specialist_correct / total) * 100, 1)
generalist_accuracy = round((generalist_correct / total) * 100, 1)

print("-" * 100)
print(f"\nSpecialist accuracy : {specialist_accuracy}%  ({specialist_correct}/{total} correct)")
print(f"Generalist accuracy : {generalist_accuracy}%  ({generalist_correct}/{total} correct)")

PYEOF
```

### Expected output (yours will differ):

```
=== SPECIALIZATION ACCURACY TEST ===

Metric                                        Cat          Expected   Specialist   Generalist
----------------------------------------------------------------------------------------------------
active_connections=199, max_connections=200   connections  CRITICAL   CRITICAL     CRITICAL
active_connections=50, max_connections=200    connections  OK         OK           OK
replication_lag_seconds=600                   replication  CRITICAL   CRITICAL     CRITICAL
replication_lag_seconds=5                     replication  OK         OK           OK
disk_usage_percent=95, tablespace=pg_default  storage      CRITICAL   CRITICAL     CRITICAL
disk_usage_percent=40, tablespace=pg_default  storage      OK         OK           OK
lock_wait_count=22, oldest_lock_age_sec=180   locks        CRITICAL   CRITICAL     WARNING
lock_wait_count=0                             locks        OK         OK           OK
----------------------------------------------------------------------------------------------------

Specialist accuracy : 100.0%  (8/8 correct)
Generalist accuracy : 87.5%  (7/8 correct)
```

---

## Exercise 5: End-to-End Multi-Agent Alert System

### What you are building

A four-stage pipeline that mirrors a real DBA on-call workflow:

```
Stage 1 - Monitor   : reads the metric, describes what is happening
Stage 2 - Classify  : assigns severity (CRITICAL / WARNING / OK)
Stage 3 - Diagnose  : identifies the root cause
Stage 4 - Remediate : recommends the fix
```

This is the equivalent of: alert fires -> DBA looks at it -> DBA diagnoses -> DBA acts.
You are encoding that workflow into four cooperating agents.

### Concepts

- Each stage is an agent with a narrow job - the Unix "do one thing well" philosophy
- Data flows forward only - the output of stage N becomes the input of stage N+1
- The final result is a dict (like a row in an alerts table) containing all four fields

### Code

On your **Mac terminal**, paste this entire block and press Enter:

```bash
python3 << 'PYEOF'

import openai
import os

client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])

# -----------------------------------------------------------------------
# AGENT DEFINITIONS
# -----------------------------------------------------------------------

def agent_monitor(raw_metric: str) -> str:
    """Stage 1: Describe what is happening in plain English."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are a database monitor. Describe what the "
                                          "metric indicates in two sentences. Be factual and specific."},
            {"role": "user",   "content": f"Raw metric: {raw_metric}"}
        ]
    )
    return response.choices[0].message.content.strip()


def agent_classify(observation: str) -> str:
    """Stage 2: Assign a severity level to the observation."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are a severity classifier. Respond with "
                                          "exactly one word: CRITICAL, WARNING, or OK."},
            {"role": "user",   "content": f"Observation: {observation}"}
        ]
    )
    return response.choices[0].message.content.strip().upper()


def agent_diagnose(observation: str, severity: str) -> str:
    """Stage 3: Identify the root cause given the observation and severity."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a PostgreSQL root cause analyst. "
                    "Given a database observation and its severity, identify the most "
                    "likely root cause. One sentence only."
                )
            },
            {
                "role": "user",
                # We pass BOTH the observation and severity into this agent
                # Stage 3 knows what happened AND how bad it is before diagnosing
                "content": f"Observation: {observation}\nSeverity: {severity}"
            }
        ]
    )
    return response.choices[0].message.content.strip()


def agent_remediate(observation: str, root_cause: str, severity: str) -> str:
    """Stage 4: Recommend a concrete remediation action."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a PostgreSQL remediation specialist. "
                    "Given an observation, root cause, and severity, recommend ONE specific action. "
                    "Be concrete - name the exact PostgreSQL command or configuration change needed."
                )
            },
            {
                "role": "user",
                # Stage 4 gets everything the previous stages produced
                # This is cumulative context - each stage adds to the shared knowledge
                "content": (
                    f"Observation : {observation}\n"
                    f"Root cause  : {root_cause}\n"
                    f"Severity    : {severity}"
                )
            }
        ]
    )
    return response.choices[0].message.content.strip()


# -----------------------------------------------------------------------
# PIPELINE ORCHESTRATOR
# -----------------------------------------------------------------------
# This function runs all four agents in sequence and returns a structured result.
# Think of it as a stored procedure that calls four sub-procedures in order
# and returns a composite row type.

def run_alert_pipeline(raw_metric: str) -> dict:
    print(f"\nInput metric: {raw_metric}")
    print("Running pipeline...")

    # Stage 1
    print("  [1/4] Monitor agent...")
    observation = agent_monitor(raw_metric)

    # Stage 2 - receives Stage 1's output
    print("  [2/4] Classifier agent...")
    severity = agent_classify(observation)

    # Stage 3 - receives Stage 1 and Stage 2 outputs
    print("  [3/4] Diagnosis agent...")
    root_cause = agent_diagnose(observation, severity)

    # Stage 4 - receives all previous outputs
    print("  [4/4] Remediation agent...")
    remedy = agent_remediate(observation, root_cause, severity)

    # Return a dict - think of this as one row in an alerts table
    # Keys map to column names: observation, severity, root_cause, recommended_action
    return {
        "observation":        observation,
        "severity":           severity,
        "root_cause":         root_cause,
        "recommended_action": remedy
    }


# -----------------------------------------------------------------------
# RUN THREE DIFFERENT SCENARIOS
# -----------------------------------------------------------------------

scenarios = [
    "connections_used=199, max_connections=200, top_application=reporting_app",
    "checkpoint_completion_target=0.9, bgwriter_lru_maxpages=100, shared_buffers=128MB, dirty_pages_written=48000/sec",
    "autovacuum_running=false, dead_tuples=8500000, table=orders, last_vacuum=14_days_ago",
]

print("=" * 70)
print("END-TO-END MULTI-AGENT ALERT SYSTEM")
print("=" * 70)

# enumerate(scenarios, start=1) adds a counter starting at 1
# Like ROW_NUMBER() OVER (ORDER BY ...) in SQL
for i, metric in enumerate(scenarios, start=1):
    result = run_alert_pipeline(metric)

    print(f"\n--- ALERT REPORT #{i} ---")
    # .items() gives us (key, value) pairs - like iterating column names and values
    for key, value in result.items():
        # Replace underscores with spaces and capitalize the key for readability
        label = key.replace("_", " ").upper()
        print(f"{label}:\n  {value}\n")

print("=" * 70)

PYEOF
```

### Expected output (yours will differ):

```
======================================================================
END-TO-END MULTI-AGENT ALERT SYSTEM
======================================================================

Input metric: connections_used=199, max_connections=200, top_application=reporting_app
Running pipeline...
  [1/4] Monitor agent...
  [2/4] Classifier agent...
  [3/4] Diagnosis agent...
  [4/4] Remediation agent...

--- ALERT REPORT #1 ---
OBSERVATION:
  The database is at 99.5% of its maximum connection capacity with 199 out of 200
  connections in use, predominantly from the reporting_app application.

SEVERITY:
  CRITICAL

ROOT CAUSE:
  The reporting_app is likely holding long-lived connections without releasing them,
  exhausting the connection pool.

RECOMMENDED ACTION:
  Run SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name =
  'reporting_app' AND state = 'idle' AND state_change < NOW() - INTERVAL '10 minutes';
  then configure PgBouncer as a connection pooler.
...
```

---

## Summary

| Exercise | Pattern | DBA Analogy |
|----------|---------|-------------|
| 1 | Two-agent pipeline | `pg_stat_activity` -> alert rule |
| 2 | Audit trail | `pg_audit` log / `dba_audit` table |
| 3 | Voting / quorum | Patroni 2-of-3 failover |
| 4 | Specialization vs generalist | Partitioned index vs full-table index |
| 5 | Four-stage end-to-end | Alert fires -> diagnose -> remediate |

Next: Module 18 Survive labs - what happens when agents deadlock or go rogue.
