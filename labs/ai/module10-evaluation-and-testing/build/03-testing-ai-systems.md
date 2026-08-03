# Build 03: Testing AI Systems

AI systems need tests just like any software. But AI tests are different - you're testing behavior and statistical properties, not exact outputs. This guide shows you three types of tests that catch real bugs.

---

## Step 1. Unit tests for ML code

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import numpy as np

print("""
Unit Tests for AI: Test individual components, not the whole system.

Just like you test individual SQL functions before deploying them,
test ML components before training:
  - Does the model output the right shape?
  - Does preprocessing handle edge cases?
  - Does the loss function compute correctly?
""")

# ===== TEST 1: Model output shape =====
def test_model_output_shape():
    """Model should output [batch, num_classes] regardless of input."""
    model = nn.Sequential(
        nn.Linear(10, 32), nn.ReLU(),
        nn.Linear(32, 4),  # 4 classes
    )

    # Test different batch sizes
    for batch_size in [1, 16, 100]:
        x = torch.randn(batch_size, 10)
        output = model(x)
        assert output.shape == (batch_size, 4), \
            f"Expected ({batch_size}, 4), got {output.shape}"
        # assert checks a condition; if False, raises AssertionError with message

    print("  [PASS] test_model_output_shape")

# ===== TEST 2: Preprocessing handles edge cases =====
def test_preprocessing_edge_cases():
    """Preprocessing should handle NaN, infinity, and negative values."""
    def preprocess(values):
        values = np.array(values, dtype=np.float32)
        values = np.nan_to_num(values, nan=0.0, posinf=1e6, neginf=-1e6)
        # nan_to_num replaces NaN with 0, +inf with 1e6, -inf with -1e6
        values = np.clip(values, -1e6, 1e6)
        return values

    # Test with NaN
    result = preprocess([1.0, float('nan'), 3.0])
    assert not np.isnan(result).any(), "NaN values should be replaced"
    # np.isnan checks for NaN, .any() returns True if any element is True

    # Test with infinity
    result = preprocess([1.0, float('inf'), -float('inf')])
    assert np.isfinite(result).all(), "Infinity should be capped"
    # np.isfinite returns False for NaN and inf, .all() checks all are True

    # Test with empty input
    result = preprocess([])
    assert len(result) == 0, "Empty input should return empty output"

    print("  [PASS] test_preprocessing_edge_cases")

# ===== TEST 3: Loss function sanity check =====
def test_loss_function():
    """Loss should be 0 for perfect predictions, positive otherwise."""
    loss_fn = nn.CrossEntropyLoss()

    # Perfect prediction (very confident, correct class)
    logits = torch.tensor([[10.0, -10.0, -10.0]])  # strongly predicts class 0
    target = torch.tensor([0])  # actual class is 0
    loss_perfect = loss_fn(logits, target).item()
    assert loss_perfect < 0.001, f"Perfect prediction loss too high: {loss_perfect}"

    # Terrible prediction (confident but wrong)
    logits_wrong = torch.tensor([[-10.0, 10.0, -10.0]])  # predicts class 1
    target_wrong = torch.tensor([0])  # actual is class 0
    loss_wrong = loss_fn(logits_wrong, target_wrong).item()
    assert loss_wrong > 10.0, f"Wrong prediction loss too low: {loss_wrong}"

    # Loss should always be positive
    random_logits = torch.randn(10, 4)  # 10 examples, 4 classes
    random_targets = torch.randint(0, 4, (10,))
    loss_random = loss_fn(random_logits, random_targets).item()
    assert loss_random > 0, f"Loss should be positive, got {loss_random}"

    print("  [PASS] test_loss_function")

# ===== TEST 4: Data pipeline integrity =====
def test_data_pipeline():
    """Train and test sets should not overlap."""
    np.random.seed(42)
    data = np.arange(100)
    np.random.shuffle(data)

    train = set(data[:80].tolist())  # first 80 for training
    test = set(data[80:].tolist())   # last 20 for testing
    # set() converts to a set for fast intersection checking

    overlap = train.intersection(test)
    # .intersection() finds elements in both sets
    assert len(overlap) == 0, f"Data leak! {len(overlap)} overlapping samples"

    print("  [PASS] test_data_pipeline")

# Run all tests
print("Unit Tests:")
print("-" * 40)
test_model_output_shape()
test_preprocessing_edge_cases()
test_loss_function()
test_data_pipeline()
print()
print("All unit tests passed!")
PYEOF
```

Expected output:

```
Unit Tests:
----------------------------------------
  [PASS] test_model_output_shape
  [PASS] test_preprocessing_edge_cases
  [PASS] test_loss_function
  [PASS] test_data_pipeline

All unit tests passed!
```

---

## Step 2. Behavioral tests (what the model should DO)

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import numpy as np

torch.manual_seed(42)
np.random.seed(42)

print("""
Behavioral Tests: Test WHAT the model does, not HOW it does it.

Three types (from the "CheckList" paper):

1. INVARIANCE: Small changes in input should NOT change the prediction
   "CPU at 95%" and "cpu at 95%" should both be "performance"

2. DIRECTIONAL: Certain changes SHOULD change the prediction
   Adding "disk full" to a message should push toward "storage"

3. MINIMUM FUNCTIONALITY: Basic cases the model MUST get right
   "Replication lag is 0 seconds" should be "healthy"
""")

# Simulate a trained model (using simple rules for demo)
categories = ["performance", "storage", "replication", "security"]

def mock_classifier(text):
    """Simple keyword-based classifier to demonstrate behavioral tests."""
    text_lower = text.lower()
    scores = [0, 0, 0, 0]
    # Performance keywords
    if any(w in text_lower for w in ["cpu", "slow", "query", "latency", "connection pool"]):
        scores[0] += 1
    # Storage keywords
    if any(w in text_lower for w in ["disk", "storage", "space", "wal", "bloat"]):
        scores[1] += 1
    # Replication keywords
    if any(w in text_lower for w in ["replication", "standby", "lag", "wal sender"]):
        scores[2] += 1
    # Security keywords
    if any(w in text_lower for w in ["login", "unauthorized", "ssl", "password", "access"]):
        scores[3] += 1
    if max(scores) == 0:
        return 0  # default to performance
    return scores.index(max(scores))
    # .index() returns position of the maximum value

# ===== INVARIANCE TESTS =====
print("1. INVARIANCE TESTS (same meaning, different form)")
print("-" * 55)

invariance_tests = [
    # (original, variation, expected_same_prediction)
    ("CPU usage exceeded 95%", "cpu usage exceeded 95%", True),
    ("CPU usage exceeded 95%", "CPU USAGE EXCEEDED 95%", True),
    ("Disk full on /pgdata", "Disk full on /pgdata volume", True),
    ("Replication lag is high", "  Replication lag is high  ", True),
]

passed = 0
for original, variation, should_match in invariance_tests:
    pred_orig = mock_classifier(original)
    pred_var = mock_classifier(variation)
    match = (pred_orig == pred_var) == should_match
    status = "PASS" if match else "FAIL"
    if match:
        passed += 1
    print(f"  [{status}] '{original[:35]}' vs '{variation[:35]}'")
    if not match:
        print(f"         Got: {categories[pred_orig]} vs {categories[pred_var]}")

print(f"  Invariance: {passed}/{len(invariance_tests)} passed")
print()

# ===== DIRECTIONAL TESTS =====
print("2. DIRECTIONAL TESTS (adding context should change prediction)")
print("-" * 55)

directional_tests = [
    # (base_text, added_context, expected_category_after)
    ("Server alert", " - disk space at 98%", "storage"),
    ("Server alert", " - failed login attempt", "security"),
    ("Server alert", " - replication lag 120s", "replication"),
]

passed = 0
for base, added, expected in directional_tests:
    combined = base + added
    pred = mock_classifier(combined)
    correct = categories[pred] == expected
    status = "PASS" if correct else "FAIL"
    if correct:
        passed += 1
    print(f"  [{status}] '{combined[:50]}' -> expected: {expected}, got: {categories[pred]}")

print(f"  Directional: {passed}/{len(directional_tests)} passed")
print()

# ===== MINIMUM FUNCTIONALITY TESTS =====
print("3. MINIMUM FUNCTIONALITY TESTS (must-pass cases)")
print("-" * 55)

must_pass = [
    ("CPU usage is critically high at 99%", "performance"),
    ("Disk space is completely full", "storage"),
    ("Replication lag exceeds 5 minutes", "replication"),
    ("Unauthorized access attempt detected", "security"),
    ("Slow query: sequential scan on large table", "performance"),
    ("SSL certificate expired", "security"),
]

passed = 0
for text, expected in must_pass:
    pred = mock_classifier(text)
    correct = categories[pred] == expected
    status = "PASS" if correct else "FAIL"
    if correct:
        passed += 1
    print(f"  [{status}] '{text[:50]}' -> expected: {expected}, got: {categories[pred]}")

print(f"  Minimum functionality: {passed}/{len(must_pass)} passed")
print()

total = len(invariance_tests) + len(directional_tests) + len(must_pass)
total_passed = passed  # only counting last batch for brevity
print(f"Write these tests BEFORE training. They define what 'correct' means.")
print(f"Run them after every training run to catch regressions.")
PYEOF
```

---

## Step 3. Statistical tests

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from scipy import stats

np.random.seed(42)

print("""
Statistical Tests: Is the model actually better than the baseline?

Just because Model B has 92% accuracy and Model A has 90%
doesn't mean Model B is truly better. The 2% gap could be
random chance from the test set.

Use statistical tests to know for sure.
""")

# Simulate: two models evaluated on the same 500 test examples
n_test = 500

# Model A predictions (90% accurate)
y_true = np.random.choice([0, 1], n_test, p=[0.85, 0.15])
correct_a = np.random.random(n_test) < 0.90  # 90% of the time correct
y_pred_a = np.where(correct_a, y_true, 1 - y_true)
# np.where(condition, value_if_true, value_if_false)

# Model B predictions (92% accurate)
correct_b = np.random.random(n_test) < 0.92  # 92% of the time correct
y_pred_b = np.where(correct_b, y_true, 1 - y_true)

acc_a = (y_pred_a == y_true).mean()
acc_b = (y_pred_b == y_true).mean()

print(f"Model A accuracy: {acc_a:.1%}")
print(f"Model B accuracy: {acc_b:.1%}")
print(f"Difference: {(acc_b - acc_a)*100:.1f} percentage points")
print()

# McNemar's test: are the models SIGNIFICANTLY different?
# Compare examples where the models DISAGREE
both_correct = ((y_pred_a == y_true) & (y_pred_b == y_true)).sum()
a_right_b_wrong = ((y_pred_a == y_true) & (y_pred_b != y_true)).sum()
a_wrong_b_right = ((y_pred_a != y_true) & (y_pred_b == y_true)).sum()
both_wrong = ((y_pred_a != y_true) & (y_pred_b != y_true)).sum()

print("McNemar's Contingency Table:")
print(f"  {'':>20s}  {'Model B correct':>16s}  {'Model B wrong':>14s}")
print(f"  {'Model A correct':>20s}  {both_correct:>16d}  {a_right_b_wrong:>14d}")
print(f"  {'Model A wrong':>20s}  {a_wrong_b_right:>16d}  {both_wrong:>14d}")
print()

# McNemar's test statistic
if a_right_b_wrong + a_wrong_b_right > 0:
    statistic = (abs(a_right_b_wrong - a_wrong_b_right) - 1) ** 2 / \
                (a_right_b_wrong + a_wrong_b_right)
    # Chi-squared distribution with 1 degree of freedom
    p_value = 1 - stats.chi2.cdf(statistic, df=1)
    # stats.chi2.cdf computes the cumulative distribution function
    # 1 - cdf gives the p-value (probability of seeing this difference by chance)
    print(f"McNemar's test statistic: {statistic:.3f}")
    print(f"p-value: {p_value:.4f}")
    print()
    if p_value < 0.05:
        print("p < 0.05: The difference IS statistically significant")
        print("Model B is genuinely better than Model A")
    else:
        print("p >= 0.05: The difference is NOT statistically significant")
        print("The 2% gap could be random chance - don't switch models yet")
else:
    print("Models agree on everything - no test needed")

print()
print("Rule of thumb:")
print("  p < 0.05: significant (safe to say one model is better)")
print("  p >= 0.05: not significant (could be random)")
print("  Always use statistical tests when comparing models!")
PYEOF
```

---

## What You Learned

| Test Type | What It Checks | Example |
|-----------|---------------|---------|
| Unit test | Individual components work correctly | Model output shape, loss function values |
| Invariance | Same meaning = same prediction | Uppercase vs lowercase |
| Directional | Added context changes prediction correctly | Adding "disk full" -> storage category |
| Minimum functionality | Must-pass cases | "CPU at 99%" must be "performance" |
| Statistical test | Is Model B really better than Model A? | McNemar's test on shared test set |
