# Build 03: Testing Strategy

Test every layer of your AI product before shipping.

---

## Step 1. Unit tests

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# UNIT TESTS
# Test each component in isolation.
#
# DBA analogy: like testing a single function or trigger
# before deploying it to production. Does pg_is_in_recovery()
# return True on a standby? Test it alone first.
# ============================================================

print("Unit Tests: Test Each Component Alone")
print("=" * 55)

# ---- Component 1: Feature Extractor ----

class FeatureExtractor:
    """Extract features from alert text and metrics."""

    KEYWORDS = {
        "performance": ["slow", "latency", "timeout", "cpu", "load"],
        "storage": ["disk", "space", "full", "tablespace", "storage"],
        "replication": ["replica", "lag", "standby", "wal", "replication"],
        "connectivity": ["connection", "refused", "timeout", "pool", "max_connections"],
        "security": ["permission", "denied", "login", "auth", "unauthorized"],
        "backup": ["backup", "wal", "archive", "pitr", "restore"],
    }

    def extract_text_features(self, text):
        """
        Count how many keywords from each category appear in the text.

        Returns a dictionary like:
          {"performance": 2, "storage": 0, "replication": 1, ...}

        DBA analogy: like counting how many times each wait event
        appears in pg_stat_activity. The counts tell you what's happening.
        """
        # lower() converts to lowercase so "SLOW" matches "slow"
        text_lower = text.lower()

        features = {}
        for category, keywords in self.KEYWORDS.items():
            # sum() adds up True values (True = 1, False = 0)
            # so this counts how many keywords appear in the text
            count = sum(1 for kw in keywords if kw in text_lower)
            features[category] = count

        return features

    def extract_metric_features(self, metrics):
        """
        Normalize metric values to 0-1 range.

        Why normalize? Because CPU (0-100) and disk (0-100%) and
        connections (0-500) are on different scales. Normalizing puts
        them all on 0-1 so we can compare them fairly.

        DBA analogy: like converting all sizes to bytes before comparing.
        You wouldn't compare 5 GB to 5000 MB without normalizing first.
        """
        # These are the expected ranges for each metric
        ranges = {
            "cpu_percent": (0, 100),
            "disk_percent": (0, 100),
            "connections": (0, 500),
            "replication_lag_seconds": (0, 3600),
            "query_time_seconds": (0, 300),
        }

        normalized = {}
        for metric_name, value in metrics.items():
            if metric_name in ranges:
                min_val, max_val = ranges[metric_name]
                # min-max normalization: (value - min) / (max - min)
                # clip to 0-1 range in case value exceeds expected range
                normalized[metric_name] = max(0.0, min(1.0,
                    (value - min_val) / (max_val - min_val)
                ))

        return normalized


# ---- Unit Tests for FeatureExtractor ----

def test_text_features():
    """Test that keyword counting works correctly."""
    extractor = FeatureExtractor()

    # Test 1: clear performance alert
    features = extractor.extract_text_features(
        "Database is slow, high CPU load causing timeouts"
    )
    # "slow", "cpu", "load" are performance keywords = 3 matches
    assert features["performance"] == 3, \
        f"Expected 3 performance keywords, got {features['performance']}"
    # no storage keywords in this text
    assert features["storage"] == 0, \
        f"Expected 0 storage keywords, got {features['storage']}"
    print("  PASS: text_features - performance keywords counted correctly")

    # Test 2: mixed alert (two categories)
    features = extractor.extract_text_features(
        "Disk full causing slow queries on replica"
    )
    assert features["storage"] >= 1, "Should find storage keywords"
    assert features["performance"] >= 1, "Should find performance keywords"
    assert features["replication"] >= 1, "Should find replication keywords"
    print("  PASS: text_features - mixed category keywords detected")

    # Test 3: empty text
    features = extractor.extract_text_features("")
    assert all(v == 0 for v in features.values()), \
        "Empty text should have zero keywords"
    print("  PASS: text_features - empty text returns all zeros")

    # Test 4: case insensitive
    features = extractor.extract_text_features("SLOW CPU TIMEOUT")
    assert features["performance"] >= 2, \
        "Should match uppercase keywords"
    print("  PASS: text_features - case insensitive matching works")


def test_metric_features():
    """Test that metric normalization works correctly."""
    extractor = FeatureExtractor()

    # Test 1: normal values
    normalized = extractor.extract_metric_features({
        "cpu_percent": 50,
        "disk_percent": 80,
    })
    assert normalized["cpu_percent"] == 0.5, \
        f"CPU 50% should normalize to 0.5, got {normalized['cpu_percent']}"
    assert normalized["disk_percent"] == 0.8, \
        f"Disk 80% should normalize to 0.8, got {normalized['disk_percent']}"
    print("  PASS: metric_features - normal values normalized correctly")

    # Test 2: edge values (0 and max)
    normalized = extractor.extract_metric_features({
        "cpu_percent": 0,
        "disk_percent": 100,
    })
    assert normalized["cpu_percent"] == 0.0, "CPU 0% should be 0.0"
    assert normalized["disk_percent"] == 1.0, "Disk 100% should be 1.0"
    print("  PASS: metric_features - edge values (0 and max) handled")

    # Test 3: values exceeding range (clipped to 1.0)
    normalized = extractor.extract_metric_features({
        "cpu_percent": 150,  # impossible but test the clipping
    })
    assert normalized["cpu_percent"] == 1.0, \
        "Values above max should be clipped to 1.0"
    print("  PASS: metric_features - out-of-range values clipped")

    # Test 4: unknown metrics ignored
    normalized = extractor.extract_metric_features({
        "cpu_percent": 50,
        "unknown_metric": 999,
    })
    assert "unknown_metric" not in normalized, \
        "Unknown metrics should not appear in output"
    print("  PASS: metric_features - unknown metrics ignored")


# Run all unit tests
print("\nFeatureExtractor Tests:")
print("-" * 40)
test_text_features()
test_metric_features()

print("\nAll unit tests passed!")

print("""
Why unit tests matter:
  - Catch bugs BEFORE they reach production
  - Each test checks ONE thing (single responsibility)
  - Tests run fast (milliseconds) so you run them often
  - When something breaks later, tests tell you exactly what

DBA analogy: like running pg_verifybackup after every backup.
You don't wait until restore time to find out the backup is bad.
""")
PYEOF
```

---

## Step 2. Integration tests

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# INTEGRATION TESTS
# Test components working together.
#
# DBA analogy: like testing streaming replication end-to-end.
# The primary works alone (unit test). The standby works alone.
# But do they replicate correctly together? That's integration.
# ============================================================

print("Integration Tests: Test the Full Pipeline")
print("=" * 55)

# ---- Simplified pipeline components ----

class FeatureExtractor:
    KEYWORDS = {
        "performance": ["slow", "latency", "timeout", "cpu", "load"],
        "storage": ["disk", "space", "full", "tablespace"],
        "replication": ["replica", "lag", "standby", "wal", "replication"],
        "connectivity": ["connection", "refused", "pool", "max_connections"],
        "security": ["permission", "denied", "login", "auth"],
        "backup": ["backup", "archive", "pitr", "restore"],
    }

    def extract(self, text, metrics):
        text_lower = text.lower()
        text_features = {}
        for cat, kws in self.KEYWORDS.items():
            text_features[cat] = sum(1 for kw in kws if kw in text_lower)

        metric_features = {}
        ranges = {
            "cpu_percent": (0, 100), "disk_percent": (0, 100),
            "connections": (0, 500), "replication_lag_seconds": (0, 3600),
        }
        for name, value in metrics.items():
            if name in ranges:
                lo, hi = ranges[name]
                metric_features[name] = max(0.0, min(1.0, (value - lo) / (hi - lo)))

        return text_features, metric_features


class AlertClassifier:
    METRIC_CATEGORIES = {
        "cpu_percent": "performance",
        "disk_percent": "storage",
        "connections": "connectivity",
        "replication_lag_seconds": "replication",
    }

    def classify(self, text_features, metric_features):
        # Text vote: category with most keyword matches
        text_category = max(text_features, key=text_features.get)
        text_score = text_features[text_category]

        # Metric vote: highest normalized metric mapped to category
        metric_category = None
        metric_score = 0
        for metric_name, value in metric_features.items():
            if value > metric_score and metric_name in self.METRIC_CATEGORIES:
                metric_score = value
                metric_category = self.METRIC_CATEGORIES[metric_name]

        # Late fusion: combine votes
        if text_category == metric_category:
            confidence = min(1.0, (text_score * 0.3 + metric_score * 0.7) + 0.1)
            return text_category, confidence
        elif metric_score > 0.8:
            # High metric value overrides text
            return metric_category, metric_score * 0.8
        elif text_score >= 2:
            # Strong text signal
            return text_category, min(1.0, text_score * 0.25)
        else:
            return text_category, 0.3  # low confidence


class SeverityScorer:
    CRITICAL_THRESHOLDS = {
        "cpu_percent": 95,
        "disk_percent": 95,
        "connections": 450,
        "replication_lag_seconds": 300,
    }

    def score(self, category, confidence, metrics, environment="production"):
        # Base score from confidence
        base = confidence * 60

        # Metric severity bonus
        metric_bonus = 0
        for metric_name, value in metrics.items():
            if metric_name in self.CRITICAL_THRESHOLDS:
                threshold = self.CRITICAL_THRESHOLDS[metric_name]
                if value >= threshold:
                    metric_bonus = max(metric_bonus, 40)
                elif value >= threshold * 0.8:
                    metric_bonus = max(metric_bonus, 20)

        # Environment weight
        env_weights = {"production": 1.0, "staging": 0.7, "development": 0.4}
        env_weight = env_weights.get(environment, 0.5)

        # Total score (0-100)
        score = min(100, (base + metric_bonus) * env_weight)

        # Metric floor: critical metrics force minimum score of 80
        for metric_name, value in metrics.items():
            if metric_name in self.CRITICAL_THRESHOLDS:
                if value >= self.CRITICAL_THRESHOLDS[metric_name]:
                    score = max(score, 80)

        # Assign priority
        if score >= 80:
            priority = "P1"
        elif score >= 60:
            priority = "P2"
        elif score >= 40:
            priority = "P3"
        else:
            priority = "P4"

        return {"score": round(score, 1), "priority": priority}


# ---- The Full Pipeline ----

class AlertPipeline:
    """
    Complete alert processing pipeline.
    Connects: FeatureExtractor -> AlertClassifier -> SeverityScorer

    DBA analogy: like a streaming replication pipeline.
    WAL writer -> WAL sender -> WAL receiver -> recovery.
    Each stage feeds the next. If one breaks, everything stops.
    """

    def __init__(self):
        self.extractor = FeatureExtractor()
        self.classifier = AlertClassifier()
        self.scorer = SeverityScorer()

    def process(self, alert_text, metrics, environment="production"):
        # Stage 1: Extract features
        text_features, metric_features = self.extractor.extract(
            alert_text, metrics
        )

        # Stage 2: Classify
        category, confidence = self.classifier.classify(
            text_features, metric_features
        )

        # Stage 3: Score severity
        severity = self.scorer.score(
            category, confidence, metrics, environment
        )

        return {
            "category": category,
            "confidence": round(confidence, 3),
            "severity_score": severity["score"],
            "priority": severity["priority"],
            "environment": environment,
        }


# ---- Integration Tests ----

pipeline = AlertPipeline()

def test_critical_performance_alert():
    """Test: high CPU alert in production should be P1."""
    result = pipeline.process(
        alert_text="Database extremely slow, queries timing out, CPU at critical levels",
        metrics={"cpu_percent": 98, "connections": 200},
        environment="production",
    )
    assert result["category"] == "performance", \
        f"Expected performance, got {result['category']}"
    assert result["priority"] == "P1", \
        f"Expected P1, got {result['priority']}"
    print(f"  PASS: critical performance alert -> {result['category']} {result['priority']}")


def test_storage_warning():
    """Test: disk filling up but not critical."""
    result = pipeline.process(
        alert_text="Disk space warning on tablespace pg_default",
        metrics={"disk_percent": 82, "cpu_percent": 30},
        environment="production",
    )
    assert result["category"] == "storage", \
        f"Expected storage, got {result['category']}"
    assert result["priority"] in ("P2", "P3"), \
        f"Expected P2 or P3, got {result['priority']}"
    print(f"  PASS: storage warning -> {result['category']} {result['priority']}")


def test_critical_disk_full():
    """Test: disk at 99% must be P1 regardless of text."""
    result = pipeline.process(
        alert_text="Routine disk check completed",  # misleading text
        metrics={"disk_percent": 99},
        environment="production",
    )
    # Metric floor should force P1 even with misleading text
    assert result["priority"] == "P1", \
        f"Expected P1 (metric floor), got {result['priority']}"
    print(f"  PASS: metric floor - disk 99% forces P1 even with misleading text")


def test_staging_downgrade():
    """Test: same alert in staging should be lower priority."""
    prod_result = pipeline.process(
        alert_text="High CPU load on database server",
        metrics={"cpu_percent": 85},
        environment="production",
    )
    staging_result = pipeline.process(
        alert_text="High CPU load on database server",
        metrics={"cpu_percent": 85},
        environment="staging",
    )
    assert staging_result["severity_score"] <= prod_result["severity_score"], \
        "Staging should score lower than production"
    print(f"  PASS: staging ({staging_result['priority']}) scores lower than prod ({prod_result['priority']})")


def test_replication_lag():
    """Test: replication lag alert classified correctly."""
    result = pipeline.process(
        alert_text="Replica lag increasing on standby pg-standby-2",
        metrics={"replication_lag_seconds": 120},
        environment="production",
    )
    assert result["category"] == "replication", \
        f"Expected replication, got {result['category']}"
    print(f"  PASS: replication lag -> {result['category']} {result['priority']}")


def test_missing_metrics():
    """Test: pipeline works even with no metrics."""
    result = pipeline.process(
        alert_text="Connection refused to database pg-primary",
        metrics={},
        environment="production",
    )
    assert result["category"] is not None, "Should still classify with text only"
    assert result["priority"] is not None, "Should still assign priority"
    print(f"  PASS: text-only (no metrics) -> {result['category']} {result['priority']}")


# Run all integration tests
print("\nPipeline Integration Tests:")
print("-" * 40)
test_critical_performance_alert()
test_storage_warning()
test_critical_disk_full()
test_staging_downgrade()
test_replication_lag()
test_missing_metrics()

print("\nAll integration tests passed!")

print("""
Integration tests vs unit tests:
  Unit test:  Does the FeatureExtractor count keywords correctly? (alone)
  Integration: Does the full pipeline classify a real alert correctly? (together)

Both are needed. Unit tests find WHERE bugs are.
Integration tests find IF bugs exist in the connections between components.
""")
PYEOF
```

---

## Step 3. Behavioral tests

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# BEHAVIORAL TESTS
# Test specific scenarios that matter to your users.
#
# DBA analogy: like runbook validation.
# "When the primary fails, does the standby promote correctly?"
# You don't just test the promote command. You test the SCENARIO.
# ============================================================

print("Behavioral Tests: Real-World Scenarios")
print("=" * 55)

# Reuse the pipeline from Step 2
class FeatureExtractor:
    KEYWORDS = {
        "performance": ["slow", "latency", "timeout", "cpu", "load"],
        "storage": ["disk", "space", "full", "tablespace"],
        "replication": ["replica", "lag", "standby", "wal", "replication"],
        "connectivity": ["connection", "refused", "pool", "max_connections"],
        "security": ["permission", "denied", "login", "auth"],
        "backup": ["backup", "archive", "pitr", "restore"],
    }

    def extract(self, text, metrics):
        text_lower = text.lower()
        text_features = {}
        for cat, kws in self.KEYWORDS.items():
            text_features[cat] = sum(1 for kw in kws if kw in text_lower)
        metric_features = {}
        ranges = {
            "cpu_percent": (0, 100), "disk_percent": (0, 100),
            "connections": (0, 500), "replication_lag_seconds": (0, 3600),
        }
        for name, value in metrics.items():
            if name in ranges:
                lo, hi = ranges[name]
                metric_features[name] = max(0.0, min(1.0, (value - lo) / (hi - lo)))
        return text_features, metric_features


class AlertClassifier:
    METRIC_CATEGORIES = {
        "cpu_percent": "performance",
        "disk_percent": "storage",
        "connections": "connectivity",
        "replication_lag_seconds": "replication",
    }

    def classify(self, text_features, metric_features):
        text_category = max(text_features, key=text_features.get)
        text_score = text_features[text_category]
        metric_category = None
        metric_score = 0
        for metric_name, value in metric_features.items():
            if value > metric_score and metric_name in self.METRIC_CATEGORIES:
                metric_score = value
                metric_category = self.METRIC_CATEGORIES[metric_name]
        if text_category == metric_category:
            confidence = min(1.0, (text_score * 0.3 + metric_score * 0.7) + 0.1)
            return text_category, confidence
        elif metric_score > 0.8:
            return metric_category, metric_score * 0.8
        elif text_score >= 2:
            return text_category, min(1.0, text_score * 0.25)
        else:
            return text_category, 0.3


class SeverityScorer:
    CRITICAL_THRESHOLDS = {
        "cpu_percent": 95, "disk_percent": 95,
        "connections": 450, "replication_lag_seconds": 300,
    }

    def score(self, category, confidence, metrics, environment="production"):
        base = confidence * 60
        metric_bonus = 0
        for metric_name, value in metrics.items():
            if metric_name in self.CRITICAL_THRESHOLDS:
                threshold = self.CRITICAL_THRESHOLDS[metric_name]
                if value >= threshold:
                    metric_bonus = max(metric_bonus, 40)
                elif value >= threshold * 0.8:
                    metric_bonus = max(metric_bonus, 20)
        env_weights = {"production": 1.0, "staging": 0.7, "development": 0.4}
        env_weight = env_weights.get(environment, 0.5)
        score = min(100, (base + metric_bonus) * env_weight)
        for metric_name, value in metrics.items():
            if metric_name in self.CRITICAL_THRESHOLDS:
                if value >= self.CRITICAL_THRESHOLDS[metric_name]:
                    score = max(score, 80)
        if score >= 80: priority = "P1"
        elif score >= 60: priority = "P2"
        elif score >= 40: priority = "P3"
        else: priority = "P4"
        return {"score": round(score, 1), "priority": priority}


class AlertPipeline:
    def __init__(self):
        self.extractor = FeatureExtractor()
        self.classifier = AlertClassifier()
        self.scorer = SeverityScorer()

    def process(self, alert_text, metrics, environment="production"):
        text_features, metric_features = self.extractor.extract(alert_text, metrics)
        category, confidence = self.classifier.classify(text_features, metric_features)
        severity = self.scorer.score(category, confidence, metrics, environment)
        return {
            "category": category,
            "confidence": round(confidence, 3),
            "severity_score": severity["score"],
            "priority": severity["priority"],
        }


pipeline = AlertPipeline()

# ---- Behavioral Tests ----
# These test SCENARIOS, not components.
# Each scenario represents a real situation a DBA would face.

print("\nScenario 1: The Silent Killer")
print("-" * 40)
print("  Disk fills up slowly. Text says 'routine check'.")
print("  Metrics show 99% disk usage.")
print("  The AI MUST flag this as P1.")

result = pipeline.process(
    "Routine daily disk space check completed successfully",
    {"disk_percent": 99}
)
status = "PASS" if result["priority"] == "P1" else "FAIL"
print(f"  [{status}] Priority: {result['priority']} (expected: P1)")
print(f"  Category: {result['category']}, Score: {result['severity_score']}")

if result["priority"] != "P1":
    print("  CRITICAL: This is the #1 safety requirement!")
    print("  A missed P1 alert can cause an outage.")


print("\nScenario 2: The Noisy Neighbor")
print("-" * 40)
print("  Dev environment has high CPU.")
print("  Should NOT page the on-call DBA.")

result = pipeline.process(
    "High CPU usage detected on development database",
    {"cpu_percent": 92},
    environment="development"
)
status = "PASS" if result["priority"] in ("P3", "P4") else "FAIL"
print(f"  [{status}] Priority: {result['priority']} (expected: P3 or P4)")
print(f"  Dev alerts should be low priority to avoid alert fatigue.")


print("\nScenario 3: The Cascade")
print("-" * 40)
print("  Replication lag causes connection pool exhaustion.")
print("  Text mentions both. Metrics show lag AND connections.")
print("  Should identify the primary issue.")

result = pipeline.process(
    "Replication lag increasing, standby falling behind, connection pool near max",
    {"replication_lag_seconds": 600, "connections": 420}
)
print(f"  Category: {result['category']}")
print(f"  Priority: {result['priority']}")
# Both replication and connectivity are valid; the key is it's high priority
status = "PASS" if result["priority"] in ("P1", "P2") else "FAIL"
print(f"  [{status}] High severity detected (expected: P1 or P2)")


print("\nScenario 4: The Ambiguous Alert")
print("-" * 40)
print("  Vague alert text. No metrics.")
print("  Should classify with low confidence.")

result = pipeline.process(
    "Something might be wrong with the database",
    {}
)
print(f"  Category: {result['category']}")
print(f"  Confidence: {result['confidence']}")
status = "PASS" if result["confidence"] < 0.5 else "FAIL"
print(f"  [{status}] Low confidence: {result['confidence']} (expected: < 0.5)")
print(f"  Ambiguous alerts should have low confidence so DBAs review them.")


print("\nScenario 5: The Contradicting Signals")
print("-" * 40)
print("  Text says 'performance' but metrics show disk is the problem.")
print("  Metrics should win when they're extreme.")

result = pipeline.process(
    "Database performance degraded, slow queries detected",
    {"disk_percent": 98, "cpu_percent": 15}
)
print(f"  Category: {result['category']}")
print(f"  Priority: {result['priority']}")
# With 98% disk, metric floor should kick in regardless
status = "PASS" if result["priority"] == "P1" else "FAIL"
print(f"  [{status}] Critical disk metric forces P1 regardless of text")


print("\nScenario 6: The Security Incident")
print("-" * 40)
print("  Multiple failed login attempts detected.")
print("  No metric anomalies. Text is the only signal.")

result = pipeline.process(
    "Multiple login failures detected: permission denied for user admin, "
    "unauthorized access attempt from unknown IP",
    {"cpu_percent": 25, "connections": 50}
)
status = "PASS" if result["category"] == "security" else "FAIL"
print(f"  [{status}] Category: {result['category']} (expected: security)")
print(f"  Priority: {result['priority']}")


# Summary
print("\n" + "=" * 55)
print("Behavioral Test Summary")
print("=" * 55)
print("""
Key safety behaviors tested:
  1. Metric floor: critical metrics ALWAYS force P1
  2. Environment weighting: dev alerts don't page on-call
  3. Cascade detection: multi-signal alerts get high priority
  4. Low confidence: ambiguous alerts flagged for human review
  5. Metric override: extreme metrics override misleading text
  6. Text-only: security alerts work without metric anomalies

The most important test: Scenario 1 (The Silent Killer).
If your AI misses a P1 because the text said "routine",
the entire product has failed its primary safety requirement.
""")
PYEOF
```

---

## Step 4. Load tests

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import statistics

# ============================================================
# LOAD TESTS
# Test that the system handles production volume.
#
# DBA analogy: like running pgbench before going to production.
# "Can this database handle 1000 transactions per second?"
# Same question for your AI: "Can it classify 60 alerts per minute?"
# ============================================================

print("Load Tests: Can It Handle Production Volume?")
print("=" * 55)

# Simplified pipeline for load testing
class FeatureExtractor:
    KEYWORDS = {
        "performance": ["slow", "latency", "timeout", "cpu", "load"],
        "storage": ["disk", "space", "full", "tablespace"],
        "replication": ["replica", "lag", "standby", "wal"],
        "connectivity": ["connection", "refused", "pool"],
        "security": ["permission", "denied", "login", "auth"],
        "backup": ["backup", "archive", "pitr", "restore"],
    }
    def extract(self, text, metrics):
        text_lower = text.lower()
        text_features = {cat: sum(1 for kw in kws if kw in text_lower)
                         for cat, kws in self.KEYWORDS.items()}
        ranges = {"cpu_percent": (0,100), "disk_percent": (0,100),
                  "connections": (0,500), "replication_lag_seconds": (0,3600)}
        metric_features = {}
        for n, v in metrics.items():
            if n in ranges:
                lo, hi = ranges[n]
                metric_features[n] = max(0.0, min(1.0, (v-lo)/(hi-lo)))
        return text_features, metric_features

class AlertClassifier:
    METRIC_CATS = {"cpu_percent":"performance","disk_percent":"storage",
                   "connections":"connectivity","replication_lag_seconds":"replication"}
    def classify(self, tf, mf):
        tc = max(tf, key=tf.get); ts = tf[tc]
        mc = None; ms = 0
        for n,v in mf.items():
            if v > ms and n in self.METRIC_CATS: ms=v; mc=self.METRIC_CATS[n]
        if tc == mc: return tc, min(1.0, ts*0.3+ms*0.7+0.1)
        elif ms > 0.8: return mc, ms*0.8
        elif ts >= 2: return tc, min(1.0, ts*0.25)
        return tc, 0.3

class SeverityScorer:
    CRITICAL = {"cpu_percent":95,"disk_percent":95,"connections":450,"replication_lag_seconds":300}
    def score(self, cat, conf, metrics, env="production"):
        base = conf * 60; bonus = 0
        for n,v in metrics.items():
            if n in self.CRITICAL:
                t = self.CRITICAL[n]
                if v >= t: bonus = max(bonus, 40)
                elif v >= t*0.8: bonus = max(bonus, 20)
        ew = {"production":1.0,"staging":0.7,"development":0.4}.get(env, 0.5)
        s = min(100, (base+bonus)*ew)
        for n,v in metrics.items():
            if n in self.CRITICAL and v >= self.CRITICAL[n]: s = max(s, 80)
        if s >= 80: p="P1"
        elif s >= 60: p="P2"
        elif s >= 40: p="P3"
        else: p="P4"
        return {"score": round(s,1), "priority": p}

class AlertPipeline:
    def __init__(self):
        self.extractor = FeatureExtractor()
        self.classifier = AlertClassifier()
        self.scorer = SeverityScorer()
    def process(self, text, metrics, env="production"):
        tf, mf = self.extractor.extract(text, metrics)
        cat, conf = self.classifier.classify(tf, mf)
        sev = self.scorer.score(cat, conf, metrics, env)
        return {"category": cat, "confidence": round(conf,3),
                "severity_score": sev["score"], "priority": sev["priority"]}


# ---- Load Test ----

pipeline = AlertPipeline()

# Test alerts (simulating real production traffic)
test_alerts = [
    ("High CPU usage on pg-primary-1", {"cpu_percent": 88, "connections": 150}),
    ("Disk space warning on pg-analytics", {"disk_percent": 85}),
    ("Replication lag increasing on pg-standby-2", {"replication_lag_seconds": 45}),
    ("Connection pool exhausted", {"connections": 480, "cpu_percent": 60}),
    ("Backup failed for pg-primary-1", {}),
    ("Slow queries detected on pg-reporting", {"cpu_percent": 72}),
    ("Permission denied for user app_readonly", {"connections": 30}),
    ("WAL archive falling behind", {"disk_percent": 70}),
    ("Database timeout from web application", {"cpu_percent": 45, "connections": 200}),
    ("Standby not receiving WAL segments", {"replication_lag_seconds": 600}),
]

# Test 1: Throughput (how many alerts per second?)
print("\nTest 1: Throughput")
print("-" * 40)

num_iterations = 1000
start_time = time.time()

for i in range(num_iterations):
    # Cycle through test alerts
    text, metrics = test_alerts[i % len(test_alerts)]
    pipeline.process(text, metrics)

elapsed = time.time() - start_time
alerts_per_second = num_iterations / elapsed

print(f"  Processed: {num_iterations} alerts")
print(f"  Time: {elapsed:.2f} seconds")
print(f"  Throughput: {alerts_per_second:.0f} alerts/second")
print(f"  Target: 60 alerts/minute = 1 alert/second")

status = "PASS" if alerts_per_second > 1 else "FAIL"
print(f"  [{status}] {'Meets' if alerts_per_second > 1 else 'Below'} throughput target")


# Test 2: Latency distribution
print("\nTest 2: Latency Distribution")
print("-" * 40)

latencies = []
for i in range(1000):
    text, metrics = test_alerts[i % len(test_alerts)]
    start = time.time()
    pipeline.process(text, metrics)
    latency_ms = (time.time() - start) * 1000
    latencies.append(latency_ms)

# Calculate percentiles
latencies.sort()
p50 = latencies[len(latencies) // 2]
p95 = latencies[int(len(latencies) * 0.95)]
p99 = latencies[int(len(latencies) * 0.99)]
avg = statistics.mean(latencies)

print(f"  Samples: {len(latencies)}")
print(f"  Average: {avg:.2f} ms")
print(f"  p50:     {p50:.2f} ms")
print(f"  p95:     {p95:.2f} ms")
print(f"  p99:     {p99:.2f} ms")
print(f"  Target:  < 200 ms at p95")

status = "PASS" if p95 < 200 else "FAIL"
print(f"  [{status}] p95 latency {'meets' if p95 < 200 else 'exceeds'} target")


# Test 3: Consistency under load
print("\nTest 3: Consistency Under Load")
print("-" * 40)
print("  Same alert should always get the same result.")

# Run the same alert 100 times
results = []
for _ in range(100):
    result = pipeline.process(
        "High CPU usage causing slow queries",
        {"cpu_percent": 92}
    )
    results.append(result["category"])

# Check all results are the same
unique_results = set(results)
status = "PASS" if len(unique_results) == 1 else "FAIL"
print(f"  Ran same alert 100 times")
print(f"  Unique results: {unique_results}")
print(f"  [{status}] {'Consistent' if len(unique_results) == 1 else 'INCONSISTENT'} results")


# Test 4: Memory stability
print("\nTest 4: Memory Stability")
print("-" * 40)

import sys

# Process many alerts and check that pipeline doesn't grow
pipeline_size_before = sys.getsizeof(pipeline)
for i in range(5000):
    text, metrics = test_alerts[i % len(test_alerts)]
    pipeline.process(text, metrics)
pipeline_size_after = sys.getsizeof(pipeline)

growth = pipeline_size_after - pipeline_size_before
status = "PASS" if growth == 0 else "WARN"
print(f"  Pipeline object size before: {pipeline_size_before} bytes")
print(f"  Pipeline object size after:  {pipeline_size_after} bytes")
print(f"  Growth: {growth} bytes")
print(f"  [{status}] {'No memory growth' if growth == 0 else 'Some growth detected'}")


# Summary
print("\n" + "=" * 55)
print("Load Test Summary")
print("=" * 55)
print(f"""
  Throughput:   {alerts_per_second:.0f} alerts/sec (target: 1/sec)
  Latency p95:  {p95:.2f} ms (target: < 200 ms)
  Consistency:  {len(unique_results)} unique result(s) for identical input
  Memory:       {growth} bytes growth over 5000 requests

Load testing answers:
  - Can it handle the volume? (throughput)
  - Is it fast enough? (latency)
  - Is it reliable? (consistency)
  - Does it leak memory? (stability)

DBA analogy: this is your pgbench for AI.
  pgbench -c 10 -t 1000 mydb
  tells you if your database can handle the load.
  Load tests tell you if your AI can handle the alerts.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Unit tests | Test components in isolation | Test a function/trigger alone |
| Integration tests | Test components working together | Test streaming replication end-to-end |
| Behavioral tests | Test real-world scenarios | Validate runbooks against real failures |
| Load tests | Test performance under volume | pgbench before production |
| Metric floor test | Verify safety requirements | Verify failover actually works |
| Consistency test | Same input = same output | Deterministic query results |
