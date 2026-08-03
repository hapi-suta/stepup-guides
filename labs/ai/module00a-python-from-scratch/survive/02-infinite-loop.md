# SURVIVE 02: The Infinite Loop That Ate the Server

**Module:** module00a-python-from-scratch
**Time:** 15-20 minutes
**Prerequisites:** BUILD 01-04 completed

---

## The Scenario

A junior engineer wrote a health check script that polls database servers every 5 seconds. It worked in testing with 3 servers. In production, with 12 servers, it entered an infinite loop and pegged the CPU at 100% for 20 minutes before someone killed it.

The monitoring system went blind during a failover event. You need to find the bug, fix it, and add safeguards so this never happens again.

---

## Part 1: Symptom

Here is the broken health check script. Create it:

```bash
vi /tmp/survive02_broken.py
```

Paste this code:

```python
# Broken health check - DO NOT RUN THIS, just read and diagnose

def find_unhealthy_servers(servers, threshold):
    """Keep checking servers until all are healthy.

    Remove unhealthy servers from the list and re-check.
    Returns when all remaining servers are healthy.
    """
    check_round = 0

    while len(servers) > 0:
        check_round = check_round + 1
        print(f"Round {check_round}: Checking {len(servers)} servers...")

        for server in servers:
            name = server[0]
            cpu = server[1]

            if cpu > threshold:
                print(f"  {name} is unhealthy (CPU: {cpu}%)")
                servers.remove(server)  # BUG: modifying list while iterating
            else:
                print(f"  {name} is healthy (CPU: {cpu}%)")

# Test data
test_servers = [
    ("pg-primary", 95),
    ("pg-replica1", 88),
    ("pg-replica2", 45),
    ("pg-replica3", 92),
    ("pg-replica4", 87),
    ("pg-replica5", 30),
]

find_unhealthy_servers(test_servers, 80)
print("All remaining servers are healthy!")
```

DO NOT run this script - it may loop for a very long time. Let's trace through the logic manually to understand the bug.

---

## Part 2: Diagnosis

There are two bugs in this script. Let's identify both.

**Bug 1: Modifying a list while iterating over it**

When you remove an item from a list while looping over it with `for server in servers`, Python gets confused. Here is what happens:

```
Round 1: servers = [A(95), B(88), C(45), D(92), E(87), F(30)]

Index 0: Check A(95) -> unhealthy -> REMOVE A
   List is now: [B(88), C(45), D(92), E(87), F(30)]
   BUT Python moves to index 1, which is now C(45), not B(88)!
   B(88) is SKIPPED entirely.

Index 1: Check C(45) -> healthy
Index 2: Check D(92) -> unhealthy -> REMOVE D
   List is now: [B(88), C(45), E(87), F(30)]
   Python moves to index 3, which is now F(30)
   E(87) is SKIPPED.

Index 3: Check F(30) -> healthy
```

After Round 1, the list is `[B(88), C(45), E(87), F(30)]`. B and E were never checked because removing items shifted the indexes.

**Bug 2: The while loop never terminates**

The while loop continues `while len(servers) > 0`. Healthy servers are never removed. The loop keeps re-checking the same healthy servers forever. Even if all unhealthy servers were eventually found and removed (they are not, due to Bug 1), the healthy servers remain and the loop runs forever.

**DBA analogy:** This is like a cursor that modifies the result set it is iterating over. In PostgreSQL, this would cause unpredictable behavior - rows could be skipped or processed twice. That is why we use `FOR UPDATE SKIP LOCKED` patterns instead of deleting mid-cursor.

Let's prove Bug 1 with a safe, limited version:

```bash
python3 -c "
servers = ['A', 'B', 'C', 'D', 'E']
print(f'Before: {servers}')

# Remove items while iterating - items get skipped
for s in servers:
    print(f'  Visiting: {s}')
    if s == 'B':
        servers.remove(s)

print(f'After: {servers}')
print('Notice: C was never visited because removing B shifted the indexes')
"
```

Expected output:
```
Before: ['A', 'B', 'C', 'D', 'E']
  Visiting: A
  Visiting: B
  Visiting: D
  Visiting: E
After: ['A', 'C', 'D', 'E']
Notice: C was never visited because removing B shifted the indexes
```

---

## Part 3: Fix with Validation

Now fix the script with proper patterns. Create the repaired version:

```bash
vi /tmp/survive02_fixed.py
```

Paste this code:

```python
# Fixed health check with proper loop patterns and safety limits

MAX_ROUNDS = 100  # safety limit - never loop more than this

def find_unhealthy_servers(servers, threshold):
    """Identify unhealthy servers and return two lists: healthy and unhealthy.

    Does NOT modify the original list.
    Uses a separate list to collect results (like building a new result set).
    """
    healthy = []
    unhealthy = []

    # Single pass - no mutation, no while loop needed
    for server in servers:
        name = server[0]
        cpu = server[1]

        if cpu > threshold:
            unhealthy.append(server)
            print(f"  UNHEALTHY: {name} (CPU: {cpu}%)")
        else:
            healthy.append(server)
            print(f"  HEALTHY:   {name} (CPU: {cpu}%)")

    return healthy, unhealthy

def monitor_with_retry(servers, threshold, max_retries=3):
    """Check servers with retry logic and safety limits.

    Simulates re-checking unhealthy servers (in real life, you would
    wait and re-poll). Includes a retry limit to prevent infinite loops.
    """
    retry = 0
    remaining = list(servers)  # copy the list - never modify the original

    while remaining and retry <= max_retries:
        if retry > 0:
            print(f"\n--- Retry {retry}/{max_retries} ---")

        print(f"Checking {len(remaining)} servers (threshold: {threshold}% CPU)...")
        healthy, unhealthy = find_unhealthy_servers(remaining, threshold)

        if not unhealthy:
            print("\nAll servers are healthy!")
            return healthy, []

        # Only re-check the unhealthy ones
        remaining = unhealthy
        retry = retry + 1

    if remaining:
        print(f"\nGave up after {max_retries} retries. Still unhealthy:")
        for name, cpu in remaining:
            print(f"  {name} (CPU: {cpu}%)")

    return healthy, remaining

# Test data - same as before
test_servers = [
    ("pg-primary", 95),
    ("pg-replica1", 88),
    ("pg-replica2", 45),
    ("pg-replica3", 92),
    ("pg-replica4", 87),
    ("pg-replica5", 30),
]

print("Server Health Monitor")
print("=" * 50)
healthy, still_unhealthy = monitor_with_retry(test_servers, 80, max_retries=2)

print(f"\nSummary:")
print(f"  Healthy servers:   {len(healthy)}")
print(f"  Unhealthy servers: {len(still_unhealthy)}")

# Verify original list was NOT modified
print(f"\n  Original list intact: {len(test_servers)} servers")
```

Run the fixed version:

```bash
python3 /tmp/survive02_fixed.py
```

Expected output:
```
Server Health Monitor
==================================================
Checking 6 servers (threshold: 80% CPU)...
  UNHEALTHY: pg-primary (CPU: 95%)
  UNHEALTHY: pg-replica1 (CPU: 88%)
  HEALTHY:   pg-replica2 (CPU: 45%)
  UNHEALTHY: pg-replica3 (CPU: 92%)
  UNHEALTHY: pg-replica4 (CPU: 87%)
  HEALTHY:   pg-replica5 (CPU: 30%)

--- Retry 1/2 ---
Checking 4 servers (threshold: 80% CPU)...
  UNHEALTHY: pg-primary (CPU: 95%)
  UNHEALTHY: pg-replica1 (CPU: 88%)
  UNHEALTHY: pg-replica3 (CPU: 92%)
  UNHEALTHY: pg-replica4 (CPU: 87%)

--- Retry 2/2 ---
Checking 4 servers (threshold: 80% CPU)...
  UNHEALTHY: pg-primary (CPU: 95%)
  UNHEALTHY: pg-replica1 (CPU: 88%)
  UNHEALTHY: pg-replica3 (CPU: 92%)
  UNHEALTHY: pg-replica4 (CPU: 87%)

Gave up after 2 retries. Still unhealthy:
  pg-primary (CPU: 95%)
  pg-replica1 (CPU: 88%)
  pg-replica3 (CPU: 92%)
  pg-replica4 (CPU: 87%)

Summary:
  Healthy servers:   2
  Unhealthy servers: 4

  Original list intact: 6 servers
```

---

## What You Survived

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| Items skipped during iteration | Modifying list while looping over it | Build new lists instead of removing from the original |
| Infinite loop | `while` condition never becomes False | Add a retry counter and max_retries limit |
| Original data corrupted | `servers.remove()` modifies the input | Copy the list with `list(servers)` before working on it |
| No visibility | Script runs silently forever | Add logging at each round with counts |

**The Rules:**
1. **Never modify a list while iterating over it.** Build a new list instead. This is like never doing `DELETE FROM table` inside a cursor that is reading from that same table.
2. **Every `while` loop needs a safety exit.** Always have a counter or timeout that guarantees termination. This is like `statement_timeout` in PostgreSQL - a safety net against runaway queries.
3. **Never modify input data.** Copy it first. This is like using a temp table instead of modifying the source table directly.
