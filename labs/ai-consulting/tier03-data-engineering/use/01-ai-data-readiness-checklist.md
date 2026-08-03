# USE: The AI Data Readiness Assessment Checklist

**Tier 3 - USE phase.** In BUILD you built a pipeline that produces clean data. Now you build the consultant artifact clients pay the most for before any model is written: a written assessment of whether an organization's data is actually ready for AI. You will apply a ten-point checklist to a real sample dataset on the box and write a verdict a client can act on.

**Validated on:** CentOS Stream 9, Python 3.12, PostgreSQL (labdb), on 2026-07-25.

**Prerequisite:** you finished BUILD Project 3 and read Concepts 3.4 (data quality) and 3.5 (data engineering). You should have a virtual environment with pandas - if not, create one as shown below.

**Goal:** produce `readiness_assessment.md`, a professional deliverable that scores a dataset on ten readiness dimensions and gives a go / fix-first / no-go verdict with reasons. This is the document you hand a client in week one.

---

## The ten dimensions of AI data readiness

Before touching a keyboard, know the checklist. For each dimension you ask a question and record a status (Ready / Gaps / Blocker).

1. **Ownership** - who owns this data and can authorize its use? No clear owner = no project.
2. **Availability** - can you actually get the data reliably, at the volume and frequency a model needs?
3. **Quality** - the six dimensions from Concepts 3.4: complete, accurate, consistent, timely, valid, unique.
4. **Privacy** - does it contain personal or sensitive data (PII/PHI) that must be protected?
5. **Permissions** - are you legally allowed to use it for AI/training? (consent, terms of service, licensing)
6. **Documentation** - is there a schema, a data dictionary, known meanings for each field?
7. **Retention** - how long is data kept, and is enough history available to train on?
8. **Integration** - can it be joined with the other data a model needs, on a shared key?
9. **Labeling** - for supervised learning, do you have labels (the target/answer) or must they be created?
10. **Residency** - are there legal constraints on where the data must physically live?

---

## Step 1: Set up the project

On your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
mkdir -p ~/use-readiness
```

Move into it:

```bash
cd ~/use-readiness
```

Create and activate a virtual environment:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Install pandas:

```bash
pip install pandas
```

---

## Step 2: Generate a realistic sample dataset

We create a customer-support dataset - the kind a client hands you saying "can we build an AI to auto-triage tickets?" It has the messiness you will assess: some PII, missing labels, stale rows, and inconsistent fields.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi make_sample.py
```

Press `i`, then enter:

```python
import numpy as np
import pandas as pd

rng = np.random.default_rng(7)
n = 500

df = pd.DataFrame({
    "ticket_id": np.arange(1, n + 1),
    "customer_email": [f"user{ i }@example.com" for i in rng.integers(1, 200, size=n)],
    "customer_ssn": [f"{rng.integers(100,999)}-{rng.integers(10,99)}-{rng.integers(1000,9999)}" for _ in range(n)],
    "opened_at": pd.to_datetime("2024-01-01") + pd.to_timedelta(rng.integers(0, 900, size=n), unit="D"),
    "channel": rng.choice(["email", "Email", "chat", "phone", "PHONE"], size=n),
    "message": rng.choice(["cannot login", "billing question", "app crashed", ""], size=n, p=[0.3, 0.3, 0.3, 0.1]),
    "category": rng.choice(["Login", "Billing", "Bug", None], size=n, p=[0.25, 0.25, 0.25, 0.25]),
})

# a few duplicates and a data-entry glitch
df = pd.concat([df, df.iloc[:8]], ignore_index=True)

df.to_csv("support_tickets.csv", index=False)
print(f"Wrote support_tickets.csv: {len(df)} rows, {df['category'].isna().sum()} missing labels")
```

Press `Esc`, type `:wq`, press Enter. Then generate it:

```bash
python make_sample.py
```

Expected output (yours will differ):

```
Wrote support_tickets.csv: 508 rows, 130 missing labels
```

---

## Step 3: Write the assessment script

This script computes the measurable parts of the checklist (quality, privacy signals, labeling, integration keys, timeliness) so your verdict is evidence-based, not a guess.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi assess.py
```

Press `i`, then enter:

```python
import re
import pandas as pd

df = pd.read_csv("support_tickets.csv", parse_dates=["opened_at"])
report = []

def line(s): report.append(s)

line("=" * 55)
line("AI DATA READINESS - MEASURED SIGNALS")
line("=" * 55)
line(f"Rows: {len(df)}  Columns: {list(df.columns)}")

# 3. Quality: completeness
line("\n-- Completeness (% missing per column) --")
for col, pct in (df.isna().mean() * 100).round(1).items():
    flag = "  <-- HIGH" if pct > 20 else ""
    line(f"  {col:16s} {pct:5.1f}%{flag}")

# 3. Quality: uniqueness
dupes = df.duplicated(subset=["ticket_id"]).sum()
line(f"\n-- Uniqueness -- duplicate ticket_id rows: {dupes}")

# 3. Quality: consistency (channel case chaos)
line("\n-- Consistency -- distinct 'channel' values (should be few):")
line("  " + ", ".join(sorted(df["channel"].astype(str).unique())))

# 4. Privacy: scan for PII-looking columns
line("\n-- Privacy (PII scan) --")
ssn_like = df.apply(lambda c: c.astype(str).str.match(r"^\d{3}-\d{2}-\d{4}$").mean() > 0.5)
email_like = df.apply(lambda c: c.astype(str).str.contains("@").mean() > 0.5)
for col in df.columns:
    tags = []
    if ssn_like.get(col): tags.append("SSN")
    if email_like.get(col): tags.append("EMAIL")
    if tags:
        line(f"  {col:16s} PII: {', '.join(tags)}  <-- must mask/remove before AI use")

# 7/timeliness
age_days = (pd.Timestamp("2026-07-25") - df["opened_at"]).dt.days
line(f"\n-- Timeliness -- oldest row: {age_days.max()} days, newest: {age_days.min()} days")

# 9. Labeling
missing_labels = df["category"].isna().sum()
line(f"\n-- Labeling -- target column 'category' missing on {missing_labels} of {len(df)} rows "
     f"({missing_labels/len(df)*100:.0f}%)")

# 8. Integration
line(f"\n-- Integration -- candidate join key 'customer_email' present: {df['customer_email'].notna().all()}")

text = "\n".join(report)
print(text)
open("measured_signals.txt", "w").write(text + "\n")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 4: Run the assessment

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python assess.py
```

Expected output (yours will differ):

```
=======================================================
AI DATA READINESS - MEASURED SIGNALS
=======================================================
Rows: 508  Columns: ['ticket_id', 'customer_email', 'customer_ssn', 'opened_at', 'channel', 'message', 'category']

-- Completeness (% missing per column) --
  ticket_id          0.0%
  customer_email     0.0%
  customer_ssn       0.0%
  opened_at          0.0%
  channel            0.0%
  message            0.0%
  category          25.6%  <-- HIGH

-- Uniqueness -- duplicate ticket_id rows: 8

-- Consistency -- distinct 'channel' values (should be few):
  Email, PHONE, chat, email, phone

-- Privacy (PII scan) --
  customer_email   PII: EMAIL  <-- must mask/remove before AI use
  customer_ssn     PII: SSN  <-- must mask/remove before AI use

-- Timeliness -- oldest row: 936 days, newest: 41 days

-- Labeling -- target column 'category' missing on 130 of 508 rows (26%)

-- Labeling -- ... 
-- Integration -- candidate join key 'customer_email' present: True
```

You now have hard evidence: 26% of labels missing, live SSNs and emails present, `channel` in five inconsistent forms, 8 duplicates, and history back 936 days.

---

## Step 5: Write the readiness assessment - the deliverable

Now turn the signals into the artifact a client reads. This is the whole point of the exercise: a written verdict, per dimension, with a status and a recommendation.

Still on your **lab server**, as **ec2-user**, open the deliverable:

```bash
vi readiness_assessment.md
```

Press `i`, then enter this assessment. It is written for a non-technical client and uses the placeholders [CLIENT] and [TEAM NAME] per house style.

```markdown
# AI Data Readiness Assessment
**Dataset:** customer support tickets (support_tickets.csv, 508 rows)
**Prepared for:** [CLIENT]
**Prepared by:** [TEAM NAME]
**Date:** 2026-07-25
**Proposed use:** train a model to auto-triage tickets into a category (Login / Billing / Bug)

## Verdict: FIX FIRST (not yet ready, but close)
The data has the right shape for auto-triage, but three issues must be resolved
before any model is trained: missing labels, live personal data, and duplicates.
Estimated remediation: 1-2 weeks. Do not train on this data as-is.

## Scorecard
| # | Dimension     | Status   | Notes |
|---|---------------|----------|-------|
| 1 | Ownership     | GAPS     | No named data owner on file - confirm who authorizes use. |
| 2 | Availability  | READY    | Full export provided; 508 rows, refreshable from source. |
| 3 | Quality       | GAPS     | channel inconsistent (5 forms), 8 duplicate ticket_ids. |
| 4 | Privacy       | BLOCKER  | Live SSNs and emails present. Must mask/remove before use. |
| 5 | Permissions   | GAPS     | Confirm customer consent covers AI/training use. |
| 6 | Documentation | GAPS     | No data dictionary; 'category' meanings assumed, not defined. |
| 7 | Retention     | READY    | ~2.5 years of history - ample for training. |
| 8 | Integration   | READY    | customer_email present on all rows as a join key. |
| 9 | Labeling      | BLOCKER  | 26% of rows have no category label - cannot train supervised on them. |
| 10| Residency     | GAPS     | Confirm whether tickets contain EU customers (GDPR residency). |

## The three blockers, in plain terms
1. **Personal data (Privacy).** The file contains real Social Security Numbers and
   email addresses. These cannot go into a model or leave [CLIENT]'s environment
   as-is. Fix: drop customer_ssn entirely (not needed for triage) and hash
   customer_email if it is needed as a key (Concepts 3.5).
2. **Missing labels (Labeling).** One in four tickets has no category. A supervised
   model learns from labeled examples, so these 130 rows are unusable for training
   until labeled. Fix: have [TEAM NAME] label a sample, or exclude unlabeled rows
   from the training set and note the reduced volume.
3. **Duplicates (Quality).** Eight tickets appear twice, which would over-weight
   those examples. Fix: de-duplicate on ticket_id (keep first) - one line in the
   pipeline you already built.

## Recommended path
Run the data through a cleaning pipeline (like Project 3) that: drops SSNs, hashes
emails, standardizes channel to lowercase, de-duplicates on ticket_id, and splits
labeled from unlabeled rows. Re-run this assessment; when Privacy, Labeling, and
Quality reach READY, the dataset is go for a triage model.

Prof. Happy (SUTA Labs)
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 6: Verify your deliverable reads well

Still on your **lab server**, as **ec2-user**:

```bash
head -20 readiness_assessment.md
```

`head -20` prints the first 20 lines so you can confirm the verdict and scorecard are there.

Expected output (yours will differ):

```
# AI Data Readiness Assessment
**Dataset:** customer support tickets (support_tickets.csv, 508 rows)
**Prepared for:** [CLIENT]
...
## Verdict: FIX FIRST (not yet ready, but close)
```

---

## What you produced

You now have `readiness_assessment.md` - a real consultant deliverable that scores a dataset across ten AI-readiness dimensions, backs the scores with measured evidence from `assess.py`, and gives a clear verdict with an actionable remediation path. This document, produced in week one, is how you save a client from spending three months building a model on data that was never ready.

The measured-signals approach matters: a readiness assessment full of opinions is worthless; one backed by "26% of labels missing, verified by script" is the artifact clients trust and pay for. In USE 3.2 you will add automated validation checks so these signals are enforced on every batch, not just assessed once.
