# USE: Score a Real Vendor and Write the Recommendation

**Tier 12 - USE phase.** In BUILD you assembled the vendor questionnaire. Now you use
it against a real AI vendor, produce a weighted score, flag any dealbreakers, and
write the recommendation a client would act on. This is core consulting work: turning
a vendor's documentation into a defensible buy / do-not-buy decision. Mostly research
and reasoning, with one small runnable scorer so the recommendation rests on a number.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** you finished the Tier 12 BUILD (you have
`~/governance-toolkit/05-vendor-questionnaire.md`). You have read Concepts 12.6. Pick a
real AI vendor to assess - use a major model provider whose documentation is public
(for example Anthropic, OpenAI, AWS Bedrock, Azure OpenAI, or Google Vertex AI).

**Goal:** a completed vendor questionnaire for one real vendor, a weighted score
computed in Python, and a written recommendation with the contract terms you would
require before signing.

**A note on data honesty:** vendor terms and certifications change. Fill in the
answers from the vendor's own current documentation at the time you assess, and date
your assessment. Do not rely on memory - go read the current data-usage and terms
pages.

---

## Step 1: Set up the working folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-vendor-scoring
```

Move into it:

```bash
cd ~/use-vendor-scoring
```

Copy the blank questionnaire in under a real filename (replace VENDOR):

```bash
cp ~/governance-toolkit/05-vendor-questionnaire.md ./VENDOR-assessment.md
```

Confirm:

```bash
ls
```

Expected output (yours will differ):

```
VENDOR-assessment.md
```

---

## Step 2: Fill in the questionnaire from the vendor's documentation

Open your working copy. Still on your **lab server**, as **ec2-user**:

```bash
vi VENDOR-assessment.md
```

Press `i` and, for the vendor you chose, fill in the "Vendor answer" column for all
fourteen areas from the vendor's current public documentation (data-usage policy,
security/trust page, terms of service, pricing page, sub-processor list). For each
area also set:

- **Score (1-5):** 5 = excellent / low risk, 1 = poor / high risk, against your
  client's needs.
- **Weight (1-3):** how much this area matters for a client who handles personal data
  and must keep it in-region (weight customer-data usage, residency, retention, and
  exit heavily).
- **Dealbreaker?:** mark "yes" if a "no" answer would sink the deal regardless (for
  example, the vendor trains on your data with no opt-out for a client with PII).

When done, press `Esc`, type `:wq` and press Enter to save and quit.

---

## Step 3: Record your scores for the scorer

Rather than add them by hand, compute the weighted score in Python so it is
reproducible. First set up the environment. Still on your **lab server**, as
**ec2-user**, in `~/use-vendor-scoring`:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Your prompt shows `(.venv)`. No third-party libraries are needed for this one - it is
plain Python.

Create the scorer:

```bash
vi score_vendor.py
```

Press `i` and type (or paste). Replace the sample scores and weights with the ones
you assigned in Step 2:

```python
"""
Vendor scorer. Computes a weighted score from your questionnaire ratings and
enforces dealbreakers. A dealbreaker fails the vendor regardless of total.

Replace the rows below with YOUR real scores/weights from the questionnaire.
Each row: (area, score 1-5, weight 1-3, is_dealbreaker_failed True/False)
is_dealbreaker_failed = True means this area is a dealbreaker AND the vendor
failed it.
"""

# area, score(1-5), weight(1-3), dealbreaker_failed
rows = [
    ("training-data statements", 3, 1, False),
    ("customer-data usage",      5, 3, False),  # enterprise no-training tier
    ("retention",                4, 3, False),
    ("data residency",           4, 3, False),
    ("encryption",               5, 2, False),
    ("security certifications",  5, 2, False),
    ("availability",             4, 2, False),
    ("subprocessors",            3, 2, False),
    ("intellectual property",    4, 1, False),
    ("indemnification",          3, 1, False),
    ("model updates",            3, 2, False),
    ("exit procedures",          3, 3, False),
    ("export capability",        3, 3, False),
    ("pricing risk",             3, 2, False),
]

max_per = 5
weighted_points = sum(score * weight for _, score, weight, _ in rows)
max_points = sum(max_per * weight for _, _, weight, _ in rows)
pct = weighted_points / max_points * 100.0

dealbreakers = [area for area, _, _, failed in rows if failed]

print("=== VENDOR SCORE ===")
print(f"Weighted score: {pct:.1f}%")
print(f"Dealbreakers failed: {dealbreakers if dealbreakers else 'none'}")
print()
if dealbreakers:
    print("VERDICT: REJECT - a dealbreaker failed:", ", ".join(dealbreakers))
elif pct >= 75:
    print("VERDICT: PROCEED (record required contract terms).")
elif pct >= 55:
    print("VERDICT: PROCEED WITH CONDITIONS (close the gaps in the contract).")
else:
    print("VERDICT: REJECT - too many weak areas for this client's needs.")
```

Press `Esc`, type `:wq` and press Enter to save and quit.

---

## Step 4: Run the scorer

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python score_vendor.py
```

Expected output (yours will differ with your real scores):

```
=== VENDOR SCORE ===
Weighted score: 75.3%
Dealbreakers failed: none

VERDICT: PROCEED (record required contract terms).
```

Read it: no dealbreaker tripped, and the weighted score clears the "proceed"
threshold - meaning the vendor is acceptable, but you still record the required
contract terms for the weaker areas (here exit, export, model updates) before
signing. That is a far more useful answer to a client than "seems fine." Note how
close this is to the boundary: nudge one weight and it drops into "proceed with
conditions." That sensitivity is exactly why a reproducible scorer beats a hunch.

Leave the environment:

```bash
deactivate
```

---

## Step 5: Write the recommendation

Reopen the questionnaire and complete the **Recommendation** section at the bottom.
Still on your **lab server**, as **ec2-user**:

```bash
vi VENDOR-assessment.md
```

Press `i` and fill in:

- **Verdict:** match the scorer (proceed / proceed with conditions / reject).
- **Reasoning:** two or three sentences citing the strongest and weakest areas and any
  dealbreaker.
- **Required contract terms before signing:** be concrete - for example "written
  no-training-on-our-data guarantee, in-region (EU/CA) processing, 90-day notice
  before any model deprecation, data + embeddings export in an open format on exit."
- **Ongoing management:** re-assess every [N months] and keep a tested exit path.

Press `Esc`, type `:wq`, Enter. This recommendation - verdict plus the exact terms you
would demand - is the deliverable that makes you worth your fee.

---

## Step 6: Verify your deliverables

Still on your **lab server**, as **ec2-user**, in `~/use-vendor-scoring`:

```bash
ls VENDOR-assessment.md score_vendor.py
```

Expected output:

```
VENDOR-assessment.md  score_vendor.py
```

Confirm the recommendation is not left blank:

```bash
grep -c "Verdict:" VENDOR-assessment.md
```

`grep -c` counts matching lines; you should have the verdict line present.

Expected output:

```
1
```

---

## What you produced and why it matters

- A completed vendor questionnaire for a real vendor, filled from current
  documentation and dated.
- A reproducible weighted score with dealbreaker enforcement - a number, not a hunch.
- A written recommendation with the exact contract terms to require, which is what a
  client acts on and the second half of this tier's proof of competence.

Prof. Happy (SUTA Labs)
