# Use 01: Capstone Exercises

Apply everything you've learned. These exercises combine concepts from all 18 previous modules.

---

## Exercise 1: End-to-end alert processing

Build a complete alert processor that takes raw alerts and returns actionable results.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 1: End-to-End Alert Processor
#
# Combine:
#   - Feature extraction (Module 16)
#   - Classification (Modules 9-10)
#   - Severity scoring (Module 17)
#   - Root cause suggestion (Module 17)
#   - Action recommendation (Module 17)
#   - Output filtering (Module 15)
#
# This is the core product you're shipping.
# ============================================================

print("Exercise 1: End-to-End Alert Processor")
print("=" * 55)

# ---- Component 1: Feature Extraction ----

class FeatureExtractor:
    """Extract features from text and metrics (Module 16)."""

    KEYWORDS = {
        "performance": ["slow", "latency", "timeout", "cpu", "load", "query_time"],
        "storage": ["disk", "space", "full", "tablespace", "storage", "pgdata"],
        "replication": ["replica", "lag", "standby", "wal", "replication", "streaming"],
        "connectivity": ["connection", "refused", "pool", "max_connections", "pgbouncer"],
        "security": ["permission", "denied", "login", "auth", "unauthorized", "ssl"],
        "backup": ["backup", "archive", "pitr", "restore", "wal_archive", "basebackup"],
    }

    def extract(self, text, metrics):
        text_lower = text.lower()

        # Text features: keyword counts per category
        text_features = {}
        for category, keywords in self.KEYWORDS.items():
            text_features[category] = sum(
                1 for kw in keywords if kw in text_lower
            )

        # Metric features: normalize to 0-1
        ranges = {
            "cpu_percent": (0, 100),
            "disk_percent": (0, 100),
            "connections": (0, 500),
            "replication_lag_seconds": (0, 3600),
            "query_time_seconds": (0, 300),
        }
        metric_features = {}
        for name, value in metrics.items():
            if name in ranges:
                lo, hi = ranges[name]
                metric_features[name] = max(0.0, min(1.0, (value - lo) / (hi - lo)))

        return text_features, metric_features


# ---- Component 2: Classification (Late Fusion) ----

class AlertClassifier:
    """Classify alerts using late fusion (Modules 9-10, 16)."""

    METRIC_TO_CATEGORY = {
        "cpu_percent": "performance",
        "disk_percent": "storage",
        "connections": "connectivity",
        "replication_lag_seconds": "replication",
        "query_time_seconds": "performance",
    }

    def classify(self, text_features, metric_features):
        # Text vote
        text_cat = max(text_features, key=text_features.get)
        text_score = text_features[text_cat]

        # Metric vote
        metric_cat = None
        metric_score = 0
        for name, value in metric_features.items():
            if value > metric_score and name in self.METRIC_TO_CATEGORY:
                metric_score = value
                metric_cat = self.METRIC_TO_CATEGORY[name]

        # Fusion
        if text_cat == metric_cat:
            confidence = min(1.0, text_score * 0.3 + metric_score * 0.7 + 0.1)
            return text_cat, confidence
        elif metric_score > 0.8:
            return metric_cat, metric_score * 0.8
        elif text_score >= 2:
            return text_cat, min(1.0, text_score * 0.25)
        else:
            return text_cat, 0.3


# ---- Component 3: Severity Scoring ----

class SeverityScorer:
    """Score severity with metric floor safety (Module 17)."""

    CRITICAL = {
        "cpu_percent": 95, "disk_percent": 95,
        "connections": 450, "replication_lag_seconds": 300,
    }

    def score(self, category, confidence, metrics, environment):
        base = confidence * 60
        bonus = 0
        for name, value in metrics.items():
            if name in self.CRITICAL:
                threshold = self.CRITICAL[name]
                if value >= threshold:
                    bonus = max(bonus, 40)
                elif value >= threshold * 0.8:
                    bonus = max(bonus, 20)

        env_weight = {"production": 1.0, "staging": 0.7, "development": 0.4}.get(
            environment, 0.5
        )
        score = min(100, (base + bonus) * env_weight)

        # Metric floor: critical metrics force P1
        for name, value in metrics.items():
            if name in self.CRITICAL and value >= self.CRITICAL[name]:
                score = max(score, 80)

        if score >= 80: priority = "P1"
        elif score >= 60: priority = "P2"
        elif score >= 40: priority = "P3"
        else: priority = "P4"

        return score, priority


# ---- Component 4: Root Cause Suggestion ----

class RootCauseSuggestor:
    """Suggest root causes based on category and metrics (Module 17)."""

    CAUSES = {
        "performance": [
            {"cause": "Long-running queries", "check": "SELECT * FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 minutes'"},
            {"cause": "Missing indexes", "check": "SELECT * FROM pg_stat_user_tables WHERE seq_scan > idx_scan AND n_live_tup > 10000"},
            {"cause": "Connection contention", "check": "SELECT wait_event_type, count(*) FROM pg_stat_activity GROUP BY 1"},
        ],
        "storage": [
            {"cause": "Table bloat", "check": "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10"},
            {"cause": "WAL accumulation", "check": "SELECT count(*) FROM pg_ls_waldir()"},
            {"cause": "Unvacuumed tables", "check": "SELECT schemaname, relname, last_autovacuum FROM pg_stat_user_tables WHERE last_autovacuum IS NULL OR last_autovacuum < now() - interval '7 days'"},
        ],
        "replication": [
            {"cause": "Network latency to standby", "check": "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication"},
            {"cause": "Standby overloaded", "check": "Check standby CPU and I/O usage"},
            {"cause": "WAL sender bottleneck", "check": "SELECT * FROM pg_stat_replication WHERE state != 'streaming'"},
        ],
        "connectivity": [
            {"cause": "Connection pool exhausted", "check": "SHOW max_connections; SELECT count(*) FROM pg_stat_activity"},
            {"cause": "pg_hba.conf misconfigured", "check": "SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL"},
            {"cause": "Network firewall change", "check": "Check security group / iptables rules"},
        ],
        "security": [
            {"cause": "Brute force login attempt", "check": "Check PostgreSQL log for 'FATAL:  password authentication failed'"},
            {"cause": "Privilege escalation", "check": "SELECT rolname, rolsuper FROM pg_roles WHERE rolsuper = true"},
        ],
        "backup": [
            {"cause": "Backup storage full", "check": "Check backup destination disk space"},
            {"cause": "WAL archiver failed", "check": "SELECT * FROM pg_stat_archiver WHERE last_failed_time > now() - interval '1 hour'"},
        ],
    }

    def suggest(self, category):
        causes = self.CAUSES.get(category, [])
        if causes:
            return causes[0]  # Return most likely cause
        return {"cause": "Unknown", "check": "Manual investigation needed"}


# ---- Component 5: Action Recommendation ----

class ActionRecommender:
    """Recommend actions based on severity (Module 17)."""

    def recommend(self, category, priority, root_cause):
        if priority == "P1":
            return {
                "action": f"Investigate immediately: {root_cause['cause']}",
                "urgency": "NOW",
                "check_query": root_cause.get("check", ""),
                "escalate": True,
            }
        elif priority == "P2":
            return {
                "action": f"Investigate within 1 hour: {root_cause['cause']}",
                "urgency": "SOON",
                "check_query": root_cause.get("check", ""),
                "escalate": False,
            }
        else:
            return {
                "action": f"Review when available: {root_cause['cause']}",
                "urgency": "SCHEDULED",
                "check_query": root_cause.get("check", ""),
                "escalate": False,
            }


# ---- Component 6: Output Filter ----

class OutputFilter:
    """Filter sensitive data from output (Module 15)."""

    SENSITIVE_PATTERNS = ["password", "secret", "token", "key", "credential"]

    def filter(self, result):
        """Remove any sensitive data from the result."""
        filtered = {}
        for key, value in result.items():
            if isinstance(value, str):
                clean = value
                for pattern in self.SENSITIVE_PATTERNS:
                    if pattern in clean.lower():
                        clean = "[REDACTED - contains sensitive pattern]"
                        break
                filtered[key] = clean
            elif isinstance(value, dict):
                filtered[key] = self.filter(value)
            else:
                filtered[key] = value
        return filtered


# ---- Assemble the Full Pipeline ----

class DBaBrainProcessor:
    """
    The complete dbaBrain alert processor.
    Assembles all components from Modules 5-18.
    """

    def __init__(self):
        self.extractor = FeatureExtractor()
        self.classifier = AlertClassifier()
        self.scorer = SeverityScorer()
        self.root_cause = RootCauseSuggestor()
        self.recommender = ActionRecommender()
        self.output_filter = OutputFilter()

    def process(self, alert_text, metrics, environment="production"):
        # Step 1: Extract features
        text_features, metric_features = self.extractor.extract(
            alert_text, metrics
        )

        # Step 2: Classify
        category, confidence = self.classifier.classify(
            text_features, metric_features
        )

        # Step 3: Score severity
        score, priority = self.scorer.score(
            category, confidence, metrics, environment
        )

        # Step 4: Suggest root cause
        cause = self.root_cause.suggest(category)

        # Step 5: Recommend action
        action = self.recommender.recommend(category, priority, cause)

        # Step 6: Filter output
        result = {
            "category": category,
            "confidence": round(confidence, 3),
            "severity_score": round(score, 1),
            "priority": priority,
            "root_cause": cause["cause"],
            "check_query": cause.get("check", ""),
            "action": action["action"],
            "urgency": action["urgency"],
            "escalate": action["escalate"],
            "environment": environment,
        }

        return self.output_filter.filter(result)


# ---- Run Test Alerts ----

processor = DBaBrainProcessor()

test_alerts = [
    {
        "name": "Critical CPU on Production",
        "text": "Extremely high CPU, queries timing out, database slow",
        "metrics": {"cpu_percent": 97, "connections": 280},
        "env": "production",
    },
    {
        "name": "Disk Full Warning",
        "text": "Disk space critical on /pgdata tablespace",
        "metrics": {"disk_percent": 96},
        "env": "production",
    },
    {
        "name": "Replication Lag",
        "text": "Standby pg-standby-1 replication lag increasing",
        "metrics": {"replication_lag_seconds": 450},
        "env": "production",
    },
    {
        "name": "Dev Environment Noise",
        "text": "High CPU on development database",
        "metrics": {"cpu_percent": 88},
        "env": "development",
    },
    {
        "name": "Security Alert",
        "text": "Multiple login denied attempts, unauthorized access from unknown IP",
        "metrics": {"connections": 45},
        "env": "production",
    },
]

for alert in test_alerts:
    print(f"\nAlert: {alert['name']}")
    print("-" * 50)
    result = processor.process(alert["text"], alert["metrics"], alert["env"])
    print(f"  Category:   {result['category']}")
    print(f"  Confidence: {result['confidence']}")
    print(f"  Priority:   {result['priority']} (score: {result['severity_score']})")
    print(f"  Root Cause: {result['root_cause']}")
    print(f"  Action:     {result['action']}")
    print(f"  Urgency:    {result['urgency']}")
    if result.get('escalate'):
        print(f"  ** ESCALATE TO ON-CALL DBA **")

print("""
What you built:
  1. Feature extraction (text keywords + metric normalization)
  2. Classification (late fusion of text and metric signals)
  3. Severity scoring (with metric floor safety)
  4. Root cause suggestion (knowledge base lookup)
  5. Action recommendation (priority-based)
  6. Output filtering (redact sensitive data)

This is a complete AI product pipeline.
Every component maps to a module you studied.
""")
PYEOF
```

---

## Exercise 2: Accuracy tracker

Build a system to track classification accuracy over time with per-category breakdown.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 2: Accuracy Tracker
#
# Track how well your classifier performs over time.
# Break down accuracy by category to find weak spots.
#
# DBA analogy: like tracking query performance per table.
# Overall queries might be fast, but one table could be slow.
# Same for AI: overall accuracy might be 90%, but one
# category could be at 60%.
# ============================================================

print("Exercise 2: Accuracy Tracker")
print("=" * 55)

class AccuracyTracker:
    """
    Track prediction accuracy over time.

    Records every prediction and its ground truth (DBA feedback).
    Calculates overall and per-category accuracy.
    Alerts when accuracy drops below thresholds.

    DBA analogy: like pg_stat_user_tables.
    It tracks reads, writes, cache hits per table.
    This tracks correct predictions, misses per category.
    """

    def __init__(self, overall_threshold=0.90, category_threshold=0.80):
        # overall_threshold: minimum overall accuracy (90%)
        # category_threshold: minimum per-category accuracy (80%)
        self.overall_threshold = overall_threshold
        self.category_threshold = category_threshold

        # Store predictions: list of {predicted, actual, correct}
        self.predictions = []

        # Per-category counts
        self.category_correct = {}
        self.category_total = {}

    def record(self, predicted_category, actual_category):
        """
        Record a prediction and its ground truth.

        Call this when a DBA reviews a classification
        and confirms or corrects the category.
        """
        correct = predicted_category == actual_category

        self.predictions.append({
            "predicted": predicted_category,
            "actual": actual_category,
            "correct": correct,
        })

        # Update per-category counts (for the ACTUAL category)
        if actual_category not in self.category_total:
            self.category_total[actual_category] = 0
            self.category_correct[actual_category] = 0

        self.category_total[actual_category] += 1
        if correct:
            self.category_correct[actual_category] += 1

    def get_overall_accuracy(self):
        """Calculate overall accuracy across all predictions."""
        if not self.predictions:
            return 0.0
        correct = sum(1 for p in self.predictions if p["correct"])
        return correct / len(self.predictions)

    def get_category_accuracy(self):
        """Calculate accuracy per category."""
        results = {}
        for category in self.category_total:
            total = self.category_total[category]
            correct = self.category_correct.get(category, 0)
            accuracy = correct / total if total > 0 else 0.0
            results[category] = {
                "accuracy": round(accuracy, 3),
                "correct": correct,
                "total": total,
            }
        return results

    def get_confusion_matrix(self):
        """
        Build a confusion matrix showing where predictions go wrong.

        Rows = actual category, Columns = predicted category.
        Diagonal = correct predictions.
        Off-diagonal = misclassifications.

        DBA analogy: like a crosstab query.
        SELECT actual, predicted, count(*)
        FROM predictions
        GROUP BY actual, predicted
        """
        categories = sorted(set(
            [p["actual"] for p in self.predictions] +
            [p["predicted"] for p in self.predictions]
        ))

        # Build the matrix
        matrix = {}
        for actual in categories:
            matrix[actual] = {}
            for predicted in categories:
                matrix[actual][predicted] = 0

        for p in self.predictions:
            matrix[p["actual"]][p["predicted"]] += 1

        return categories, matrix

    def check_alerts(self):
        """Check if any accuracy thresholds are breached."""
        alerts = []

        overall = self.get_overall_accuracy()
        if overall < self.overall_threshold:
            alerts.append({
                "type": "overall_accuracy",
                "message": f"Overall accuracy {overall:.1%} below threshold {self.overall_threshold:.0%}",
                "severity": "high",
            })

        per_category = self.get_category_accuracy()
        for category, stats in per_category.items():
            if stats["total"] >= 5 and stats["accuracy"] < self.category_threshold:
                alerts.append({
                    "type": "category_accuracy",
                    "message": f"{category} accuracy {stats['accuracy']:.1%} below {self.category_threshold:.0%} ({stats['total']} samples)",
                    "severity": "medium",
                })

        return alerts


# ---- Simulate predictions and DBA feedback ----

tracker = AccuracyTracker(overall_threshold=0.90, category_threshold=0.80)

# Simulated results: (predicted, actual)
# Most are correct, some are wrong
feedback_data = [
    # Performance alerts - mostly correct
    ("performance", "performance"),
    ("performance", "performance"),
    ("performance", "performance"),
    ("performance", "performance"),
    ("performance", "performance"),
    ("connectivity", "performance"),  # misclassified!

    # Storage alerts - all correct
    ("storage", "storage"),
    ("storage", "storage"),
    ("storage", "storage"),
    ("storage", "storage"),
    ("storage", "storage"),

    # Replication alerts - some confusion with connectivity
    ("replication", "replication"),
    ("replication", "replication"),
    ("replication", "replication"),
    ("connectivity", "replication"),  # misclassified!
    ("connectivity", "replication"),  # misclassified!

    # Connectivity - often confused with performance
    ("connectivity", "connectivity"),
    ("connectivity", "connectivity"),
    ("performance", "connectivity"),  # misclassified!
    ("performance", "connectivity"),  # misclassified!
    ("connectivity", "connectivity"),

    # Security - mostly correct
    ("security", "security"),
    ("security", "security"),
    ("security", "security"),
    ("security", "security"),

    # Backup - correct
    ("backup", "backup"),
    ("backup", "backup"),
    ("backup", "backup"),
]

for predicted, actual in feedback_data:
    tracker.record(predicted, actual)

# ---- Display Results ----

print(f"\nOverall Accuracy: {tracker.get_overall_accuracy():.1%}")
print(f"Total Predictions: {len(tracker.predictions)}")

print(f"\nPer-Category Accuracy:")
print(f"  {'Category':<15s} {'Accuracy':>10s} {'Correct':>8s} {'Total':>8s}")
print(f"  {'-'*15} {'-'*10} {'-'*8} {'-'*8}")
per_cat = tracker.get_category_accuracy()
for cat, stats in sorted(per_cat.items()):
    flag = " <-- LOW" if stats["accuracy"] < 0.80 else ""
    print(f"  {cat:<15s} {stats['accuracy']:>9.1%} {stats['correct']:>8d} {stats['total']:>8d}{flag}")

# Confusion matrix
print(f"\nConfusion Matrix:")
categories, matrix = tracker.get_confusion_matrix()
header = f"  {'Actual \\ Pred':<15s}"
for cat in categories:
    header += f" {cat[:5]:>6s}"
print(header)
print(f"  {'-'*15}" + " ------" * len(categories))
for actual in categories:
    row = f"  {actual:<15s}"
    for predicted in categories:
        count = matrix[actual][predicted]
        marker = f"  [{count}]" if actual == predicted else f"   {count} "
        row += f"{marker:>6s}"
    print(row)

# Check alerts
print(f"\nAccuracy Alerts:")
alerts = tracker.check_alerts()
if alerts:
    for alert in alerts:
        print(f"  [{alert['severity'].upper():>6s}] {alert['message']}")
else:
    print(f"  No alerts - all thresholds met!")

print("""
What the accuracy tracker tells you:
  1. Overall accuracy: is the system meeting the 90% target?
  2. Per-category accuracy: which categories need more training data?
  3. Confusion matrix: which categories get confused with each other?
  4. Alerts: automatic notification when accuracy drops

Action items from this analysis:
  - Replication is confused with connectivity (fix: add more keywords)
  - Connectivity is confused with performance (fix: use metric signals)
  - Storage and backup are reliable (keep the current approach)
""")
PYEOF
```

---

## Exercise 3: DBA feedback system

Build the feedback loop that lets DBAs correct the AI and improve it over time.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# EXERCISE 3: DBA Feedback System
#
# The AI gets better from DBA corrections.
# This is the learning loop: predict -> review -> correct -> improve.
#
# DBA analogy: like PostgreSQL's autovacuum learning.
# Autovacuum tracks dead tuple rates and adjusts thresholds.
# Your AI tracks misclassifications and adjusts keywords.
# ============================================================

print("Exercise 3: DBA Feedback System")
print("=" * 55)

from datetime import datetime

class FeedbackSystem:
    """
    Collect and process DBA feedback on classifications.

    Three types of feedback:
      confirm:  DBA agrees with the classification (no change needed)
      correct:  DBA changes the category (AI was wrong)
      annotate: DBA adds context (not wrong, but more detail)

    DBA analogy: like a change management system.
    Every correction is tracked, reviewed, and applied
    through a controlled process.
    """

    def __init__(self):
        self.feedback_log = []
        self.correction_counts = {}  # actual -> predicted -> count
        self.keyword_suggestions = {}  # category -> [new keywords]

    def submit_feedback(self, alert_id, predicted, feedback_type,
                         corrected_category=None, dba_name="unknown",
                         notes=""):
        """
        Submit feedback on a classification.

        Parameters:
          alert_id: which alert this feedback is for
          predicted: what the AI predicted
          feedback_type: "confirm", "correct", or "annotate"
          corrected_category: the correct category (if feedback_type is "correct")
          dba_name: who submitted the feedback
          notes: any additional context
        """
        entry = {
            "alert_id": alert_id,
            "predicted": predicted,
            "feedback_type": feedback_type,
            "corrected_category": corrected_category,
            "dba_name": dba_name,
            "notes": notes,
            "timestamp": datetime.now().isoformat(),
        }

        self.feedback_log.append(entry)

        # Track corrections for retraining
        if feedback_type == "correct" and corrected_category:
            key = f"{corrected_category} <- {predicted}"
            self.correction_counts[key] = self.correction_counts.get(key, 0) + 1

        return entry

    def get_correction_summary(self):
        """
        Summarize where the AI makes mistakes.

        Returns the most common misclassifications.
        This tells you what to fix first.

        DBA analogy: like pg_stat_statements showing your slowest queries.
        Fix the most frequent/expensive ones first.
        """
        return dict(sorted(
            self.correction_counts.items(),
            key=lambda x: x[1],
            reverse=True
        ))

    def suggest_keyword_updates(self):
        """
        Analyze corrections to suggest keyword improvements.

        If the AI keeps classifying "replication" alerts as
        "connectivity", maybe we need more replication keywords.
        """
        suggestions = []

        for correction, count in self.correction_counts.items():
            if count >= 2:  # only suggest if pattern repeats
                actual, predicted = correction.split(" <- ")
                suggestions.append({
                    "action": f"Add more keywords to '{actual}' category",
                    "reason": f"AI classified {count} '{actual}' alerts as '{predicted}'",
                    "priority": "high" if count >= 5 else "medium",
                })

        return suggestions

    def get_dba_activity(self):
        """
        Track which DBAs are providing feedback.

        DBA analogy: like tracking which DBAs are responding to alerts.
        Some DBAs review more alerts. Their feedback has more weight.
        """
        activity = {}
        for entry in self.feedback_log:
            name = entry["dba_name"]
            if name not in activity:
                activity[name] = {"confirms": 0, "corrections": 0, "annotations": 0}
            activity[name][f"{entry['feedback_type']}s"] += 1
        return activity

    def get_accuracy_trend(self, window_size=10):
        """
        Calculate rolling accuracy over the last N feedbacks.

        Shows if accuracy is improving or degrading over time.
        """
        if not self.feedback_log:
            return []

        # Only look at confirms and corrections (not annotations)
        reviews = [
            f for f in self.feedback_log
            if f["feedback_type"] in ("confirm", "correct")
        ]

        if len(reviews) < window_size:
            window_size = len(reviews)

        trend = []
        for i in range(window_size, len(reviews) + 1):
            window = reviews[i - window_size:i]
            correct = sum(1 for f in window if f["feedback_type"] == "confirm")
            accuracy = correct / len(window)
            trend.append(round(accuracy, 2))

        return trend


# ---- Simulate DBA Feedback ----

feedback = FeedbackSystem()

# Simulate feedback from multiple DBAs
feedbacks = [
    # Senior DBA confirms correct predictions
    ("alert-001", "performance", "confirm", None, "sarah_dba", "Correct - CPU spike from vacuum"),
    ("alert-002", "storage", "confirm", None, "sarah_dba", "Yes, /pgdata at 92%"),
    ("alert-003", "replication", "confirm", None, "sarah_dba", "Lag due to long transaction"),

    # Senior DBA corrects mistakes
    ("alert-004", "connectivity", "correct", "replication", "sarah_dba", "This was actually a replication issue causing connection drops"),
    ("alert-005", "performance", "correct", "connectivity", "sarah_dba", "Slow because connection pool exhausted, not CPU"),
    ("alert-006", "connectivity", "correct", "replication", "mike_dba", "Standby disconnect, not client connectivity"),

    # Junior DBA feedback
    ("alert-007", "performance", "confirm", None, "junior_kim", "Looks right"),
    ("alert-008", "storage", "confirm", None, "junior_kim", ""),
    ("alert-009", "performance", "correct", "storage", "junior_kim", "Actually disk I/O causing slowness"),

    # More senior feedback
    ("alert-010", "replication", "confirm", None, "mike_dba", "Correct"),
    ("alert-011", "connectivity", "correct", "replication", "mike_dba", "WAL receiver disconnect"),
    ("alert-012", "backup", "confirm", None, "sarah_dba", "Archive command failed"),
    ("alert-013", "security", "confirm", None, "sarah_dba", "Brute force attempt"),
    ("alert-014", "performance", "confirm", None, "mike_dba", ""),
    ("alert-015", "storage", "confirm", None, "sarah_dba", "Correct"),
]

for alert_id, predicted, ftype, corrected, dba, notes in feedbacks:
    feedback.submit_feedback(alert_id, predicted, ftype, corrected, dba, notes)

# ---- Display Results ----

print(f"\nFeedback Summary:")
print(f"  Total feedback entries: {len(feedback.feedback_log)}")
confirms = sum(1 for f in feedback.feedback_log if f["feedback_type"] == "confirm")
corrections = sum(1 for f in feedback.feedback_log if f["feedback_type"] == "correct")
print(f"  Confirmed correct: {confirms}")
print(f"  Corrected (AI wrong): {corrections}")
print(f"  Accuracy from feedback: {confirms / (confirms + corrections):.1%}")

print(f"\nMost Common Misclassifications:")
print(f"  {'Pattern':<40s} {'Count':>5s}")
print(f"  {'-'*40} {'-'*5}")
for pattern, count in feedback.get_correction_summary().items():
    print(f"  {pattern:<40s} {count:>5d}")

print(f"\nSuggested Improvements:")
for suggestion in feedback.suggest_keyword_updates():
    print(f"  [{suggestion['priority']:>6s}] {suggestion['action']}")
    print(f"           {suggestion['reason']}")

print(f"\nDBA Activity:")
print(f"  {'DBA':<15s} {'Confirms':>10s} {'Corrections':>12s}")
print(f"  {'-'*15} {'-'*10} {'-'*12}")
for dba, activity in feedback.get_dba_activity().items():
    print(f"  {dba:<15s} {activity['confirms']:>10d} {activity['corrections']:>12d}")

print(f"\nAccuracy Trend (rolling window of 10):")
trend = feedback.get_accuracy_trend(window_size=10)
if trend:
    for i, acc in enumerate(trend):
        bar = "#" * int(acc * 20)
        print(f"  Window {i+1:>2d}: {acc:>5.0%} {bar}")

print("""
What the feedback system does:
  1. Collects DBA corrections on AI predictions
  2. Identifies the most common misclassification patterns
  3. Suggests specific keyword/rule improvements
  4. Tracks which DBAs contribute (trust weighting)
  5. Shows accuracy trends over time

This is how the AI improves:
  predict -> DBA reviews -> corrections logged -> patterns identified ->
  keywords updated -> model retrained -> accuracy improves
""")
PYEOF
```

---

## Exercise 4: Production monitoring dashboard

Build the monitoring system that tracks your AI product's health.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import random

# ============================================================
# EXERCISE 4: Production Monitoring Dashboard
#
# Track everything about your AI in production.
#
# DBA analogy: like pg_stat_statements + pg_stat_activity
# + Prometheus + Grafana. You need to see what's happening
# inside your system at all times.
# ============================================================

print("Exercise 4: Production Monitoring Dashboard")
print("=" * 55)

class ProductionMonitor:
    """
    Monitor all aspects of the AI product in production.

    Tracks:
      - Request metrics (rate, latency, errors)
      - Classification metrics (accuracy, distribution, confidence)
      - System health (component status, resource usage)
      - Alerts (threshold breaches)

    DBA analogy: this IS your Grafana dashboard for the AI.
    Instead of queries/second, you track predictions/second.
    Instead of cache hit ratio, you track classification accuracy.
    """

    def __init__(self):
        self.requests = []
        self.classifications = []
        self.errors = []

    def record_request(self, latency_ms, category, confidence, priority, success=True):
        """Record a single request and its result."""
        self.requests.append({
            "latency_ms": latency_ms,
            "success": success,
            "timestamp": time.time(),
        })
        if success:
            self.classifications.append({
                "category": category,
                "confidence": confidence,
                "priority": priority,
            })
        else:
            self.errors.append({"timestamp": time.time()})

    def get_request_metrics(self):
        """Calculate request rate, latency percentiles, error rate."""
        if not self.requests:
            return {}

        latencies = [r["latency_ms"] for r in self.requests]
        latencies.sort()

        total = len(self.requests)
        errors = sum(1 for r in self.requests if not r["success"])

        return {
            "total_requests": total,
            "error_count": errors,
            "error_rate": round(errors / total * 100, 2),
            "latency_avg": round(sum(latencies) / len(latencies), 1),
            "latency_p50": latencies[len(latencies) // 2],
            "latency_p95": latencies[int(len(latencies) * 0.95)],
            "latency_p99": latencies[int(len(latencies) * 0.99)],
        }

    def get_classification_metrics(self):
        """Calculate classification distribution and confidence."""
        if not self.classifications:
            return {}

        # Category distribution
        categories = {}
        for c in self.classifications:
            cat = c["category"]
            categories[cat] = categories.get(cat, 0) + 1

        # Priority distribution
        priorities = {}
        for c in self.classifications:
            pri = c["priority"]
            priorities[pri] = priorities.get(pri, 0) + 1

        # Average confidence
        avg_confidence = sum(c["confidence"] for c in self.classifications) / len(self.classifications)

        # Low confidence count (< 0.5)
        low_confidence = sum(1 for c in self.classifications if c["confidence"] < 0.5)

        return {
            "total_classifications": len(self.classifications),
            "category_distribution": categories,
            "priority_distribution": priorities,
            "avg_confidence": round(avg_confidence, 3),
            "low_confidence_count": low_confidence,
            "low_confidence_rate": round(low_confidence / len(self.classifications) * 100, 1),
        }

    def check_thresholds(self):
        """Check if any operational thresholds are breached."""
        alerts = []
        req_metrics = self.get_request_metrics()
        class_metrics = self.get_classification_metrics()

        # Latency check
        if req_metrics.get("latency_p95", 0) > 200:
            alerts.append(f"WARN: p95 latency {req_metrics['latency_p95']}ms > 200ms target")

        # Error rate check
        if req_metrics.get("error_rate", 0) > 1:
            alerts.append(f"WARN: Error rate {req_metrics['error_rate']}% > 1% threshold")

        # Low confidence check
        if class_metrics.get("low_confidence_rate", 0) > 20:
            alerts.append(f"WARN: {class_metrics['low_confidence_rate']}% low-confidence predictions")

        # P1 flood check
        p1_count = class_metrics.get("priority_distribution", {}).get("P1", 0)
        total = class_metrics.get("total_classifications", 1)
        if p1_count / total > 0.3:
            alerts.append(f"WARN: {p1_count} P1 alerts ({p1_count/total:.0%}) - possible alert storm")

        return alerts


# ---- Simulate Production Traffic ----

monitor = ProductionMonitor()

# Simulate 200 requests with realistic distribution
random.seed(42)

categories = ["performance", "storage", "replication", "connectivity", "security", "backup"]
cat_weights = [0.30, 0.25, 0.15, 0.15, 0.10, 0.05]

for _ in range(200):
    # Pick category based on weights
    cat = random.choices(categories, weights=cat_weights, k=1)[0]

    # Simulate latency (most fast, some slow)
    latency = random.gauss(15, 5)
    if random.random() < 0.05:  # 5% slow requests
        latency = random.gauss(100, 30)
    latency = max(1, latency)

    # Simulate confidence
    confidence = random.gauss(0.75, 0.15)
    confidence = max(0.1, min(1.0, confidence))

    # Simulate priority
    if confidence > 0.8:
        priority = random.choice(["P1", "P2", "P2", "P3"])
    else:
        priority = random.choice(["P2", "P3", "P3", "P4"])

    # Simulate occasional errors (2%)
    success = random.random() > 0.02

    monitor.record_request(
        latency_ms=round(latency, 1),
        category=cat,
        confidence=round(confidence, 3),
        priority=priority,
        success=success,
    )


# ---- Display Dashboard ----

print("\n--- REQUEST METRICS ---")
req = monitor.get_request_metrics()
print(f"  Total requests:  {req['total_requests']}")
print(f"  Errors:          {req['error_count']} ({req['error_rate']}%)")
print(f"  Latency avg:     {req['latency_avg']} ms")
print(f"  Latency p50:     {req['latency_p50']} ms")
print(f"  Latency p95:     {req['latency_p95']} ms")
print(f"  Latency p99:     {req['latency_p99']} ms")

print("\n--- CLASSIFICATION METRICS ---")
cls = monitor.get_classification_metrics()
print(f"  Total classified: {cls['total_classifications']}")
print(f"  Avg confidence:   {cls['avg_confidence']}")
print(f"  Low confidence:   {cls['low_confidence_count']} ({cls['low_confidence_rate']}%)")

print(f"\n  Category Distribution:")
for cat, count in sorted(cls["category_distribution"].items(), key=lambda x: -x[1]):
    pct = count / cls["total_classifications"] * 100
    bar = "#" * int(pct / 2)
    print(f"    {cat:<15s} {count:>4d} ({pct:>5.1f}%) {bar}")

print(f"\n  Priority Distribution:")
for pri in ["P1", "P2", "P3", "P4"]:
    count = cls["priority_distribution"].get(pri, 0)
    pct = count / cls["total_classifications"] * 100
    bar = "#" * int(pct / 2)
    print(f"    {pri} {count:>4d} ({pct:>5.1f}%) {bar}")

print(f"\n--- ALERTS ---")
alerts = monitor.check_thresholds()
if alerts:
    for alert in alerts:
        print(f"  {alert}")
else:
    print(f"  All thresholds OK")

print("""
Your monitoring dashboard tracks:
  1. Request metrics: rate, latency, errors (is the API healthy?)
  2. Classification metrics: distribution, confidence (is the AI working?)
  3. Threshold alerts: automatic warning when something degrades

DBA analogy:
  Request metrics = pg_stat_statements (query performance)
  Classification metrics = custom metrics (business logic health)
  Threshold alerts = Prometheus alert rules (automated monitoring)
""")
PYEOF
```

---

## Exercise 5: Complete system test

Run the entire system end-to-end and verify all components work together.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time

# ============================================================
# EXERCISE 5: Complete System Test
#
# Run the full system: process alerts, collect feedback,
# track accuracy, monitor health. Everything together.
#
# DBA analogy: like a full disaster recovery test.
# You don't just test backup. You test backup + restore +
# promotion + application reconnection + data verification.
# The full end-to-end.
# ============================================================

print("Exercise 5: Complete System Test")
print("=" * 55)

# All components assembled
class CompleteSystem:
    def __init__(self):
        self.predictions = []
        self.feedback = []
        self.accuracy_by_category = {}
        self.total_correct = 0
        self.total_predictions = 0

    def classify(self, text, metrics, env="production"):
        """Simplified classifier for system test."""
        KEYWORDS = {
            "performance": ["slow", "cpu", "timeout", "load", "latency"],
            "storage": ["disk", "space", "full", "tablespace"],
            "replication": ["replica", "lag", "standby", "wal"],
            "connectivity": ["connection", "refused", "pool"],
            "security": ["permission", "denied", "login", "auth"],
            "backup": ["backup", "archive", "pitr", "restore"],
        }
        METRIC_CATS = {
            "cpu_percent": "performance", "disk_percent": "storage",
            "connections": "connectivity", "replication_lag_seconds": "replication",
        }
        CRITICAL = {
            "cpu_percent": 95, "disk_percent": 95,
            "connections": 450, "replication_lag_seconds": 300,
        }

        text_lower = text.lower()
        text_scores = {cat: sum(1 for kw in kws if kw in text_lower)
                       for cat, kws in KEYWORDS.items()}
        text_cat = max(text_scores, key=text_scores.get)
        text_score = text_scores[text_cat]

        metric_cat = None; metric_score = 0
        for n, v in metrics.items():
            ranges = {"cpu_percent":(0,100),"disk_percent":(0,100),
                      "connections":(0,500),"replication_lag_seconds":(0,3600)}
            if n in ranges:
                lo, hi = ranges[n]
                norm = max(0.0, min(1.0, (v - lo) / (hi - lo)))
                if norm > metric_score and n in METRIC_CATS:
                    metric_score = norm; metric_cat = METRIC_CATS[n]

        if text_cat == metric_cat:
            category = text_cat
            confidence = min(1.0, text_score * 0.3 + metric_score * 0.7 + 0.1)
        elif metric_score > 0.8:
            category = metric_cat; confidence = metric_score * 0.8
        elif text_score >= 2:
            category = text_cat; confidence = min(1.0, text_score * 0.25)
        else:
            category = text_cat; confidence = 0.3

        base = confidence * 60; bonus = 0
        for n, v in metrics.items():
            if n in CRITICAL:
                if v >= CRITICAL[n]: bonus = max(bonus, 40)
                elif v >= CRITICAL[n]*0.8: bonus = max(bonus, 20)
        ew = {"production":1.0,"staging":0.7,"development":0.4}.get(env, 0.5)
        score = min(100, (base + bonus) * ew)
        for n, v in metrics.items():
            if n in CRITICAL and v >= CRITICAL[n]: score = max(score, 80)

        if score >= 80: priority = "P1"
        elif score >= 60: priority = "P2"
        elif score >= 40: priority = "P3"
        else: priority = "P4"

        result = {
            "category": category,
            "confidence": round(confidence, 3),
            "score": round(score, 1),
            "priority": priority,
        }
        self.predictions.append(result)
        return result

    def record_feedback(self, predicted, actual):
        """Record DBA feedback."""
        correct = predicted == actual
        self.total_predictions += 1
        if correct:
            self.total_correct += 1

        if actual not in self.accuracy_by_category:
            self.accuracy_by_category[actual] = {"correct": 0, "total": 0}
        self.accuracy_by_category[actual]["total"] += 1
        if correct:
            self.accuracy_by_category[actual]["correct"] += 1

        self.feedback.append({"predicted": predicted, "actual": actual, "correct": correct})

    def get_report(self):
        """Get system health report."""
        overall_acc = self.total_correct / max(1, self.total_predictions)
        cat_acc = {}
        for cat, data in self.accuracy_by_category.items():
            cat_acc[cat] = data["correct"] / max(1, data["total"])
        return {
            "total_predictions": self.total_predictions,
            "overall_accuracy": round(overall_acc, 3),
            "category_accuracy": cat_acc,
            "feedback_count": len(self.feedback),
        }


# ---- Run Complete System Test ----

system = CompleteSystem()

# Test suite: alerts with known correct categories
test_suite = [
    # (text, metrics, env, expected_category, expected_priority_range)
    ("High CPU on pg-primary, queries timing out", {"cpu_percent": 96}, "production", "performance", ["P1"]),
    ("Disk full on /pgdata, tablespace running out of space", {"disk_percent": 97}, "production", "storage", ["P1"]),
    ("Replication lag on standby pg-standby-1", {"replication_lag_seconds": 400}, "production", "replication", ["P1"]),
    ("Connection pool exhausted, max_connections reached", {"connections": 470}, "production", "connectivity", ["P1"]),
    ("Permission denied for login attempt, auth failed", {"connections": 20}, "production", "security", ["P3", "P4"]),
    ("Backup archive failed, WAL archive not working", {}, "production", "backup", ["P3", "P4"]),
    ("Slow queries on dev database", {"cpu_percent": 80}, "development", "performance", ["P3", "P4"]),
    ("Disk space warning on staging", {"disk_percent": 85}, "staging", "storage", ["P2", "P3"]),
]

print("\nRunning System Test Suite:")
print("-" * 55)

all_passed = True
for text, metrics, env, expected_cat, expected_pri in test_suite:
    result = system.classify(text, metrics, env)

    # Record feedback (using expected as ground truth)
    system.record_feedback(result["category"], expected_cat)

    # Check results
    cat_ok = result["category"] == expected_cat
    pri_ok = result["priority"] in expected_pri

    status = "PASS" if (cat_ok and pri_ok) else "FAIL"
    if status == "FAIL":
        all_passed = False

    print(f"\n  [{status}] {text[:50]}...")
    print(f"    Expected: {expected_cat} {expected_pri}")
    print(f"    Got:      {result['category']} {result['priority']} (conf: {result['confidence']})")

# System report
print(f"\n{'=' * 55}")
print("System Health Report")
print(f"{'=' * 55}")
report = system.get_report()

print(f"\n  Overall Accuracy: {report['overall_accuracy']:.1%}")
print(f"  Total Predictions: {report['total_predictions']}")
print(f"  Feedback Collected: {report['feedback_count']}")

print(f"\n  Per-Category Accuracy:")
for cat, acc in sorted(report['category_accuracy'].items()):
    flag = " OK" if acc >= 0.80 else " <-- NEEDS WORK"
    print(f"    {cat:<15s} {acc:.0%}{flag}")

# Final verdict
print(f"\n  {'=' * 40}")
if all_passed:
    print(f"  SYSTEM TEST: ALL PASSED")
    print(f"  The system is ready for production.")
else:
    print(f"  SYSTEM TEST: SOME FAILURES")
    print(f"  Fix failing tests before deploying.")

print("""
Complete system test validates:
  1. Classification accuracy (right category?)
  2. Priority assignment (right urgency?)
  3. Metric floor safety (critical metrics force P1?)
  4. Environment weighting (dev alerts are low priority?)
  5. Feedback collection (learning loop works?)
  6. Health reporting (can we monitor accuracy?)

This is your go/no-go checklist before shipping.
All tests must pass before the product goes live.
""")
PYEOF
```

---

## What You Learned

| Exercise | What You Built | Modules Used |
|----------|---------------|-------------|
| End-to-end processor | Complete alert pipeline | 5-10, 15-17 |
| Accuracy tracker | Per-category accuracy monitoring | 14, 17 |
| DBA feedback system | Learning loop from corrections | 17 |
| Production monitoring | Health and performance dashboard | 13, 14, 17 |
| Complete system test | Full integration validation | All modules |
