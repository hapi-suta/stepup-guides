# Build 03: Remediation Engine

After classifying and diagnosing, the next step is recommending (or executing) fixes. The remediation engine suggests actions, enforces safety levels, and learns from DBA feedback.

---

## Step 1. Action catalog

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ACTION CATALOG
# Every action the system can take or recommend,
# with risk levels and prerequisites.
#
# DBA analogy: this is the runbook, but structured.
# Each entry says: what to do, how risky it is,
# what to check first, and what could go wrong.
# ============================================================

print("Remediation Action Catalog")
print("=" * 50)

ACTION_CATALOG = {
    "performance": [
        {
            "action": "Identify the slow query",
            "command": "SELECT pid, query, now()-query_start AS duration FROM pg_stat_activity WHERE state='active' ORDER BY duration DESC LIMIT 5;",
            "risk": "low",
            "auto_execute": True,
            "description": "Read-only query to find the offending query",
        },
        {
            "action": "Check query plan",
            "command": "EXPLAIN (ANALYZE, BUFFERS) <query>;",
            "risk": "low",
            "auto_execute": False,  # needs the specific query
            "description": "Get execution plan to find missing indexes or bad joins",
        },
        {
            "action": "Kill long-running query",
            "command": "SELECT pg_terminate_backend(<pid>);",
            "risk": "medium",
            "auto_execute": False,
            "prerequisites": ["Query running > 1 hour", "Not a critical transaction"],
            "description": "Terminate the offending backend process",
        },
        {
            "action": "Tune autovacuum for table",
            "command": "ALTER TABLE <table> SET (autovacuum_vacuum_cost_delay = 10);",
            "risk": "medium",
            "auto_execute": False,
            "description": "Reduce autovacuum impact on performance",
        },
    ],
    "storage": [
        {
            "action": "Check disk usage breakdown",
            "command": "SELECT pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;",
            "risk": "low",
            "auto_execute": True,
            "description": "Find which databases use the most disk",
        },
        {
            "action": "Check WAL archive status",
            "command": "SELECT * FROM pg_stat_archiver;",
            "risk": "low",
            "auto_execute": True,
            "description": "Check if WAL archiving is working",
        },
        {
            "action": "VACUUM bloated tables",
            "command": "VACUUM VERBOSE <table>;",
            "risk": "low",
            "auto_execute": False,
            "description": "Reclaim dead tuple space (safe, doesn't lock)",
        },
        {
            "action": "VACUUM FULL for severe bloat",
            "command": "VACUUM FULL <table>;",
            "risk": "high",
            "prerequisites": ["Maintenance window scheduled", "Exclusive lock acceptable"],
            "description": "Full table rewrite - locks the table for duration",
        },
    ],
    "replication": [
        {
            "action": "Check replication status",
            "command": "SELECT client_addr, state, sent_lsn, replay_lsn, replay_lag FROM pg_stat_replication;",
            "risk": "low",
            "auto_execute": True,
            "description": "Check current replication state and lag",
        },
        {
            "action": "Check replication slots",
            "command": "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;",
            "risk": "low",
            "auto_execute": True,
            "description": "Check if any slots are retaining too much WAL",
        },
        {
            "action": "Restart WAL receiver on standby",
            "command": "SELECT pg_reload_conf(); -- on standby",
            "risk": "medium",
            "auto_execute": False,
            "description": "Reconnect replication without full restart",
        },
        {
            "action": "Failover to standby",
            "command": "pg_ctl promote -D $PGDATA",
            "risk": "critical",
            "auto_execute": False,
            "prerequisites": ["Primary confirmed down", "Standby is caught up", "Application can reconnect"],
            "description": "Promote standby to primary - IRREVERSIBLE",
        },
    ],
    "connectivity": [
        {
            "action": "Check connection distribution",
            "command": "SELECT application_name, count(*), count(*) FILTER (WHERE state='idle') AS idle FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;",
            "risk": "low",
            "auto_execute": True,
            "description": "Find which applications use the most connections",
        },
        {
            "action": "Kill idle connections over 1 hour",
            "command": "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle' AND state_change < now() - interval '1 hour';",
            "risk": "medium",
            "auto_execute": False,
            "description": "Free up connections from idle sessions",
        },
        {
            "action": "Set idle session timeout",
            "command": "ALTER SYSTEM SET idle_in_transaction_session_timeout = '300s';",
            "risk": "medium",
            "auto_execute": False,
            "description": "Auto-kill idle-in-transaction sessions after 5 minutes",
        },
    ],
}

# Display catalog
for category, actions in ACTION_CATALOG.items():
    print(f"\n  {category.upper()} ({len(actions)} actions):")
    for a in actions:
        auto = "AUTO" if a.get("auto_execute") else "MANUAL"
        print(f"    [{a['risk']:>8s}] [{auto:>6s}] {a['action']}")

total = sum(len(acts) for acts in ACTION_CATALOG.values())
auto = sum(1 for acts in ACTION_CATALOG.values() for a in acts if a.get("auto_execute"))
print(f"\nTotal: {total} actions ({auto} auto-executable, {total-auto} manual)")
PYEOF
```

---

## Step 2. Remediation engine

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# REMEDIATION ENGINE
# Given a diagnosis, recommend and optionally execute actions.
# Enforces safety: only auto-execute low-risk actions.
#
# DBA analogy: the senior DBA who says:
# "Here's what I'd check first (auto-run these safe queries),
#  and here's what you might need to do (but check with me first)."
# ============================================================

print("Remediation Engine")
print("=" * 50)

class RemediationEngine:
    """
    Recommend and execute remediation actions.

    Safety rules:
    - LOW risk: can auto-execute (read-only queries, logging)
    - MEDIUM risk: recommend with notification (kill query, tune config)
    - HIGH risk: recommend with human approval required (VACUUM FULL, failover)
    - CRITICAL risk: never auto-execute (promote, DROP, data changes)

    DBA analogy: like role-based permissions.
    Junior DBA (AI): can run SELECT, VACUUM, send alerts
    Senior DBA (human): approves kills, config changes
    Principal DBA (human): approves failover, schema changes
    """

    def __init__(self):
        # Risk level -> execution policy
        self.execution_policy = {
            "low": "auto_execute",        # AI does it automatically
            "medium": "recommend_notify",  # AI recommends + sends alert
            "high": "require_approval",    # AI recommends + waits for approval
            "critical": "human_only",      # AI mentions it but cannot execute
        }

        # Action catalog (simplified)
        self.actions = {
            "performance": [
                {"action": "Check pg_stat_activity", "risk": "low", "auto": True,
                 "command": "SELECT pid, query, state FROM pg_stat_activity WHERE state='active';"},
                {"action": "Kill long-running query", "risk": "medium", "auto": False,
                 "command": "SELECT pg_terminate_backend(<pid>);"},
            ],
            "storage": [
                {"action": "Check disk usage", "risk": "low", "auto": True,
                 "command": "SELECT pg_size_pretty(pg_database_size(current_database()));"},
                {"action": "Check WAL status", "risk": "low", "auto": True,
                 "command": "SELECT * FROM pg_stat_archiver;"},
                {"action": "VACUUM table", "risk": "low", "auto": False,
                 "command": "VACUUM VERBOSE <table>;"},
                {"action": "VACUUM FULL", "risk": "high", "auto": False,
                 "command": "VACUUM FULL <table>;"},
            ],
            "replication": [
                {"action": "Check replication status", "risk": "low", "auto": True,
                 "command": "SELECT * FROM pg_stat_replication;"},
                {"action": "Failover to standby", "risk": "critical", "auto": False,
                 "command": "pg_ctl promote -D $PGDATA"},
            ],
            "connectivity": [
                {"action": "Check connections", "risk": "low", "auto": True,
                 "command": "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY 1;"},
                {"action": "Kill idle connections", "risk": "medium", "auto": False,
                 "command": "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle' AND state_change < now()-interval '1 hour';"},
            ],
        }

    def get_remediation_plan(self, category, severity_score=50):
        """
        Create a step-by-step remediation plan.

        Higher severity = more aggressive actions recommended.
        Lower severity = only diagnostic (low-risk) actions.
        """
        category_actions = self.actions.get(category, [])
        if not category_actions:
            return {"steps": [], "note": "No actions found for this category"}

        plan = {
            "category": category,
            "severity": severity_score,
            "auto_steps": [],        # AI will execute these
            "manual_steps": [],      # human must execute these
            "blocked_steps": [],     # too risky, mentioned but not recommended
        }

        for action in category_actions:
            risk = action["risk"]
            policy = self.execution_policy[risk]

            step = {
                "action": action["action"],
                "command": action["command"],
                "risk": risk,
                "policy": policy,
            }

            if policy == "auto_execute":
                plan["auto_steps"].append(step)
            elif policy == "recommend_notify":
                if severity_score >= 60:  # only recommend medium actions for high severity
                    plan["manual_steps"].append(step)
            elif policy == "require_approval":
                if severity_score >= 80:  # only suggest high-risk for critical severity
                    plan["manual_steps"].append(step)
            elif policy == "human_only":
                plan["blocked_steps"].append(step)

        return plan


# Test
engine = RemediationEngine()

test_cases = [
    ("performance", 85, "High severity performance issue"),
    ("storage", 95, "Critical storage issue"),
    ("replication", 70, "Medium severity replication lag"),
    ("connectivity", 40, "Low severity connection warning"),
]

print("\nRemediation Plans:")
print("-" * 65)

for category, severity, description in test_cases:
    plan = engine.get_remediation_plan(category, severity)

    print(f"\n  {description} (severity={severity})")

    if plan["auto_steps"]:
        print(f"    Auto-execute ({len(plan['auto_steps'])} steps):")
        for step in plan["auto_steps"]:
            print(f"      [{step['risk']:>8s}] {step['action']}")

    if plan["manual_steps"]:
        print(f"    Manual steps ({len(plan['manual_steps'])} steps):")
        for step in plan["manual_steps"]:
            print(f"      [{step['risk']:>8s}] {step['action']}")

    if plan["blocked_steps"]:
        print(f"    Blocked (human only):")
        for step in plan["blocked_steps"]:
            print(f"      [{step['risk']:>8s}] {step['action']} <- CANNOT AUTO-EXECUTE")

print("""
Remediation safety:
  - Low severity (< 60): only run diagnostic queries automatically
  - Medium severity (60-80): recommend medium-risk actions
  - High severity (>= 80): recommend high-risk actions (with approval)
  - Critical actions: always blocked from auto-execution

This ensures the AI NEVER does something dangerous without oversight.
""")
PYEOF
```

---

## Step 3. DBA feedback loop

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime

# ============================================================
# DBA FEEDBACK LOOP
# The AI learns from DBA corrections.
# Every time a DBA accepts or corrects a recommendation,
# the system gets smarter.
#
# DBA analogy: training a junior DBA.
# They make a diagnosis, you correct them, next time they're better.
# This is the same process, automated.
# ============================================================

print("DBA Feedback Loop")
print("=" * 50)

class FeedbackCollector:
    """
    Collect DBA feedback on AI predictions and actions.

    Feedback types:
    1. CONFIRM: AI was right (positive reinforcement)
    2. CORRECT: AI was wrong, here's the right answer (learning)
    3. OVERRIDE: AI's action was wrong, do this instead (action learning)
    4. ESCALATE: AI can't handle this, need senior DBA (limitation learning)

    DBA analogy: like a review system for your monitoring.
    "This alert was correctly classified" -> confirm
    "This should have been storage, not performance" -> correct
    """

    def __init__(self):
        self.feedback_log = []
        self.correction_counts = {}      # category -> correction count
        self.accuracy_per_category = {}  # category -> [correct, total]

    def record_feedback(self, alert_id, ai_prediction, feedback_type,
                        correct_answer=None, dba_notes=None):
        """Record DBA feedback on an AI prediction."""
        entry = {
            "alert_id": alert_id,
            "timestamp": datetime.now().isoformat(),
            "ai_prediction": ai_prediction,
            "feedback_type": feedback_type,    # confirm, correct, override, escalate
            "correct_answer": correct_answer,
            "dba_notes": dba_notes,
        }
        self.feedback_log.append(entry)

        # Track accuracy per category
        category = ai_prediction.get("category", "unknown")
        if category not in self.accuracy_per_category:
            self.accuracy_per_category[category] = {"correct": 0, "total": 0}

        self.accuracy_per_category[category]["total"] += 1

        if feedback_type == "confirm":
            self.accuracy_per_category[category]["correct"] += 1
        elif feedback_type == "correct":
            # Track what we got wrong
            self.correction_counts[category] = self.correction_counts.get(category, 0) + 1

        return entry

    def get_accuracy_report(self):
        """Show accuracy per category based on DBA feedback."""
        report = {}
        for category, stats in self.accuracy_per_category.items():
            total = stats["total"]
            correct = stats["correct"]
            accuracy = correct / total * 100 if total > 0 else 0
            corrections = self.correction_counts.get(category, 0)

            report[category] = {
                "total": total,
                "correct": correct,
                "accuracy": round(accuracy, 1),
                "corrections": corrections,
            }
        return report

    def get_retraining_suggestions(self):
        """
        Based on feedback, suggest what to retrain.

        Categories with low accuracy need more training data.
        Common corrections become new training examples.
        """
        suggestions = []
        for category, stats in self.accuracy_per_category.items():
            total = stats["total"]
            correct = stats["correct"]
            accuracy = correct / total * 100 if total > 0 else 0

            if total >= 10 and accuracy < 80:
                suggestions.append({
                    "category": category,
                    "accuracy": accuracy,
                    "suggestion": f"Retrain {category} classifier (accuracy {accuracy:.0f}% < 80%)",
                    "priority": "high" if accuracy < 60 else "medium",
                })

        # Check for systematic errors (same correction pattern)
        corrections = [
            f for f in self.feedback_log if f["feedback_type"] == "correct"
        ]
        if len(corrections) >= 3:
            suggestions.append({
                "category": "all",
                "suggestion": f"{len(corrections)} corrections collected - add to training data",
                "priority": "medium",
            })

        return suggestions


# Simulate DBA feedback over time
collector = FeedbackCollector()

# Simulate 30 predictions with DBA review
import random
random.seed(42)

predictions = [
    # (ai_prediction, feedback_type, correct_answer_if_wrong)
    ({"category": "performance", "confidence": 0.9}, "confirm", None),
    ({"category": "performance", "confidence": 0.85}, "confirm", None),
    ({"category": "storage", "confidence": 0.88}, "confirm", None),
    ({"category": "performance", "confidence": 0.7}, "correct", {"category": "connectivity"}),
    ({"category": "replication", "confidence": 0.9}, "confirm", None),
    ({"category": "storage", "confidence": 0.8}, "confirm", None),
    ({"category": "performance", "confidence": 0.6}, "correct", {"category": "storage"}),
    ({"category": "connectivity", "confidence": 0.85}, "confirm", None),
    ({"category": "replication", "confidence": 0.75}, "confirm", None),
    ({"category": "performance", "confidence": 0.92}, "confirm", None),
    ({"category": "storage", "confidence": 0.5}, "correct", {"category": "backup"}),
    ({"category": "performance", "confidence": 0.88}, "confirm", None),
    ({"category": "replication", "confidence": 0.7}, "correct", {"category": "connectivity"}),
    ({"category": "storage", "confidence": 0.9}, "confirm", None),
    ({"category": "performance", "confidence": 0.8}, "confirm", None),
]

for i, (pred, feedback, correct) in enumerate(predictions):
    collector.record_feedback(
        alert_id=f"alert_{i:03d}",
        ai_prediction=pred,
        feedback_type=feedback,
        correct_answer=correct,
        dba_notes=f"Reviewed by DBA" if feedback == "correct" else None,
    )

# Show accuracy report
report = collector.get_accuracy_report()
print("\nAccuracy Report (based on DBA feedback):")
print("-" * 55)
print(f"{'Category':<15s} {'Total':>6s} {'Correct':>8s} {'Accuracy':>9s} {'Fixes':>6s}")
print("-" * 55)

for cat, stats in sorted(report.items()):
    print(f"{cat:<15s} {stats['total']:>6d} {stats['correct']:>8d} "
          f"{stats['accuracy']:>8.0f}% {stats['corrections']:>6d}")

# Show retraining suggestions
suggestions = collector.get_retraining_suggestions()
if suggestions:
    print(f"\nRetraining Suggestions:")
    for s in suggestions:
        print(f"  [{s['priority']:>6s}] {s['suggestion']}")

print("""
The Feedback Loop:
  1. AI predicts -> DBA reviews
  2. DBA confirms (right) or corrects (wrong)
  3. Corrections become training data
  4. Low-accuracy categories get retrained
  5. Over time, AI accuracy improves per category

This is how dbaBrain gets smarter:
  Week 1: 75% accuracy (many corrections needed)
  Month 1: 85% accuracy (common patterns learned)
  Month 6: 93% accuracy (most patterns seen)
  Year 1: 96% accuracy (rare edge cases too)

The DBA's expertise is captured in the feedback data.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Action catalog | Library of possible fixes | Your runbook, structured |
| Risk levels | Safety classification per action | Junior vs senior permissions |
| Execution policy | Who can execute what | GRANT/REVOKE for AI actions |
| Remediation plan | Step-by-step fix based on severity | "Do this first, then this" |
| Feedback loop | DBA corrections improve the AI | Training a junior DBA |
| Retraining suggestions | Identify weak categories | Focus training where it's needed |
