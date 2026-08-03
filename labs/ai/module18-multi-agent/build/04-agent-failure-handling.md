# Build 04: Agent Failure Handling

## What You Will Build

A resilient multi-agent system where agents can fail, degrade, or become unreliable - and the system keeps running. You will build three layers of protection: health monitoring, graceful degradation, and a circuit breaker.

By the end of this guide you will understand how production multi-agent systems stay alive even when individual components break down.

---

## Before You Start

You need:
- Python 3 installed (`python3 --version`)
- The `anthropic` Python package (`pip3 install anthropic`)
- An Anthropic API key exported in your terminal:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## Step 1: Agent Health Monitoring

### What is agent health monitoring?

In a production multi-agent system, agents are running processes. Any of them can:
- Crash (fail completely)
- Become slow or unresponsive (degraded)
- Start returning bad results (unhealthy but running)

Before routing a task to an agent, the system should check: is this agent healthy enough to receive work?

**DBA analogy:** This is exactly like monitoring replication status on your standbys. Before you promote a standby to primary during failover, you check:
- Is the standby streaming? (`pg_stat_replication`)
- How far is it behind? (replication lag)
- Is it responding to queries?

You would not promote a standby that is 30 minutes behind or not responding. You apply the same logic here: do not route tasks to an agent that is failing.

### The heartbeat system

A heartbeat is a lightweight check sent to an agent at regular intervals. If the agent responds, it is alive. If it does not respond (or responds too slowly), it is marked degraded or failed.

**DBA analogy:** Like the `pg_isready` command you run before connecting to a PostgreSQL instance. You send a tiny probe; a healthy instance responds immediately.

### Run this script

```bash
python3 << 'PYEOF'
import anthropic
import json
import time       # Used for timestamps and measuring elapsed time
                  # DBA analogy: like clock_timestamp() in PostgreSQL
import random     # Used to simulate random failures for testing
                  # DBA analogy: like random() in PostgreSQL test queries

client = anthropic.Anthropic()


# AgentStatus is a class - think of it like a row definition (schema) for one agent's health record
# Every agent gets one of these objects to track its current state
# DBA analogy: like one row in a pg_stat_replication view - status data for one replica
class AgentStatus:
    def __init__(self, name: str):
        self.name = name                    # agent identifier - like a server hostname
        self.status = "healthy"             # healthy | degraded | failed
        self.last_heartbeat = time.time()   # Unix timestamp of last successful response
                                            # time.time() returns seconds since epoch (like EXTRACT(EPOCH FROM NOW()))
        self.consecutive_failures = 0       # how many times in a row it has failed
        self.total_calls = 0                # total number of tasks sent to this agent
        self.total_failures = 0             # total number of failures (not just consecutive)

    def record_success(self):
        """Called when an agent responds successfully."""
        self.last_heartbeat = time.time()   # update the last-seen timestamp
        self.consecutive_failures = 0       # reset the consecutive failure counter
        self.total_calls += 1
        # If agent was degraded but now responding, promote it back to healthy
        if self.status == "degraded":
            self.status = "healthy"
            print(f"  [HEALTH] {self.name} recovered - status: healthy")

    def record_failure(self):
        """Called when an agent fails or times out."""
        self.consecutive_failures += 1      # increment consecutive failure count
        self.total_calls += 1
        self.total_failures += 1

        # After 2 consecutive failures: mark as degraded
        # After 5 consecutive failures: mark as failed
        # DBA analogy: like a replica that has been behind for 2 check intervals gets a WARNING,
        #              and behind for 5 intervals gets an ALERT
        if self.consecutive_failures >= 5:
            self.status = "failed"
            print(f"  [HEALTH] {self.name} marked FAILED after {self.consecutive_failures} consecutive failures")
        elif self.consecutive_failures >= 2:
            self.status = "degraded"
            print(f"  [HEALTH] {self.name} marked DEGRADED after {self.consecutive_failures} consecutive failures")

    def lag_seconds(self) -> float:
        """How many seconds since the last successful heartbeat."""
        # time.time() - self.last_heartbeat gives elapsed seconds
        # DBA analogy: like calculating replication lag in seconds
        return time.time() - self.last_heartbeat

    def summary(self) -> str:
        """One-line status summary for display."""
        failure_rate = (self.total_failures / self.total_calls * 100) if self.total_calls > 0 else 0
        return (f"{self.name}: status={self.status}, "
                f"consecutive_failures={self.consecutive_failures}, "
                f"failure_rate={failure_rate:.0f}%, "
                f"lag={self.lag_seconds():.1f}s")


# AgentRegistry is a class that tracks ALL agents in the system
# DBA analogy: like a monitoring table that has one row per replica
class AgentRegistry:
    def __init__(self):
        # self.agents is a dictionary: agent_name (string) -> AgentStatus object
        # DBA analogy: like a dict-indexed version of pg_stat_replication
        self.agents: dict = {}

    def register(self, name: str):
        """Add a new agent to the registry."""
        self.agents[name] = AgentStatus(name)
        print(f"  [REGISTRY] Registered agent: {name}")

    def get_status(self, name: str) -> AgentStatus:
        """Retrieve the status object for an agent."""
        return self.agents[name]

    def is_available(self, name: str) -> bool:
        """Returns True if the agent is healthy or degraded (still usable), False if failed."""
        status = self.agents[name].status
        # "healthy" and "degraded" agents can still receive tasks
        # "failed" agents should not receive tasks
        # DBA analogy: a degraded standby can still serve reads, but a failed standby cannot
        return status in ("healthy", "degraded")

    def print_all_statuses(self):
        """Print a health dashboard - like a monitoring summary view."""
        print("\n--- Agent Health Dashboard ---")
        for name, agent_status in self.agents.items():
            print(f"  {agent_status.summary()}")
        print("-----------------------------")


def send_heartbeat(registry: AgentRegistry, agent_name: str, fail_rate: float = 0.0):
    """
    Simulates sending a heartbeat ping to an agent.
    fail_rate controls how often the heartbeat fails (0.0 = never, 1.0 = always).
    In production, this would be a real network call or health-check endpoint.
    DBA analogy: like running `pg_isready -h standby_host` on a schedule
    """
    # random.random() returns a float between 0.0 and 1.0
    # If it falls below fail_rate, we simulate a failure
    if random.random() < fail_rate:
        registry.get_status(agent_name).record_failure()
        return False
    else:
        registry.get_status(agent_name).record_success()
        return True


# --- TEST IT ---
print("=== AGENT HEALTH MONITORING ===\n")

# Create the registry and register our specialist agents
registry = AgentRegistry()
for agent_name in ["performance_agent", "storage_agent", "connection_agent", "security_agent"]:
    registry.register(agent_name)

print("\nSimulating heartbeat rounds (like a monitoring loop running every 30s)...\n")

# Simulate 8 heartbeat rounds
# performance_agent: healthy (0% fail rate)
# storage_agent:     intermittently failing (40% fail rate)
# connection_agent:  consistently failing (90% fail rate)
# security_agent:    perfectly healthy (0% fail rate)
for round_number in range(1, 9):
    print(f"Round {round_number}:")
    send_heartbeat(registry, "performance_agent", fail_rate=0.0)
    send_heartbeat(registry, "storage_agent",     fail_rate=0.4)
    send_heartbeat(registry, "connection_agent",  fail_rate=0.9)
    send_heartbeat(registry, "security_agent",    fail_rate=0.0)

registry.print_all_statuses()

# Check which agents are available for task routing
print("\nAvailability check (used before routing tasks):")
for name in ["performance_agent", "storage_agent", "connection_agent", "security_agent"]:
    available = registry.is_available(name)
    print(f"  {name}: {'AVAILABLE' if available else 'NOT AVAILABLE - skip routing'}")
PYEOF
```

### What to expect

```
Expected output (yours will differ):
=== AGENT HEALTH MONITORING ===

  [REGISTRY] Registered agent: performance_agent
  [REGISTRY] Registered agent: storage_agent
  ...

Simulating heartbeat rounds...

Round 3:
  [HEALTH] connection_agent marked DEGRADED after 2 consecutive failures
Round 5:
  [HEALTH] connection_agent marked FAILED after 5 consecutive failures

--- Agent Health Dashboard ---
  performance_agent: status=healthy, consecutive_failures=0, failure_rate=0%, lag=0.0s
  storage_agent:     status=degraded, consecutive_failures=2, failure_rate=40%, lag=0.1s
  connection_agent:  status=failed, consecutive_failures=6, failure_rate=90%, lag=0.8s
  security_agent:    status=healthy, consecutive_failures=0, failure_rate=0%, lag=0.0s
```

---

## Step 2: Graceful Degradation

### What is graceful degradation?

Graceful degradation means: when one component fails, the rest of the system keeps running as best it can. The system does not crash completely just because one agent is down. It routes around the failure and uses fallback strategies.

**DBA analogy:** Automatic failover. When your primary PostgreSQL instance fails, the standby takes over. The application keeps running - maybe with a brief pause, maybe in read-only mode for a moment, but it does NOT go fully down. Streaming replication and repmgr exist precisely so that one failure does not end everything. Graceful degradation in multi-agent systems is the same idea.

### Fallback strategies

When a specialist agent is unavailable, you have three options:
1. **Use a fallback agent** - a simpler, cheaper, more reliable agent that covers the basics
2. **Use rule-based logic** - hardcoded rules that handle common cases without any AI
3. **Skip and flag** - skip the analysis for that domain but include a warning in the final report

**DBA analogy:**
- Fallback agent = promoting a warm standby when the primary dies
- Rule-based logic = a manual runbook your on-call DBA follows when monitoring tools are down
- Skip and flag = acknowledging in the incident report that the security check could not run

### Run this script

```bash
python3 << 'PYEOF'
import anthropic
import json
import random

client = anthropic.Anthropic()


# A simple fallback function that uses rule-based logic instead of an AI agent
# This runs without any API call - it is pure Python logic
# DBA analogy: like a manual runbook - if monitoring is down, follow these rules
def rule_based_fallback(agent_name: str, task: str) -> dict:
    """
    Returns a basic analysis based on hardcoded rules.
    Used when the real specialist agent is unavailable.
    This is NOT as good as the real agent, but it is better than nothing.
    """

    # These are hardcoded rules per agent type
    # Each entry in the dict is a domain: list of (keyword, finding, action) tuples
    # We check if any keyword from the task appears in our rules
    fallback_rules = {
        "performance_agent": [
            ("slow",    "Slow query detected",          "Run EXPLAIN ANALYZE on the slow query"),
            ("cpu",     "High CPU detected",            "Check pg_stat_activity for long-running queries"),
            ("lock",    "Lock contention suspected",    "Run SELECT * FROM pg_locks to identify blocking"),
            ("index",   "Possible missing index",       "Run pg_stat_user_indexes to find unused indexes"),
        ],
        "storage_agent": [
            ("disk",    "Disk pressure detected",       "Check df -h and pg_database_size()"),
            ("wal",     "WAL accumulation suspected",   "Check pg_ls_waldir() and replication slots"),
            ("bloat",   "Table bloat suspected",        "Run pgstattuple on large tables"),
        ],
        "connection_agent": [
            ("connection", "Connection pressure detected", "Check pg_stat_activity and connection counts"),
            ("idle",       "Idle connections detected",    "Terminate idle connections with pg_terminate_backend()"),
            ("pool",       "Connection pool issue",        "Check PgBouncer stats: SHOW POOLS"),
        ],
        "security_agent": [
            ("login",    "Authentication issue detected", "Check pg_log for failed login attempts"),
            ("privilege","Privilege change detected",     "Review pg_roles and recent GRANT statements"),
            ("access",   "Unusual access detected",       "Review pg_stat_activity for unexpected clients"),
        ],
    }

    # Convert the task to lowercase for case-insensitive matching
    # DBA analogy: like LOWER() in a SQL WHERE clause for case-insensitive search
    task_lower = task.lower()

    # Look up the rules for this specific agent type
    # .get() returns an empty list if the agent_name is not in the dict (safe default)
    rules = fallback_rules.get(agent_name, [])

    # Check each rule: if the keyword appears in the task, use that rule
    for keyword, finding, action in rules:
        if keyword in task_lower:
            return {
                "agent": agent_name,
                "mode": "FALLBACK_RULE_BASED",     # flag so we know this is a fallback result
                "findings": finding,
                "root_cause": f"Rule-based match on keyword '{keyword}' - real agent unavailable",
                "immediate_actions": [action, "Investigate further when specialist agent recovers"],
                "severity_score": 5,               # default middle-ground score for fallback results
                "warning": f"{agent_name} was unavailable. This is a rule-based fallback, not an AI diagnosis."
            }

    # If no rule matched, return a generic fallback
    return {
        "agent": agent_name,
        "mode": "FALLBACK_GENERIC",
        "findings": "Agent unavailable - no matching rule found",
        "root_cause": "Unknown - specialist agent required",
        "immediate_actions": ["Manual investigation required", f"Restart {agent_name} and re-run analysis"],
        "severity_score": 5,
        "warning": f"{agent_name} was unavailable and no matching fallback rule was found."
    }


def call_specialist_agent(agent_name: str, task: str, should_fail: bool = False) -> dict:
    """
    Simulates calling a specialist agent via the Claude API.
    should_fail=True simulates the agent being unavailable (for testing).
    """
    if should_fail:
        # Raise an exception to simulate the agent failing
        # DBA analogy: like a connection timeout when trying to reach a standby
        raise ConnectionError(f"{agent_name} is unreachable")

    response = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=300,
        system=f"""You are a PostgreSQL {agent_name.replace('_', ' ')}.
Respond ONLY with valid JSON:
{{
  "agent": "{agent_name}",
  "mode": "LIVE",
  "findings": "brief finding",
  "root_cause": "root cause",
  "immediate_actions": ["action1"],
  "severity_score": 7
}}""",
        messages=[{"role": "user", "content": task}]
    )
    result = json.loads(response.content[0].text)
    result["mode"] = "LIVE"
    return result


def route_with_degradation(tasks: dict, failed_agents: list) -> list:
    """
    Routes tasks to agents with graceful degradation.
    If an agent is in failed_agents, use the fallback instead.

    tasks: dict of agent_name -> task_string
    failed_agents: list of agent names that are currently unavailable
    """
    results = []

    for agent_name, task in tasks.items():
        print(f"\n  Routing to {agent_name}...")

        # Check if this agent is currently failed
        # DBA analogy: like checking pg_stat_replication before routing a read to a standby
        if agent_name in failed_agents:
            print(f"  {agent_name} is DOWN - using fallback")

            # Use the rule-based fallback instead of the real agent
            result = rule_based_fallback(agent_name, task)
            print(f"  Fallback result: {result['findings']}")
        else:
            # Try the real agent, but catch any unexpected failures too
            # try/except is like BEGIN/EXCEPTION in a PL/pgSQL block
            # If the code in "try" raises an error, "except" catches it
            try:
                result = call_specialist_agent(agent_name, task, should_fail=False)
                print(f"  Live result: {result['findings'][:60]}...")
            except Exception as e:
                # Even if we didn't expect this agent to fail, it did
                # Log the error and use the fallback anyway
                # DBA analogy: unexpected standby crash - activate the failover procedure
                print(f"  Unexpected failure for {agent_name}: {e} - using fallback")
                result = rule_based_fallback(agent_name, task)

        results.append(result)

    return results


# --- TEST IT ---
print("=== GRACEFUL DEGRADATION ===\n")

tasks = {
    "performance_agent": "CPU at 94%, 3 slow queries running over 10 minutes",
    "connection_agent":  "Connections at 487 of 500 max, many idle-in-transaction",
    "storage_agent":     "Disk at 89%, WAL directory growing fast",
}

# Simulate connection_agent being down
failed = ["connection_agent"]

print(f"Agents marked as failed: {failed}")
print("Routing tasks with graceful degradation...\n")

results = route_with_degradation(tasks, failed)

print("\n--- Results Summary ---")
for r in results:
    mode_label = f"[{r['mode']}]"
    print(f"  {mode_label:25s} {r['agent']}: {r['findings'][:70]}")
    if "warning" in r:
        print(f"    WARNING: {r['warning']}")
PYEOF
```

### What to expect

```
Expected output (yours will differ):
=== GRACEFUL DEGRADATION ===

Agents marked as failed: ['connection_agent']
Routing tasks with graceful degradation...

  Routing to performance_agent...
  Live result: Lock contention causing CPU spike from retry loops...

  Routing to connection_agent...
  connection_agent is DOWN - using fallback
  Fallback result: Connection pressure detected

  Routing to storage_agent...
  Live result: WAL accumulation from long transaction blocking recycling...

--- Results Summary ---
  [LIVE]                    performance_agent: Lock contention causing CPU spike...
  [FALLBACK_RULE_BASED]     connection_agent: Connection pressure detected
    WARNING: connection_agent was unavailable. This is a rule-based fallback...
  [LIVE]                    storage_agent: WAL accumulation...
```

The system produced a complete report for all three domains, even though one agent was down. The connection analysis is less detailed, but it is there and it is clearly flagged as a fallback.

---

## Step 3: Circuit Breaker Pattern

### What is a circuit breaker?

A circuit breaker is a pattern that stops sending work to a failing component after it has failed a certain number of times. After a cooldown period, it tries again cautiously. If the retry succeeds, it resumes normal operation.

There are three states:
- **CLOSED** - normal operation, requests flow through (circuit is closed = current flows)
- **OPEN** - too many failures, requests are blocked (circuit is open = current is cut)
- **HALF_OPEN** - cooldown period is over, send ONE test request to see if the agent recovered

**DBA analogy:** PgBouncer has a concept of marking a backend as down. When a backend server fails health checks too many times, PgBouncer stops routing connections to it. After a retry interval, PgBouncer sends a test connection. If the test succeeds, the backend is returned to the pool. If it fails again, the backend stays marked as down. This is exactly the circuit breaker pattern.

Without a circuit breaker, a failed agent would receive a flood of tasks, fail every one, and every API call would waste money and slow down your system. The circuit breaker prevents this.

### Run this script

```bash
python3 << 'PYEOF'
import time
import json
import random


# CircuitBreaker is a class that wraps an agent function
# It tracks failure counts and manages the three states: CLOSED, OPEN, HALF_OPEN
# DBA analogy: like PgBouncer sitting in front of a PostgreSQL backend
#              - PgBouncer decides whether to send the connection or block it
class CircuitBreaker:
    def __init__(self,
                 name: str,
                 failure_threshold: int = 3,
                 cooldown_seconds: float = 10.0):
        """
        name: the agent this circuit breaker protects
        failure_threshold: how many consecutive failures before opening the circuit
        cooldown_seconds: how long to wait in OPEN state before trying again
        """
        self.name = name
        self.failure_threshold = failure_threshold
        self.cooldown_seconds = cooldown_seconds

        self.state = "CLOSED"              # start in normal operating state
        self.consecutive_failures = 0      # consecutive failure counter
        self.opened_at = None              # timestamp when circuit was opened
                                           # None means it has never been opened

    def _should_attempt(self) -> bool:
        """
        Decides whether to allow a request through.
        Returns True if the request should proceed, False if it should be blocked.
        """
        if self.state == "CLOSED":
            # Normal operation - always allow through
            return True

        if self.state == "OPEN":
            # Circuit is open - check if cooldown period has elapsed
            # time.time() - self.opened_at gives seconds since circuit opened
            elapsed = time.time() - self.opened_at
            if elapsed >= self.cooldown_seconds:
                # Cooldown is over - move to HALF_OPEN and allow ONE test request
                # DBA analogy: like PgBouncer's retry interval expiring,
                #              sending one test connection to the backend
                self.state = "HALF_OPEN"
                print(f"  [CIRCUIT] {self.name}: OPEN -> HALF_OPEN (cooldown elapsed {elapsed:.1f}s)")
                return True
            else:
                # Still in cooldown - block the request
                print(f"  [CIRCUIT] {self.name}: OPEN - blocking request (cooldown: {elapsed:.1f}/{self.cooldown_seconds}s)")
                return False

        if self.state == "HALF_OPEN":
            # Allow the single test request through
            return True

        return False   # should never reach here, but safe default

    def _on_success(self):
        """Called when the wrapped function succeeds."""
        if self.state == "HALF_OPEN":
            # Test request succeeded - fully recover
            # DBA analogy: PgBouncer's test connection worked, backend is healthy again
            print(f"  [CIRCUIT] {self.name}: HALF_OPEN -> CLOSED (recovery confirmed)")
            self.state = "CLOSED"
        self.consecutive_failures = 0   # reset failure counter on any success

    def _on_failure(self):
        """Called when the wrapped function raises an exception."""
        self.consecutive_failures += 1

        if self.state == "HALF_OPEN":
            # Test request also failed - go back to OPEN and reset the cooldown timer
            # DBA analogy: PgBouncer's test connection failed, backend still down
            print(f"  [CIRCUIT] {self.name}: HALF_OPEN -> OPEN (test failed, resetting cooldown)")
            self.state = "OPEN"
            self.opened_at = time.time()   # restart the cooldown timer
            return

        if self.consecutive_failures >= self.failure_threshold:
            # Too many consecutive failures - open the circuit
            # DBA analogy: PgBouncer marks the backend as down after N failed health checks
            print(f"  [CIRCUIT] {self.name}: CLOSED -> OPEN "
                  f"({self.consecutive_failures} consecutive failures)")
            self.state = "OPEN"
            self.opened_at = time.time()   # record when the circuit opened

    def call(self, agent_func, task: str) -> dict:
        """
        The main entry point. Wraps agent_func with circuit breaker logic.
        agent_func: the actual function to call
        task: the argument to pass to agent_func
        Returns the result dict, or a circuit-open error dict if blocked.
        """
        if not self._should_attempt():
            # Circuit is open - return an error dict without calling the agent at all
            # DBA analogy: PgBouncer returns "no server available" without touching PostgreSQL
            return {
                "agent": self.name,
                "mode": "CIRCUIT_OPEN",
                "findings": "Circuit breaker is OPEN - agent requests blocked",
                "root_cause": "Agent failed too many times",
                "immediate_actions": [f"Investigate and restart {self.name}"],
                "severity_score": 0,
                "warning": f"Circuit breaker for {self.name} is OPEN. No request was sent."
            }

        # Circuit allows the request - try to call the agent
        try:
            result = agent_func(task)          # call the real agent function
            self._on_success()                 # record success
            return result
        except Exception as e:
            # Agent call raised an exception - record failure
            print(f"  [CIRCUIT] {self.name}: call failed - {e}")
            self._on_failure()                 # record failure, possibly open circuit
            # Return an error dict so the caller always gets a result
            return {
                "agent": self.name,
                "mode": "CIRCUIT_FAILURE",
                "findings": f"Agent call failed: {e}",
                "root_cause": "Agent unavailable",
                "immediate_actions": [f"Investigate {self.name} failure"],
                "severity_score": 0,
                "warning": f"{self.name} failed. Circuit breaker state: {self.state}"
            }

    def status(self) -> str:
        """One-line status for display."""
        if self.state == "OPEN":
            elapsed = time.time() - self.opened_at
            return f"{self.name}: {self.state} (opened {elapsed:.1f}s ago, cooldown={self.cooldown_seconds}s)"
        return f"{self.name}: {self.state} (consecutive_failures={self.consecutive_failures})"


# Simulated agent functions for testing
# fail_rate controls how often each agent fails
def make_agent(agent_name: str, fail_rate: float):
    """
    Factory function that creates a simulated agent function.
    A factory function is a function that returns another function.
    DBA analogy: like a function that returns a query plan, not the result itself.
    """
    def agent(task: str) -> dict:
        # random.random() < fail_rate: True with probability = fail_rate
        if random.random() < fail_rate:
            raise RuntimeError(f"{agent_name} internal error")
        return {
            "agent": agent_name,
            "mode": "LIVE",
            "findings": f"Analysis complete for: {task[:40]}",
            "root_cause": "Identified root cause",
            "immediate_actions": ["Take action 1", "Take action 2"],
            "severity_score": 7
        }
    return agent   # return the function itself, not the result of calling it


# --- TEST IT ---
print("=== CIRCUIT BREAKER PATTERN ===\n")

# Create agents: one reliable, one flaky, one completely broken
perf_agent    = make_agent("performance_agent", fail_rate=0.0)  # always succeeds
storage_agent = make_agent("storage_agent",     fail_rate=0.7)  # fails 70% of the time
conn_agent    = make_agent("connection_agent",  fail_rate=1.0)  # always fails

# Create circuit breakers for each agent
# failure_threshold=3: open circuit after 3 consecutive failures
# cooldown_seconds=5:  wait 5 seconds before trying again (short for demo)
cb_perf    = CircuitBreaker("performance_agent", failure_threshold=3, cooldown_seconds=5)
cb_storage = CircuitBreaker("storage_agent",     failure_threshold=3, cooldown_seconds=5)
cb_conn    = CircuitBreaker("connection_agent",  failure_threshold=3, cooldown_seconds=5)

task = "CPU at 94%, disk at 89%, connections at 487/500"

print("Sending 8 rounds of tasks to all agents...\n")

for round_num in range(1, 9):
    print(f"--- Round {round_num} ---")

    # Each call goes through the circuit breaker
    # The circuit breaker decides: send the request OR block it
    r1 = cb_perf.call(perf_agent,    task)
    r2 = cb_storage.call(storage_agent, task)
    r3 = cb_conn.call(conn_agent,    task)

    print(f"  performance: {r1['mode']}")
    print(f"  storage:     {r2['mode']}")
    print(f"  connection:  {r3['mode']}")

    # Small pause between rounds to make timing visible
    # In production, rounds would be driven by actual incoming alerts
    time.sleep(0.2)

print("\n--- Circuit Breaker Status After 8 Rounds ---")
print(f"  {cb_perf.status()}")
print(f"  {cb_storage.status()}")
print(f"  {cb_conn.status()}")

print("\nWaiting 5 seconds for cooldown to expire on connection_agent...")
time.sleep(5.5)   # wait slightly longer than cooldown_seconds=5

print("\n--- Round 9 (after cooldown) ---")
r = cb_conn.call(conn_agent, task)
print(f"  connection: {r['mode']}")
print(f"  {cb_conn.status()}")
print("\nNote: connection_agent still fails (fail_rate=1.0), so it goes back to OPEN.")
PYEOF
```

### What to expect

```
Expected output (yours will differ):
=== CIRCUIT BREAKER PATTERN ===

Sending 8 rounds of tasks to all agents...

--- Round 1 ---
  performance: LIVE
  storage:     LIVE
  connection:  CIRCUIT_FAILURE
--- Round 3 ---
  [CIRCUIT] connection_agent: CLOSED -> OPEN (3 consecutive failures)
  performance: LIVE
  storage:     LIVE
  connection:  CIRCUIT_FAILURE
--- Round 4 ---
  [CIRCUIT] connection_agent: OPEN - blocking request (cooldown: 0.6/5.0s)
  performance: LIVE
  storage:     CIRCUIT_FAILURE (or LIVE, depends on random)
  connection:  CIRCUIT_OPEN

--- Circuit Breaker Status After 8 Rounds ---
  performance_agent: CLOSED (consecutive_failures=0)
  storage_agent:     OPEN (opened 1.6s ago, cooldown=5s)
  connection_agent:  OPEN (opened 1.8s ago, cooldown=5s)

Waiting 5 seconds for cooldown to expire...

--- Round 9 (after cooldown) ---
  [CIRCUIT] connection_agent: OPEN -> HALF_OPEN (cooldown elapsed 5.5s)
  [CIRCUIT] connection_agent: HALF_OPEN -> OPEN (test failed, resetting cooldown)
  connection: CIRCUIT_FAILURE
```

Notice that during rounds 4-8, the circuit breaker blocks the connection_agent entirely - no API call is made, no money is spent, no time is wasted. The system fails fast and moves on.

---

## Putting It All Together

The three steps form a layered defense:

```
Incoming alert
    |
    v
[Health Monitor] -- checks heartbeats --> agent_status map
    |
    v
[Router with Graceful Degradation]
    |-- agent HEALTHY   -> route to live agent
    |-- agent DEGRADED  -> route to live agent (but flag results)
    |-- agent FAILED    -> use fallback (rule-based or simpler agent)
    |
    v
[Circuit Breaker] -- wraps every live agent call
    |-- state CLOSED    -> send request, track success/failure
    |-- state OPEN      -> block request immediately, return error dict
    |-- state HALF_OPEN -> send one test request, recover or re-open
    |
    v
Results (mix of LIVE, FALLBACK, and CIRCUIT_OPEN) -> aggregator
```

This is how production systems stay alive under partial failure. Individual components break - your orchestration layer keeps the overall system running.

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---|---|---|
| Agent health monitoring | Tracks status of each agent (healthy, degraded, failed) | Monitoring replication status in pg_stat_replication |
| Heartbeat | Lightweight periodic check to confirm an agent is alive | `pg_isready` run on a schedule |
| record_success / record_failure | Update an agent's health status after each call | Incrementing or resetting a replication lag counter |
| Graceful degradation | Keep the system running when an agent fails, using a fallback | Automatic failover to standby when primary dies |
| Rule-based fallback | Hardcoded logic that handles common cases without AI | A manual DBA runbook used when monitoring tools are down |
| Circuit breaker | Stops sending work to a repeatedly failing agent | PgBouncer marking a backend as down after N failed health checks |
| CLOSED state | Normal operation, requests flow through | Backend in the active pool |
| OPEN state | Too many failures, requests are blocked | Backend marked as down, no connections sent |
| HALF_OPEN state | Cooldown elapsed, send one test request | PgBouncer's retry interval: send one test connection |
| failure_threshold | How many consecutive failures before opening the circuit | N failed health checks before marking backend as down |
| cooldown_seconds | How long to wait before retrying a failed agent | PgBouncer's `server_login_retry` interval |
| Factory function | A function that returns another function | A function that returns a query plan, not the result |
| try/except | Catch errors without crashing the whole program | BEGIN/EXCEPTION block in PL/pgSQL |
