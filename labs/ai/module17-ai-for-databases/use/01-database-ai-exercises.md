# Use 01: Database AI Exercises

Practice building AI tools for real database scenarios.

---

## Exercise 1. Alert priority queue

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
from datetime import datetime, timedelta

random.seed(42)

# ============================================================
# Exercise: Build a priority queue that ranks alerts by urgency.
#
# When 50 alerts fire at once, which one do you look at first?
# The priority queue sorts by: severity * environment_weight.
#
# DBA analogy: like triage in an emergency room.
# Most critical patient first, not first-come-first-served.
# ============================================================

print("Exercise 1: Alert Priority Queue")
print("=" * 50)

class AlertPriorityQueue:
    """
    Rank alerts by urgency so you handle the worst ones first.

    Priority = severity_score * environment_weight * recency_weight

    DBA analogy: when 20 pages fire at 3 AM, you need to know
    which one to look at first. This queue answers that.
    """

    def __init__(self):
        self.queue = []
        self.env_weights = {"production": 2.0, "staging": 1.0, "development": 0.5}

    def add(self, text, category, severity, environment="production", timestamp=None):
        """Add an alert to the queue."""
        ts = timestamp or datetime.now()
        env_weight = self.env_weights.get(environment, 1.0)

        # Recency weight: newer alerts get slight priority
        age_minutes = (datetime.now() - ts).total_seconds() / 60
        recency = max(1.0 - age_minutes / 60, 0.5)  # decays over 1 hour

        priority = severity * env_weight * recency

        self.queue.append({
            "text": text[:60],
            "category": category,
            "severity": severity,
            "environment": environment,
            "priority": round(priority, 1),
            "timestamp": ts,
        })

        # Sort by priority (highest first)
        self.queue.sort(key=lambda x: x["priority"], reverse=True)

    def get_top(self, n=5):
        """Get the top N most urgent alerts."""
        return self.queue[:n]

    def acknowledge(self, index=0):
        """Remove the top alert (DBA is handling it)."""
        if self.queue:
            return self.queue.pop(index)
        return None


# Simulate a burst of alerts
pq = AlertPriorityQueue()
now = datetime.now()

alerts = [
    ("Disk at 99% on pg-primary-prod", "storage", 95, "production"),
    ("CPU at 88% on pg-dev-1", "performance", 60, "development"),
    ("Replication lag 500s on standby", "replication", 85, "production"),
    ("Connection pool at 92%", "connectivity", 70, "production"),
    ("Backup failed on staging", "backup", 50, "staging"),
    ("CPU at 95% on pg-primary-prod", "performance", 90, "production"),
    ("SSL cert expires in 5 days", "security", 40, "production"),
    ("Disk at 82% on staging-db", "storage", 55, "staging"),
    ("Memory at 93% on prod", "performance", 80, "production"),
    ("Auth failures from 10.0.0.55", "security", 65, "production"),
]

for text, cat, sev, env in alerts:
    ts = now - timedelta(minutes=random.randint(0, 30))
    pq.add(text, cat, sev, env, ts)

# Show the priority queue
print(f"\n{len(pq.queue)} alerts in queue. Top 10 by priority:")
print("-" * 75)
print(f"{'#':>3s} {'Priority':>8s} {'Severity':>8s} {'Env':>12s} {'Category':<15s} {'Alert'}")
print("-" * 75)

for i, alert in enumerate(pq.queue[:10]):
    print(f"{i+1:>3d} {alert['priority']:>8.0f} {alert['severity']:>8d} "
          f"{alert['environment']:>12s} {alert['category']:<15s} {alert['text'][:40]}")

print("""
How priority is calculated:
  priority = severity * env_weight * recency_weight

  Disk 99% on prod: 95 * 2.0 * 1.0 = 190 (highest)
  CPU 88% on dev:   60 * 0.5 * 1.0 = 30  (lowest)

  Even a 95-severity alert on dev ranks lower than
  a 70-severity alert on production.
""")
PYEOF
```

---

## Exercise 2. Smart alert grouping

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta
from collections import defaultdict

# ============================================================
# Exercise: Group related alerts together.
#
# When disk fills, you get: disk warning, disk critical,
# WAL archive failure, query timeout, backup failure.
# That's 5 alerts for 1 problem. Group them.
#
# DBA analogy: like incident grouping in PagerDuty.
# One root cause = one incident, not 10 pages.
# ============================================================

print("Exercise 2: Smart Alert Grouping")
print("=" * 50)

class AlertGrouper:
    """
    Group related alerts into incidents.

    Rules for grouping:
    1. Same category within 30 minutes = same group
    2. Known cascade patterns = same group
    3. Same server within 15 minutes = same group

    DBA analogy: five alerts from the same server in 10 minutes
    are probably ONE problem. Group them and investigate once.
    """

    def __init__(self, window_minutes=30):
        self.window = timedelta(minutes=window_minutes)
        self.groups = []                 # list of alert groups
        self.cascade_rules = {
            # trigger_category -> related categories
            "storage": ["backup", "performance"],  # disk full causes backup fail + slow queries
            "replication": ["connectivity"],        # repl failure can cause connection issues
            "connectivity": ["performance"],        # connection issues cause query slowness
        }

    def _find_matching_group(self, alert):
        """Find an existing group this alert belongs to."""
        for group in self.groups:
            # Check time window
            group_latest = max(a["timestamp"] for a in group["alerts"])
            if alert["timestamp"] - group_latest > self.window:
                continue

            # Same category?
            if alert["category"] == group["primary_category"]:
                return group

            # Cascade relationship?
            related = self.cascade_rules.get(group["primary_category"], [])
            if alert["category"] in related:
                return group

        return None

    def add_alert(self, text, category, severity, timestamp=None):
        """Add an alert, grouping if related."""
        alert = {
            "text": text,
            "category": category,
            "severity": severity,
            "timestamp": timestamp or datetime.now(),
        }

        group = self._find_matching_group(alert)

        if group:
            group["alerts"].append(alert)
            # Update severity to max
            if severity > group["max_severity"]:
                group["max_severity"] = severity
            group["alert_count"] += 1
        else:
            # New group
            self.groups.append({
                "primary_category": category,
                "max_severity": severity,
                "alerts": [alert],
                "alert_count": 1,
                "created": alert["timestamp"],
            })

    def get_incidents(self):
        """Get all groups as incidents."""
        return sorted(self.groups, key=lambda g: g["max_severity"], reverse=True)


# Simulate a cascading failure
grouper = AlertGrouper(window_minutes=30)
now = datetime.now()

# Incident 1: Disk fills -> cascade
grouper.add_alert("Disk at 85% on pg-primary", "storage", 60,
                  now - timedelta(minutes=45))
grouper.add_alert("Disk at 92% on pg-primary", "storage", 80,
                  now - timedelta(minutes=30))
grouper.add_alert("WAL archive failing", "storage", 75,
                  now - timedelta(minutes=25))
grouper.add_alert("Backup failed: no disk space", "backup", 70,
                  now - timedelta(minutes=20))
grouper.add_alert("Query timeout due to disk I/O", "performance", 65,
                  now - timedelta(minutes=15))
grouper.add_alert("Disk at 98% on pg-primary", "storage", 95,
                  now - timedelta(minutes=5))

# Incident 2: Separate - auth issue
grouper.add_alert("Auth failure from 10.0.0.99", "security", 40,
                  now - timedelta(minutes=10))
grouper.add_alert("Multiple auth failures from 10.0.0.99", "security", 60,
                  now - timedelta(minutes=5))

# Incident 3: Separate - replication
grouper.add_alert("Replication lag 120s on standby-2", "replication", 70,
                  now - timedelta(minutes=8))

incidents = grouper.get_incidents()

print(f"\n{sum(g['alert_count'] for g in incidents)} alerts grouped into {len(incidents)} incidents:")
print("-" * 65)

for i, incident in enumerate(incidents):
    print(f"\n  Incident {i+1}: {incident['primary_category'].upper()} "
          f"(severity={incident['max_severity']}, {incident['alert_count']} alerts)")
    for alert in incident['alerts']:
        age = (now - alert['timestamp']).total_seconds() / 60
        print(f"    {age:>4.0f}m ago [{alert['severity']:>3d}] {alert['text'][:50]}")

print("""
Without grouping: DBA gets 9 separate pages
With grouping: DBA gets 3 incidents (disk cascade, auth, replication)

Key benefit: the DBA sees ONE root cause per incident,
not a flood of symptoms. Fix the disk, and 6 alerts resolve.
""")
PYEOF
```

---

## Exercise 3. Runbook automation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# Exercise: Auto-generate a runbook for an alert.
#
# Given an alert classification and root cause, generate
# a step-by-step runbook the DBA (or AI) can follow.
#
# DBA analogy: instead of remembering steps from memory,
# the system generates the specific runbook for THIS alert
# on THIS server with THIS problem.
# ============================================================

print("Exercise 3: Runbook Generation")
print("=" * 50)

class RunbookGenerator:
    """
    Generate a context-specific runbook for an alert.

    Instead of a generic "check disk space" runbook,
    generates: "On pg-primary-prod-3, check /pgdata partition,
    WAL directory is likely the cause based on recent archive failures."
    """

    def __init__(self):
        self.templates = {
            "storage_disk_full": [
                "Step 1: Check current disk usage",
                "  Command: df -h {mount_point}",
                "  Expected: see which partition is full",
                "",
                "Step 2: Check PostgreSQL database sizes",
                "  Command: SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;",
                "",
                "Step 3: Check WAL directory size",
                "  Command: du -sh {pgdata}/pg_wal/",
                "  If WAL is large, check archiving: SELECT * FROM pg_stat_archiver;",
                "",
                "Step 4: Check for table bloat",
                "  Command: SELECT schemaname, relname, n_dead_tup FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5;",
                "  If dead tuples high: VACUUM VERBOSE {table};",
                "",
                "Step 5: Emergency space recovery (if > 95%)",
                "  Option A: Remove old WAL files (if archiving is confirmed)",
                "  Option B: Drop unused indexes",
                "  Option C: Truncate log tables",
                "  WARNING: Get approval before deleting anything",
            ],
            "performance_cpu_high": [
                "Step 1: Check active queries",
                "  Command: SELECT pid, now()-query_start AS duration, query FROM pg_stat_activity WHERE state='active' ORDER BY duration DESC LIMIT 5;",
                "",
                "Step 2: Check for locks",
                "  Command: SELECT * FROM pg_locks WHERE NOT granted;",
                "",
                "Step 3: Check autovacuum activity",
                "  Command: SELECT * FROM pg_stat_progress_vacuum;",
                "",
                "Step 4: If long-running query found",
                "  Review the query plan: EXPLAIN (ANALYZE, BUFFERS) <query>;",
                "  If appropriate, kill it: SELECT pg_terminate_backend({pid});",
                "  WARNING: Confirm the query is not critical before killing",
            ],
            "replication_lag": [
                "Step 1: Check replication status on primary",
                "  Command: SELECT client_addr, state, replay_lag FROM pg_stat_replication;",
                "",
                "Step 2: Check WAL receiver on standby",
                "  Command: SELECT * FROM pg_stat_wal_receiver;",
                "",
                "Step 3: Check network connectivity",
                "  Command: ping {standby_ip}",
                "  Command: nc -zv {standby_ip} 5432",
                "",
                "Step 4: Check standby disk and CPU",
                "  If standby is overloaded, it can't replay fast enough",
                "",
                "Step 5: If lag keeps growing",
                "  Check for replication slot retention: SELECT * FROM pg_replication_slots;",
                "  Consider rebuilding standby if lag is too large to catch up",
            ],
        }

    def generate(self, category, root_cause, context=None):
        """
        Generate a runbook for a specific alert.

        context: dict with server-specific info
          {"server": "pg-primary-prod-3", "mount_point": "/pgdata", ...}
        """
        ctx = context or {}

        # Find matching template
        template_key = f"{category}_{root_cause}"
        template = self.templates.get(template_key)

        if not template:
            # Fall back to generic
            return {
                "title": f"Runbook: {category} - {root_cause}",
                "steps": [f"No specific runbook for '{template_key}'. Use general procedures."],
            }

        # Fill in context variables
        steps = []
        for line in template:
            for key, value in ctx.items():
                line = line.replace(f"{{{key}}}", str(value))
            steps.append(line)

        return {
            "title": f"Runbook: {category} - {root_cause}",
            "server": ctx.get("server", "unknown"),
            "generated_at": "auto-generated based on alert classification",
            "steps": steps,
        }


# Generate runbooks
gen = RunbookGenerator()

# Scenario 1: Disk full on production
runbook = gen.generate(
    category="storage",
    root_cause="disk_full",
    context={
        "server": "pg-primary-prod-3",
        "mount_point": "/pgdata",
        "pgdata": "/var/lib/pgsql/16/data",
    }
)

print(f"\n{runbook['title']}")
print(f"Server: {runbook['server']}")
print("-" * 55)
for step in runbook["steps"]:
    print(f"  {step}")

# Scenario 2: CPU high
runbook2 = gen.generate(
    category="performance",
    root_cause="cpu_high",
    context={"server": "pg-primary-prod-3", "pid": "12345"}
)

print(f"\n{runbook2['title']}")
print("-" * 55)
for step in runbook2["steps"][:8]:   # show first 8 lines
    print(f"  {step}")
print(f"  ... ({len(runbook2['steps'])} total lines)")

print("""
Runbook automation benefits:
  1. Consistent: every DBA follows the same steps
  2. Context-aware: server names and paths filled in automatically
  3. Safe: warnings before dangerous actions
  4. Fast: no time wasted looking up procedures at 3 AM
""")
PYEOF
```

---

## Exercise 4. Capacity planning predictor

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# Exercise: Predict when you'll run out of capacity.
#
# Given historical growth data, predict when you'll need:
# - More disk space
# - More connections
# - A replica upgrade
#
# DBA analogy: "At this growth rate, we need 2 more servers
# in 6 months." The AI does this math for every metric.
# ============================================================

print("Exercise 4: Capacity Planning Predictor")
print("=" * 55)

class CapacityPlanner:
    """
    Predict when resources will be exhausted.

    Takes historical data, fits a trend line, extrapolates
    to find when the limit will be hit.
    """

    def __init__(self):
        self.resources = {}

    def add_resource(self, name, historical_values, limit, unit="days"):
        """
        Register a resource with historical data and its limit.

        historical_values: list of measurements (one per time period)
        limit: the maximum capacity
        unit: what each time step represents
        """
        n = len(historical_values)
        if n < 3:
            return

        # Linear regression for trend
        x = list(range(n))
        y = historical_values
        sum_x = sum(x)
        sum_y = sum(y)
        sum_xy = sum(xi * yi for xi, yi in zip(x, y))
        sum_x2 = sum(xi ** 2 for xi in x)
        denom = n * sum_x2 - sum_x ** 2

        if denom == 0:
            slope = 0
        else:
            slope = (n * sum_xy - sum_x * sum_y) / denom

        current = historical_values[-1]
        remaining = limit - current

        if slope <= 0:
            time_to_limit = None
        else:
            time_to_limit = remaining / slope

        self.resources[name] = {
            "current": current,
            "limit": limit,
            "utilization": round(current / limit * 100, 1),
            "growth_rate": round(slope, 2),
            "time_to_limit": round(time_to_limit, 1) if time_to_limit else None,
            "unit": unit,
        }

    def get_report(self):
        """Generate capacity planning report."""
        report = []
        for name, data in self.resources.items():
            urgency = "ok"
            if data["time_to_limit"] is not None:
                ttl = data["time_to_limit"]
                if ttl <= 7:
                    urgency = "critical"
                elif ttl <= 30:
                    urgency = "warning"
                elif ttl <= 90:
                    urgency = "plan"

            report.append({
                "resource": name,
                "urgency": urgency,
                **data,
            })

        return sorted(report, key=lambda x: x.get("time_to_limit") or 9999)


planner = CapacityPlanner()

# Disk: growing 2GB/day, 500GB total, currently at 350GB
disk_history = [300 + i * 2 for i in range(30)]     # 30 days
planner.add_resource("Disk (pg-primary)", disk_history, limit=500, unit="days")

# Connections: growing slowly, currently at 280 of 500
conn_history = [250 + i * 1 for i in range(30)]
planner.add_resource("Connections", conn_history, limit=500, unit="days")

# Database size: growing 5GB/week, 100GB max
db_history = [40 + i * 5 for i in range(12)]        # 12 weeks
planner.add_resource("Database size", db_history, limit=100, unit="weeks")

# WAL: stable (no growth)
wal_history = [5, 5.2, 4.8, 5.1, 5.0, 4.9, 5.1]   # 7 days
planner.add_resource("WAL size (GB)", wal_history, limit=50, unit="days")

report = planner.get_report()

print(f"\nCapacity Planning Report:")
print("-" * 80)
print(f"{'Resource':<25s} {'Current':>8s} {'Limit':>8s} {'Used':>6s} "
      f"{'Growth':>8s} {'Runway':>10s} {'Status':>10s}")
print("-" * 80)

for r in report:
    runway = f"{r['time_to_limit']:.0f} {r['unit']}" if r['time_to_limit'] else "stable"
    print(f"{r['resource']:<25s} {r['current']:>8.0f} {r['limit']:>8.0f} "
          f"{r['utilization']:>5.0f}% {r['growth_rate']:>+7.1f} "
          f"{runway:>10s} {r['urgency']:>10s}")

print("""
Capacity planning actions:
  critical (< 7 days):  Expand NOW or data loss imminent
  warning (< 30 days):  Schedule expansion this sprint
  plan (< 90 days):     Add to next quarter's budget
  ok (90+ days):        Monitor, no action needed

This replaces manual "how's our disk?" checks with automated predictions.
""")
PYEOF
```

---

## Exercise 5. DBA knowledge capture

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

# ============================================================
# Exercise: Capture DBA expertise as structured knowledge.
#
# When a senior DBA resolves an incident, capture:
# - What they checked
# - What they found
# - What they did
# - What they'd do differently next time
#
# This becomes training data for the AI.
# ============================================================

print("Exercise 5: DBA Knowledge Capture")
print("=" * 50)

class KnowledgeBase:
    """
    Capture and retrieve DBA expertise.

    DBA analogy: like a wiki, but structured.
    Instead of free-text pages, each entry has:
    symptoms, diagnosis, resolution, and lessons learned.
    """

    def __init__(self):
        self.entries = []

    def capture_incident(self, symptoms, diagnosis, resolution, lessons=None):
        """Record a resolved incident."""
        entry = {
            "id": len(self.entries) + 1,
            "timestamp": datetime.now().isoformat(),
            "symptoms": symptoms,        # what was observed
            "diagnosis": diagnosis,      # root cause
            "resolution": resolution,    # what was done
            "lessons": lessons or [],    # what to do differently
            "search_text": f"{' '.join(symptoms)} {diagnosis} {' '.join(resolution)}".lower(),
        }
        self.entries.append(entry)
        return entry

    def search(self, query, max_results=3):
        """
        Find relevant past incidents.

        Simple keyword search for now.
        Module 8 (embeddings) would make this much better.
        """
        query_words = set(query.lower().split())
        scored = []

        for entry in self.entries:
            # Count matching words
            entry_words = set(entry["search_text"].split())
            overlap = len(query_words & entry_words)
            if overlap > 0:
                scored.append((overlap, entry))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [entry for _, entry in scored[:max_results]]


# Populate with DBA knowledge
kb = KnowledgeBase()

kb.capture_incident(
    symptoms=["Disk at 95%", "WAL files accumulating", "archive_command failing"],
    diagnosis="WAL archiving broken - archive destination disk was full",
    resolution=[
        "Freed space on archive destination",
        "Restarted archive_command",
        "WAL files archived and cleaned up",
        "Disk usage dropped to 72%",
    ],
    lessons=["Monitor archive destination disk separately", "Set up WAL size alerts"],
)

kb.capture_incident(
    symptoms=["CPU at 98%", "Long-running query", "Application timeout"],
    diagnosis="Missing index on users table - seq scan on 50M row table",
    resolution=[
        "Identified query: SELECT * FROM users WHERE email = ?",
        "Created index: CREATE INDEX idx_users_email ON users(email)",
        "Query time dropped from 45s to 2ms",
    ],
    lessons=["Run EXPLAIN on all new queries", "Set up pg_stat_statements monitoring"],
)

kb.capture_incident(
    symptoms=["Replication lag 600s", "Standby not catching up", "Disk I/O at 100% on standby"],
    diagnosis="Standby disk too slow for replay - HDD instead of SSD",
    resolution=[
        "Migrated standby to SSD storage",
        "Replication lag dropped to < 1s",
    ],
    lessons=["Standby hardware must match primary", "Monitor standby I/O latency"],
)

# Search for similar past incidents
test_queries = [
    "disk filling up WAL",
    "CPU high slow query",
    "replication lag growing standby",
]

print(f"\nKnowledge Base: {len(kb.entries)} incidents captured")
print("-" * 55)

for query in test_queries:
    results = kb.search(query)
    print(f"\n  Search: '{query}'")
    if results:
        top = results[0]
        print(f"    Match: incident #{top['id']}")
        print(f"    Diagnosis: {top['diagnosis'][:60]}")
        print(f"    Resolution: {top['resolution'][0][:60]}")
        if top['lessons']:
            print(f"    Lesson: {top['lessons'][0]}")
    else:
        print(f"    No matching incidents found")

print("""
Knowledge capture benefits:
  1. New DBAs learn from past incidents instantly
  2. AI uses past resolutions to recommend actions
  3. Patterns emerge (same problem = systemic issue)
  4. Senior DBA knowledge preserved when they leave

This is the foundation of dbaBrain's learning system.
Every resolved incident makes the AI smarter.
""")
PYEOF
```

---

## What You Practiced

| Exercise | Skill | Production Use |
|----------|-------|---------------|
| Priority queue | Rank alerts by urgency | Triage 50 alerts at 3 AM |
| Alert grouping | Combine related alerts | One root cause = one incident |
| Runbook generation | Auto-generate fix procedures | Consistent, fast incident response |
| Capacity planning | Predict resource exhaustion | "Need more disk in 30 days" |
| Knowledge capture | Record DBA expertise | AI learns from every incident |
