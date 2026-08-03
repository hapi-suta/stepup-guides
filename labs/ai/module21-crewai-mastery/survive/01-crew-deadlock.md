# SURVIVE 01: The Delegation Deadlock

## Scenario

You built a 2-agent crew for incident response. Agent A is a "Triage Lead" and Agent B is a "Replication Specialist." Both have `allow_delegation=True`. You kick off the crew with a replication lag alert, and nothing happens for 10 minutes. Eventually, the crew times out or burns through your entire API budget.

What happened? Agent A looks at the alert and says "this is a replication issue, let me delegate to the Replication Specialist." Agent B gets it, looks at the metrics, and says "the root cause seems to be performance-related, let me delegate back to the Triage Lead for re-categorization." Agent A gets it back and delegates to B again. Infinite loop.

**DBA analogy:** This is like a database deadlock - transaction A holds lock 1 and waits for lock 2, transaction B holds lock 2 and waits for lock 1. Neither can proceed.

---

## The Broken Code

On your **Mac terminal**, run this to see the problem:

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# Both agents can delegate - this is the problem
triage = Agent(
    role='Triage Lead',
    goal='Classify alerts and route to specialists',
    backstory='''You classify alerts. If an alert is about replication, you
    ALWAYS delegate to the Replication Specialist. You never handle
    replication issues yourself.''',
    allow_delegation=True,    # BUG: can delegate
    verbose=True
)

repl = Agent(
    role='Replication Specialist',
    goal='Handle replication issues',
    backstory='''You handle replication issues. However, if you think the
    root cause is actually a performance problem (high CPU, slow queries),
    you delegate back to the Triage Lead for re-classification.''',
    allow_delegation=True,    # BUG: can delegate back
    verbose=True
)

task = Task(
    description='''Alert: pg-replica-1 replication lag is 30 seconds.
    Replica CPU: 95%. The replica is running a heavy analytics query.

    This alert has BOTH replication AND performance symptoms.
    Investigate and resolve.''',
    expected_output='Root cause and resolution.',
    agent=triage
)

crew = Crew(
    agents=[triage, repl],
    tasks=[task],
    process=Process.sequential,
    verbose=True
)

print('WARNING: This crew may enter a delegation loop.')
print('The triage agent delegates to replication specialist.')
print('The replication specialist delegates back to triage.')
print('Neither agent actually does the work.')
print()
print('In production, this burns API credits until the timeout.')
print()
# Uncomment below to see the loop (will use API credits):
# result = crew.kickoff()
print('(Crew kickoff commented out to save API credits)')
print('See the fix below.')
"
```

Expected output:
```
WARNING: This crew may enter a delegation loop.
The triage agent delegates to replication specialist.
The replication specialist delegates back to triage.
Neither agent actually does the work.

In production, this burns API credits until the timeout.

(Crew kickoff commented out to save API credits)
See the fix below.
```

---

## Your Mission

Fix the delegation deadlock so the crew resolves the alert without getting stuck in a loop.

**Rules:**
- Both agents must still exist in the crew
- The alert must be fully investigated (not just triaged)
- The fix should be structural (prevent the problem), not just a workaround

---

## Diagnostic Steps

Before fixing, understand the problem:

```bash
python3 -c "
print('Delegation Deadlock Diagnosis')
print('=' * 40)
print()
print('Symptoms:')
print('  - Crew runs for much longer than expected')
print('  - Same agents keep appearing in verbose output')
print('  - API costs spike without useful output')
print('  - Eventually times out or hits max iterations')
print()
print('Root cause:')
print('  - Both agents have allow_delegation=True')
print('  - Agent backstories encourage delegation')
print('  - The alert has mixed symptoms (replication + performance)')
print('  - Neither agent owns the final answer')
print()
print('This is exactly like a PostgreSQL deadlock:')
print('  Transaction A: LOCK table_1, then tries LOCK table_2')
print('  Transaction B: LOCK table_2, then tries LOCK table_1')
print('  Both wait forever.')
print()
print('PostgreSQL solution: deadlock_timeout detects it.')
print('CrewAI solution: break the cycle structurally.')
"
```

---

## Validation

After your fix, run the crew and verify:

1. The crew completes without getting stuck in a loop
2. Both agents contribute to the investigation
3. The output contains a root cause and resolution
4. The crew uses fewer than 6 API calls (a deadlocked crew uses 10+)

```bash
python3 -c "
# Your fixed crew should produce output like:
print('Expected: Crew completes in 2-3 agent calls')
print('Expected: Output contains root cause (analytics query on replica)')
print('Expected: Output contains fix (terminate query, set statement_timeout)')
print('Expected: No delegation loops in verbose output')
"
```

---

<details>
<summary>Runbook (hints, not answers)</summary>

**Fix 1: Remove delegation from specialists.**
The key insight: only the MANAGER should delegate. Specialists should do their assigned work and return results, never delegate back.

- Set `allow_delegation=False` on the Replication Specialist
- Keep `allow_delegation=True` only on the Triage Lead (if needed)

**Fix 2: Make backstories definitive.**
The backstory "if you think the root cause is performance, delegate back" is the trigger for the loop. Instead, the specialist's backstory should say "you handle ALL aspects of issues assigned to you, including performance-related root causes."

**Fix 3: Use explicit task assignments.**
Instead of relying on delegation, assign specific tasks to specific agents using `context`:
- Task 1 (triage): assigned to Triage Lead
- Task 2 (investigate + fix): assigned to Replication Specialist with `context=[task1]`

This eliminates the need for delegation entirely. It's the equivalent of a runbook with clear ownership per step.

**Fix 4: Set max_iter on agents.**
As a safety net: `Agent(max_iter=3)` prevents any agent from running more than 3 internal loops. This is like `deadlock_timeout` in PostgreSQL - it doesn't prevent the deadlock, but it limits the damage.
</details>

<details>
<summary>Solution</summary>

```bash
python3 -c "
from crewai import Agent, Task, Crew, Process

# FIX 1: Only the triage lead can delegate. Specialist cannot.
triage = Agent(
    role='Triage Lead',
    goal='Classify alerts and provide initial assessment',
    backstory='You classify alerts by severity and category. You provide your assessment, then the specialist takes over.',
    allow_delegation=False,    # FIXED: no delegation needed with explicit task flow
    verbose=True
)

# FIX 2: Specialist owns the full investigation - no delegating back
repl = Agent(
    role='Replication Specialist',
    goal='Fully investigate and resolve replication issues, including performance-related root causes',
    backstory='''You handle ALL aspects of replication issues, even when the
    root cause is performance-related (like a heavy query on the replica).
    You NEVER delegate back - you own the investigation from diagnosis to fix.''',
    allow_delegation=False,    # FIXED: never delegates
    verbose=True
)

# FIX 3: Explicit task chain with context (no delegation needed)
task_triage = Task(
    description='''Alert: pg-replica-1 replication lag is 30 seconds.
    Replica CPU: 95%. The replica is running a heavy analytics query.
    Classify severity and category.''',
    expected_output='Severity (P1-P4), category, and initial assessment.',
    agent=triage
)

task_investigate = Task(
    description='''Based on the triage, fully investigate this replication lag.
    The replica CPU is at 95% due to a heavy analytics query.
    Find the root cause and provide remediation with exact commands.''',
    expected_output='Root cause analysis and remediation plan with commands.',
    agent=repl,
    context=[task_triage]    # explicitly feeds triage output to specialist
)

crew = Crew(
    agents=[triage, repl],
    tasks=[task_triage, task_investigate],
    process=Process.sequential,
    verbose=True
)

print('Fixed crew: no delegation loops possible')
print('  - Triage Lead: classifies (no delegation)')
print('  - Replication Specialist: investigates fully (no delegation)')
print('  - Explicit context passing instead of delegation')
print()
result = crew.kickoff()
print()
print('RESULT:')
print(result)
"
```
</details>
