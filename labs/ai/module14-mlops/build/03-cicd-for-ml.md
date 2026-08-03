# Build 03: CI/CD for ML

CI/CD (Continuous Integration / Continuous Deployment) automates testing and deploying your models. Instead of manually running tests and deploying, every change triggers an automated pipeline that validates, tests, and deploys.

---

## Step 1. ML testing pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime

print("""
CI/CD for ML: Automated testing before deployment.

Traditional CI/CD (for code):
  1. Push code -> 2. Run tests -> 3. Build -> 4. Deploy

ML CI/CD (for models):
  1. New data or code change
  2. Validate data quality
  3. Train model
  4. Run model tests (accuracy, behavioral, performance)
  5. Compare against current production model
  6. Deploy if better (shadow mode first)

DBA analogy:
  Like running your migration through a staging environment:
  1. Test migration on staging
  2. Check no queries regressed
  3. Verify data integrity
  4. Then apply to production
""")

class MLTestPipeline:
    """Automated ML testing pipeline."""

    def __init__(self):
        self.results = []
        self.passed = True

    def run_test(self, name, test_func):
        """Run a single test and record results."""
        start = time.time()
        try:
            passed, details = test_func()
            duration = (time.time() - start) * 1000
            self.results.append({
                "name": name,
                "passed": passed,
                "details": details,
                "duration_ms": round(duration, 2),
            })
            if not passed:
                self.passed = False
            status = "PASS" if passed else "FAIL"
            print(f"  [{status}] {name} ({duration:.1f}ms)")
            if not passed:
                print(f"         {details}")
            return passed
        except Exception as e:
            self.passed = False
            duration = (time.time() - start) * 1000
            self.results.append({
                "name": name,
                "passed": False,
                "details": f"Exception: {e}",
                "duration_ms": round(duration, 2),
            })
            print(f"  [FAIL] {name} ({duration:.1f}ms)")
            print(f"         Exception: {e}")
            return False

    def summary(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r["passed"])
        failed = total - passed
        return {
            "total": total,
            "passed": passed,
            "failed": failed,
            "all_passed": self.passed,
        }

# Define tests

# Test 1: Data quality checks
def test_data_quality():
    """Check training data meets quality standards."""
    data = [
        {"message": "CPU at 95%", "category": "performance"},
        {"message": "Disk full", "category": "storage"},
        {"message": "Replication lag", "category": "replication"},
        {"message": "Failed login", "category": "security"},
    ]
    # Check: no empty messages
    empty = sum(1 for d in data if not d.get("message", "").strip())
    if empty > 0:
        return False, f"{empty} empty messages"

    # Check: all categories are valid
    valid_cats = {"performance", "storage", "replication", "security", "backup"}
    invalid = [d["category"] for d in data if d["category"] not in valid_cats]
    if invalid:
        return False, f"Invalid categories: {invalid}"

    # Check: minimum dataset size
    if len(data) < 3:
        return False, f"Dataset too small: {len(data)} < 100 minimum"

    return True, f"Data quality OK ({len(data)} rows, {len(valid_cats)} categories)"

# Test 2: Model accuracy threshold
def test_accuracy_threshold():
    """Check model accuracy meets minimum threshold."""
    # Simulate model evaluation
    accuracy = 0.92
    threshold = 0.85
    if accuracy < threshold:
        return False, f"Accuracy {accuracy:.2f} < threshold {threshold:.2f}"
    return True, f"Accuracy {accuracy:.2f} >= {threshold:.2f}"

# Test 3: Model doesn't regress vs production
def test_no_regression():
    """Check new model isn't worse than production model."""
    production_accuracy = 0.91
    new_accuracy = 0.92
    min_improvement = -0.02  # allow up to 2% regression
    diff = new_accuracy - production_accuracy
    if diff < min_improvement:
        return False, f"Regression: {diff:+.2f} (new: {new_accuracy:.2f}, prod: {production_accuracy:.2f})"
    return True, f"No regression: {diff:+.2f} (new: {new_accuracy:.2f}, prod: {production_accuracy:.2f})"

# Test 4: Behavioral tests
def test_behavioral():
    """Check model handles known patterns correctly."""
    # Simulate model predictions
    def predict(msg):
        msg = msg.lower()
        if "cpu" in msg: return "performance"
        if "disk" in msg: return "storage"
        if "replication" in msg: return "replication"
        return "unknown"

    test_cases = [
        ("CPU at 99% on primary", "performance"),
        ("Disk space critical", "storage"),
        ("Replication lag 300s", "replication"),
    ]

    failures = []
    for msg, expected in test_cases:
        actual = predict(msg)
        if actual != expected:
            failures.append(f"'{msg}': expected {expected}, got {actual}")

    if failures:
        return False, f"{len(failures)} behavioral test failures: {failures[0]}"
    return True, f"All {len(test_cases)} behavioral tests passed"

# Test 5: Latency check
def test_latency():
    """Check model inference speed."""
    # Simulate inference timing
    latencies = [5, 8, 12, 6, 15, 7, 9, 11, 4, 100]  # ms, last one is an outlier
    p95 = sorted(latencies)[int(len(latencies) * 0.95)]
    max_p95 = 50  # ms

    if p95 > max_p95:
        return False, f"p95 latency {p95}ms > {max_p95}ms limit"
    return True, f"p95 latency {p95}ms <= {max_p95}ms limit"

# Test 6: Model size check
def test_model_size():
    """Check model file size is within limits."""
    model_size_mb = 253
    max_size_mb = 500
    if model_size_mb > max_size_mb:
        return False, f"Model {model_size_mb}MB > {max_size_mb}MB limit"
    return True, f"Model size {model_size_mb}MB <= {max_size_mb}MB limit"

# Run the pipeline
pipeline = MLTestPipeline()

print("ML CI/CD Test Pipeline")
print("=" * 55)

pipeline.run_test("Data Quality", test_data_quality)
pipeline.run_test("Accuracy Threshold", test_accuracy_threshold)
pipeline.run_test("No Regression", test_no_regression)
pipeline.run_test("Behavioral Tests", test_behavioral)
pipeline.run_test("Latency Check", test_latency)
pipeline.run_test("Model Size", test_model_size)

# Summary
summary = pipeline.summary()
print(f"\n{'='*55}")
print(f"Results: {summary['passed']}/{summary['total']} passed, {summary['failed']} failed")

if summary["all_passed"]:
    print("PIPELINE: PASSED - model is ready for deployment")
else:
    print("PIPELINE: FAILED - fix issues before deploying")
PYEOF
```

---

## Step 2. GitHub Actions for ML

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
GitHub Actions for ML CI/CD:

When you push code or data changes, GitHub Actions runs your test pipeline.

Here's what the workflow file looks like:
""")

workflow = '''# .github/workflows/ml-pipeline.yml
name: ML Pipeline

on:
  push:
    branches: [main]
    paths:
      - "models/**"      # model code changes
      - "data/**"         # data changes
      - "training/**"     # training script changes
  schedule:
    - cron: "0 0 * * 0"  # weekly retraining (Sunday midnight)
    # Same cron syntax as pg_cron!

jobs:
  data-validation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Validate training data
        run: python scripts/validate_data.py
        # Checks: no empty rows, valid categories, minimum size

  train-and-test:
    needs: data-validation
    # Only runs if data-validation passes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Train model
        run: python scripts/train.py --config configs/production.yaml
        # Train with production config

      - name: Run model tests
        run: python scripts/test_model.py
        # Accuracy threshold, behavioral tests, latency checks

      - name: Compare against production
        run: python scripts/compare_models.py --baseline production --candidate new
        # Check new model doesn't regress

      - name: Upload model artifact
        uses: actions/upload-artifact@v4
        with:
          name: model-${{ github.sha }}
          path: models/alert_classifier.pt
          # Save model file, tagged with the git commit

  deploy:
    needs: train-and-test
    if: github.ref == 'refs/heads/main'
    # Only deploy from main branch
    runs-on: ubuntu-latest
    steps:
      - name: Download model artifact
        uses: actions/download-artifact@v4
        with:
          name: model-${{ github.sha }}

      - name: Deploy to shadow mode
        run: |
          python scripts/deploy.py \\
            --model models/alert_classifier.pt \\
            --mode shadow \\
            --version ${{ github.sha }}
        # First deploy as shadow (no user impact)
        # After 24h of shadow testing, promote to production
'''

print(workflow)

print("""
Key patterns:
  1. 'needs' creates dependencies (data-validation must pass before training)
  2. 'paths' triggers only when relevant files change
  3. 'schedule' enables automatic retraining
  4. Artifacts save the trained model for deployment
  5. Shadow mode deployment = safe by default

DBA analogy:
  This is like a CI/CD pipeline for schema migrations:
  1. Validate migration SQL
  2. Run on staging database
  3. Check no queries regressed (pg_stat_statements diff)
  4. Apply to production
  5. Monitor for issues
""")
PYEOF
```

---

## Step 3. Automated deployment gates

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
Deployment Gates: Automated checks that must pass before a model goes live.

Each gate is a yes/no decision:
  Pass all gates -> deploy
  Fail any gate -> block deployment, alert the team

DBA analogy:
  Like pre-flight checks before a database migration:
  [ ] Backup verified
  [ ] Staging test passed
  [ ] No active long-running queries
  [ ] Replication lag < 10 seconds
  [ ] DBA approval
""")

class DeploymentGate:
    """A single deployment gate (check)."""

    def __init__(self, name, check_func, required=True):
        self.name = name
        self.check = check_func
        self.required = required
        # required=True means deployment is blocked if this fails
        # required=False means it's a warning, not a blocker

class DeploymentPipeline:
    """Run all deployment gates."""

    def __init__(self):
        self.gates = []

    def add_gate(self, name, check_func, required=True):
        self.gates.append(DeploymentGate(name, check_func, required))

    def run(self, model_info):
        """Run all gates. Return (can_deploy, results)."""
        results = []
        can_deploy = True

        for gate in self.gates:
            try:
                passed, detail = gate.check(model_info)
            except Exception as e:
                passed = False
                detail = f"Gate crashed: {e}"

            results.append({
                "gate": gate.name,
                "passed": passed,
                "required": gate.required,
                "detail": detail,
            })

            if not passed and gate.required:
                can_deploy = False

        return can_deploy, results

# Define gates
def check_accuracy(model):
    acc = model.get("accuracy", 0)
    threshold = 0.85
    return acc >= threshold, f"accuracy={acc:.2f} (threshold={threshold})"

def check_no_regression(model):
    prod_acc = model.get("production_accuracy", 0)
    new_acc = model.get("accuracy", 0)
    diff = new_acc - prod_acc
    return diff >= -0.02, f"diff={diff:+.3f} (new={new_acc:.2f}, prod={prod_acc:.2f})"

def check_latency(model):
    p95 = model.get("p95_latency_ms", 999)
    limit = 100
    return p95 <= limit, f"p95={p95}ms (limit={limit}ms)"

def check_behavioral_tests(model):
    tests_passed = model.get("behavioral_tests_passed", 0)
    tests_total = model.get("behavioral_tests_total", 0)
    rate = tests_passed / tests_total if tests_total > 0 else 0
    return rate >= 0.95, f"{tests_passed}/{tests_total} passed ({rate:.0%})"

def check_data_freshness(model):
    days_old = model.get("training_data_age_days", 999)
    limit = 30
    return days_old <= limit, f"data is {days_old} days old (limit={limit})"

def check_model_size(model):
    size_mb = model.get("model_size_mb", 0)
    limit = 500
    return size_mb <= limit, f"{size_mb}MB (limit={limit}MB)"

# Build pipeline
pipeline = DeploymentPipeline()
pipeline.add_gate("Accuracy Threshold", check_accuracy, required=True)
pipeline.add_gate("No Regression", check_no_regression, required=True)
pipeline.add_gate("Latency SLA", check_latency, required=True)
pipeline.add_gate("Behavioral Tests", check_behavioral_tests, required=True)
pipeline.add_gate("Data Freshness", check_data_freshness, required=False)  # warning only
pipeline.add_gate("Model Size", check_model_size, required=False)          # warning only

# Test: model that passes all gates
good_model = {
    "version": "v4",
    "accuracy": 0.94,
    "production_accuracy": 0.91,
    "p95_latency_ms": 47,
    "behavioral_tests_passed": 48,
    "behavioral_tests_total": 50,
    "training_data_age_days": 7,
    "model_size_mb": 253,
}

print("Deployment Gate Check: Model v4")
print("=" * 60)

can_deploy, results = pipeline.run(good_model)

for r in results:
    status = "PASS" if r["passed"] else ("FAIL" if r["required"] else "WARN")
    req = "required" if r["required"] else "optional"
    print(f"  [{status:>4s}] {r['gate']:<25s} {r['detail']}")

print(f"\nDeployment: {'APPROVED' if can_deploy else 'BLOCKED'}")

# Test: model that fails
print(f"\n{'='*60}")
bad_model = {
    "version": "v5",
    "accuracy": 0.82,          # below threshold
    "production_accuracy": 0.91,
    "p95_latency_ms": 150,     # above limit
    "behavioral_tests_passed": 40,
    "behavioral_tests_total": 50,
    "training_data_age_days": 45,
    "model_size_mb": 600,
}

print("Deployment Gate Check: Model v5")
print("=" * 60)

can_deploy, results = pipeline.run(bad_model)

for r in results:
    status = "PASS" if r["passed"] else ("FAIL" if r["required"] else "WARN")
    print(f"  [{status:>4s}] {r['gate']:<25s} {r['detail']}")

print(f"\nDeployment: {'APPROVED' if can_deploy else 'BLOCKED'}")
if not can_deploy:
    failed = [r for r in results if not r["passed"] and r["required"]]
    print(f"Blockers: {', '.join(r['gate'] for r in failed)}")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| ML test pipeline | Run all tests before deployment | Pre-migration checks |
| Data validation | Check data quality before training | CHECK constraints on import |
| Accuracy threshold | Minimum model performance | SLA for query response time |
| Regression check | New model vs production model | Comparing query plans before/after |
| Behavioral tests | Check known patterns are handled | Smoke tests after deployment |
| Deployment gates | Automated go/no-go for deployment | Change management approval |
| GitHub Actions | Automate the entire pipeline | pg_cron for CI/CD |
