# USE: Run an A/B Test with Significance and Confidence Intervals

**Tier 2 - USE phase.** In BUILD you analyzed one dataset. Now you run a proper controlled experiment: an A/B test comparing two versions of a checkout page. You will compute conversion rates, test whether the difference is real (significance) and by how much you can trust it (confidence intervals). This is the single most-requested analysis an AI/data consultant delivers.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** you finished BUILD Project 2 and read Concepts 2.4 (hypothesis testing, confidence intervals, A/B testing). You should still have a virtual environment with numpy/pandas/scipy - if not, create one as shown below.

**Goal:** decide, with evidence, whether the new checkout page (B) really converts better than the old one (A), and report the result honestly to a stakeholder.

---

## Step 1: Set up the project

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-ab-test
```

Move into it:

```bash
cd ~/use-ab-test
```

Create and activate a virtual environment:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Install the libraries:

```bash
pip install numpy scipy
```

`numpy` for the data, `scipy` for the statistical test.

---

## Step 2: Generate the A/B test data

We simulate a two-week experiment. Version A (control) converts at 12%. Version B (treatment) converts at 14% - a real but modest lift. Each visitor is a Bernoulli trial (Concepts 2.3): 1 = purchased, 0 = did not.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi make_ab_data.py
```

Press `i` and enter:

```python
import numpy as np

np.random.seed(7)

# Version A: 4000 visitors, true conversion 12%
a = np.random.binomial(1, 0.12, size=4000)
# Version B: 4000 visitors, true conversion 14%
b = np.random.binomial(1, 0.14, size=4000)

np.save("group_a.npy", a)
np.save("group_b.npy", b)
print(f"Group A: {a.sum()} conversions of {len(a)} visitors")
print(f"Group B: {b.sum()} conversions of {len(b)} visitors")
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python make_ab_data.py
```

Expected output (yours will differ):

```
Group A: 476 conversions of 4000 visitors
Group B: 582 conversions of 4000 visitors
```

---

## Step 3: Write the A/B analysis

The plan: compute each group's conversion rate, run a two-proportion test for significance, and build a 95% confidence interval on the difference so we can say how big the lift really is.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi ab_test.py
```

Press `i` and enter:

```python
import numpy as np
from scipy import stats

a = np.load("group_a.npy")
b = np.load("group_b.npy")

n_a, n_b = len(a), len(b)
conv_a, conv_b = a.sum(), b.sum()
rate_a, rate_b = a.mean(), b.mean()

print(f"Version A: {rate_a:.3%} conversion ({conv_a}/{n_a})")
print(f"Version B: {rate_b:.3%} conversion ({conv_b}/{n_b})")
print(f"Observed lift: {(rate_b - rate_a):.3%}")

# --- Significance test (two-proportion z-test) ---
# Null hypothesis: the two versions convert at the same rate.
pooled = (conv_a + conv_b) / (n_a + n_b)
se_pooled = np.sqrt(pooled * (1 - pooled) * (1 / n_a + 1 / n_b))
z = (rate_b - rate_a) / se_pooled
p_value = 2 * (1 - stats.norm.cdf(abs(z)))   # two-sided p-value
print(f"\nz-statistic: {z:.3f}")
print(f"p-value: {p_value:.5f}")
if p_value < 0.05:
    print("SIGNIFICANT: reject the null. B beats A by more than luck would explain.")
else:
    print("NOT SIGNIFICANT: cannot rule out luck. Keep A or gather more data.")

# --- 95% confidence interval on the difference in rates ---
# This tells us the plausible RANGE of the true lift, not just a point.
se_diff = np.sqrt(rate_a * (1 - rate_a) / n_a + rate_b * (1 - rate_b) / n_b)
diff = rate_b - rate_a
lo, hi = diff - 1.96 * se_diff, diff + 1.96 * se_diff
print(f"\n95% CI on the lift: [{lo:.3%}, {hi:.3%}]")
if lo > 0:
    print("The entire interval is positive, so we are confident B is genuinely better.")
else:
    print("The interval crosses zero, so we cannot be confident B is better.")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 4: Run the A/B test

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python ab_test.py
```

Expected output (yours will differ):

```
Version A: 11.900% conversion (476/4000)
Version B: 14.550% conversion (582/4000)
Observed lift: 2.650%

z-statistic: 3.498
p-value: 0.00047
SIGNIFICANT: reject the null. B beats A by more than luck would explain.

95% CI on the lift: [1.166%, 4.134%]
The entire interval is positive, so we are confident B is genuinely better.
```

Read it like a consultant: version B converts about 2.7 percentage points higher. The p-value of 0.0005 is well below 0.05, so the difference is unlikely to be luck. The 95% confidence interval `[1.2%, 4.1%]` is entirely above zero, so we are confident the lift is real - but notice it could be as small as 1.2% or as large as 4.1%. That range is the honest truth you owe the stakeholder.

---

## Step 5: Explore - what if the sample were smaller?

The confidence interval width depends on sample size. Prove it to yourself. Open the data generator:

```bash
vi make_ab_data.py
```

Press `i`, change both `size=4000` to `size=400` (a tenth of the visitors). Press `Esc`, type `:wq`, press Enter. Regenerate and rerun:

```bash
python make_ab_data.py
```

```bash
python ab_test.py
```

Expected output (yours will differ):

```
...
p-value: 0.1803
NOT SIGNIFICANT: cannot rule out luck. Keep A or gather more data.

95% CI on the lift: [-1.499%, 7.999%]
The interval crosses zero, so we cannot be confident B is better.
```

Same true effect, but with 400 visitors instead of 4000 the interval is much wider and crosses zero - you can no longer confidently tell B from A. This is why you decide sample size **before** running a test (Concepts 2.4). A "failed" test is often just an underpowered one.

Restore `size=4000` in `make_ab_data.py` when done, then regenerate:

```bash
vi make_ab_data.py
```

Change both back to `size=4000`, save with `:wq`, then:

```bash
python make_ab_data.py
```

---

## Step 6: Write the stakeholder recommendation

Open a note file:

```bash
vi recommendation.md
```

Press `i` and write a short recommendation using YOUR numbers. Structure:

```markdown
# A/B Test Result: New Checkout Page

Recommendation: SHIP version B.

- Version B converted at 14.6% vs 11.9% for the current page.
- That is a lift of about 2.7 percentage points (a ~22% relative improvement).
- The result is statistically significant (p = 0.0005), so it is very unlikely
  to be chance.
- We are 95% confident the true lift is between 1.2% and 4.1%. Even the low end
  is a real gain, so shipping B is safe.

Caveat: the lift could be as small as 1.2%. If a decision hinges on the exact
size, run the test another week to narrow the interval.
```

Press `Esc`, type `:wq`, press Enter.

---

## What you practiced

- Framed a business question as a null hypothesis and a controlled A/B test.
- Computed conversion rates and a two-proportion significance test, interpreting the p-value correctly.
- Built a confidence interval on the lift and read it as a range of trust, not a single number.
- Showed yourself how sample size drives confidence, and why underpowered tests mislead.
- Turned the statistics into a clear, caveated recommendation a stakeholder can act on.

Next USE lab: embedding distances and cosine similarity on real sentences - a preview of the retrieval systems you build in later tiers.
