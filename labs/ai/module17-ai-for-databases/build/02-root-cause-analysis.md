# Build 02: Root Cause Analysis Engine

Classification tells you WHAT. Root cause analysis tells you WHY. "Category: performance" is useful, but "CPU high because of a long-running VACUUM on the users table" is actionable.

---

## Step 1. Knowledge base of causes

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ROOT CAUSE KNOWLEDGE BASE
# A structured collection of known causes for each alert type.
# Each cause has: conditions to match, evidence to check,
# and recommended actions.
#
# DBA analogy: this is the runbook in your head.
# When you see "CPU high," you mentally run through:
#   - Is there a long-running query? (check pg_stat_activity)
#   - Is autovacuum running? (check pg_stat_progress_vacuum)
#   - Is it a lock chain? (check pg_locks)
# This code encodes that same thought process.
# ============================================================

print("Root Cause Knowledge Base")
print("=" * 50)

CAUSE_DATABASE = {
    "performance": [
        {
            "cause": "Long-running query",
            "conditions": {
                "text_patterns": ["long running", "query", "pid", "slow query"],
                "metric_conditions": [
                    ("longest_query_seconds", ">", 300),
                    ("cpu_percent", ">", 80),
                ],
            },
            "evidence_queries": [
                "SELECT pid, query, state, now()-query_start AS duration FROM pg_stat_activity WHERE state='active' ORDER BY duration DESC LIMIT 5;",
            ],
            "actions": [
                {"action": "Identify the query and check its plan", "risk": "low"},
                {"action": "Check if the query has a missing index", "risk": "low"},
                {"action": "Kill the query if it's been running too long", "risk": "medium"},
            ],
        },
        {
            "cause": "Autovacuum running on large table",
            "conditions": {
                "text_patterns": ["vacuum", "autovacuum", "bloat"],
                "metric_conditions": [
                    ("cpu_percent", ">", 70),
                ],
            },
            "evidence_queries": [
                "SELECT relname, phase, heap_blks_scanned, heap_blks_total FROM pg_stat_progress_vacuum;",
            ],
            "actions": [
                {"action": "Wait for vacuum to finish (normal operation)", "risk": "low"},
                {"action": "Tune autovacuum_vacuum_cost_delay to reduce impact", "risk": "medium"},
            ],
        },
        {
            "cause": "Lock contention",
            "conditions": {
                "text_patterns": ["lock", "blocked", "wait", "deadlock"],
                "metric_conditions": [
                    ("active_connections", ">", 100),
                ],
            },
            "evidence_queries": [
                "SELECT blocked.pid, blocked.query, blocking.pid AS blocking_pid FROM pg_locks blocked JOIN pg_locks blocking ON blocked.locktype = blocking.locktype WHERE NOT blocked.granted;",
            ],
            "actions": [
                {"action": "Identify blocking query", "risk": "low"},
                {"action": "Kill the blocking session", "risk": "medium"},
                {"action": "Review application for transaction patterns", "risk": "low"},
            ],
        },
    ],
    "storage": [
        {
            "cause": "WAL archiving failed",
            "conditions": {
                "text_patterns": ["wal", "archive", "pg_wal"],
                "metric_conditions": [
                    ("disk_percent", ">", 80),
                    ("wal_size_gb", ">", 10),
                ],
            },
            "evidence_queries": [
                "SELECT * FROM pg_stat_archiver;",
                "SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();",
            ],
            "actions": [
                {"action": "Check archive_command status", "risk": "low"},
                {"action": "Fix archiving and wait for cleanup", "risk": "medium"},
                {"action": "Manually remove old WAL files", "risk": "high"},
            ],
        },
        {
            "cause": "Table bloat from UPDATE-heavy workload",
            "conditions": {
                "text_patterns": ["bloat", "dead tuples", "full", "disk"],
                "metric_conditions": [
                    ("disk_percent", ">", 80),
                ],
            },
            "evidence_queries": [
                "SELECT schemaname, relname, n_dead_tup, n_live_tup, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5;",
            ],
            "actions": [
                {"action": "Run VACUUM on affected tables", "risk": "low"},
                {"action": "Run VACUUM FULL if regular VACUUM isn't enough", "risk": "high"},
                {"action": "Tune autovacuum for this table", "risk": "medium"},
            ],
        },
    ],
    "replication": [
        {
            "cause": "Network issue between primary and standby",
            "conditions": {
                "text_patterns": ["replication", "lag", "standby"],
                "metric_conditions": [
                    ("replication_lag_seconds", ">", 30),
                ],
            },
            "evidence_queries": [
                "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;",
            ],
            "actions": [
                {"action": "Check network connectivity to standby", "risk": "low"},
                {"action": "Check standby server resources (disk, CPU)", "risk": "low"},
                {"action": "Restart WAL receiver on standby", "risk": "medium"},
            ],
        },
        {
            "cause": "Large transaction causing WAL burst",
            "conditions": {
                "text_patterns": ["replication", "lag", "burst"],
                "metric_conditions": [
                    ("replication_lag_bytes", ">", 100_000_000),
                ],
            },
            "evidence_queries": [
                "SELECT pid, query, xact_start, now()-xact_start AS duration FROM pg_stat_activity WHERE state='active' AND xact_start < now() - interval '5 minutes';",
            ],
            "actions": [
                {"action": "Wait for the transaction to complete", "risk": "low"},
                {"action": "Check if the transaction can be split into smaller ones", "risk": "low"},
            ],
        },
    ],
    "connectivity": [
        {
            "cause": "Connection leak in application",
            "conditions": {
                "text_patterns": ["connection", "too many", "max"],
                "metric_conditions": [
                    ("connection_count", ">", 400),
                    ("idle_connections", ">", 200),
                ],
            },
            "evidence_queries": [
                "SELECT application_name, count(*), count(*) FILTER (WHERE state='idle') AS idle FROM pg_stat_activity GROUP BY application_name ORDER BY count DESC;",
            ],
            "actions": [
                {"action": "Identify leaking application", "risk": "low"},
                {"action": "Kill idle connections older than 1 hour", "risk": "medium"},
                {"action": "Set idle_in_transaction_session_timeout", "risk": "medium"},
            ],
        },
    ],
}

# Display the knowledge base
total_causes = 0
for category, causes in CAUSE_DATABASE.items():
    print(f"\n  {category.upper()} ({len(causes)} known causes):")
    for cause_info in causes:
        total_causes += 1
        action_count = len(cause_info["actions"])
        print(f"    - {cause_info['cause']} ({action_count} actions)")

print(f"\nTotal: {total_causes} known root causes across {len(CAUSE_DATABASE)} categories")
PYEOF
```

---

## Step 2. Root cause matcher

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ROOT CAUSE MATCHER
# Given an alert (text + metrics), find the most likely cause.
# Scores each known cause by how well its conditions match.
#
# DBA analogy: this is the diagnostic process.
# You check each possible cause against the symptoms.
# The cause with the most matching symptoms wins.
# ============================================================

print("Root Cause Matcher")
print("=" * 50)

class RootCauseAnalyzer:
    """
    Match alerts to known root causes.

    For each possible cause, check:
    1. Do the text patterns match? (keyword evidence)
    2. Do the metric conditions match? (numeric evidence)

    The cause with the most matching conditions wins.

    DBA analogy: like a differential diagnosis.
    Symptom: CPU high.
    Cause A (long query): needs text match + high CPU + long query duration
    Cause B (autovacuum): needs text match + high CPU
    If we see "PID 12345" in text + query duration > 300s -> Cause A wins
    """

    def __init__(self, cause_database):
        self.cause_database = cause_database

    def _match_text(self, text, patterns):
        """Count how many text patterns match."""
        text_lower = text.lower()
        matches = []
        for pattern in patterns:
            if pattern in text_lower:
                matches.append(pattern)
        return matches

    def _match_metrics(self, metrics, conditions):
        """Check which metric conditions are met."""
        if not metrics:
            return []

        matches = []
        for metric_name, operator, threshold in conditions:
            value = metrics.get(metric_name)
            if value is None:
                continue

            if operator == ">" and value > threshold:
                matches.append({
                    "metric": metric_name,
                    "value": value,
                    "threshold": threshold,
                    "operator": operator,
                })
            elif operator == "<" and value < threshold:
                matches.append({
                    "metric": metric_name,
                    "value": value,
                    "threshold": threshold,
                    "operator": operator,
                })

        return matches

    def analyze(self, text, metrics, category=None):
        """
        Find the most likely root cause.

        category: if already classified, only check causes in that category.
        Returns list of possible causes ranked by match score.
        """
        candidates = []

        # Determine which categories to check
        if category and category in self.cause_database:
            categories_to_check = {category: self.cause_database[category]}
        else:
            categories_to_check = self.cause_database

        for cat, causes in categories_to_check.items():
            for cause_info in causes:
                # Match text patterns
                text_matches = self._match_text(
                    text, cause_info["conditions"]["text_patterns"]
                )

                # Match metric conditions
                metric_matches = self._match_metrics(
                    metrics, cause_info["conditions"]["metric_conditions"]
                )

                # Calculate match score
                total_text_patterns = len(cause_info["conditions"]["text_patterns"])
                total_metric_conditions = len(cause_info["conditions"]["metric_conditions"])
                total_possible = total_text_patterns + total_metric_conditions

                matched = len(text_matches) + len(metric_matches)

                if matched == 0:
                    continue             # no evidence at all

                score = matched / total_possible if total_possible > 0 else 0

                candidates.append({
                    "cause": cause_info["cause"],
                    "category": cat,
                    "score": round(score, 3),
                    "text_evidence": text_matches,
                    "metric_evidence": metric_matches,
                    "evidence_queries": cause_info["evidence_queries"],
                    "actions": cause_info["actions"],
                })

        # Sort by score (highest first)
        candidates.sort(key=lambda x: x["score"], reverse=True)

        return candidates


# Build the knowledge base (simplified for testing)
CAUSES = {
    "performance": [
        {
            "cause": "Long-running query",
            "conditions": {
                "text_patterns": ["long running", "query", "pid", "slow"],
                "metric_conditions": [("longest_query_seconds", ">", 300), ("cpu_percent", ">", 80)],
            },
            "evidence_queries": ["SELECT pid, query FROM pg_stat_activity WHERE state='active' ORDER BY query_start LIMIT 5;"],
            "actions": [
                {"action": "Check query plan with EXPLAIN ANALYZE", "risk": "low"},
                {"action": "Kill the long-running query", "risk": "medium"},
            ],
        },
        {
            "cause": "Autovacuum on large table",
            "conditions": {
                "text_patterns": ["vacuum", "autovacuum"],
                "metric_conditions": [("cpu_percent", ">", 70)],
            },
            "evidence_queries": ["SELECT * FROM pg_stat_progress_vacuum;"],
            "actions": [
                {"action": "Wait for vacuum to complete", "risk": "low"},
                {"action": "Tune autovacuum settings", "risk": "medium"},
            ],
        },
    ],
    "storage": [
        {
            "cause": "WAL archiving failed",
            "conditions": {
                "text_patterns": ["wal", "archive", "disk"],
                "metric_conditions": [("disk_percent", ">", 80), ("wal_size_gb", ">", 10)],
            },
            "evidence_queries": ["SELECT * FROM pg_stat_archiver;"],
            "actions": [
                {"action": "Check archive_command status", "risk": "low"},
                {"action": "Fix archiving configuration", "risk": "medium"},
            ],
        },
    ],
}

analyzer = RootCauseAnalyzer(CAUSES)

# Test cases
test_alerts = [
    {
        "text": "CPU at 95% - long running query PID 12345 for 2 hours",
        "metrics": {"cpu_percent": 95, "longest_query_seconds": 7200},
        "category": "performance",
    },
    {
        "text": "Disk at 92% on /pgdata, WAL files accumulating",
        "metrics": {"disk_percent": 92, "wal_size_gb": 25},
        "category": "storage",
    },
    {
        "text": "CPU at 85%, autovacuum appears to be running",
        "metrics": {"cpu_percent": 85},
        "category": "performance",
    },
]

print("\nRoot Cause Analysis Results:")
print("-" * 65)

for alert in test_alerts:
    results = analyzer.analyze(
        alert["text"], alert["metrics"], alert.get("category")
    )

    print(f"\n  Alert: '{alert['text'][:55]}...'")

    if results:
        top = results[0]
        print(f"  Most likely cause: {top['cause']} (score: {top['score']:.0%})")
        print(f"    Text evidence: {top['text_evidence']}")
        if top['metric_evidence']:
            for me in top['metric_evidence']:
                print(f"    Metric evidence: {me['metric']}={me['value']} (threshold: {me['threshold']})")
        print(f"    Recommended query: {top['evidence_queries'][0][:60]}...")
        print(f"    Actions:")
        for a in top['actions']:
            print(f"      [{a['risk']:>6s}] {a['action']}")

        if len(results) > 1:
            print(f"    Alternative: {results[1]['cause']} (score: {results[1]['score']:.0%})")
    else:
        print(f"  No matching root cause found")

print("""
How root cause analysis works:
  1. Start with the classified category (narrows the search)
  2. Check each known cause's conditions against the alert
  3. Score by how many conditions match (text + metrics)
  4. Return ranked list with evidence and recommended actions

The knowledge base grows over time:
  - Every resolved incident adds a new cause or refines existing ones
  - DBA corrections improve the matching logic
  - Like pg_stat_statements: more data = better insights
""")
PYEOF
```

---

## Step 3. Context-aware diagnosis

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta

# ============================================================
# CONTEXT-AWARE DIAGNOSIS
# Use recent alerts and metric history for better diagnosis.
#
# A single alert in isolation is ambiguous.
# But "disk warning" + "WAL archive failure 2 hours ago" = clear cause.
#
# DBA analogy: you don't diagnose in a vacuum.
# You check: "Did anything change recently? What else is happening?"
# ============================================================

print("Context-Aware Diagnosis")
print("=" * 50)

class ContextEngine:
    """
    Enrich alerts with context from recent history.

    DBA analogy: when an alert fires, you check:
    1. Recent alerts on the same server (what else is happening?)
    2. Recent changes (was there a deployment? config change?)
    3. Historical patterns (does this happen every Sunday?)
    """

    def __init__(self):
        self.alert_history = []          # recent alerts
        self.known_patterns = [          # recurring patterns
            {
                "name": "Sunday backup + analytics overlap",
                "pattern": {"day_of_week": 6, "hour_range": (0, 4), "category": "performance"},
                "explanation": "CPU spike from backup + analytics jobs running together",
            },
            {
                "name": "15-minute ANALYZE cron",
                "pattern": {"minute_interval": 15, "category": "performance"},
                "explanation": "CPU spike from scheduled ANALYZE cron job",
            },
        ]

    def add_alert(self, text, category, timestamp=None):
        """Record an alert in history."""
        self.alert_history.append({
            "text": text,
            "category": category,
            "timestamp": timestamp or datetime.now(),
        })
        # Keep last 100 alerts
        if len(self.alert_history) > 100:
            self.alert_history = self.alert_history[-100:]

    def get_related_alerts(self, category, window_hours=4):
        """
        Find recent alerts in the same category.

        DBA analogy: "What other alerts fired in the last 4 hours
        for this category?" Helps spot cascading failures.
        """
        cutoff = datetime.now() - timedelta(hours=window_hours)
        related = [
            a for a in self.alert_history
            if a["category"] == category and a["timestamp"] > cutoff
        ]
        return related

    def detect_cascade(self, category):
        """
        Detect if this alert is part of a cascade.

        Cascade = 3+ alerts in the same category within 1 hour.

        DBA analogy: one alert is noise. Three alerts in an hour
        is a cascade (something is actively breaking).
        """
        recent = self.get_related_alerts(category, window_hours=1)
        return {
            "is_cascade": len(recent) >= 3,
            "alert_count": len(recent),
            "first_alert": recent[0]["text"][:50] if recent else None,
        }

    def find_preceding_events(self, timestamp=None, window_hours=6):
        """
        Find events that happened before this alert.
        Often the CAUSE fires first, then the SYMPTOM.

        Example: "WAL archive failure" fires at 10 AM
                 "Disk full" fires at 2 PM
                 The archive failure CAUSED the disk to fill.
        """
        ts = timestamp or datetime.now()
        cutoff = ts - timedelta(hours=window_hours)
        preceding = [
            a for a in self.alert_history
            if cutoff < a["timestamp"] < ts
        ]
        return preceding

    def check_known_patterns(self, category, timestamp=None):
        """Check if this alert matches a known recurring pattern."""
        ts = timestamp or datetime.now()
        matches = []

        for pattern in self.known_patterns:
            p = pattern["pattern"]
            if p.get("category") != category:
                continue

            if "day_of_week" in p and ts.weekday() == p["day_of_week"]:
                hour_range = p.get("hour_range", (0, 23))
                if hour_range[0] <= ts.hour <= hour_range[1]:
                    matches.append(pattern)

            if "minute_interval" in p:
                if ts.minute % p["minute_interval"] < 3:  # within 3 min of interval
                    matches.append(pattern)

        return matches


# Simulate a context-enriched diagnosis
ctx = ContextEngine()

# Build some history
now = datetime.now()
ctx.add_alert("WAL archive command failed", "storage",
              now - timedelta(hours=4))
ctx.add_alert("Disk at 82% on /pgdata", "storage",
              now - timedelta(hours=2))
ctx.add_alert("Disk at 88% on /pgdata", "storage",
              now - timedelta(hours=1))
ctx.add_alert("Disk at 92% on /pgdata", "storage",
              now - timedelta(minutes=30))

# New alert arrives
new_alert = {
    "text": "Disk at 95% on /pgdata - CRITICAL",
    "category": "storage",
}

print(f"\nNew Alert: '{new_alert['text']}'")
print("-" * 55)

# Check context
related = ctx.get_related_alerts("storage", window_hours=6)
cascade = ctx.detect_cascade("storage")
preceding = ctx.find_preceding_events()

print(f"\n  Related alerts (last 6 hours): {len(related)}")
for a in related:
    age = (now - a["timestamp"]).total_seconds() / 3600
    print(f"    {age:.1f}h ago: '{a['text']}'")

print(f"\n  Cascade detection: {'YES - ACTIVE CASCADE' if cascade['is_cascade'] else 'No cascade'}")
if cascade['is_cascade']:
    print(f"    {cascade['alert_count']} alerts in the last hour")

print(f"\n  Preceding events (possible causes):")
for a in preceding:
    if a["category"] != new_alert["category"]:
        print(f"    [{a['category']}] '{a['text'][:50]}' (different category - could be root cause)")
    else:
        print(f"    [{a['category']}] '{a['text'][:50]}'")

print("""
Context-Enriched Diagnosis:
  The disk alert is part of a CASCADE (4 alerts, escalating).
  Root cause: "WAL archive command failed" (4 hours ago).
  This caused WAL files to accumulate, filling the disk.

  Without context: "Disk at 95%" -> "Clean up disk space"
  With context: "Disk at 95% because WAL archiving broke 4h ago" -> "Fix archiving"

  The fix is different! Context changes the action.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Cause knowledge base | Structured library of known causes | Your runbook in code |
| Root cause matching | Score causes against symptoms | Differential diagnosis |
| Evidence queries | SQL to confirm the diagnosis | "Let me check pg_stat_activity" |
| Action recommendations | What to do, with risk levels | Runbook steps |
| Context engine | Use recent history for diagnosis | "What else happened recently?" |
| Cascade detection | Spot escalating failure patterns | Multiple alerts = something is breaking |
| Preceding events | Find what caused this alert | Root cause often fires first |
