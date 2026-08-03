# USE: The Model and Vendor Selection Matrix

**Tier 6 - USE phase.** In BUILD you produced a comparison table with hard numbers. Now you turn that into a consultant artifact a client can act on: a **Model and Vendor Selection Matrix** - a structured, weighted scorecard that recommends a provider for a specific use case and, just as importantly, documents *why* and *how the client gets out* if they need to.

**Validated on:** CentOS Stream 9, Python 3.12. No API key required - this exercise is analysis and a small scoring script; the numbers you plug in come from BUILD, from provider docs, and from the client's requirements.

**Prerequisite:** you finished BUILD Project 6 and read Concepts 6.3 (providers) and 6.4 (API mechanics, cost).

**Goal:** produce a reusable, defensible selection matrix and a one-paragraph recommendation, for a concrete scenario.

---

## The scenario

Your client, [CLIENT], a mid-size insurance firm, wants to add an LLM feature that reads incoming claims emails and returns structured triage (category, urgency, next action) for their support queue. Roughly 40,000 emails a month. The data includes personal information, so data handling and compliance matter a lot. The team is on AWS. They want the feature live in six weeks and they are nervous about betting the company on one AI vendor.

Your job: recommend a provider and deployment, and hand over a matrix they can re-run themselves when the market changes.

---

## Step 1: Set up the exercise folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-selection-matrix
```

Move into it:

```bash
cd ~/use-selection-matrix
```

---

## Step 2: List the criteria that actually decide this

A selection matrix scores each candidate against the dimensions that matter (Concepts 6.3). For [CLIENT]'s scenario the criteria are:

| Criterion | Why it matters here |
|---|---|
| **Data handling** | Claims contain PII. Does the provider train on your data? Retain it? For how long? |
| **Deployment options** | On AWS, so a cloud-native platform or a self-host path is attractive |
| **Model quality** | Triage accuracy on the client's real emails (test it, per BUILD) |
| **Latency** | Support queue is semi-interactive - seconds matter, not milliseconds |
| **Cost** | 40k emails/month; output tokens dominate the bill |
| **Context capacity** | Emails are short, so this is not a constraint here - but score it |
| **Security** | Access controls, key management, isolation |
| **Compliance** | Certifications the insurer's auditors require |
| **Regional availability** | Data-residency rules may force a region |
| **Vendor dependency** | How locked in would we be? |
| **Exit strategy** | If we must leave, what does it take? |

Write these into a criteria file. Open it with vi:

```bash
vi criteria.md
```

Press `i`, paste the table above (or your own refined version), press `Esc`, type `:wq`, press Enter. This document is itself a deliverable - it shows the client you thought about the right things.

---

## Step 3: Estimate the monthly cost (grounding the "cost" score)

Before scoring, get a real cost estimate so the cost column is not a guess. Use the formula from Concepts 6.4. Open a small script:

```bash
vi cost_estimate.py
```

Press `i`, then enter:

```python
"""Estimate monthly cost of the triage feature per candidate provider.

Token counts come from BUILD (a real sample of the client's emails run through
the model's tokenizer). Prices are ILLUSTRATIVE - always confirm current prices
from the provider before quoting a client.
"""

CALLS_PER_MONTH = 40_000
AVG_INPUT_TOKENS = 350    # a claims email + system prompt (measure for real)
AVG_OUTPUT_TOKENS = 40    # the small structured triage JSON

# Illustrative per-1K-token prices in USD. VERIFY current numbers per provider.
CANDIDATES = {
    "hosted-A":       {"input": 0.005, "output": 0.025},
    "hosted-B":       {"input": 0.003, "output": 0.015},
    "cloud-platform": {"input": 0.005, "output": 0.025},  # same model, AWS-native
    "self-hosted":    {"input": 0.0,   "output": 0.0},    # no per-token bill
}

# Self-hosting has no per-token cost but a fixed monthly infra cost. Include it.
SELF_HOSTED_FIXED_MONTHLY = 1500.0  # illustrative GPU + ops estimate

print(f"{'candidate':16} {'monthly_usd':>12}")
print("-" * 30)
for name, price in CANDIDATES.items():
    per_call = (AVG_INPUT_TOKENS / 1000.0) * price["input"] + \
               (AVG_OUTPUT_TOKENS / 1000.0) * price["output"]
    monthly = per_call * CALLS_PER_MONTH
    if name == "self-hosted":
        monthly += SELF_HOSTED_FIXED_MONTHLY
    print(f"{name:16} {monthly:12.2f}")
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python3.12 cost_estimate.py
```

Expected output (yours will differ):

```
candidate         monthly_usd
------------------------------
hosted-A               110.00
hosted-B                66.00
cloud-platform         110.00
self-hosted           1500.00
```

Read the result honestly: at 40k short emails a month, hosted is *cheap* and self-hosting's fixed infra cost dominates. Volume would have to be far higher (or data rules far stricter) before self-hosting pays off on cost alone. That is exactly the kind of finding that changes a client's mind - and it is grounded in a number, not a hunch.

---

## Step 4: Build the weighted scoring matrix

Now score each candidate 1-5 on each criterion, weight the criteria by importance to *this* client, and compute a total. Open the scorer:

```bash
vi score.py
```

Press `i`, then enter:

```python
"""Weighted selection matrix. Scores are 1 (poor) to 5 (excellent).

Fill scores from evidence: BUILD's accuracy/latency numbers, cost_estimate.py,
and each provider's published data-handling / compliance / region docs. Weights
reflect THIS client: PII-heavy insurer on AWS, so data handling, compliance,
and exit strategy are weighted heavily.
"""

# Weight each criterion by how much it matters to this client (higher = more).
WEIGHTS = {
    "data_handling":         5,
    "deployment_options":    3,
    "model_quality":         4,
    "latency":               2,
    "cost":                  3,
    "context_capacity":      1,
    "security":              4,
    "compliance":            5,
    "regional_availability": 3,
    "vendor_dependency":     4,
    "exit_strategy":         4,
}

# Scores 1-5 per candidate per criterion. THESE ARE ILLUSTRATIVE - replace with
# your own evidence-based scores for the real engagement.
SCORES = {
    "hosted-A": {
        "data_handling": 4, "deployment_options": 3, "model_quality": 5,
        "latency": 4, "cost": 5, "context_capacity": 5, "security": 4,
        "compliance": 4, "regional_availability": 4, "vendor_dependency": 2,
        "exit_strategy": 3,
    },
    "cloud-platform": {
        "data_handling": 5, "deployment_options": 5, "model_quality": 5,
        "latency": 4, "cost": 4, "context_capacity": 5, "security": 5,
        "compliance": 5, "regional_availability": 5, "vendor_dependency": 3,
        "exit_strategy": 4,
    },
    "self-hosted": {
        "data_handling": 5, "deployment_options": 4, "model_quality": 3,
        "latency": 3, "cost": 2, "context_capacity": 3, "security": 5,
        "compliance": 5, "regional_availability": 5, "vendor_dependency": 5,
        "exit_strategy": 5,
    },
}


def weighted_total(scores: dict) -> int:
    return sum(scores[c] * WEIGHTS[c] for c in WEIGHTS)


max_possible = sum(5 * w for w in WEIGHTS.values())

print(f"{'candidate':16} {'weighted':>9} {'of_max':>8} {'pct':>6}")
print("-" * 42)
ranked = sorted(SCORES.items(), key=lambda kv: weighted_total(kv[1]), reverse=True)
for name, scores in ranked:
    total = weighted_total(scores)
    pct = 100.0 * total / max_possible
    print(f"{name:16} {total:9d} {max_possible:8d} {pct:5.1f}%")

winner = ranked[0][0]
print(f"\nTop candidate for this client: {winner}")
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python3.12 score.py
```

Expected output (yours will differ with your scores/weights):

```
candidate          weighted   of_max    pct
------------------------------------------
cloud-platform          173      190   91.1%
self-hosted             164      190   86.3%
hosted-A                145      190   76.3%

Top candidate for this client: cloud-platform
```

For this PII-heavy, AWS-based, deadline-driven client, the cloud-platform option wins - it keeps data inside a trusted AWS boundary with the compliance story auditors want, while still using a top model. Notice self-hosted scores well on control but loses on cost, model quality, and time-to-value.

---

## Step 5: Write the exit strategy (the column consultants forget)

A matrix that recommends a vendor without an exit plan is half a deliverable. Document how [CLIENT] leaves each candidate if they must (Concepts 6.3). Open:

```bash
vi exit_strategy.md
```

Press `i`, then write a short plan. A good template:

```
# Exit Strategy

We reduce lock-in from day one so leaving any vendor is a bounded project,
not a rewrite:

1. Provider abstraction: all model calls go through one interface (see the
   BUILD provider layer). Swapping providers is a one-file change.
2. Credentials from env vars only - no keys in code.
3. Prompts live in a versioned, portable library (see the prompt-library USE),
   with a regression set to re-validate on a new model.
4. A keyless mock provider lets us develop and test the switch offline.

Per-candidate exit cost:
- cloud-platform -> hosted direct: swap the client class + re-test prompts.
  Est. 2-3 days. Low risk.
- cloud-platform -> self-hosted: stand up GPU infra + re-test. Est. 2-3 weeks.
  Medium risk; driven by ops, not code.
- Any -> any: prompts re-validated against the regression set before cutover;
  we do not cut over until accuracy on the client's real emails is confirmed.
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 6: Write the recommendation

The client reads one paragraph, not four scripts. Open:

```bash
vi recommendation.md
```

Press `i`, then write the recommendation. A strong version for this scenario:

```
# Recommendation for [CLIENT]

We recommend running the claims-triage feature on a cloud-native model platform
inside your existing AWS account. It scored highest (87%) on our weighted
matrix because it keeps claims data (which contains PII) within a boundary your
auditors already trust, meets your compliance and regional requirements, and
still gives you a top-tier model - all achievable within the six-week deadline.
At 40,000 short emails a month the estimated cost is modest (about $110/month
on illustrative prices; we will confirm live pricing before sign-off), so
self-hosting's control benefits do not justify its higher fixed cost and longer
setup at this volume. Critically, we build the feature behind a provider
abstraction with env-var credentials and a versioned, regression-tested prompt
library, so if the market shifts you can move to a different vendor in days, not
months. See the attached matrix, cost estimate, and exit strategy.
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 7: Review the deliverable

List everything you produced:

```bash
ls -1
```

Expected output (yours will differ):

```
cost_estimate.py
criteria.md
exit_strategy.md
recommendation.md
score.py
```

You now hold a complete consultant artifact: the criteria, a grounded cost estimate, a weighted scoring matrix, an exit strategy, and a one-paragraph recommendation - all re-runnable when the market changes. This is what "which model should we use?" looks like when answered by a professional.

**Reusing this for real engagements:** replace the illustrative scores with evidence from a BUILD run on the client's real data, replace the illustrative prices with current published prices (verify them), and re-weight the criteria for that client's priorities. The structure stays; the inputs change.

Prof. Happy (SUTA Labs)
