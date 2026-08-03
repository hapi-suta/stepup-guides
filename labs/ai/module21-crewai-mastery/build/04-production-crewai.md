# Build 04: Production CrewAI

Your crews work in the terminal. Now you need them to work in production - with error handling, cost control, testing, and integration with your existing tools. This guide covers the patterns that separate demo crews from production crews.

## DBA Analogy: Dev vs Production

| Dev Crew | Production Crew |
|---------|----------------|
| Runs in terminal, you watch it | Runs unattended, triggered by alerts |
| Errors crash the process | Errors are caught, logged, and escalated |
| No cost tracking | Every LLM call is tracked and budgeted |
| "It worked once" | Tested with unit tests, integration tests, chaos tests |
| Single crew | Pipeline of crews with handoffs |
| Like running ad-hoc queries in psql | Like a stored procedure with error handling, logging, and monitoring |

---

## Step 1. CrewAI Flows - pipelines of crews

A Flow connects multiple crews into a pipeline. Think of it like a CI/CD pipeline where each stage is a crew.

**DBA analogy:** A Flow is like a multi-step maintenance window:
1. Pre-check crew (verify backups, check replication)
2. Migration crew (run DDL, update configs)
3. Post-check crew (verify everything still works)

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.flow.flow import Flow, listen, start

class IncidentFlow(Flow):
    '''Multi-stage incident response flow.'''

    @start()
    def triage_stage(self):
        '''Stage 1: Triage the alert.'''
        print('STAGE 1: Triage')
        triage_agent = Agent(
            role='Triage Lead',
            goal='Classify the incident',
            backstory='Expert at rapid triage.',
            verbose=False
        )
        task = Task(
            description=f'''Triage this alert: {self.state.get('alert', 'Unknown alert')}.
            Classify as P1-P4 and categorize.''',
            expected_output='Severity and category.',
            agent=triage_agent
        )
        crew = Crew(agents=[triage_agent], tasks=[task], process=Process.sequential, verbose=False)
        result = crew.kickoff()
        return str(result)

    @listen(triage_stage)
    def investigate_stage(self, triage_result):
        '''Stage 2: Investigate based on triage.'''
        print(f'STAGE 2: Investigate (triage said: {str(triage_result)[:80]}...)')
        investigator = Agent(
            role='Investigator',
            goal='Find the root cause',
            backstory='Deep PostgreSQL internals expert.',
            verbose=False
        )
        task = Task(
            description=f'''Triage result: {triage_result}
            Investigate the root cause. Provide specific diagnostic steps.''',
            expected_output='Root cause analysis.',
            agent=investigator
        )
        crew = Crew(agents=[investigator], tasks=[task], process=Process.sequential, verbose=False)
        result = crew.kickoff()
        return str(result)

    @listen(investigate_stage)
    def remediate_stage(self, investigation_result):
        '''Stage 3: Remediate based on investigation.'''
        print(f'STAGE 3: Remediate (investigation said: {str(investigation_result)[:80]}...)')
        fixer = Agent(
            role='Remediation Engineer',
            goal='Fix the issue safely',
            backstory='Expert at safe production changes.',
            verbose=False
        )
        task = Task(
            description=f'''Investigation result: {investigation_result}
            Create a remediation plan with exact commands and rollback steps.''',
            expected_output='Remediation plan with commands.',
            agent=fixer
        )
        crew = Crew(agents=[fixer], tasks=[task], process=Process.sequential, verbose=False)
        result = crew.kickoff()
        return str(result)

# Run the flow
flow = IncidentFlow()
print('Incident Response Flow')
print('=' * 40)
print('Pipeline: Triage -> Investigate -> Remediate')
print()
final = flow.kickoff(inputs={
    'alert': 'pg-primary connection pool exhausted. 200/200 connections used. New connections failing.'
})
print()
print('FINAL RESULT:')
print(final)
"
```

Expected output (yours will differ):
```
Incident Response Flow
========================================
Pipeline: Triage -> Investigate -> Remediate

STAGE 1: Triage
STAGE 2: Investigate (triage said: P1 - Connection exhaustion on pg-primary...)
STAGE 3: Remediate (investigation said: Root cause: connection leak from app server...)

FINAL RESULT:
## Remediation Plan
1. Identify idle connections: SELECT pid, state, query_start FROM pg_stat_activity...
2. Terminate idle-in-transaction: SELECT pg_terminate_backend(pid)...
...
```

Flows give you a clear pipeline with explicit stage boundaries. If stage 2 fails, you know exactly where the pipeline stopped - like a CI/CD pipeline with stage gates.

---

## Step 2. Error handling

In production, agents can fail: API rate limits, malformed responses, tool errors, timeouts. You need to handle these gracefully.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool
import traceback

# A tool that sometimes fails (like a database connection timeout)
@tool('Flaky Database Check')
def flaky_check(server: str) -> str:
    '''Check a database server. May fail due to network issues.'''
    import random
    random.seed(42)    # deterministic for demo
    if random.random() < 0.3:    # 30% failure rate
        raise ConnectionError(f'Connection to {server} timed out after 5 seconds')
    return f'{server}: healthy (connections: 45/200, lag: 0s)'

# Wrap crew execution with error handling
def run_crew_safely(alert_text: str) -> dict:
    '''Run a crew with full error handling.'''
    result = {
        'status': 'unknown',
        'output': None,
        'error': None,
        'retries': 0,
    }

    agent = Agent(
        role='On-Call DBA',
        goal='Check database health',
        backstory='Handles flaky connections gracefully.',
        tools=[flaky_check],
        verbose=False,
        max_retry_limit=2    # retry failed tool calls up to 2 times
    )

    task = Task(
        description=f'Respond to: {alert_text}',
        expected_output='Health check result or error report.',
        agent=agent
    )

    crew = Crew(
        agents=[agent],
        tasks=[task],
        process=Process.sequential,
        verbose=False
    )

    max_attempts = 3
    for attempt in range(1, max_attempts + 1):
        try:
            print(f'  Attempt {attempt}/{max_attempts}...')
            crew_result = crew.kickoff()
            result['status'] = 'success'
            result['output'] = str(crew_result)
            result['retries'] = attempt - 1
            return result
        except Exception as e:
            result['error'] = str(e)
            result['retries'] = attempt
            print(f'  Attempt {attempt} failed: {e}')
            if attempt < max_attempts:
                print(f'  Retrying...')

    result['status'] = 'failed'
    return result

# Run it
print('Running crew with error handling...')
print()
outcome = run_crew_safely('Check health of pg-primary and pg-replica-1')
print()
print(f'Status: {outcome[\"status\"]}')
print(f'Retries: {outcome[\"retries\"]}')
if outcome['output']:
    print(f'Output: {str(outcome[\"output\"])[:200]}...')
if outcome['error']:
    print(f'Last error: {outcome[\"error\"]}')
"
```

Expected output (yours will differ):
```
Running crew with error handling...

  Attempt 1/3...
  ...

Status: success
Retries: 0
Output: pg-primary: healthy (connections: 45/200, lag: 0s)...
```

Key patterns:
- `max_retry_limit` on the agent - retries failed tool calls automatically
- Outer retry loop - retries the entire crew if it fails
- Structured result dict - always know the status, output, and error

**DBA analogy:** This is like `pg_isready` with retries - you don't give up on the first connection timeout. You retry a few times before declaring the server down.

---

## Step 3. Rate limiting and cost control

Every agent call costs API credits. A 4-agent crew making 2 calls each = 8 API calls. At scale, this adds up fast.

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
import time

# Cost tracking wrapper
class CostTracker:
    def __init__(self, budget_dollars: float):
        self.budget = budget_dollars
        self.spent = 0.0
        self.calls = 0

    def track_call(self, model: str, input_tokens: int, output_tokens: int) -> None:
        # Approximate costs per 1K tokens (as of 2026)
        costs = {
            'gpt-4o': {'input': 0.005, 'output': 0.015},
            'gpt-4o-mini': {'input': 0.00015, 'output': 0.0006},
            'claude-sonnet': {'input': 0.003, 'output': 0.015},
        }
        rates = costs.get(model, costs['gpt-4o'])
        cost = (input_tokens / 1000 * rates['input']) + (output_tokens / 1000 * rates['output'])
        self.spent += cost
        self.calls += 1

    def check_budget(self) -> bool:
        return self.spent < self.budget

    def report(self) -> str:
        return f'''Cost Report:
  API calls: {self.calls}
  Total spent: \${self.spent:.4f}
  Budget: \${self.budget:.2f}
  Remaining: \${self.budget - self.spent:.4f}
  Budget used: {(self.spent / self.budget * 100):.1f}%'''

# Demo the tracker
tracker = CostTracker(budget_dollars=1.00)

# Simulate crew API calls
calls = [
    ('gpt-4o', 800, 400),     # triage agent
    ('gpt-4o', 1200, 600),    # investigator
    ('gpt-4o', 1500, 800),    # remediation
    ('gpt-4o', 2000, 1000),   # post-mortem writer
]

print('Simulating a 4-agent incident crew:')
print()
for i, (model, inp, out) in enumerate(calls, 1):
    tracker.track_call(model, inp, out)
    print(f'  Agent {i}: {inp} input + {out} output tokens')
    if not tracker.check_budget():
        print(f'  WARNING: Budget exceeded!')
        break

print()
print(tracker.report())
print()
print('Cost reduction strategies:')
print('  1. Use gpt-4o-mini for simple tasks (triage, formatting)')
print('  2. Use gpt-4o only for complex reasoning (diagnosis)')
print('  3. Cache common responses (same alert = same triage)')
print('  4. Set max_tokens on agent responses')
print('  5. Reduce agent count - do you really need 5 agents or will 3 do?')
"
```

Expected output (yours will differ):
```
Simulating a 4-agent incident crew:

  Agent 1: 800 input + 400 output tokens
  Agent 2: 1200 input + 600 output tokens
  Agent 3: 1500 input + 800 output tokens
  Agent 4: 2000 input + 1000 output tokens

Cost Report:
  API calls: 4
  Total spent: $0.0695
  Budget: $1.00
  Remaining: $0.9305
  Budget used: 7.0%

Cost reduction strategies:
  1. Use gpt-4o-mini for simple tasks (triage, formatting)
  2. Use gpt-4o only for complex reasoning (diagnosis)
  ...
```

**DBA analogy:** This is like monitoring query costs in a serverless database. Each query costs money, so you optimize: use indexes (cheaper agents for simple tasks), cache results (don't re-triage known alerts), and set resource limits (max_tokens = statement_timeout).

---

## Step 4. Testing crews

You wouldn't deploy a migration without testing it. Same for crews. Here's how to test agents and tasks:

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# --- Test Framework ---
class CrewTest:
    def __init__(self, name: str):
        self.name = name
        self.passed = 0
        self.failed = 0
        self.results: list[dict] = []

    def check(self, description: str, condition: bool, detail: str = '') -> None:
        status = 'PASS' if condition else 'FAIL'
        if condition:
            self.passed += 1
        else:
            self.failed += 1
        self.results.append({'description': description, 'status': status, 'detail': detail})
        print(f'  [{status}] {description}' + (f' - {detail}' if detail and not condition else ''))

    def summary(self) -> str:
        total = self.passed + self.failed
        return f'{self.name}: {self.passed}/{total} passed, {self.failed} failed'

# --- Unit Tests ---
print('=== Unit Tests: Agent Configuration ===')
print()

test = CrewTest('Agent Config')

# Test 1: Agent has correct role
triage = Agent(
    role='Database Triage Lead',
    goal='Classify alerts by severity',
    backstory='Senior DBA with 15 years experience.',
    verbose=False
)
test.check('Triage agent has correct role', triage.role == 'Database Triage Lead')
test.check('Triage agent has a goal', len(triage.goal) > 0)
test.check('Triage agent has a backstory', len(triage.backstory) > 0)

# Test 2: Agent with tools has tools
from crewai.tools import tool

@tool('Mock Check')
def mock_check(server: str) -> str:
    '''Mock tool for testing.'''
    return f'{server}: OK'

tooled_agent = Agent(
    role='DBA with Tools',
    goal='Use tools to check databases',
    backstory='Has access to diagnostic tools.',
    tools=[mock_check],
    verbose=False
)
test.check('Agent has 1 tool', len(tooled_agent.tools) == 1)
test.check('Tool name is correct', tooled_agent.tools[0].name == 'Mock Check')

print()
print(test.summary())

# --- Integration Tests ---
print()
print('=== Integration Tests: Task Execution ===')
print()

test2 = CrewTest('Task Execution')

# Test: Crew produces output
task = Task(
    description='Classify this as P1, P2, P3, or P4: Database disk is 95% full.',
    expected_output='A severity level (P1-P4) with justification.',
    agent=triage
)

crew = Crew(agents=[triage], tasks=[task], process=Process.sequential, verbose=False)

try:
    result = crew.kickoff()
    result_text = str(result).upper()
    test2.check('Crew produced output', len(str(result)) > 0)
    test2.check('Output contains severity level',
                any(p in result_text for p in ['P1', 'P2', 'P3', 'P4']),
                f'Output: {str(result)[:100]}')
    test2.check('Output is not empty', str(result).strip() != '')
except Exception as e:
    test2.check('Crew execution succeeded', False, str(e))

print()
print(test2.summary())

# --- Summary ---
print()
print('=== Test Summary ===')
total_pass = test.passed + test2.passed
total_fail = test.failed + test2.failed
print(f'Total: {total_pass}/{total_pass + total_fail} passed')
if total_fail > 0:
    print('SOME TESTS FAILED - do not deploy')
else:
    print('ALL TESTS PASSED - safe to deploy')
"
```

Expected output (yours will differ):
```
=== Unit Tests: Agent Configuration ===

  [PASS] Triage agent has correct role
  [PASS] Triage agent has a goal
  [PASS] Triage agent has a backstory
  [PASS] Agent has 1 tool
  [PASS] Tool name is correct

Agent Config: 5/5 passed, 0 failed

=== Integration Tests: Task Execution ===

  [PASS] Crew produced output
  [PASS] Output contains severity level
  [PASS] Output is not empty

Task Execution: 3/3 passed, 0 failed

=== Test Summary ===
Total: 8/8 passed
ALL TESTS PASSED - safe to deploy
```

**DBA analogy:** Unit tests are like `SELECT 1` health checks - verify the basics. Integration tests are like running your migration on a staging database - verify the full flow works.

---

## Step 5. Crew composition - how many agents?

More agents is not always better. Each agent adds latency and cost.

On your **Mac terminal**, run:

```bash
python3 -c "
print('Crew Composition Guidelines')
print('=' * 40)
print()
print('When to use 1-2 agents:')
print('  - Simple, well-defined tasks')
print('  - Single domain (all performance, all replication)')
print('  - Speed matters more than thoroughness')
print('  - Example: Quick health check, simple alert classification')
print('  - DBA analogy: Solo on-call shift at 3am')
print()
print('When to use 3-4 agents:')
print('  - Multi-step workflows with handoffs')
print('  - Different expertise needed at each step')
print('  - Triage -> Investigate -> Fix is the sweet spot')
print('  - Example: Incident response, capacity planning')
print('  - DBA analogy: Standard incident response team')
print()
print('When to use 5+ agents:')
print('  - Complex, cross-domain problems')
print('  - Need multiple perspectives')
print('  - Quality matters more than speed/cost')
print('  - Example: Architecture review, post-mortem analysis')
print('  - DBA analogy: War room during a major outage')
print()
print('Cost estimate per crew run (gpt-4o):')
print('  2 agents: ~\$0.02-0.05')
print('  4 agents: ~\$0.05-0.15')
print('  6 agents: ~\$0.10-0.30')
print()
print('Rule of thumb: Start with 2 agents.')
print('Add more only when you see quality gaps.')
print('Like database indexes - add when needed, not preemptively.')
"
```

Expected output:
```
Crew Composition Guidelines
========================================

When to use 1-2 agents:
  - Simple, well-defined tasks
  ...

When to use 3-4 agents:
  - Multi-step workflows with handoffs
  ...

When to use 5+ agents:
  - Complex, cross-domain problems
  ...
```

---

## Step 6. Integration with external systems

Production crews need to talk to Slack, PagerDuty, Jira, and other tools. Here's the pattern using custom tools:

On your **Mac terminal**, run:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool
import json

# --- External system tools (simulated) ---

@tool('Send Slack Message')
def send_slack(channel: str, message: str) -> str:
    '''Send a message to a Slack channel.'''
    # In production: use slack_sdk
    # from slack_sdk import WebClient
    # client = WebClient(token=os.environ['SLACK_TOKEN'])
    # client.chat_postMessage(channel=channel, text=message)
    print(f'  [SLACK] #{channel}: {message[:80]}...')
    return f'Message sent to #{channel}'

@tool('Create Jira Ticket')
def create_jira(title: str, description: str, priority: str) -> str:
    '''Create a Jira ticket for tracking.'''
    # In production: use jira library
    # from jira import JIRA
    # jira = JIRA(server=url, basic_auth=(user, token))
    # issue = jira.create_issue(project='DBA', summary=title, ...)
    ticket_id = 'DBA-1234'
    print(f'  [JIRA] Created {ticket_id}: {title} (Priority: {priority})')
    return f'Ticket created: {ticket_id} - {title}'

@tool('Page On-Call DBA')
def page_oncall(severity: str, message: str) -> str:
    '''Page the on-call DBA via PagerDuty.'''
    # In production: use pdpyras (PagerDuty API)
    # session = pdpyras.EventsAPISession(routing_key)
    # session.trigger(summary=message, severity=severity)
    print(f'  [PAGERDUTY] {severity.upper()} page sent: {message[:60]}...')
    return f'Page sent at {severity} severity'

@tool('Write Post-Mortem')
def write_postmortem(title: str, content: str) -> str:
    '''Write a post-mortem document.'''
    filepath = f'/tmp/postmortem_{title.replace(\" \", \"_\")[:30]}.md'
    # In production: write to Confluence or Google Docs
    print(f'  [POSTMORTEM] Written to {filepath}')
    return f'Post-mortem saved: {filepath}'

# --- Production Incident Crew ---
coordinator = Agent(
    role='Incident Coordinator',
    goal='Coordinate incident response and communicate with stakeholders',
    backstory='Manages incident communications. Keeps Slack updated, creates tickets, pages when needed.',
    tools=[send_slack, create_jira, page_oncall],
    verbose=True
)

investigator = Agent(
    role='Root Cause Analyst',
    goal='Find and document the root cause',
    backstory='PostgreSQL internals expert. Writes clear post-mortems.',
    tools=[write_postmortem],
    verbose=True
)

# Tasks
task_alert = Task(
    description='''New P1 alert: pg-primary is out of disk space. /pgdata is 99% full.
    WAL archiving has stopped. No new transactions can be written.
    1. Page the on-call DBA
    2. Send alert to #dba-incidents Slack channel
    3. Create a Jira ticket''',
    expected_output='Confirmation that on-call is paged, Slack notified, and Jira ticket created.',
    agent=coordinator
)

task_investigate = Task(
    description='''Investigate the disk space issue and write a post-mortem.
    Common causes: WAL accumulation, table bloat, temp files, unarchived WAL.
    Create a post-mortem with timeline, root cause, and action items.''',
    expected_output='Post-mortem document with root cause and prevention steps.',
    agent=investigator,
    context=[task_alert]
)

task_notify = Task(
    description='''Post the investigation results to Slack.
    Include: root cause summary, current status, and link to Jira ticket.''',
    expected_output='Slack message sent with investigation summary.',
    agent=coordinator,
    context=[task_investigate]
)

crew = Crew(
    agents=[coordinator, investigator],
    tasks=[task_alert, task_investigate, task_notify],
    process=Process.sequential,
    verbose=True
)

print('Production Incident Response Crew')
print('=' * 40)
print('External integrations: Slack, Jira, PagerDuty, Post-Mortem')
print()
result = crew.kickoff()
print()
print('RESULT:')
print(result)
"
```

Expected output (yours will differ):
```
Production Incident Response Crew
========================================
External integrations: Slack, Jira, PagerDuty, Post-Mortem

 [INFO]: Working Agent: Incident Coordinator
 ...
  [PAGERDUTY] CRITICAL page sent: pg-primary out of disk space. WAL archiving...
  [SLACK] #dba-incidents: P1 ALERT: pg-primary disk 99% full. WAL archiving...
  [JIRA] Created DBA-1234: P1 - pg-primary disk space critical (Priority: P1)
 ...
 [INFO]: Working Agent: Root Cause Analyst
 ...
  [POSTMORTEM] Written to /tmp/postmortem_pg-primary_disk_space.md
 ...
 [INFO]: Working Agent: Incident Coordinator
 ...
  [SLACK] #dba-incidents: Investigation complete. Root cause: WAL accumulation...

RESULT:
Investigation results posted to #dba-incidents...
```

---

## What You Built

In this guide you:
- Built **Flows** for multi-stage crew pipelines
- Added **error handling** with retries and structured results
- Implemented **cost tracking** and budgeting strategies
- Created a **test framework** for agents and crews
- Learned **crew composition** guidelines (when 2 agents vs 5)
- Integrated with **Slack, Jira, PagerDuty** via custom tools

**DBA translation:** You went from "a crew that runs in my terminal" to "a production incident response system that pages on-call, creates tickets, investigates root causes, writes post-mortems, and notifies the team on Slack - all automatically."

This is the full module. You now know how to build, test, and deploy CrewAI crews for database operations.
