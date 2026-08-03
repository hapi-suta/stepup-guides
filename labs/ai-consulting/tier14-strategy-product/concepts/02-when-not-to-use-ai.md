# Concepts: When NOT to Use AI

**Tier 14, Module 14.2** - The disqualifiers that tell a consultant to say no to AI, and what to recommend instead.

The fastest way to lose a client's trust is to sell them AI where it does not belong. A good consultant is as valuable for the projects they kill as the ones they launch. AI is probabilistic, data-hungry, and needs ongoing care. When those traits clash with the problem, a simpler tool wins - and recommending the simpler tool builds more credibility than any demo.

This concept gives you seven disqualifiers. For each you get the test question you ask out loud, why AI is the wrong fit, and what to recommend instead. Run every candidate opportunity through these before you propose a build.

---

### Deterministic rules solve it

**Test question:** "Can this be written as clear if-then rules that are right every time?"

**Why AI is wrong here:** If the logic is fixed and knowable, AI adds cost, unpredictability, and a maintenance burden while a rule engine gives exact, auditable, free answers. Introducing probability into a solved deterministic problem only creates new failure modes.

**Recommend instead:** A rules engine, a lookup table, database constraints, or plain business logic. Example: computing sales tax by jurisdiction is a table lookup, not a model.

---

### Data unavailable

**Test question:** "Do we have enough relevant, labeled, accessible data - and can we keep getting it?"

**Why AI is wrong here:** Models learn from data. With no historical data, no labels, or data locked in inaccessible or non-consented sources, the model cannot be trained or evaluated. You cannot even measure whether it works.

**Recommend instead:** Start a data-collection effort first (instrument the process, log outcomes, get consent), use a rules-based interim solution, or buy a pre-trained vendor tool that already learned from someone else's data. Revisit AI once data exists.

---

### Errors unacceptable

**Test question:** "What is the cost of a single wrong answer, and can the business tolerate it?"

**Why AI is wrong here:** AI is probabilistic; it will be wrong some percentage of the time. In domains where one error means death, large financial loss, or irreversible harm with no chance to catch it, that residual error rate is disqualifying on its own. This maps to the "validity and reliability" and "safety" characteristics of trustworthy AI in the NIST AI RMF, which treats residual error and harm as first-class risks to be measured and managed. (see: https://www.nist.gov/itl/ai-risk-management-framework)

**Recommend instead:** Deterministic systems with formal verification, or keep AI strictly as a suggestion behind a mandatory human decision and a hard safety interlock. Never let a probabilistic system take the irreversible action unsupervised. Consider narrowing scope to a lower-stakes sub-task.

---

### No human can supervise

**Test question:** "When the model is unsure or wrong, who catches it, and do they have the time and skill?"

**Why AI is wrong here:** Most safe AI deployments rely on human-in-the-loop review for low-confidence or high-impact cases. If there is no one to review, no expertise to judge the output, or the volume makes review impossible, errors flow straight to the customer or the ledger unchecked.

**Recommend instead:** Redesign the workflow to create a review point, reduce volume to a reviewable level, or defer AI until a supervision capability exists. If supervision is truly impossible and stakes are non-trivial, do not deploy.

---

### Organization cannot maintain it

**Test question:** "After we leave, who monitors, retrains, and fixes this - and can they?"

**Why AI is wrong here:** AI systems drift as the world changes and need monitoring, retraining, and incident response. An organization with no ML skills, no MLOps, and no budget for upkeep will watch the system silently decay into a liability.

**Recommend instead:** A fully managed vendor SaaS where the vendor owns maintenance, a much simpler solution the team can actually run, or a capability-building plan (hire/train/partner) before any custom build. Match the solution's complexity to the client's ability to sustain it.

---

### Benefit too small

**Test question:** "What does this save or earn, and does that clear the cost of building and running it?"

**Why AI is wrong here:** AI projects carry real build and operating costs. If the task is low-volume or low-value, the savings never repay the investment. It is a solution in search of a problem, common when a client wants AI for its own sake.

**Recommend instead:** Do nothing, use an off-the-shelf feature already in their existing tools, or redirect the budget to a higher-value opportunity you identified in Module 14.1. Be honest that the ROI is not there (see Module 14.3).

---

### Conflicts with law or policy

**Test question:** "Is there a regulation, contract, or policy that restricts automated decisions or the use of this data here?"

**Why AI is wrong here:** In regulated decisions (credit, hiring, healthcare, some public-sector uses) automated decision-making may be restricted, require explainability the model cannot give, or demand data uses that consent and privacy law forbid. Deploying anyway creates legal and reputational risk that dwarfs the benefit.

**Recommend instead:** Involve legal and compliance early; use interpretable models with documented reasoning where explainability is required; keep a human as the accountable decision-maker; or drop the use case. Sometimes the right answer is "not until the law or our policy changes."

---

## Quick reference

| Disqualifier | Ask | Recommend instead |
|---|---|---|
| Deterministic rules solve it | Can we write exact if-then rules? | Rules engine / lookup table |
| Data unavailable | Do we have enough usable data? | Collect data first / buy pre-trained tool |
| Errors unacceptable | Cost of one wrong answer? | Deterministic + verification / suggestion-only |
| No human can supervise | Who catches mistakes? | Add a review point / defer |
| Organization cannot maintain it | Who runs it after we leave? | Managed SaaS / simpler solution |
| Benefit too small | Does it clear its cost? | Do nothing / existing feature |
| Conflicts with law or policy | Is automation allowed here? | Legal review / interpretable model / drop it |

Rule of thumb: if any single row is a hard yes against AI, that alone can be enough to say no. Do not average the disqualifiers away.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. State all seven disqualifiers and the test question for each without notes.
2. Take a proposed AI project and correctly decide to advance it or kill it, citing which disqualifier applies.
3. For any killed project, recommend a concrete non-AI alternative that fits the client's constraints.

## References

- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - the validity, reliability, and safety characteristics that make "errors unacceptable" a real disqualifier.
- [Google - People + AI Guidebook: Deciding whether to use AI](https://pair.withgoogle.com/guidebook/) - a practitioner guide to when a rules-based or non-AI approach is the better fit.
- [Harvard Business Review - AI Should Augment Human Intelligence, Not Replace It](https://hbr.org/2021/03/ai-should-augment-human-intelligence-not-replace-it) - the case for keeping a human decision-maker where stakes are high.
- [Gartner - Artificial Intelligence insights](https://www.gartner.com/en/topics/artificial-intelligence) - analyst view on assessing AI feasibility and value before committing to a build.
