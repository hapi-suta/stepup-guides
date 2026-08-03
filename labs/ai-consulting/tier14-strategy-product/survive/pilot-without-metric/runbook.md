# SURVIVE Runbook: A Pilot Has No Success Metric Defined

**Tier 14 - SURVIVE scenario 3 of 3**

This is a review-assessed scenario. There is no script to run. You retrofit a running pilot with measurable 90-day outcomes and a reviewer judges whether the metrics are real, measurable, and tied to business value.

---

## The situation

[COMPANY] launched an AI pilot before you arrived: a tool that summarizes long internal policy documents for their compliance team. It has been running for five weeks. Everyone says it is "going well" and "people like it," but when you ask "how will we know if this pilot succeeded?" you get shrugs. There is no defined success metric, no baseline, no target, and no decision rule for what happens at the end.

This is dangerous. A pilot with no success metric cannot be judged, cannot be defended to a CFO, and cannot produce a real go/no-go decision. It will drift into a permanent "it seems fine" state, consuming budget forever or getting killed on a whim. Worse, five weeks in, no baseline was captured, so some evidence is already lost.

Your job: retrofit measurable 90-day outcomes onto the running pilot, recover what baseline you can, and install a decision rule.

---

## Why this happens

- **The team fell in love with the tool, not the outcome.** "People like it" is a feeling, not a result.
- **No hypothesis was written.** Without "we believe X will improve Y by Z," there is nothing to test.
- **No baseline was captured before launch,** so improvement cannot be proven.
- **Vanity metrics crept in.** "Number of summaries generated" or "logins" measure activity, not value.
- **No go/no-go rule exists,** so the pilot cannot end cleanly either way.

A pilot is an experiment. An experiment without a metric and a decision rule is just spending.

---

## Diagnosis: what is missing

Check the pilot against the five things every pilot needs. Mark each present or missing:

| Element | Present? | Notes |
|---|---|---|
| A written hypothesis | Missing | "We believe X improves Y by Z%" |
| A baseline (pre-pilot measurement) | Missing | not captured before launch |
| Leading metrics (early signals) | Missing | usage quality, not just usage |
| Lagging metrics (the business outcome) | Missing | time-to-review, error rate |
| Acceptance criteria + go/no-go rule | Missing | what number = success |

For this pilot, the real outcome the compliance team cares about is almost certainly: **how long it takes a reviewer to process a policy document, and whether review quality holds.** That is the lagging metric. Everything else supports it.

---

## Recovery: retrofit measurable 90-day outcomes

### 1. Write the hypothesis first
Everything hangs off this. Example:

```
We believe that giving compliance reviewers AI-generated summaries of
policy documents will reduce average document review time by at least 30%
without increasing review errors, within 90 days.
```

It names the intervention, the outcome, a target, a guardrail, and a timeframe. If you cannot write this sentence, you do not have a pilot.

### 2. Recover a baseline
You launched without one, but you can still get it:
- **Historical data:** pull review-time records from before the pilot from the ticketing or document system.
- **A hold-out group:** have a subset of reviewers keep working without the tool for two weeks and measure them as a proxy baseline.
- **Reconstruction:** interview reviewers for typical pre-tool times and corroborate with any timestamps.
Document how you obtained the baseline and its limits. An imperfect, disclosed baseline beats none.

### 3. Define leading metrics (early signals, weekly)
These tell you if the pilot is on track before the outcome lands:
- Percent of eligible documents where the summary was actually used.
- Reviewer-rated summary quality (a quick 1-5 after each use).
- Percent of summaries edited heavily (a proxy for poor quality).

### 4. Define lagging metrics (the outcome, the real test)
- **Average review time per document** (target: -30 percent vs baseline).
- **Review error / rework rate** (guardrail: must not rise).
- **Reviewer capacity** (documents processed per reviewer per week).

### 5. Set acceptance criteria and a go/no-go rule
Make the decision automatic, not political:

```
GO (scale up):    review time down >= 30% AND error rate not increased
                  AND reviewers want to keep it.
ITERATE:          review time down 10-30%, or quality issues fixable.
                  Extend 30 days with specific fixes.
NO-GO (stop):     review time down < 10%, or error rate up,
                  or reviewers abandon it.
```

Agree this rule with the sponsor NOW, before the numbers come in, so the decision is honest.

### 6. Set the measurement cadence
Leading metrics weekly; lagging metrics at day 45 (mid-point check) and day 90 (decision). Put a calendar hold on the go/no-go meeting today.

---

## What you must produce for this scenario

1. **A one-sentence written hypothesis** (intervention, outcome, target, guardrail, timeframe).
2. **A baseline-recovery plan** naming the method (historical / hold-out / reconstruction) and its limits.
3. **A metrics table**: leading and lagging metrics, each with a definition, a target/guardrail, and how it is measured.
4. **A go/no-go decision rule** with explicit thresholds, agreed with the sponsor.
5. **A measurement cadence** with the day-45 and day-90 dates booked.

---

## Decision checklist (self-assess or reviewer-assess)

- [ ] You wrote a single, testable hypothesis with a numeric target and a timeframe.
- [ ] Your metrics measure business outcome (review time, error rate), not vanity (summaries generated, logins).
- [ ] You have both leading (early-signal) and lagging (outcome) metrics.
- [ ] You recovered a baseline honestly and disclosed its limits.
- [ ] You set acceptance criteria and a go/no-go rule with real thresholds.
- [ ] The go/no-go rule was agreed with the sponsor BEFORE results arrive.
- [ ] Metrics are actually measurable from data or a quick reviewer rating - not aspirational.
- [ ] A day-90 decision meeting is on the calendar.

If any box is unchecked, the pilot still cannot be judged. Fix it before day 90.

---

## What you learned

- A pilot is an experiment: no hypothesis and no metric means no experiment, just spending.
- Measure the outcome the client cares about (time, errors, capacity), never vanity activity.
- Capture a baseline before launch. If you missed it, recover one honestly and disclose its limits.
- Set the go/no-go rule and thresholds before results arrive, so the decision is evidence-based, not political. Be willing to say no-go.

Prof. Happy (SUTA Labs)
