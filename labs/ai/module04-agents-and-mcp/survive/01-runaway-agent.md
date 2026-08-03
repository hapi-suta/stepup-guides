# SURVIVE 01: The Runaway Agent

Your agent is stuck in an infinite loop, calling the same tool over and over. Token costs are climbing. Time to fix it.

---

## The Scenario

A junior developer built an agent to investigate database slowness. It works sometimes, but when the database is healthy (no problems to find), the agent keeps looping - calling tools endlessly, never giving a final answer.

---

## Step 1. See the broken agent

On your **Mac terminal**, save and run this broken agent:

```bash
cat > /tmp/runaway_agent.py << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

tools = [
    {
        "name": "get_server_metrics",
        "description": "Get CPU, memory, disk metrics for a server.",
        "input_schema": {
            "type": "object",
            "properties": {"server": {"type": "string"}},
            "required": ["server"]
        }
    },
    {
        "name": "run_sql_query",
        "description": "Execute a read-only SQL query.",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"]
        }
    },
]

# Everything is healthy - no problems to find
def get_server_metrics(server):
    return json.dumps({"server": server, "cpu_percent": 15.2, "memory_percent": 42.1,
                       "disk_percent": 30.0, "active_connections": 25, "max_connections": 300})

def run_sql_query(query):
    return json.dumps({"rows": [], "message": "No issues found"})

REGISTRY = {"get_server_metrics": get_server_metrics, "run_sql_query": run_sql_query}

# BUG 1: No max_steps limit
# BUG 2: System prompt tells agent to "keep investigating until you find the problem"
# BUG 3: No cost tracking
def run_agent(question):
    system = """You are a PostgreSQL DBA agent. Keep investigating until you find the problem.
    Always use tools. Do not stop until you have found an issue to report."""

    messages = [{"role": "user", "content": question}]
    step = 0

    while True:  # BUG 1: infinite loop
        step += 1
        print(f"[Step {step}] Calling API...")

        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=300,
            system=system,
            tools=tools,
            messages=messages,
        )

        if response.stop_reason == "end_turn":
            for block in response.content:
                if block.type == "text":
                    print(f"Final: {block.text[:200]}")
            return

        if response.stop_reason == "tool_use":
            messages.append({"role": "assistant", "content": response.content})
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    print(f"[Step {step}] {block.name}({json.dumps(block.input)[:60]})")
                    result = REGISTRY[block.name](**block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })
            messages.append({"role": "user", "content": tool_results})

        # No exit condition if something unexpected happens
        # Agent can loop 20, 50, 100+ times

run_agent("The database feels slow, investigate.")
PYEOF
echo "Broken agent saved. DO NOT run this - it will loop and burn tokens."
echo "Read the code and find the 3 bugs first."
```

---

## Step 2. Understand what goes wrong

Without running the broken code, identify the 3 bugs:

```bash
python3 << 'PYEOF'
print("""
BUG 1: No max_steps limit
  Line: while True:  # runs forever
  Problem: If Claude never says "end_turn", the loop never stops.
  Cost: Each iteration is an API call. 50 loops = 50 API calls = $$$.

BUG 2: System prompt forces investigation
  Line: "Keep investigating until you find the problem"
  Problem: When everything is healthy, Claude CAN'T find a problem.
           But the prompt says "do not stop until you find an issue."
           So it keeps trying different queries, looking for something wrong.

BUG 3: No cost tracking
  Problem: No way to know how many tokens you've spent.
           In production, a runaway agent could burn hundreds of dollars
           before anyone notices.

Combined effect:
  - Healthy database (nothing to find)
  - System prompt says "don't stop until you find something"
  - No step limit to force an exit
  = Infinite loop of API calls
""")
PYEOF
```

---

## Step 3. Fix all 3 bugs

```bash
cat > /tmp/fixed_agent.py << 'PYEOF'
import anthropic
import json

client = anthropic.Anthropic()

tools = [
    {
        "name": "get_server_metrics",
        "description": "Get CPU, memory, disk metrics for a server.",
        "input_schema": {
            "type": "object",
            "properties": {"server": {"type": "string"}},
            "required": ["server"]
        }
    },
    {
        "name": "run_sql_query",
        "description": "Execute a read-only SQL query.",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"]
        }
    },
]

def get_server_metrics(server):
    return json.dumps({"server": server, "cpu_percent": 15.2, "memory_percent": 42.1,
                       "disk_percent": 30.0, "active_connections": 25, "max_connections": 300})

def run_sql_query(query):
    return json.dumps({"rows": [], "message": "No issues found"})

REGISTRY = {"get_server_metrics": get_server_metrics, "run_sql_query": run_sql_query}

# FIX 1: max_steps parameter
# FIX 2: System prompt allows "all clear" answers
# FIX 3: Token tracking
def run_agent(question, max_steps=6):
    # FIX 2: Rewritten system prompt
    system = """You are a PostgreSQL DBA agent. Investigate database issues using your tools.

Rules:
1. Gather data before making recommendations.
2. If everything looks healthy, say so. Not every investigation finds a problem.
3. After 2-3 tool calls, provide your assessment - even if it's "all clear."
4. Be specific about what you checked and what the values were."""

    messages = [{"role": "user", "content": question}]
    total_input_tokens = 0   # FIX 3
    total_output_tokens = 0  # FIX 3

    for step in range(max_steps):  # FIX 1: bounded loop
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=300,
            system=system,
            tools=tools,
            messages=messages,
        )

        # FIX 3: Track tokens
        total_input_tokens += response.usage.input_tokens
        total_output_tokens += response.usage.output_tokens

        if response.stop_reason == "end_turn":
            print(f"\n--- Final Answer (after {step} tool calls) ---")
            for block in response.content:
                if block.type == "text":
                    print(block.text)
            break

        if response.stop_reason == "tool_use":
            messages.append({"role": "assistant", "content": response.content})
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    print(f"[Step {step+1}] {block.name}({json.dumps(block.input)[:60]})")
                    result = REGISTRY[block.name](**block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })
            messages.append({"role": "user", "content": tool_results})
    else:
        # FIX 1: If we hit max_steps, force a summary
        print(f"\n[Hit max steps ({max_steps}). Agent stopped.]")

    # FIX 3: Print token usage
    print(f"\n--- Token Usage ---")
    print(f"Input tokens:  {total_input_tokens:,}")
    print(f"Output tokens: {total_output_tokens:,}")
    print(f"Total tokens:  {total_input_tokens + total_output_tokens:,}")
    estimated_cost = (total_input_tokens * 3 / 1_000_000) + (total_output_tokens * 15 / 1_000_000)
    print(f"Estimated cost: ${estimated_cost:.4f}")

run_agent("The database feels slow, investigate.")
PYEOF
echo "Fixed agent saved to /tmp/fixed_agent.py"
echo "Run: python3 /tmp/fixed_agent.py"
```

Expected output (yours will differ):
```
[Step 1] get_server_metrics({"server": "pg-primary"})
[Step 2] run_sql_query({"query": "SELECT state, count(*) FROM pg_stat_act...)

--- Final Answer (after 2 tool calls) ---
Good news - the database looks healthy:

- **CPU:** 15.2% (well within normal range)
- **Memory:** 42.1% (comfortable headroom)
- **Connections:** 25/300 (very low utilization)
- **Disk:** 30% used

No active issues found. The perceived slowness may be:
- Application-level (not database)
- Network latency between app and database
- A transient issue that has already resolved

--- Token Usage ---
Input tokens:  2,847
Output tokens: 312
Total tokens:  3,159
Estimated cost: $0.0132
```

The fixed agent:
- Checks 2 tools, finds nothing wrong, and says "all clear" (2 steps, not 50)
- Tracks exactly how many tokens it used
- Would stop at 6 steps maximum even if Claude kept requesting tools

---

## Step 4. What you learned

```bash
python3 << 'PYEOF'
print("""
Runaway Agent Fixes:

| Bug | Fix | Why It Matters |
|-----|-----|---------------|
| while True (no limit) | for step in range(max_steps) | Prevents infinite loops |
| "Don't stop until you find a problem" | "If healthy, say so" | Lets agent exit gracefully |
| No token tracking | Track input/output tokens | Know your costs in real time |

Production safeguards to add:
1. Token budget: stop if total_tokens > 50,000
2. Time budget: stop if elapsed > 30 seconds
3. Alerting: notify if agent uses > N steps on average
4. Circuit breaker: disable agent if cost > $X in 1 hour
""")
PYEOF
```
