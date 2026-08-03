# Build 04: Pattern Detection and Prediction

Spot recurring patterns in alert history and predict issues before they become emergencies.

---

## Step 1. Recurring pattern detection

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta
from collections import Counter, defaultdict
import random

random.seed(42)

# ============================================================
# RECURRING PATTERN DETECTION
# Find alerts that happen at predictable times.
#
# DBA analogy: "Disk fills every Sunday at 2 AM" or
# "CPU spikes every 15 minutes." You notice these after a
# few weeks. The AI spots them immediately from the data.
# ============================================================

print("Recurring Pattern Detection")
print("=" * 55)

class PatternDetector:
    """
    Detect recurring patterns in alert history.

    Looks for:
    1. Time-of-day patterns (always happens at 3 AM)
    2. Day-of-week patterns (every Sunday)
    3. Interval patterns (every 15 minutes)
    4. Category clustering (storage alerts always precede performance)

    DBA analogy: like analyzing slow query log patterns.
    You might notice certain queries spike at specific times.
    pg_stat_statements tracks frequency; we do the same for alerts.
    """

    def __init__(self):
        self.alerts = []                 # historical alerts

    def add_alert(self, text, category, severity, timestamp=None):
        """Record an alert."""
        self.alerts.append({
            "text": text,
            "category": category,
            "severity": severity,
            "timestamp": timestamp or datetime.now(),
        })

    def detect_hourly_patterns(self, min_occurrences=3):
        """
        Find hours where alerts cluster.

        If 80% of "backup" alerts happen between 2-4 AM,
        that's a pattern (backup cron runs then).
        """
        # Group alerts by category + hour
        category_hours = defaultdict(lambda: Counter())

        for alert in self.alerts:
            hour = alert["timestamp"].hour
            category_hours[alert["category"]][hour] += 1

        patterns = []
        for category, hour_counts in category_hours.items():
            total = sum(hour_counts.values())
            for hour, count in hour_counts.most_common(3):
                if count >= min_occurrences:
                    pct = count / total * 100
                    if pct >= 30:        # at least 30% of alerts at this hour
                        patterns.append({
                            "type": "hourly",
                            "category": category,
                            "hour": hour,
                            "count": count,
                            "percent": round(pct, 1),
                            "description": f"{category} alerts cluster at {hour}:00 ({pct:.0f}% of all {category})",
                        })

        return sorted(patterns, key=lambda x: x["percent"], reverse=True)

    def detect_day_of_week_patterns(self, min_occurrences=3):
        """
        Find days where alerts cluster.

        If storage alerts spike every Sunday, that's a pattern.
        """
        day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        category_days = defaultdict(lambda: Counter())

        for alert in self.alerts:
            day = alert["timestamp"].weekday()  # 0=Monday, 6=Sunday
            category_days[alert["category"]][day] += 1

        patterns = []
        for category, day_counts in category_days.items():
            total = sum(day_counts.values())
            for day, count in day_counts.most_common(2):
                if count >= min_occurrences:
                    pct = count / total * 100
                    if pct >= 25:
                        patterns.append({
                            "type": "daily",
                            "category": category,
                            "day": day_names[day],
                            "count": count,
                            "percent": round(pct, 1),
                            "description": f"{category} alerts spike on {day_names[day]} ({pct:.0f}%)",
                        })

        return sorted(patterns, key=lambda x: x["percent"], reverse=True)

    def detect_cascades(self, window_minutes=30):
        """
        Find alert sequences that always happen together.

        If "WAL archive failure" is always followed by "disk full"
        within 30 minutes, that's a cascade pattern.
        """
        # Sort alerts by time
        sorted_alerts = sorted(self.alerts, key=lambda x: x["timestamp"])

        # Find sequential pairs
        pair_counts = Counter()
        for i in range(len(sorted_alerts) - 1):
            a1 = sorted_alerts[i]
            a2 = sorted_alerts[i + 1]

            time_diff = (a2["timestamp"] - a1["timestamp"]).total_seconds() / 60

            if time_diff <= window_minutes and a1["category"] != a2["category"]:
                pair = (a1["category"], a2["category"])
                pair_counts[pair] += 1

        patterns = []
        for (cat1, cat2), count in pair_counts.most_common(5):
            if count >= 3:
                patterns.append({
                    "type": "cascade",
                    "trigger": cat1,
                    "result": cat2,
                    "count": count,
                    "description": f"{cat1} -> {cat2} (happened {count} times within {window_minutes}min)",
                })

        return patterns


# Simulate 3 months of alert history
detector = PatternDetector()

now = datetime.now()

# Pattern 1: Storage alerts on Sundays at 2 AM (backup + analytics)
for week in range(12):
    sunday = now - timedelta(weeks=week)
    # Find the previous Sunday
    days_since_sunday = (sunday.weekday() + 1) % 7
    sunday = sunday - timedelta(days=days_since_sunday)
    sunday = sunday.replace(hour=2, minute=random.randint(0, 30))
    detector.add_alert("Disk usage spike during backup", "storage", 60, sunday)
    # Performance alert follows 10 min later
    detector.add_alert("CPU high during analytics", "performance", 50,
                       sunday + timedelta(minutes=random.randint(5, 15)))

# Pattern 2: Performance alerts at 9 AM on weekdays (morning batch jobs)
for day in range(60):
    date = now - timedelta(days=day)
    if date.weekday() < 5:           # weekdays only
        morning = date.replace(hour=9, minute=random.randint(0, 15))
        if random.random() < 0.7:    # 70% of weekday mornings
            detector.add_alert("Morning batch job CPU spike", "performance", 40, morning)

# Pattern 3: Random alerts (no pattern)
for _ in range(50):
    rand_time = now - timedelta(
        days=random.randint(0, 90),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59),
    )
    cats = ["performance", "storage", "replication", "connectivity"]
    detector.add_alert("Random alert", random.choice(cats),
                       random.randint(20, 80), rand_time)

# Detect patterns
print(f"\nAnalyzing {len(detector.alerts)} alerts over 3 months...")
print()

hourly = detector.detect_hourly_patterns()
daily = detector.detect_day_of_week_patterns()
cascades = detector.detect_cascades()

if hourly:
    print("Hourly Patterns Found:")
    print("-" * 55)
    for p in hourly[:5]:
        print(f"  {p['description']}")

if daily:
    print(f"\nDay-of-Week Patterns Found:")
    print("-" * 55)
    for p in daily[:5]:
        print(f"  {p['description']}")

if cascades:
    print(f"\nCascade Patterns Found:")
    print("-" * 55)
    for p in cascades:
        print(f"  {p['description']}")

print("""
What patterns tell you:
  - Hourly: "Performance spikes at 9 AM" -> morning batch jobs
  - Daily: "Storage alerts on Sundays" -> backup + analytics overlap
  - Cascade: "storage -> performance" -> disk issue causes CPU spikes

Actions:
  - Schedule batch jobs to avoid overlap
  - Pre-allocate disk before Sunday backups
  - Set up predictive alerts ("disk will be full in 6 hours at current rate")
""")
PYEOF
```

---

## Step 2. Trend analysis and prediction

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

# ============================================================
# TREND ANALYSIS AND PREDICTION
# Look at metric trends to predict future problems.
#
# DBA analogy: "Disk is at 80% and growing 2% per day.
# At this rate, it'll be full in 10 days."
# You do this math in your head. The AI does it automatically.
# ============================================================

print("Trend Analysis and Prediction")
print("=" * 55)

class TrendAnalyzer:
    """
    Analyze metric trends and predict when thresholds will be breached.

    Uses linear regression (fitting a straight line to data points).

    DBA analogy: like extrapolating database growth.
    If the database grows 10GB/month and has 50GB free,
    you'll run out in 5 months. Same math, automated.
    """

    def __init__(self):
        pass

    def fit_trend(self, values):
        """
        Fit a straight line to the values.
        Returns (slope, intercept).

        slope = how much the value changes per time step
        intercept = starting value

        Math (simple linear regression):
          slope = (N * sum(x*y) - sum(x) * sum(y)) / (N * sum(x^2) - sum(x)^2)
          intercept = (sum(y) - slope * sum(x)) / N

        DBA analogy: like calculating growth rate.
        If disk usage over 7 days is [80, 82, 84, 86, 88, 90, 92],
        the slope is +2 per day. That's the growth rate.
        """
        n = len(values)
        if n < 2:
            return 0, values[0] if values else 0

        # x = time step (0, 1, 2, ..., n-1)
        # y = the metric values
        x = list(range(n))
        y = values

        sum_x = sum(x)                  # sum of all x values
        sum_y = sum(y)                  # sum of all y values
        sum_xy = sum(xi * yi for xi, yi in zip(x, y))  # sum of x*y
        sum_x2 = sum(xi ** 2 for xi in x)               # sum of x^2

        # Calculate slope
        denominator = n * sum_x2 - sum_x ** 2
        if denominator == 0:
            return 0, sum_y / n

        slope = (n * sum_xy - sum_x * sum_y) / denominator
        intercept = (sum_y - slope * sum_x) / n

        return round(slope, 4), round(intercept, 4)

    def predict_when(self, values, threshold):
        """
        Predict when a threshold will be breached.

        Returns number of time steps until threshold is reached,
        or None if trend is flat/declining.

        DBA analogy: "At current growth rate, disk will be full in X days."
        """
        slope, intercept = self.fit_trend(values)

        if slope <= 0:
            return None, slope           # not growing, won't breach

        current = values[-1]
        remaining = threshold - current

        if remaining <= 0:
            return 0, slope              # already breached!

        time_steps = remaining / slope   # time steps until breach

        return round(time_steps, 1), slope

    def analyze_metric(self, name, values, threshold, unit="days"):
        """Full analysis of a metric trend."""
        slope, intercept = self.fit_trend(values)
        time_to_breach, _ = self.predict_when(values, threshold)

        current = values[-1]
        direction = "increasing" if slope > 0 else "decreasing" if slope < 0 else "stable"

        result = {
            "metric": name,
            "current": current,
            "threshold": threshold,
            "trend": direction,
            "rate": abs(slope),
            "time_to_breach": time_to_breach,
            "unit": unit,
        }

        # Set urgency
        if time_to_breach is not None:
            if time_to_breach <= 1:
                result["urgency"] = "critical"
            elif time_to_breach <= 7:
                result["urgency"] = "high"
            elif time_to_breach <= 30:
                result["urgency"] = "medium"
            else:
                result["urgency"] = "low"
        else:
            result["urgency"] = "none"

        return result


# Test trend analysis
analyzer = TrendAnalyzer()

# Scenario 1: Disk filling steadily
disk_daily = [72, 74, 76, 78, 80, 82, 84]  # 7 days of disk %

result = analyzer.analyze_metric("disk_percent", disk_daily, threshold=95, unit="days")

print(f"\nScenario 1: Disk filling steadily")
print("-" * 50)
print(f"  Values (last 7 days): {disk_daily}")
print(f"  Current: {result['current']}%")
print(f"  Trend: {result['trend']} at {result['rate']:.1f}%/day")
print(f"  Threshold: {result['threshold']}%")
if result['time_to_breach'] is not None:
    print(f"  Predicted breach in: {result['time_to_breach']:.0f} {result['unit']}")
    print(f"  Urgency: {result['urgency']}")
else:
    print(f"  No breach predicted (trend is {result['trend']})")

# Scenario 2: Connection count spiking
conn_hourly = [100, 120, 150, 190, 240, 300, 370]  # 7 hours

result2 = analyzer.analyze_metric("connections", conn_hourly, threshold=500, unit="hours")

print(f"\nScenario 2: Connections spiking")
print("-" * 50)
print(f"  Values (last 7 hours): {conn_hourly}")
print(f"  Current: {result2['current']}")
print(f"  Trend: {result2['trend']} at {result2['rate']:.0f}/hour")
if result2['time_to_breach'] is not None:
    print(f"  Predicted breach in: {result2['time_to_breach']:.1f} {result2['unit']}")
    print(f"  Urgency: {result2['urgency']}")

# Scenario 3: Stable metric (no concern)
cpu_hourly = [45, 48, 42, 47, 44, 46, 43]  # fluctuating, no trend

result3 = analyzer.analyze_metric("cpu_percent", cpu_hourly, threshold=90, unit="hours")

print(f"\nScenario 3: Stable CPU (no concern)")
print("-" * 50)
print(f"  Values (last 7 hours): {cpu_hourly}")
print(f"  Current: {result3['current']}%")
print(f"  Trend: {result3['trend']} (rate: {result3['rate']:.2f}%/hour)")
print(f"  Urgency: {result3['urgency']}")

# Scenario 4: Replication lag growing
lag_values = [5, 8, 15, 25, 40, 60, 90]     # 7 data points

result4 = analyzer.analyze_metric("replication_lag", lag_values, threshold=300, unit="intervals")

print(f"\nScenario 4: Replication lag growing")
print("-" * 50)
print(f"  Values: {lag_values}")
print(f"  Current: {result4['current']}s")
print(f"  Trend: {result4['trend']} at {result4['rate']:.0f}s/interval")
if result4['time_to_breach'] is not None:
    print(f"  Predicted breach in: {result4['time_to_breach']:.0f} {result4['unit']}")
    print(f"  Urgency: {result4['urgency']}")

print("""
Trend analysis powers PREDICTIVE alerts:
  Instead of "disk is at 95%" (reactive),
  you get "disk will be full in 5 days" (predictive).

  Predictive alerts give you TIME to fix the problem
  before it becomes an emergency.

DBA parallel: like capacity planning.
  "At current growth rate, we need more storage in 3 months."
  Same math, applied to every metric, continuously.
""")
PYEOF
```

---

## Step 3. Anomaly detection

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

# ============================================================
# ANOMALY DETECTION
# Detect when a metric behaves DIFFERENTLY from its history.
# Not just "is it above the threshold?" but "is it unusual?"
#
# DBA analogy: CPU at 80% might be normal during business hours
# but anomalous at 3 AM. Static thresholds miss this.
# Anomaly detection knows what's "normal for this time."
# ============================================================

print("Anomaly Detection")
print("=" * 50)

class AnomalyDetector:
    """
    Detect anomalous metric values using statistical methods.

    Method: Z-score (how many standard deviations from the mean).
    If a value is > 2 standard deviations from the mean, it's anomalous.

    DBA analogy: you know "normal" CPU for each time of day.
    9 AM: CPU 60% is normal (morning batch).
    3 AM: CPU 60% is suspicious (nothing should be running).
    This detector learns what's normal and flags the unusual.
    """

    def __init__(self, z_threshold=2.0):
        """
        z_threshold: how many standard deviations = anomalous.
        2.0 = flags ~5% of values (reasonably sensitive).
        3.0 = flags ~0.3% of values (very conservative).
        """
        self.z_threshold = z_threshold
        self.baselines = {}              # metric -> {"mean": X, "std": Y}

    def learn_baseline(self, metric_name, historical_values):
        """
        Learn what's "normal" for a metric from historical data.

        DBA analogy: look at a month of data to establish
        what "normal" looks like for this metric.
        """
        n = len(historical_values)
        if n < 5:
            return                       # not enough data

        mean = sum(historical_values) / n
        variance = sum((v - mean) ** 2 for v in historical_values) / n
        std = variance ** 0.5

        self.baselines[metric_name] = {
            "mean": round(mean, 2),
            "std": round(std, 2),
            "sample_size": n,
        }

    def check(self, metric_name, value):
        """
        Check if a value is anomalous.

        Returns (is_anomalous, z_score, details).
        """
        baseline = self.baselines.get(metric_name)
        if not baseline:
            return False, 0, "No baseline established"

        mean = baseline["mean"]
        std = baseline["std"]

        if std == 0:
            # If standard deviation is 0, ANY deviation is anomalous
            is_anomalous = abs(value - mean) > 0.01
            return is_anomalous, float('inf') if is_anomalous else 0, "Zero variance baseline"

        z_score = (value - mean) / std   # how many std devs from mean
        is_anomalous = abs(z_score) > self.z_threshold

        direction = "high" if z_score > 0 else "low"

        return is_anomalous, round(z_score, 2), {
            "direction": direction,
            "mean": mean,
            "std": std,
            "deviation": f"{abs(z_score):.1f} standard deviations {direction}",
        }


# Test anomaly detection
detector = AnomalyDetector(z_threshold=2.0)

# Learn baseline from historical data (30 days of normal)
# CPU: normally 40-60% during business hours
normal_cpu = [random.gauss(50, 8) for _ in range(200)]     # mean=50, std=8
detector.learn_baseline("cpu_percent", normal_cpu)

# Connections: normally 100-200
normal_conn = [random.gauss(150, 30) for _ in range(200)]  # mean=150, std=30
detector.learn_baseline("connections", normal_conn)

# Disk: normally around 60%, slow growth
normal_disk = [random.gauss(60, 3) for _ in range(200)]    # mean=60, std=3
detector.learn_baseline("disk_percent", normal_disk)

# Show baselines
print("\nLearned Baselines:")
print("-" * 50)
for name, bl in detector.baselines.items():
    print(f"  {name:<20s} mean={bl['mean']:>6.1f}  std={bl['std']:>5.1f}  samples={bl['sample_size']}")

# Test with normal and anomalous values
test_values = [
    ("cpu_percent", 55, "Normal CPU (within 1 std)"),
    ("cpu_percent", 92, "High CPU (anomalous)"),
    ("cpu_percent", 15, "Low CPU (anomalous - suspiciously quiet)"),
    ("connections", 180, "Normal connections"),
    ("connections", 450, "Spike in connections (anomalous)"),
    ("disk_percent", 62, "Normal disk"),
    ("disk_percent", 85, "High disk (anomalous jump)"),
]

print(f"\nAnomaly Detection Results:")
print("-" * 70)
print(f"{'Metric':<15s} {'Value':>6s} {'Z-score':>8s} {'Status':<12s} {'Description'}")
print("-" * 70)

for metric, value, desc in test_values:
    is_anomaly, z_score, details = detector.check(metric, value)
    status = "ANOMALY" if is_anomaly else "normal"
    print(f"{metric:<15s} {value:>6.0f} {z_score:>+7.1f}  {status:<12s} {desc}")

print("""
Anomaly detection vs static thresholds:

  Static threshold: "Alert if CPU > 90%"
    - Misses: CPU 80% at 3 AM (unusual but below threshold)
    - False alarm: CPU 90% at 9 AM (normal for morning batch)

  Anomaly detection: "Alert if CPU is unusual for this time"
    - Catches: CPU 80% at 3 AM (z-score > 3, very unusual)
    - Ignores: CPU 90% at 9 AM (z-score < 2, normal for morning)

Use BOTH: static thresholds for hard limits (disk > 95%),
anomaly detection for behavioral changes (anything unusual).
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Recurring patterns | Find alerts that repeat predictably | "Disk fills every Sunday" |
| Cascade detection | Find alert sequences that always happen together | "WAL failure causes disk full" |
| Trend analysis | Predict when thresholds will be breached | Capacity planning |
| Linear regression | Fit a line to predict future values | Growth rate calculation |
| Anomaly detection | Flag values unusual for their context | "CPU 80% at 3 AM is weird" |
| Z-score | Measure how far from normal a value is | Standard deviations from average |
