# Interview / Executive Delivery: Capstone Part 7

**Tier 18 - Part 7.** This is where the whole engagement is presented to leadership and defended. It produces the executive-facing deliverables and prepares you to survive the board Q&A. Part 7 is graded as an interview: you rehearse the board's questions and answer them live in front of a reviewer.

**Prerequisite:** Parts 1-6 complete. The assistant passes its full security SURVIVE suite. You are presenting a real, governed, secure, operating system - not a concept.

---

## The nine Part-7 deliverables

### 1. Executive proposal
The whole engagement, distilled for leadership: the need, the approach, the governed and secure solution, the pilot result, and the ask. Plain language, no jargon. This is the cover document for the package.

### 2. Architecture diagram
One clean, executive-legible diagram: the components, the data flow, the trust boundaries (what data stays in-boundary), and the human-oversight point. A caption states the takeaway. If a board member cannot read it in thirty seconds, simplify it.

### 3. Financial model
The numbers: build cost, running cost (inference, hosting, maintenance), the unglamorous costs (data classification, training), and the value (staff time saved, service quality). Honest, with assumptions stated. Include the cost-control ceiling from Part 6.

### 4. 90-day roadmap
The near-term plan: finish the pilot, close the top readiness gaps, train the first staff, and reach the pilot success metrics. Concrete milestones.

### 5. One-year roadmap
The medium term: scale the internal assistant, expand the corpus with governed ingestion, mature operations, and evaluate whether a carefully-scoped citizen-facing use is justified.

### 6. Three-year roadmap
The long term: the institution's AI program - additional governed use cases, sustained governance and security cadence, and skills development so the institution can eventually run it without you. Ambitious but honest about pace.

### 7. Board presentation deck
The 10-15 slide deck you actually deliver: the opportunity, the approach, the architecture at altitude, governance and security (how you keep them safe), the pilot result, the ask, the value, and the roadmap. Built to be defended, with a recorded demo backup (see the Tier 17 live-demo-failure discipline).

### 8. Staff-training plan
How the institution's people learn to use and eventually operate the system, drawn from the Part 1 skills assessment. Role-based: users learn to use it, an owner learns to operate it.

### 9. Final evaluation report
The honest assessment of the engagement: what was delivered, whether the pilot met its success metrics (per language), what the security suite found and how it was remediated, the limits, and the recommendation. This is the artifact that becomes your Tier 17 flagship case study.

---

## The board Q&A rehearsal (the graded interview)

Present the board deck to a reviewer playing the board, then survive the questions. Prepare answers to these before you present:

### Q1: "How do we know this is safe?"
Point to the threat model and the full security SURVIVE suite that passes: prompt injection, role bypass, malicious documents, data leakage, tool permissions. Say plainly: restricted data is unreachable because access control is enforced in the query, not the prompt, and the assistant supports staff but never decides consequential citizen outcomes.

### Q2: "What happens when it gets an answer wrong?"
Every answer is cited, so staff can verify. The assistant refuses when it lacks a good source rather than guessing. There is a support workflow to report bad answers, an incident process with a pause switch, and an appeal-grade log so any decision can be reconstructed and overturned.

### Q3: "Why not just buy a commercial chatbot?"
A commercial chatbot does not respect our records classification, does not keep restricted data in-boundary, does not produce appeal-grade logs, and cannot be governed to our accountability standard. We built for legitimacy, not just convenience.

### Q4: "What does it cost, really?"
Walk the financial model, including the honest costs (data classification, maintenance, inference) and the cost-control ceiling. Give the value in staff time saved and service quality, not inflated ROI.

### Q5: "What if it leaks citizen or restricted data?"
It cannot leak through retrieval because a lower-clearance user never has restricted data in context - proven by the data-leakage and role-bypass tests. If a novel path were found, the incident process pauses the system, we remediate, and the audit log tells us exactly what was exposed.

### Q6: "Can our people actually run this after you leave?"
Yes - that is the point of the staff-training plan and the three-year roadmap. We hand over documented, tested operations and train an owner. Independence is a deliverable, not an afterthought.

### Q7: "What is out of scope, and why?"
Anything citizen-facing or high-impact, for now. We start administrative and internal to prove value and safety, and earn the way up. Overreaching before the foundation exists is how public-sector AI fails.

---

## How you are graded

You survive the board Q&A if you answer calmly, ground every claim in a real deliverable or test result, admit limits honestly, and never overclaim. A board respects "here is exactly how we contained that risk, and here is the test that proves it" far more than confident hand-waving.

---

## Exit standard for Part 7

All nine deliverables complete and coherent as one package, and the board deck survives a live Q&A rehearsal in front of a real reviewer. Combined with the passing security suite, this completes the capstone.

---

Prof. Happy (SUTA Labs)
