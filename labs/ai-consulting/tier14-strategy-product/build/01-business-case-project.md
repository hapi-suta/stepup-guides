# BUILD: Build a Full AI Business Case for One Real Use Case

**Tier 14 - Strategy & Product. In this BUILD you produce a complete, defensible business case for a single AI use case: baseline, ROI, payback, TCO, and a build-versus-buy recommendation. The deliverable is a document a skeptical executive or CFO would sign off on.**

This guide walks you through the case end to end. Use it alongside two companion files in this folder:

- `business-case-template.md` - the blank template you fill in.
- `business-case-worked-example.md` - a fully worked example (a mid-size insurer automating claims-document triage) you can copy the structure and math from.

A business case is not a pitch. It is an argument built on numbers a reviewer can check. Every figure must trace to a source or a stated assumption. If you cannot defend a number, do not use it.

---

### Before you start: gather your inputs

You cannot build a business case from your desk. Collect these first:

- One clearly scoped use case (not "use AI in the company" - a single, nameable workflow).
- A named process owner who will confirm your baseline numbers.
- Volume data: how many times per day/week/month the task runs.
- Time data: how long the task takes today, per unit.
- Cost data: fully loaded labor cost of the people doing it (salary + benefits + overhead).
- Error/rework data: how often it goes wrong and what a mistake costs.
- A rough sense of the technical options (vendor product vs. internal build).

If any of these is a guess, label it a guess in the assumptions section. A business case with honest assumptions beats one with confident fiction.

---

### Step 1 - Define the use case

**What to do.** Write a one-paragraph summary: what the workflow is, who does it today, what "AI does it" would look like, and what specific outcome improves. Name the single primary metric you expect to move (hours saved, revenue gained, or errors avoided).

**Data to gather.** Process name, process owner, current tools, trigger event, and the end state.

**How to write it.** Use this shape: "Today, [role] spends [time] doing [task] [frequency]. We propose [AI capability] to [reduce time / increase throughput / cut errors], measured by [primary metric]."

**Numeric example.** "Today, 6 claims clerks spend ~12 minutes manually reading and routing each incoming claims document, ~200 documents/day. We propose an AI triage assistant that pre-classifies and extracts key fields, measured by clerk-minutes per document."

A use case that names a role, a volume, a time, and a metric is scopeable. One that says "improve efficiency" is not.

---

### Step 2 - Establish the baseline

**What to do.** Quantify the current cost of doing the task the way it is done today. This is your comparison point. No baseline, no case.

**Data to gather.** Volume (units per period), time per unit, fully loaded hourly labor cost, and current error rate + cost per error.

**How to compute.**

```
Annual volume        = units per day x working days per year
Annual labor hours   = annual volume x minutes per unit / 60
Annual labor cost    = annual labor hours x fully loaded hourly rate
Annual error cost    = annual volume x error rate x cost per error
Baseline annual cost = annual labor cost + annual error cost
```

**Numeric example.** 200 docs/day x 250 working days = 50,000 docs/year. At 12 min each = 10,000 hours/year. At a fully loaded $45/hour = $450,000/year labor. Error rate 8% at $60 rework cost each = 50,000 x 0.08 x $60 = $240,000/year. Baseline annual cost = $690,000.

Get the process owner to confirm the volume and time-per-unit before you go further. These two numbers drive everything downstream.

---

### Step 3 - Quantify the benefits

Benefits fall into three buckets. Estimate each separately so a reviewer can accept or reject them one at a time.

**3a. Time saved (efficiency).**

```
Time saved per unit  = baseline minutes per unit x reduction %
Annual hours saved   = annual volume x time saved per unit / 60
Time saved value     = annual hours saved x fully loaded hourly rate
```

Example: AI cuts handling from 12 min to 4 min (a 67% reduction, 8 min saved). 50,000 x 8 / 60 = 6,667 hours saved. x $45 = $300,015/year.

Be explicit whether saved time is a hard saving (headcount avoided or reduced) or a soft saving (freed capacity). Reviewers discount soft savings. If it is capacity redeployed rather than cost removed, say so.

**3b. Revenue impact.**

```
Revenue benefit = incremental units x margin per unit
```

Example: faster triage lets the team handle 15% more claims without adding staff, capturing $80,000/year in throughput-driven revenue. Only count this if there is real demand for the extra capacity.

**3c. Error / risk reduction.**

```
Error reduction value = annual volume x (old error rate - new error rate) x cost per error
```

Example: error rate falls from 8% to 3%. 50,000 x (0.08 - 0.03) x $60 = $150,000/year.

**Total gross annual benefit** = time saved + revenue + error reduction. In the example: $300,015 + $80,000 + $150,000 = $530,015/year (before adoption ramp - see Step 5).

---

### Step 4 - Estimate the costs

Split costs into one-time implementation and recurring operating. Both feed TCO.

**4a. Implementation (one-time).** Software licensing/setup, integration engineering, data preparation, security review, change management and training, and a contingency buffer (add 15-20%).

**4b. Operating (recurring, annual).** Subscription or inference/API cost, cloud infrastructure, model monitoring and maintenance, support, and periodic retraining.

**How to compute.**

```
Implementation cost = sum of one-time line items x (1 + contingency %)
Annual operating cost = sum of recurring line items
```

**Numeric example.** Implementation: $120,000 integration + $40,000 data prep + $25,000 change mgmt = $185,000, x 1.15 contingency = ~$212,750. Round to $210,000. Operating: $60,000 platform + $30,000 monitoring/maintenance = $90,000/year.

Do not lowball operating cost. AI systems have ongoing inference, drift, and retraining costs that many cases forget. A case that ignores year-2 and year-3 operating cost is not defensible.

---

### Step 5 - Model adoption

Benefits do not arrive at full strength on day one. Apply an adoption ramp so year 1 is realistic.

**What to do.** Estimate what fraction of the full benefit is captured in each period as users adopt and the model matures.

**How to compute.**

```
Realized benefit (period) = gross annual benefit x adoption %
```

**Numeric example.** Ramp: 50% in year 1, 90% in year 2, 100% in year 3.
- Year 1 realized: $530,015 x 0.50 = $265,008
- Year 2 realized: $530,015 x 0.90 = $477,014
- Year 3 realized: $530,015 x 1.00 = $530,015

State your ramp assumption plainly. A flat "100% from month one" ramp is the single most common way business cases overstate returns.

---

### Step 6 - Compute payback, ROI, and TCO

Now assemble the numbers into the three headline figures every reviewer looks for.

**6a. TCO (Total Cost of Ownership) over the horizon.**

```
TCO = implementation cost + sum of operating costs over horizon
```

3-year example: $210,000 + ($90,000 x 3) = $210,000 + $270,000 = $480,000.

**6b. Net benefit.**

```
Net benefit (period) = realized benefit - operating cost (period)
Cumulative net benefit = running sum of net benefit minus implementation
```

| Year | Realized benefit | Operating cost | Net benefit | Cumulative (incl. implementation) |
|------|-----------------:|---------------:|------------:|----------------------------------:|
| 0    | -                | -              | -           | -$210,000 |
| 1    | $265,008         | $90,000        | $175,008    | -$34,992  |
| 2    | $477,014         | $90,000        | $387,014    | $352,022  |
| 3    | $530,015         | $90,000        | $440,015    | $792,037  |

**6c. Payback period.** The moment cumulative net benefit crosses zero.

```
Payback = implementation cost / monthly net benefit
```

Using year-2 steady-state monthly net benefit ($387,014 / 12 = $32,251/month): $210,000 / $32,251 = ~6.5 months of steady-state operation. But because year 1 ramps, the cumulative table above shows breakeven early in year 2 (cumulative is -$34,992 at end of year 1, positive by end of year 2). Report payback from the cumulative table when a ramp is present - it is the honest figure. Here: roughly month 14.

**6d. ROI over the horizon.**

```
Net benefit over horizon = sum of realized benefits - TCO
ROI = (net benefit over horizon / TCO) x 100
```

Example: total realized benefit = $265,008 + $477,014 + $530,015 = $1,272,037. TCO = $480,000. Net = $792,037. ROI = ($792,037 / $480,000) x 100 = 165%.

State the horizon with every ROI number. "165% ROI" is meaningless without "over 3 years."

---

### Step 7 - Do the build-versus-buy analysis

For any AI use case there are usually three paths: buy a vendor product, build in-house, or a hybrid (buy the model/platform, build the integration). Score them side by side.

**What to do.** Compare on cost (implementation + 3-yr operating), time to value, control/customization, risk, and internal capability required. Recommend one.

**How to compare.** Put both options through the same cost model from Steps 4-6, then weigh the non-cost factors.

| Factor | Buy (vendor) | Build (in-house) |
|--------|-------------|------------------|
| Implementation cost | Lower ($90k) | Higher ($260k) |
| 3-yr operating cost | Higher (per-seat/usage) | Lower after build |
| Time to value | Fast (8-10 weeks) | Slow (6-9 months) |
| Customization/control | Limited | Full |
| Vendor lock-in risk | High | Low |
| Internal capability needed | Low | High (ML + MLOps) |
| 3-yr TCO | $480,000 | $620,000 |

**How to decide.** If the use case is common and non-differentiating, buy. If it is core to competitive advantage and you have the talent, build. If you need speed now but control later, buy to prove value then reassess. Write the reasoning, not just the verdict.

**Example conclusion.** "Buy. Claims triage is a solved, non-differentiating capability; a vendor gets us to value in 8-10 weeks at a lower 3-year TCO ($480k vs $620k), and we avoid standing up an ML/MLOps team we do not have. Revisit build only if per-document usage cost outgrows a fixed-cost internal system at scale."

---

### Step 8 - Write the recommendation

**What to do.** Open the document with a one-page recommendation a busy executive can read alone. It states the ask, the headline numbers, the recommended path, and the top risks.

**Structure.**

1. The ask (approve $X to do Y).
2. Headline numbers: baseline cost, ROI %, payback months, 3-yr TCO, net benefit.
3. Recommended path (build vs buy) in one sentence with the reason.
4. Top 3 risks and how each is mitigated.
5. What you need to proceed (budget, sponsor, pilot window).

**Example.** "Approve $210k to deploy a vendor claims-triage assistant. Baseline cost $690k/year; expected 165% 3-year ROI, ~14-month payback, $480k 3-year TCO, $792k net benefit. Buy over build for speed and lower TCO. Top risks: adoption (mitigated by phased rollout + training), model accuracy on edge cases (human-in-the-loop review below confidence threshold), vendor lock-in (data export clause in contract)."

---

### Step 9 - List risks and assumptions

Every number rests on an assumption. Name them so a reviewer can pressure-test the case instead of dismissing it.

- List each material assumption (volume, time-per-unit, reduction %, adoption ramp, error rate, hourly rate) with its source (measured / owner estimate / benchmark).
- List the top risks with likelihood, impact, and mitigation.
- Note which benefits are hard (cash) vs soft (capacity) - reviewers will.
- Run one sensitivity check: recompute ROI if the biggest benefit is 30% lower. If the case still clears the hurdle, say so; if it does not, the case is fragile and you should say that too.

Sensitivity example: if time-saved value drops 30% ($300k -> $210k gross), 3-yr realized benefit falls to ~$1.05M, net ~$570k, ROI ~119% over 3 years. Still positive - the case is robust.

---

## What good looks like

A finished Tier 14 business case passes all of these:

- [ ] The use case names a role, a volume, a time-per-unit, and one primary metric.
- [ ] The baseline annual cost is computed from real volume and time data, confirmed by the process owner.
- [ ] Benefits are split into time saved, revenue, and error/risk reduction - each independently defensible.
- [ ] Hard savings and soft (capacity) savings are labeled distinctly.
- [ ] Implementation cost includes a contingency buffer; operating cost includes years 2 and 3.
- [ ] An adoption ramp is applied - benefits do not hit 100% in month one.
- [ ] TCO = implementation + operating over a stated horizon.
- [ ] ROI is stated with its horizon and computed as (net benefit / TCO) x 100.
- [ ] Payback is read from the cumulative net-benefit table when a ramp is present.
- [ ] A build-vs-buy table compares cost, time to value, control, risk, and capability, with a reasoned recommendation.
- [ ] A one-page recommendation leads the document (ask, headline numbers, path, risks).
- [ ] Every material number traces to a source or a labeled assumption.
- [ ] One sensitivity check shows what happens if the biggest benefit is 30% lower.
- [ ] A neutral reviewer, given the assumptions, agrees the numbers are realistic and the conclusion follows.
