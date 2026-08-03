# USE: AI Opportunity Prioritization Matrix

**Tier 14 - Strategy & Product. A matrix that ranks candidate AI use cases so leadership funds the right ones first. Score each use case on 8 criteria, apply weights, and produce a single comparable number.**

Most organizations have more AI ideas than budget. The matrix turns "which one should we do first?" from an opinion contest into a transparent, defensible ranking. It scores every candidate on the same 8 criteria, weights them, and sums to one score.

---

### The 8 criteria and their 1-5 anchors

Every criterion is scored 1-5. For six criteria, higher is better. For two (Risk and Cost), lower real-world exposure is better - see the inversion note after the tables.

**1. Business value** - size of the impact if it works.

| Score | Anchor |
|------:|--------|
| 1 | Marginal; nice to have |
| 2 | Modest local efficiency |
| 3 | Meaningful savings or revenue for one team |
| 4 | Significant cross-team impact |
| 5 | Strategic; moves a top company metric |

**2. Feasibility** - can we actually build/deploy it with current tech and skills.

| Score | Anchor |
|------:|--------|
| 1 | Research-grade; unproven |
| 2 | Hard; needs new capabilities |
| 3 | Doable with effort |
| 4 | Well-understood pattern |
| 5 | Off-the-shelf, proven approach |

**3. Data readiness** - do we have the data, is it clean, is it accessible.

| Score | Anchor |
|------:|--------|
| 1 | Data does not exist |
| 2 | Exists but scattered/dirty |
| 3 | Available, needs prep |
| 4 | Clean and accessible |
| 5 | Clean, labeled, pipeline-ready |

**4. Risk** - regulatory, safety, reputational, and failure exposure. Scored inversely.

| Score | Anchor |
|------:|--------|
| 1 | Severe (regulated decisions, safety, PII exposure) |
| 2 | High |
| 3 | Moderate |
| 4 | Low |
| 5 | Minimal (internal, reversible, low stakes) |

**5. Cost** - implementation + operating cost. Scored inversely.

| Score | Anchor |
|------:|--------|
| 1 | Very high (>$500k) |
| 2 | High |
| 3 | Moderate |
| 4 | Low |
| 5 | Very low (<$50k) |

**6. Implementation time** - time to first value. Scored so faster is better.

| Score | Anchor |
|------:|--------|
| 1 | >12 months |
| 2 | 6-12 months |
| 3 | 3-6 months |
| 4 | 6-12 weeks |
| 5 | <6 weeks |

**7. Employee impact** - how positively it affects the people who do the work (adoption, morale, change burden).

| Score | Anchor |
|------:|--------|
| 1 | Threatens jobs; heavy resistance expected |
| 2 | Significant disruption |
| 3 | Neutral / manageable change |
| 4 | Removes drudgery; welcomed |
| 5 | Clearly augments staff; strong pull |

**8. Leadership sponsorship** - strength of executive backing.

| Score | Anchor |
|------:|--------|
| 1 | No sponsor |
| 2 | Interested but uncommitted |
| 3 | A sponsor exists |
| 4 | Committed sponsor with budget |
| 5 | Top-team priority, funded and vocal |

---

### Handling inverse criteria (Risk and Cost)

Risk and Cost are dangers, not benefits. To keep the math simple, we score them so that a HIGHER score always means a BETTER (more attractive) use case. So a low-risk use case scores 5 on Risk, and a cheap use case scores 5 on Cost. This lets every criterion be summed the same way - higher total is always better - with no sign flips in the formula.

The anchor tables above already bake this in: read Risk and Cost as "attractiveness on that dimension," not "amount of risk/cost." Document this convention on the matrix so reviewers do not misread a 5 on Risk as "very risky."

---

### Weighting scheme

Not all criteria matter equally. Assign weights that sum to 100%. A common default for a first-year AI portfolio:

| Criterion | Weight |
|-----------|-------:|
| Business value | 25% |
| Feasibility | 15% |
| Data readiness | 15% |
| Risk | 10% |
| Cost | 10% |
| Implementation time | 10% |
| Employee impact | 7% |
| Leadership sponsorship | 8% |
| **Total** | **100%** |

Adjust weights to strategy. A regulated firm might push Risk to 20%. A speed-focused startup might push Implementation time and Feasibility up. State your weights on the matrix.

---

### Scoring formula

```
Weighted score (per criterion) = raw score (1-5) x criterion weight
Total score = sum of all weighted scores
Max possible = 5.00 (when every raw score is 5)
Rank use cases by total score, highest first.
```

Because weights sum to 100% and scores run 1-5, the total also runs 1.00-5.00, which is easy to compare and communicate.

---

### Blank template

Fill raw 1-5 scores; the weighted columns = raw x weight.

| Criterion | Weight | [USE CASE A] | [USE CASE B] | [USE CASE C] |
|-----------|-------:|-------------:|-------------:|-------------:|
| Business value | 25% | [ ] | [ ] | [ ] |
| Feasibility | 15% | [ ] | [ ] | [ ] |
| Data readiness | 15% | [ ] | [ ] | [ ] |
| Risk (inverse) | 10% | [ ] | [ ] | [ ] |
| Cost (inverse) | 10% | [ ] | [ ] | [ ] |
| Implementation time | 10% | [ ] | [ ] | [ ] |
| Employee impact | 7% | [ ] | [ ] | [ ] |
| Leadership sponsorship | 8% | [ ] | [ ] | [ ] |
| **Total weighted score** | 100% | **[ ]** | **[ ]** | **[ ]** |
| **Rank** | | [ ] | [ ] | [ ] |

---

### Worked example

Four candidate use cases for [CLIENT], a mid-size insurer. Raw 1-5 scores (Risk/Cost read as attractiveness):

| Criterion | Weight | Claims-doc triage | Customer chatbot | Fraud detection | Underwriting copilot |
|-----------|-------:|------------------:|-----------------:|----------------:|---------------------:|
| Business value | 25% | 4 | 3 | 5 | 4 |
| Feasibility | 15% | 4 | 4 | 2 | 3 |
| Data readiness | 15% | 4 | 3 | 3 | 2 |
| Risk (inverse) | 10% | 4 | 3 | 2 | 2 |
| Cost (inverse) | 10% | 3 | 4 | 2 | 3 |
| Implementation time | 10% | 4 | 4 | 2 | 3 |
| Employee impact | 7% | 4 | 3 | 4 | 4 |
| Leadership sponsorship | 8% | 4 | 3 | 5 | 3 |

Weighted totals (raw x weight, summed):

```
Claims-doc triage    = 4(.25)+4(.15)+4(.15)+4(.10)+3(.10)+4(.10)+4(.07)+4(.08)
                     = 1.00+0.60+0.60+0.40+0.30+0.40+0.28+0.32 = 3.90
Customer chatbot     = 0.75+0.60+0.45+0.30+0.40+0.40+0.21+0.24 = 3.35
Fraud detection      = 1.25+0.30+0.45+0.20+0.20+0.20+0.28+0.40 = 3.28
Underwriting copilot = 1.00+0.45+0.30+0.20+0.30+0.30+0.28+0.24 = 3.07
```

| Rank | Use case | Total score |
|-----:|----------|------------:|
| 1 | Claims-doc triage | 3.90 |
| 2 | Customer chatbot | 3.35 |
| 3 | Fraud detection | 3.28 |
| 4 | Underwriting copilot | 3.07 |

**Reading the result.** Claims-doc triage wins: strong value, feasible, data-ready, low risk, fast. Fraud detection has the highest raw business value (5) but is dragged down by weak feasibility, high risk, high cost, and slow delivery - a classic "high value, not yet ready" case to sequence later. Fund triage first, chatbot second; put fraud detection through a feasibility spike before committing.

---

### How to use the ranking

- Fund top-ranked cases first; each winner should then get a full business case (see the BUILD folder) before spend is approved.
- A high raw Business value with a low total is a signal to invest in readiness (data, feasibility) before building.
- Re-score quarterly - data readiness and sponsorship change fast.
- Keep the completed matrix as the audit trail for why the portfolio is ordered the way it is.
