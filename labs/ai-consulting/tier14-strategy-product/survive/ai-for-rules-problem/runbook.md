# SURVIVE Runbook: A Stakeholder Demands AI Where Deterministic Rules Are Correct

**Tier 14 - SURVIVE scenario 1 of 3**

This is a review-assessed scenario. There is no script to run. You work through the situation, write the artifacts the runbook asks for, and a reviewer (or you, honestly, against the decision checklist) judges whether you handled it like a professional consultant.

---

## The situation

You are three weeks into a discovery engagement at [CLIENT], a logistics company. The VP of Operations, who sponsors your project and controls the budget, pulls you aside after a demo she saw at a conference.

"I want an AI model that decides which shipments qualify for our free-returns policy. The vendor at the conference said their AI does this. Build us that."

You look at the actual policy. It is: free returns if the order is under 30 days old, the item is unopened, the customer is a loyalty-tier member, and the item is not on the final-sale list. Four conditions, all recorded in fields the company already has. There is no ambiguity, no judgment call, no unstructured input. It is a deterministic rule.

If you say yes, you will spend the client's money training a model to reproduce an IF-statement, and it will be less accurate and less auditable than the IF-statement. If you say no badly, you damage the relationship with your sponsor.

Your job: say no, and justify it, without losing the sponsor.

---

## Why this is a trap

AI is the wrong tool here for concrete reasons a client will accept:

- **A rule is 100 percent accurate and auditable.** A model is probabilistic. Reproducing a known rule with a model can only lose accuracy, and now you cannot explain a specific decision by pointing at the rule.
- **It costs more to build and to run.** You pay for data labelling, training, serving, and monitoring to get a worse version of `if age < 30 and unopened and loyalty and not final_sale`.
- **It creates governance and legal exposure.** A returns decision that a customer disputes must be explainable. "The model scored you 0.42" is not a defensible answer; "your item was on the final-sale list" is.
- **It sets a bad precedent.** If you AI-wash a rules problem, the client learns that "AI" means "expensive rebranding of what we already have," and your credibility drops the first time it misfires.

The consultant's value here is judgment, not compliance. Saying yes to a bad idea to keep a sponsor happy is how engagements fail slowly.

---

## Diagnosis: confirm it really is a rules problem

Do not reject on instinct. Run the "when not to use AI" test out loud, on paper, so your no is evidence-based.

Ask and answer these:

1. **Can the decision be written as a finite set of explicit conditions?** If yes, it is a rules problem. (Here: yes, four conditions.)
2. **Are all inputs already available as structured fields?** (Here: yes.)
3. **Is there ambiguity, unstructured input, or a judgment call a human would make differently case to case?** (Here: no.)
4. **Does the decision need to be explainable or audited?** If yes, this pushes even harder toward rules. (Here: yes, returns can be disputed.)
5. **Would a model ever outperform the rule?** Only if the "rule" is actually a fuzzy human judgment being approximated. (Here: it is not.)

If 1, 2, and 5 point to rules, you have your answer. Write it down. That paper is your evidence when you deliver the no.

---

## Recovery: how to deliver the no without losing the sponsor

The goal is to protect the client's money AND the relationship. Reframe from "no" to "here is the faster, cheaper, safer path, and here is where AI actually pays off for you."

### 1. Acknowledge the intent, not the solution
"You want returns decisions to be fast, consistent, and off your team's plate. That is exactly the right goal." You are agreeing with the outcome she wants, which is real.

### 2. Separate the goal from the tool
"The fastest way to get there is a simple rules engine, not a trained model. Your policy is four clear conditions we can encode today. It will be 100 percent accurate, instant, free to run, and fully auditable, which matters because customers dispute returns."

### 3. Name what she would lose with AI, in her terms
"If we train a model instead, we would spend weeks and budget to reproduce a rule we already know, end up slightly less accurate, and lose the ability to explain a specific decision. That is cost and risk for a worse result."

### 4. Redirect the AI appetite to a real opportunity
Do not leave her feeling AI was rejected. Give her a genuine target. "Where AI would earn its keep for you is the returns work that is NOT a clean rule: reading the free-text damage descriptions and photos customers submit, and predicting which shipments are at high risk of damage before they go out. I would love to prioritize those in the opportunity matrix." Now the sponsor gets AI where it actually helps.

### 5. Offer to prove it cheaply
"Give me two days. I will stand up the rules version so you see it working, and I will scope the document-reading use case as a proper pilot. Then you choose with real options in front of you." Low-risk, decisive, keeps you in control.

### 6. Put it in writing
Send a short recommendation memo: the goal, the recommendation (rules engine now), the reason (accuracy, cost, auditability), the alternative AI opportunity you are prioritizing, and the two-day proof plan. Writing it protects you if anyone later asks "why didn't we do AI here" and it demonstrates the discipline the client is paying for.

---

## What you must produce for this scenario

1. **A one-page recommendation memo to the sponsor** that says no to AI-for-this, justifies it on accuracy/cost/auditability, and redirects to a genuine AI opportunity plus a cheap proof plan.
2. **The filled-in "when not to use AI" test** (the five diagnosis questions with your answers) as your evidence.
3. **Two lines added to your opportunity matrix**: the rejected use case marked "rules, not AI," and the redirected real use case (damage-description reading / damage-risk prediction) scored for later prioritization.

---

## Decision checklist (self-assess or reviewer-assess)

- [ ] You confirmed it is a rules problem with the five-question test, on paper, before rejecting.
- [ ] You said no clearly - you did not hedge into building it anyway to keep the sponsor happy.
- [ ] You justified the no in the client's language: accuracy, cost, auditability, legal exposure.
- [ ] You agreed with the sponsor's GOAL even while rejecting her solution.
- [ ] You redirected the AI appetite to a real, appropriate opportunity so AI was not just "rejected."
- [ ] You offered a low-risk, decisive next step (cheap proof) that keeps momentum.
- [ ] You put the recommendation in writing.
- [ ] The relationship with the sponsor is intact or stronger, not damaged.

If any box is unchecked, rework the memo before you would ever send it.

---

## What you learned

- A consultant's core value is saying no to the wrong tool, with evidence, and keeping the client.
- "Say no" is not "reject the person" - agree with the goal, reject only the solution, and redirect the appetite.
- Rules beat models when the decision is finite, structured, and must be explained. Never AI-wash an IF-statement.
- Always put the no in writing. The memo is both a professional deliverable and your protection.

Prof. Happy (SUTA Labs)
