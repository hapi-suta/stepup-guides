# SURVIVE: Misleading Stats - Sampling Bias in a Retention Study

## Scenario

Your product team is celebrating. An analyst just ran the numbers and reported:

> "Users who use Feature X have 30% higher retention (p < 0.001)! We should
> ship Feature X to everyone."

Leadership wants to act on this today. Before anyone ships anything, you have
been asked to sanity-check the analysis. Something feels too good to be true.

Your job in this SURVIVE scenario:
1. Detect that the result is suspicious.
2. Diagnose why the "significant" result is really an artifact of sampling
   (selection) bias.
3. Fix it by producing a corrected, honest analysis and a written finding.

The scenario has already been injected into `~/survive-misleading-stats`.

This runbook uses the SUTA 3-layer structure:
- Layer 1: Detect (what is the symptom)
- Layer 2: Diagnose (what is the root cause)
- Layer 3: Fix and verify

Throughout, remember: a low p-value tells you a difference is unlikely to be
pure chance. It does NOT tell you the two groups were comparable in the first
place. That is the whole trap here.

---

## Layer 1: Detect (the symptom)

### Step 1.1 - Go to the working directory

On your lab server, as ec2-user:

```
cd ~/survive-misleading-stats
```

This moves you into the folder where the injected dataset and scripts live.
`cd` means "change directory".

### Step 1.2 - See what files are there

Still on your lab server, as ec2-user:

```
ls -l
```

`ls` lists files. The `-l` flag shows the long format (permissions, size,
name) so you can confirm the pieces of the scenario are present.

Expected output (yours will differ):

```
-rw-r--r--. 1 ec2-user ec2-user  98543 Jul 25 14:02 customers.csv
-rw-r--r--. 1 ec2-user ec2-user   1120 Jul 25 14:02 generate_data.py
-rw-r--r--. 1 ec2-user ec2-user    980 Jul 25 14:02 naive_analysis.py
drwxrwxr-x. 5 ec2-user ec2-user     74 Jul 25 14:02 venv
...
```

### Step 1.3 - Activate the Python environment

Still on your lab server, as ec2-user:

```
source venv/bin/activate
```

`source` runs the activation script in your current shell. After this, the
`python` command uses the project virtual environment where numpy, pandas, and
scipy are installed. Your prompt will now start with `(venv)`.

Expected output (yours will differ):

```
(venv) [ec2-user@ip-10-0-1-23 survive-misleading-stats]$
```

### Step 1.4 - Re-run the naive analysis to see the reported result

Still on your lab server, as ec2-user (inside the venv):

```
python naive_analysis.py
```

`python naive_analysis.py` runs the analyst's script. It does a raw two-sample
t-test comparing retention for Feature-X users versus everyone else.

Expected output (yours will differ):

```
=== NAIVE RETENTION ANALYSIS ===
Feature-X retention rate:   0.735
Non-Feature-X retention:    0.505
Relative lift:              45.5%
t-statistic:                18.6
p-value:                    1.2e-70
CONCLUSION: Feature X drives a HUGE, highly significant lift in
retention (p < 0.001). SHIP IT to everyone!
```

Symptom confirmed: the script reports a large lift and a tiny p-value, and
tells you to ship. This is exactly the claim leadership is excited about.

An enormous effect (45% lift) with an almost impossibly small p-value on
observational data should raise your eyebrows, not lower your guard. Real
product features rarely move retention that much. This smell is your cue to
dig into HOW the two groups were formed.

---

## Layer 2: Diagnose (the root cause)

The p-value is real math on the data given. The problem is upstream: the two
groups being compared are not comparable. We need to inspect how customers
ended up in the "Feature X" group.

### Step 2.1 - Open the data generator to understand how groups were formed

Still on your lab server, as ec2-user:

```
vi generate_data.py
```

`vi` opens the file in the vi editor so you can read how the dataset was
built. Look for the lines that decide `uses_feature_x`. To quit vi without
changing anything, type `:q!` and press Enter.

You will see that Feature X was only offered to customers with
`tenure >= 24` months, and that base retention rises with tenure. That is the
tell: the feature was never randomly assigned.

### Step 2.2 - Inspect the two groups directly with a quick check

Instead of trusting the code comments, prove it from the data. Create a small
inspection script.

Still on your lab server, as ec2-user:

```
vi inspect_groups.py
```

In vi, press `i` to enter insert mode, then type the following. Press `Esc`,
then type `:wq` and press Enter to save and quit.

```python
import pandas as pd

df = pd.read_csv("customers.csv")

for label, sub in df.groupby("uses_feature_x"):
    name = "Feature-X users" if label == 1 else "Non-users"
    print(name)
    print("  count:              ", len(sub))
    print("  mean tenure_months: ", round(sub.tenure_months.mean(), 1))
    print("  min tenure_months:  ", int(sub.tenure_months.min()))
    print("  retention rate:     ", round(sub.retained.mean(), 3))
    print()
```

This groups the customers by whether they use Feature X and prints the average
tenure and minimum tenure for each group.

### Step 2.3 - Run the inspection

Still on your lab server, as ec2-user (inside the venv):

```
python inspect_groups.py
```

Expected output (yours will differ):

```
Feature-X users
  count:               986
  mean tenure_months:  36.2
  min tenure_months:   24
  retention rate:      0.735

Non-users
  count:               3014
  mean tenure_months:  20.4
  min tenure_months:   1
  retention rate:      0.505
```

Root cause found. The two groups are NOT comparable:
- Feature-X users have a minimum tenure of 24 months. No new customer is in
  that group.
- Non-users span the full range, including brand-new customers.
- Feature-X users are much older on average (36 vs 20 months).

Older customers retain better no matter what. So the naive comparison is
really measuring "old customers vs a mix that includes new customers", not
"Feature X vs no Feature X". This is textbook sampling / selection bias: the
sample that got Feature X was self-selected (and gated) rather than randomized.
Tenure is a confounder driving both group membership and retention.

---

## Layer 3: Fix and verify

The honest way to isolate the feature effect is to compare like-with-like.
We stratify: only compare customers who were actually eligible for Feature X
(tenure >= 24 months), so both groups are drawn from the same population.
(In the real world you would run a randomized A/B test. Stratification is the
best correction we can make on the data we already have.)

### Step 3.1 - Write the corrected analysis

Still on your lab server, as ec2-user:

```
vi corrected_analysis.py
```

In vi, press `i` to enter insert mode, then type the following. Press `Esc`,
then type `:wq` and press Enter to save and quit.

```python
"""
Corrected analysis. Compares retention like-with-like by restricting to
customers who were ELIGIBLE for Feature X (tenure >= 24 months), then
running the t-test only within that matched population.
"""
import pandas as pd
from scipy import stats

df = pd.read_csv("customers.csv")

# Only customers who could ever have used Feature X. This removes the
# tenure confounder by comparing within the same eligible population.
eligible = df[df.tenure_months >= 24].copy()

x_users = eligible[eligible.uses_feature_x == 1]["retained"]
non_users = eligible[eligible.uses_feature_x == 0]["retained"]

x_rate = x_users.mean()
non_rate = non_users.mean()
lift = (x_rate - non_rate) / non_rate * 100.0

t_stat, p_value = stats.ttest_ind(x_users, non_users, equal_var=False)

print("=== CORRECTED (STRATIFIED / MATCHED) RETENTION ANALYSIS ===")
print("Restricted to eligible customers: tenure >= 24 months")
print(f"Eligible Feature-X users:   {len(x_users)}")
print(f"Eligible non-users:         {len(non_users)}")
print(f"Feature-X retention rate:   {x_rate:.3f}")
print(f"Non-Feature-X retention:    {non_rate:.3f}")
print(f"Relative lift:              {lift:.1f}%")
print(f"t-statistic:                {t_stat:.3f}")
print(f"p-value:                    {p_value:.3f}")
print()
if p_value < 0.05 and abs(lift) > 5:
    print("CONCLUSION: A real effect may remain after matching. Recommend a")
    print("randomized A/B test to confirm before shipping.")
else:
    print("CONCLUSION: Once we compare like-with-like (same tenure band), the")
    print("Feature X effect is small and NOT significant. The original 'huge")
    print("lift' was sampling bias (tenure confounding), not a real feature")
    print("effect. Do NOT ship on the basis of the original analysis. A")
    print("randomized A/B test is required to measure the true effect.")
```

### Step 3.2 - Run the corrected analysis

Still on your lab server, as ec2-user (inside the venv):

```
python corrected_analysis.py
```

`python corrected_analysis.py` runs your matched comparison. Because both
groups now have tenure >= 24 months, the tenure confounder is removed.

Expected output (yours will differ):

```
=== CORRECTED (STRATIFIED / MATCHED) RETENTION ANALYSIS ===
Restricted to eligible customers: tenure >= 24 months
Eligible Feature-X users:   986
Eligible non-users:         654
Feature-X retention rate:   0.735
Non-Feature-X retention:    0.727
Relative lift:              1.1%
t-statistic:                0.42
p-value:                    0.674
CONCLUSION: Once we compare like-with-like (same tenure band), the
Feature X effect is small and NOT significant. The original 'huge
lift' was sampling bias (tenure confounding), not a real feature
effect. Do NOT ship on the basis of the original analysis. A
randomized A/B test is required to measure the true effect.
```

The lift collapsed from ~45% to ~1%, and the p-value went from ~1e-70 to well
above 0.05. The dramatic "significant" result was an illusion created by
comparing old customers to new customers.

### Step 3.3 - Write your corrected findings

Now document the honest conclusion so leadership does not ship on bad data.

Still on your lab server, as ec2-user:

```
vi corrected_findings.md
```

In vi, press `i` to enter insert mode, then type your write-up. It MUST
explain that the original result was sampling bias. A template you can adapt:

```markdown
# Corrected Findings: Feature X and Retention

## Original claim
Feature-X users showed ~45% higher retention with p < 0.001, and the team
proposed shipping Feature X to everyone.

## Why the original result is wrong: sampling bias
Feature X was only offered to long-tenure customers (tenure >= 24 months).
Long-tenure customers retain better regardless of any feature. The naive
comparison therefore mixed the feature effect with a tenure effect. The two
groups were not comparable, so this is selection / sampling bias, not causation.
Tenure is a confounding variable.

## Corrected analysis
I restricted the comparison to eligible customers only (tenure >= 24 months),
so Feature-X users and non-users came from the same population (stratified /
matched comparison). After controlling for tenure:
- Relative lift dropped from ~45% to ~1%.
- p-value rose from ~1e-70 to ~0.67 (not significant).

## Honest conclusion
There is no evidence that Feature X improves retention once we compare
like-with-like. The original "significant" result was an artifact of sampling
bias. Do NOT ship based on the original analysis. To measure the true causal
effect, run a randomized A/B test where Feature X is randomly assigned across
all tenure levels.
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

### Step 3.4 - Verify your work

Still on your lab server, as ec2-user (inside the venv):

```
ls corrected_analysis.py corrected_findings.md
```

`ls` with both filenames confirms both deliverables exist. If either is
missing, you will see a "No such file" error and should redo that step.

Expected output (yours will differ):

```
corrected_analysis.py  corrected_findings.md
```

Then run the scenario validator from the survive folder to confirm you passed.
The exact path depends on where this scenario was placed on your server, for
example:

```
bash ~/survive-misleading-stats/validate.sh
```

Expected output (yours will differ):

```
PASS: corrected_analysis.py exists
PASS: corrected_findings.md exists and mentions bias
PASS: corrected_analysis.py runs and reports a stratified/matched comparison
ALL CHECKS PASSED
```

### Step 3.5 - Leave the environment

Still on your lab server, as ec2-user:

```
deactivate
```

`deactivate` exits the Python virtual environment and returns your shell to
normal. The `(venv)` prefix will disappear from your prompt.

---

## Key takeaways

- A tiny p-value does not mean the finding is trustworthy. It only means the
  observed difference is unlikely under pure chance FOR THE DATA YOU FED IN.
- If groups were not randomly assigned, they may differ on a hidden variable
  (a confounder). Here, tenure drove both feature access and retention.
- Always ask: how did subjects end up in each group? If a group is gated or
  self-selected, you have sampling / selection bias.
- The fix on existing data is to compare like-with-like (stratify or match on
  the confounder). The gold-standard fix going forward is a randomized A/B test.

Prof. Happy (SUTA Labs)
