# SURVIVE Runbook: A Business Case Built on Optimistic Adoption Collapses

**Tier 14 - SURVIVE scenario 2 of 3**

This is a review-assessed scenario. There is no script to run. You diagnose a broken business case, rebuild it with realistic numbers, and a reviewer judges whether the rebuilt case is defensible.

---

## The situation

Six weeks ago you delivered a business case for [CLIENT], a customer-support organization, to justify an AI assistant that drafts replies to support tickets. Leadership approved it on the strength of the ROI you showed: a 320 percent first-year return, payback in 3.5 months.

The pilot has now run for 60 days. Adoption is far below what you modelled. Your case assumed 90 percent of agents would use the assistant on 80 percent of tickets within the first month. Reality: 35 percent of agents use it, on about half of their tickets, and usage is flat, not climbing. The CFO has noticed the numbers do not match and has asked you to explain. Your credibility is on the line.

Your job: find out why the case was wrong, rebuild it with realistic numbers, and decide honestly whether the project still makes sense.

---

## Why this happens

Optimistic business cases fail for predictable reasons. Recognize the pattern:

- **Adoption was assumed, not modelled.** The single biggest error. New tools do not hit 90 percent usage in a month. Adoption follows an S-curve and often plateaus well below 100 percent.
- **Benefits were counted at full adoption from day one.** The case took the steady-state saving and applied it to month one, inflating year-one return.
- **Time-saved was measured on a best-case ticket, then applied to all tickets.** Not every ticket benefits equally; some are faster to answer by hand.
- **No ramp, no plateau, no non-adopters.** Real rollouts have a ramp period, a realistic ceiling, and a chunk of users who never adopt.
- **Costs of adoption were omitted.** Training, change management, and the productivity dip while people learn were left out.

None of this means the project is bad. It means the case was built on wishes. The fix is to rebuild it on evidence you now actually have from the pilot.

---

## Diagnosis: find where the numbers broke

Do not guess. Pull the pilot's real data and compare it to what you assumed. Build this comparison table:

| Driver | Assumed in case | Actual from pilot | Gap |
|---|---|---|---|
| Agents using the tool | 90% | 35% | -55 pts |
| Tickets where it is used | 80% | ~50% | -30 pts |
| Time saved per assisted ticket | 6 min | measure it - suppose 3.5 min | -2.5 min |
| Ramp to steady state | 1 month | not reached at 2 months | slower |
| Adoption ceiling | 100% (implied) | flat at ~35% | needs a realistic ceiling |
| Training / change cost | $0 | actual spend | omitted |

The gaps tell you exactly which assumptions to replace. The two that usually dominate are adoption rate and time-saved-per-item, because they multiply through the whole benefit calculation.

Ask why adoption is low, because the rebuild depends on it:
- Is it a tool problem (drafts are poor, so agents rewrite them)?
- A workflow problem (the assistant is not where agents work)?
- A trust or incentive problem (agents fear it or are measured on volume, not quality)?
- A training gap (they were never shown how)?

The cause changes both your numbers and your recommendation.

---

## Recovery: rebuild the case on realistic numbers

### 1. Replace point assumptions with an adoption curve
Do not model a flat 90 percent. Model a ramp to a realistic ceiling. Use the pilot as your anchor. Example rebuild:

```
Month 1-2:  35% of agents (observed)
Month 3-4:  45% (with the fixes below)
Month 5-6:  55%
Steady state (month 7+): 60% ceiling
```

Sixty percent, not 100, because pilots rarely exceed the level a well-run rollout sustains, and some agents will never adopt. If you have a reason to believe higher, justify it; do not assume it.

### 2. Use the measured time-saved, not the best case
Replace 6 minutes with the pilot's measured 3.5 minutes per assisted ticket, and apply it only to the ~50 percent of tickets where the tool is actually used.

### 3. Recompute the benefit bottom-up
```
Monthly benefit =
  agents_using x tickets_per_agent x pct_tickets_assisted
  x minutes_saved x (loaded cost per minute)
```
Do this month by month across the ramp, not as one steady-state number applied to the whole year.

### 4. Add the costs you left out
Training, change-management effort, and a first-month productivity dip. Put them in the implementation and operating lines.

### 5. Recompute ROI, payback, and TCO honestly
```
ROI (year 1)  = (year-1 net benefit / year-1 total cost) x 100
Payback       = cumulative cost / cumulative monthly net benefit (find the month it turns positive)
TCO (3-yr)    = implementation + sum of operating costs over 36 months
```
Expect a much lower, believable number. A case that now shows, say, 70 percent year-one ROI and 9-month payback is worth far more to the client than the fictional 320 percent, because it will actually happen.

### 6. Add a sensitivity analysis
Show the case at three adoption ceilings (e.g. 45 / 60 / 75 percent) so leadership sees the range, not a single fragile point. This is the single most credibility-restoring thing you can add: it proves you now model uncertainty instead of hiding it.

### 7. Make an honest recommendation
- If the realistic case still clears the client's hurdle rate: continue, and fund the specific adoption fixes you identified.
- If it clears only at high adoption: continue conditionally, with an adoption target and a checkpoint - do not pretend it is safe.
- If it does not clear even at the optimistic ceiling: recommend stopping or re-scoping. Killing a weak project honestly is a professional service, not a failure.

---

## What you must produce for this scenario

1. **The assumed-vs-actual gap table**, filled from pilot data.
2. **A rebuilt business case** with a month-by-month adoption ramp, measured time-saved, added adoption costs, and recomputed ROI / payback / TCO.
3. **A three-scenario sensitivity analysis** (low / expected / high adoption).
4. **A short honest recommendation** (continue / continue-conditionally / stop) tied to the client's hurdle rate, plus the specific adoption fixes.

---

## Decision checklist (self-assess or reviewer-assess)

- [ ] You used real pilot data, not new guesses, to find the gap.
- [ ] You identified WHY adoption was low, not just that it was low.
- [ ] You replaced the flat adoption assumption with a ramp to a realistic ceiling (not 100 percent).
- [ ] You used measured time-saved applied only to tickets actually assisted.
- [ ] You added the omitted adoption/training/change costs.
- [ ] You recomputed ROI, payback, and TCO month by month, not steady-state x 12.
- [ ] You included a sensitivity analysis across at least three adoption levels.
- [ ] Your recommendation is honest, tied to the hurdle rate, and willing to say "stop" if the numbers say stop.
- [ ] You owned the original error without excuses when explaining to the CFO.

If any box is unchecked, the rebuild is not defensible yet.

---

## What you learned

- Adoption is the assumption that breaks business cases. Never assume it - model it as a ramp to a realistic ceiling, and pull the ceiling from evidence.
- Count benefits bottom-up, month by month, and only on the work actually affected.
- Always include a sensitivity analysis so leadership sees the range, not a fragile single number.
- Rebuilding honestly - even recommending "stop" - restores credibility. Defending a broken case destroys it.

Prof. Happy (SUTA Labs)
