# Build 01: Database Alert Classifier

Build a production-grade alert classifier for PostgreSQL alerts. This combines text classification (Modules 5-8) with metrics (Module 16) into one specialized database tool.

---

## Step 1. PostgreSQL alert taxonomy

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# POSTGRESQL ALERT TAXONOMY
# Define the categories, keywords, and metrics for each
# type of database alert. This is the knowledge base.
#
# DBA analogy: this is your mental model of alert types,
# written as code. When you see "disk full" you instantly
# think "storage." We're teaching the AI that mapping.
# ============================================================

print("PostgreSQL Alert Taxonomy")
print("=" * 50)

# Each category has:
#   keywords: words in alert text that signal this category
#   metrics: which metrics matter and their thresholds
#   severity_rules: how to determine severity for this category

ALERT_TAXONOMY = {
    "performance": {
        "description": "CPU, memory, slow queries, locks",
        "keywords": [
            "cpu", "slow", "latency", "query", "lock", "wait",
            "idle in transaction", "long running", "blocked",
            "vacuum", "analyze", "autovacuum", "bloat",
        ],
        "metrics": {
            "cpu_percent": {"warning": 80, "critical": 95},
            "memory_percent": {"warning": 85, "critical": 95},
            "active_connections": {"warning": 200, "critical": 400},
            "longest_query_seconds": {"warning": 300, "critical": 3600},
        },
        "common_causes": [
            "Long-running query (check pg_stat_activity)",
            "Missing index (check seq_scan count in pg_stat_user_tables)",
            "Autovacuum running on large table",
            "Lock contention (check pg_locks)",
        ],
    },
    "storage": {
        "description": "Disk space, WAL, tablespace, bloat",
        "keywords": [
            "disk", "space", "full", "tablespace", "wal",
            "archive", "pg_xlog", "pg_wal", "bloat", "toast",
            "filesystem", "mount", "partition",
        ],
        "metrics": {
            "disk_percent": {"warning": 80, "critical": 95},
            "wal_size_gb": {"warning": 10, "critical": 50},
            "table_bloat_percent": {"warning": 30, "critical": 60},
        },
        "common_causes": [
            "WAL archiving failed (check archive_command status)",
            "Table bloat from UPDATE-heavy workload (need VACUUM FULL)",
            "Unmanaged temp files from large sorts",
            "Backup files not cleaned up",
        ],
    },
    "replication": {
        "description": "Standby lag, WAL shipping, failover",
        "keywords": [
            "replication", "lag", "standby", "replica", "failover",
            "wal receiver", "wal sender", "streaming", "catchup",
            "timeline", "promote", "pg_basebackup",
        ],
        "metrics": {
            "replication_lag_seconds": {"warning": 30, "critical": 300},
            "replication_lag_bytes": {"warning": 100_000_000, "critical": 1_000_000_000},
            "standby_count": {"warning_below": 1},  # below = bad
        },
        "common_causes": [
            "Network issue between primary and standby",
            "Standby can't keep up (undersized hardware)",
            "WAL sender slot not advancing (check pg_replication_slots)",
            "Large transaction on primary causing WAL burst",
        ],
    },
    "security": {
        "description": "Authentication, SSL, permissions",
        "keywords": [
            "login", "password", "authentication", "ssl", "tls",
            "permission", "denied", "unauthorized", "role",
            "pg_hba", "certificate", "expired", "brute force",
        ],
        "metrics": {
            "failed_auth_count": {"warning": 10, "critical": 50},
            "ssl_cert_days_remaining": {"warning_below": 30, "critical_below": 7},
        },
        "common_causes": [
            "Expired password",
            "pg_hba.conf misconfigured after change",
            "SSL certificate expired",
            "Brute force login attempt",
        ],
    },
    "connectivity": {
        "description": "Connection limits, pooling, network",
        "keywords": [
            "connection", "timeout", "refused", "pool", "pgbouncer",
            "max_connections", "too many", "remaining", "slot",
            "socket", "listen", "port",
        ],
        "metrics": {
            "connection_count": {"warning": 400, "critical": 480},
            "connection_percent": {"warning": 80, "critical": 95},
            "idle_connections": {"warning": 200, "critical": 350},
        },
        "common_causes": [
            "Connection leak in application (connections not returned to pool)",
            "PgBouncer misconfigured (pool_size too low)",
            "max_connections reached (check pg_stat_activity)",
            "DNS resolution failure",
        ],
    },
    "backup": {
        "description": "Backup failures, PITR, recovery",
        "keywords": [
            "backup", "restore", "pitr", "basebackup", "pg_dump",
            "pg_restore", "wal-g", "pgbackrest", "barman",
            "recovery", "checkpoint", "archive",
        ],
        "metrics": {
            "hours_since_last_backup": {"warning": 25, "critical": 49},
            "backup_size_change_percent": {"warning": 50, "critical": 200},
        },
        "common_causes": [
            "Backup script failed (check cron job)",
            "Disk full on backup server",
            "WAL archiving broken (PITR gap)",
            "pg_dump killed by OOM",
        ],
    },
}

# Display the taxonomy
for category, info in ALERT_TAXONOMY.items():
    keyword_count = len(info["keywords"])
    metric_count = len(info["metrics"])
    cause_count = len(info["common_causes"])
    print(f"\n  {category.upper()}: {info['description']}")
    print(f"    {keyword_count} keywords | {metric_count} metrics | {cause_count} known causes")
    print(f"    Sample keywords: {info['keywords'][:4]}")

total_keywords = sum(len(info["keywords"]) for info in ALERT_TAXONOMY.values())
total_metrics = sum(len(info["metrics"]) for info in ALERT_TAXONOMY.values())
print(f"\nTotal: {len(ALERT_TAXONOMY)} categories, {total_keywords} keywords, {total_metrics} metrics")
PYEOF
```

---

## Step 2. Multi-modal database classifier

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

# ============================================================
# DATABASE ALERT CLASSIFIER
# Combines text classification + metric analysis
# specifically tuned for PostgreSQL alerts.
#
# This is dbaBrain's classification engine.
# ============================================================

print("Database Alert Classifier")
print("=" * 50)

class DatabaseAlertClassifier:
    """
    Classify PostgreSQL alerts using text + metrics.

    This combines everything from Modules 5-16:
    - Text keyword matching (Module 5)
    - Multi-modal fusion (Module 16)
    - Confidence scoring (Module 10)
    - Missing data handling (Module 16)

    DBA analogy: this is your brain when triaging alerts.
    You read the message, glance at the metrics, and instantly
    know the category. We're encoding that process.
    """

    def __init__(self):
        # Category keywords (from taxonomy above)
        self.category_keywords = {
            "performance": [
                "cpu", "slow", "latency", "query", "lock", "wait",
                "idle in transaction", "long running", "vacuum", "bloat",
            ],
            "storage": [
                "disk", "space", "full", "tablespace", "wal",
                "archive", "pg_wal", "filesystem",
            ],
            "replication": [
                "replication", "lag", "standby", "replica", "failover",
                "wal receiver", "wal sender", "streaming",
            ],
            "security": [
                "login", "password", "authentication", "ssl",
                "permission", "denied", "unauthorized", "pg_hba",
            ],
            "connectivity": [
                "connection", "timeout", "refused", "pool",
                "pgbouncer", "max_connections", "too many",
            ],
            "backup": [
                "backup", "restore", "pitr", "basebackup",
                "pg_dump", "wal-g", "pgbackrest", "barman",
            ],
        }

        # Metric thresholds per category
        self.metric_rules = {
            "performance": [
                ("cpu_percent", 80, 1.0),
                ("memory_percent", 85, 0.8),
                ("active_connections", 200, 0.6),
                ("longest_query_seconds", 300, 0.7),
            ],
            "storage": [
                ("disk_percent", 80, 1.0),
                ("wal_size_gb", 10, 0.8),
            ],
            "replication": [
                ("replication_lag_seconds", 30, 1.0),
                ("replication_lag_bytes", 100_000_000, 0.8),
            ],
            "connectivity": [
                ("connection_count", 400, 1.0),
                ("connection_percent", 80, 0.9),
                ("idle_connections", 200, 0.6),
            ],
            "security": [
                ("failed_auth_count", 10, 1.0),
            ],
            "backup": [
                ("hours_since_last_backup", 25, 1.0),
            ],
        }

    def _classify_text(self, text):
        """Score each category based on keyword matches."""
        text_lower = text.lower()
        scores = {}

        for category, keywords in self.category_keywords.items():
            # Count keyword matches
            matches = 0
            matched_keywords = []
            for kw in keywords:
                if kw in text_lower:
                    matches += 1
                    matched_keywords.append(kw)

            if matches > 0:
                # Score: more matches = higher confidence
                confidence = min(0.5 + matches * 0.12, 0.85)
                scores[category] = {
                    "confidence": round(confidence, 3),
                    "keywords": matched_keywords,
                }

        return scores

    def _classify_metrics(self, metrics):
        """Score each category based on metric thresholds."""
        if not metrics:
            return {}

        scores = {}
        for category, rules in self.metric_rules.items():
            triggered = []
            for metric_name, threshold, weight in rules:
                value = metrics.get(metric_name)
                if value is not None and value >= threshold:
                    # How far over the threshold? Higher = more severe
                    overshoot = (value - threshold) / threshold
                    severity = min(overshoot, 1.0)
                    triggered.append({
                        "metric": metric_name,
                        "value": value,
                        "threshold": threshold,
                        "severity": round(severity, 3),
                    })

            if triggered:
                # Average severity of all triggered metrics
                avg_severity = sum(t["severity"] for t in triggered) / len(triggered)
                confidence = min(0.5 + avg_severity * 0.35, 0.9)
                scores[category] = {
                    "confidence": round(confidence, 3),
                    "triggered_metrics": triggered,
                }

        return scores

    def classify(self, text, metrics=None):
        """
        Classify a database alert.
        Returns category, confidence, and explanation.
        """
        text_scores = self._classify_text(text)
        metric_scores = self._classify_metrics(metrics or {})

        # Combine scores (late fusion)
        all_categories = set(list(text_scores.keys()) + list(metric_scores.keys()))

        combined = {}
        for cat in all_categories:
            text_conf = text_scores.get(cat, {}).get("confidence", 0)
            metric_conf = metric_scores.get(cat, {}).get("confidence", 0)

            if text_conf > 0 and metric_conf > 0:
                # Both agree - boost
                combined_conf = (text_conf * 0.5 + metric_conf * 0.5) + 0.08
            elif text_conf > 0:
                combined_conf = text_conf * 0.85     # text only - slight penalty
            else:
                combined_conf = metric_conf * 0.85   # metrics only - slight penalty

            combined[cat] = min(round(combined_conf, 3), 0.95)

        if not combined:
            return {
                "category": "unknown",
                "confidence": 0.1,
                "text_evidence": [],
                "metric_evidence": [],
                "explanation": "No matching patterns found",
            }

        # Best category
        best_cat = max(combined, key=combined.get)

        # Build explanation
        text_evidence = text_scores.get(best_cat, {}).get("keywords", [])
        metric_evidence = metric_scores.get(best_cat, {}).get("triggered_metrics", [])

        explanation_parts = []
        if text_evidence:
            explanation_parts.append(f"Text keywords: {', '.join(text_evidence)}")
        if metric_evidence:
            for m in metric_evidence:
                explanation_parts.append(
                    f"{m['metric']}={m['value']} (threshold={m['threshold']})"
                )

        return {
            "category": best_cat,
            "confidence": combined[best_cat],
            "text_evidence": text_evidence,
            "metric_evidence": metric_evidence,
            "explanation": "; ".join(explanation_parts) if explanation_parts else "Low confidence",
            "all_scores": combined,
        }


# Test the classifier
classifier = DatabaseAlertClassifier()

test_alerts = [
    {
        "text": "CPU at 95% on pg-primary-prod-3, long running query PID 12345",
        "metrics": {"cpu_percent": 95, "longest_query_seconds": 7200},
    },
    {
        "text": "Disk space at 92% on /pgdata partition",
        "metrics": {"disk_percent": 92},
    },
    {
        "text": "Replication lag 300 seconds on standby pg-standby-2",
        "metrics": {"replication_lag_seconds": 300},
    },
    {
        "text": "Too many connections: 485 of 500 max",
        "metrics": {"connection_count": 485, "connection_percent": 97},
    },
    {
        "text": "Authentication failure for user app_reader from 10.0.0.55",
        "metrics": {"failed_auth_count": 25},
    },
    {
        "text": "pg_basebackup hasn't completed in 48 hours",
        "metrics": {"hours_since_last_backup": 48},
    },
    {
        "text": "Something seems wrong with the database",
        "metrics": {"cpu_percent": 40, "disk_percent": 30},
    },
]

print("\nClassification Results:")
print("-" * 70)

for alert in test_alerts:
    result = classifier.classify(alert["text"], alert.get("metrics"))

    print(f"\n  Alert: '{alert['text'][:55]}...'")
    print(f"  Result: {result['category']} ({result['confidence']:.0%})")
    print(f"  Evidence: {result['explanation'][:65]}")

print("""
What this classifier does:
  1. Reads alert text and finds category keywords
  2. Checks metric values against thresholds
  3. Fuses both sources (agreement = boost, single source = penalty)
  4. Returns category + confidence + evidence

What it builds on:
  Module 5: Text preprocessing (lowercase, keyword matching)
  Module 8: Feature extraction (keyword features)
  Module 10: Confidence scoring
  Module 16: Multi-modal fusion
""")
PYEOF
```

---

## Step 3. Severity scoring

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime

# ============================================================
# SEVERITY SCORING
# Not just WHAT the alert is, but HOW URGENT it is.
#
# A disk at 82% is a warning. A disk at 99% with active writes
# is a P1 emergency. The classifier tells you the category,
# the severity scorer tells you how fast to run.
#
# DBA analogy: the difference between "check this tomorrow"
# and "wake up the on-call RIGHT NOW."
# ============================================================

print("Severity Scoring for Database Alerts")
print("=" * 55)

class SeverityScorer:
    """
    Score alert severity from 0-100 and assign priority P1-P4.

    Factors considered:
    1. Metric value vs threshold (how far over?)
    2. Rate of change (getting worse?)
    3. Impact scope (production vs dev? how many databases?)
    4. Time context (3 AM production vs business hours dev)

    DBA analogy: you instinctively know that "disk 99% on prod at 3 AM"
    is P1 and "disk 82% on dev at 2 PM" is P4. We encode that logic.
    """

    def __init__(self):
        # Severity thresholds per metric
        self.metric_severity = {
            "cpu_percent":              {"low": 70, "medium": 85, "high": 95, "critical": 99},
            "memory_percent":           {"low": 75, "medium": 85, "high": 95, "critical": 98},
            "disk_percent":             {"low": 75, "medium": 85, "high": 95, "critical": 99},
            "replication_lag_seconds":   {"low": 10, "medium": 60, "high": 300, "critical": 900},
            "connection_percent":       {"low": 60, "medium": 80, "high": 95, "critical": 99},
            "hours_since_last_backup":  {"low": 12, "medium": 25, "high": 49, "critical": 72},
            "failed_auth_count":        {"low": 5, "medium": 15, "high": 30, "critical": 100},
            "longest_query_seconds":    {"low": 60, "medium": 300, "high": 3600, "critical": 7200},
        }

        # Environment multipliers
        self.env_multiplier = {
            "production": 1.5,
            "staging": 1.0,
            "development": 0.5,
        }

        # Time-of-day multiplier (off-hours are more serious because fewer people)
        # and also less serious because fewer users affected - context dependent

    def _metric_score(self, metric_name, value):
        """Score a single metric from 0-100."""
        thresholds = self.metric_severity.get(metric_name)
        if not thresholds or value is None:
            return 0

        if value >= thresholds["critical"]:
            return 90 + min((value - thresholds["critical"]) / 10, 10)  # 90-100
        elif value >= thresholds["high"]:
            return 70 + (value - thresholds["high"]) / (thresholds["critical"] - thresholds["high"]) * 20
        elif value >= thresholds["medium"]:
            return 40 + (value - thresholds["medium"]) / (thresholds["high"] - thresholds["medium"]) * 30
        elif value >= thresholds["low"]:
            return 10 + (value - thresholds["low"]) / (thresholds["medium"] - thresholds["low"]) * 30
        else:
            return 0

    def score(self, metrics, environment="production", category=None):
        """
        Calculate overall severity score (0-100) and priority.

        Returns dict with score, priority, and breakdown.
        """
        # Score each metric
        metric_scores = {}
        for name, value in metrics.items():
            s = self._metric_score(name, value)
            if s > 0:
                metric_scores[name] = round(s, 1)

        if not metric_scores:
            return {"score": 0, "priority": "P4", "breakdown": {}}

        # Overall score = highest metric score (worst symptom drives urgency)
        base_score = max(metric_scores.values())

        # Environment multiplier
        env_mult = self.env_multiplier.get(environment, 1.0)
        adjusted_score = min(base_score * env_mult, 100)

        # Assign priority
        if adjusted_score >= 80:
            priority = "P1"    # page immediately
        elif adjusted_score >= 60:
            priority = "P2"    # respond within 30 minutes
        elif adjusted_score >= 30:
            priority = "P3"    # respond within 4 hours
        else:
            priority = "P4"    # check next business day

        return {
            "score": round(adjusted_score, 1),
            "priority": priority,
            "environment": environment,
            "breakdown": metric_scores,
        }


# Test severity scoring
scorer = SeverityScorer()

test_cases = [
    # (description, metrics, environment)
    ("Disk 99% on production", {"disk_percent": 99}, "production"),
    ("Disk 82% on dev", {"disk_percent": 82}, "development"),
    ("CPU 96% + replication lag 500s on prod",
     {"cpu_percent": 96, "replication_lag_seconds": 500}, "production"),
    ("48 hours since last backup on prod",
     {"hours_since_last_backup": 48}, "production"),
    ("Connection pool at 97% on staging",
     {"connection_percent": 97}, "staging"),
    ("CPU 50% on prod (normal)",
     {"cpu_percent": 50}, "production"),
]

print("\nSeverity Scoring Results:")
print("-" * 70)
print(f"{'Description':<45s} {'Score':>6s} {'Priority':>8s} {'Env':>12s}")
print("-" * 70)

for desc, metrics, env in test_cases:
    result = scorer.score(metrics, environment=env)
    print(f"{desc:<45s} {result['score']:>5.0f} {result['priority']:>8s} {env:>12s}")

print("""
Priority Guide:
  P1 (score >= 80): Page immediately. Data at risk.
  P2 (score >= 60): Respond in 30 min. Service degraded.
  P3 (score >= 30): Respond in 4 hours. Early warning.
  P4 (score < 30):  Next business day. Informational.

Environment matters:
  Production disk at 99% = P1 (score 100)
  Development disk at 82% = P4 (score ~20)
  Same metric, very different urgency.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Alert taxonomy | Define categories + keywords + metrics | Your mental model of alert types |
| Multi-modal classifier | Text + metrics = better classification | Reading logs + checking Grafana |
| Evidence tracking | Show WHY it classified that way | "Here's what I checked" |
| Severity scoring | How urgent is this? 0-100 | P1 vs P4 triage |
| Environment weighting | Prod > staging > dev | Production gets priority |
| Priority assignment | P1-P4 based on score | SLA response times |
