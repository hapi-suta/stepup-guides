# SURVIVE: Correlation Is Not Causation

## The situation

A stakeholder (the VP of Customer Success) looked at your company's customer
data, noticed that customers who attend more webinars have higher revenue, and
concluded that webinars CAUSE revenue. They now want to spend 250,000 dollars
mandating webinars for everyone, expecting a 40 percent revenue boost.

The correlation in the data is real. The causal conclusion is wrong. Your job
is to catch the error, prove it with data, and correct the write-up before the
company wastes money.

This connects to Concepts 2.4 (Correlation vs Causation and Confounding
Variables).

Everything below runs on your lab server, as ec2-user.

---

## Layer 1: Detect

First, activate the Python environment that the injector created. A virtual
environment (venv) is an isolated Python setup so the packages you install do
not affect the rest of the system.

On your lab server, as ec2-user, move into the working directory:

```
cd ~/survive-corr-causation
```

Activate the venv. The `source` command runs the activate script in your
current shell so `python` points at the isolated environment:

```
source .venv/bin/activate
```

Now read the stakeholder's claim. The `cat` command prints a file to your
screen:

```
cat stakeholder_claim.md
```

Expected output (yours will differ):

```
# Proposal: Mandate Webinars to Boost Revenue
...
## The claim
The data proves that webinars drive revenue.
## The decision
We will mandate that ALL customers attend at least 5 webinars this quarter.
Based on the correlation, this should boost revenue by roughly 40 percent.
...
```

Read the language carefully. The words "proves", "drive", and "boost" are
CAUSAL claims - they say webinars MAKE revenue go up. But all the stakeholder
actually measured is a CORRELATION - the two numbers move together. Correlation
alone never proves that one thing causes the other.

Now reproduce what the stakeholder saw. Run their naive analysis. `python
analysis.py` runs the analysis script the injector wrote:

```
python analysis.py
```

Expected output (yours will differ):

```
=== Naive analysis (what the stakeholder saw) ===
Rows analyzed: 800
Raw correlation (webinars_attended vs revenue): 0.7...
Naive conclusion: 'Webinars are strongly correlated with revenue,
therefore webinars CAUSE revenue. Mandate more webinars.'
```

The raw correlation really is strong (above 0.6). So the stakeholder is not
lying about the numbers. The problem is the LEAP from "correlated" to "causes".

---

## Layer 2: Diagnose

### Why a correlation can be real but not causal

When two variables move together, there are several possible explanations:

- A causes B (webinars cause revenue).
- B causes A (revenue causes webinars).
- A third, hidden variable causes BOTH (a confounder, also called a lurking
  variable).
- Pure coincidence.

Here the hidden third variable is COMPANY SIZE. Big companies have more staff
and budget, so they attend more webinars AND they spend more money. Company
size drives both. Webinars and revenue only look linked because both are tied
to size.

The way to test this is to hold the confounder constant. If you look only
within a single company-size group and the webinar-revenue link disappears,
that tells you the raw link was an illusion created by size. This collapse of a
relationship once you control for a third variable is the flavor of Simpson's
paradox, and it is the fingerprint of a confounder.

### Prove it with data

You will write a short script that (a) shows the strong raw correlation, then
(b) stratifies (splits) the data by company-size bucket and re-checks the
correlation inside each bucket.

On your lab server, as ec2-user, open a new file with vi. `vi` is the text
editor; the argument is the filename to create:

```
vi confound_check.py
```

In vi, press `i` to enter insert mode, then type (or paste) the following:

```python
"""
Show that the webinar-revenue correlation is caused by a confounder:
company size. Raw correlation is strong; within each size bucket it collapses.
"""
import pandas as pd

df = pd.read_csv("customers.csv")

# (a) The raw correlation the stakeholder relied on.
raw_corr = df["webinars_attended"].corr(df["revenue"])
print("Raw correlation (all customers): {:.3f}".format(raw_corr))
print()

# (b) Stratify by company size and re-check the correlation in each group.
# If webinars truly caused revenue, the link would survive inside each bucket.
print("Correlation WITHIN each company-size bucket:")
for label, group in df.groupby("company_size_label"):
    if len(group) > 2:
        within = group["webinars_attended"].corr(group["revenue"])
        print("  {:<12} n={:<4} corr={:.3f}".format(label, len(group), within))

print()
print("Reading: the raw correlation is strong, but inside each size bucket")
print("it is near zero. Company size drove both webinars and revenue.")
print("The webinar-revenue link is confounded, not causal.")
```

Now save and quit vi. Press `Esc` to leave insert mode, then type `:wq` and
press Enter. `:wq` means write (save) and quit:

```
:wq
```

Run your script. `python confound_check.py` executes it:

```
python confound_check.py
```

Expected output (yours will differ):

```
Raw correlation (all customers): 0.7...

Correlation WITHIN each company-size bucket:
  enterprise   n=2..  corr=0.0...
  large        n=2..  corr=-0.0...
  medium       n=1..  corr=0.0...
  small        n=2..  corr=0.0...

Reading: the raw correlation is strong, but inside each size bucket
it is near zero. Company size drove both webinars and revenue.
The webinar-revenue link is confounded, not causal.
```

This is the proof. The overall correlation is strong (above 0.6), but once you
compare only companies of the same size, the correlation between webinars and
revenue drops to roughly zero. That means webinars are not what moves revenue -
company size is.

---

## Layer 3: Fix

Now write the corrected analysis for the stakeholder. It must make three
points: correlation is not causation, name the confounder (company size), and
recommend how to actually test the causal question (a randomized experiment /
A/B test) before spending money.

On your lab server, as ec2-user, open the corrected write-up with vi:

```
vi corrected_claim.md
```

Press `i` to enter insert mode, then adapt this template (change wording to
match what you saw, keep the three required points):

```markdown
# Corrected Analysis: Webinars and Revenue

## What the original claim got wrong

The proposal treated a correlation as causation. Yes, customers who attend
more webinars have higher revenue (raw correlation above 0.6). But correlation
is not causation. A strong correlation does not prove that webinars cause
revenue.

## The real driver: a confounding variable

Company size is a confounder (a lurking variable) that drives BOTH webinar
attendance and revenue. Larger companies have more staff and budget, so they
attend more webinars AND spend more.

I verified this with confound_check.py: when I stratify by company size, the
correlation between webinars and revenue collapses to near zero inside each
size bucket. That means the raw correlation was an artifact of company size,
not evidence that webinars cause revenue.

## Recommendation before spending money

Do NOT mandate webinars based on this correlation. Instead, run a randomized
controlled experiment (an A/B test):

- Randomly assign customers to a webinar group and a no-webinar (control)
  group.
- Randomization balances company size (and other confounders) across both
  groups.
- Compare revenue between the groups after the test window.

Only if the webinar group shows higher revenue than the control group do we
have real evidence that webinars cause revenue. Until then, the 250,000 dollar
mandate is not justified.
```

Save and quit vi. Press `Esc`, then type `:wq` and press Enter:

```
:wq
```

---

## Verify

Run the validator to confirm you caught the confound and corrected the claim.
`bash validate.sh` runs the check script:

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: correlation-not-causation ===
OK:   corrected_claim.md exists
OK:   corrected_claim.md mentions causation
OK:   corrected_claim.md names a corrective concept (confounder / randomized test / experiment)
OK:   confound_check.py exists
OK:   confound_check.py ran successfully (exit 0)
----------------------------------------------------
RESULT: PASS - you caught the confound and corrected the claim.
```

When you are done, you can leave the virtual environment. `deactivate` returns
your shell to normal:

```
deactivate
```

## What you practiced

- Spotting causal language ("proves", "drives") layered on top of a mere
  correlation.
- Identifying a confounding / lurking variable (company size).
- Demonstrating the confound by stratifying and watching the correlation
  collapse within groups (Concepts 2.4).
- Recommending a randomized experiment (A/B test) to answer the causal
  question before committing budget.
