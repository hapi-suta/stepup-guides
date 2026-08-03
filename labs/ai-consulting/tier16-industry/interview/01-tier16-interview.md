# Interview: Tier 16 - Industry Specialization

**Tier 16 interview prep.** These are the questions a sector client, a hiring panel, or a skeptical executive will ask to find out whether you truly understand their industry or are just a generalist with a template. The whole point of Tier 16 is that you can walk into two different rooms and speak each sector's language. Each entry has the question, a model answer in plain language, and "why they ask".

---

## 1. What makes public-sector AI different from commercial AI?

**Model answer.** Commercial AI optimizes for value; public-sector AI optimizes for legitimacy. A private company can accept an opaque model that makes more money, but a public institution spends public money, serves people who cannot go elsewhere, and must be able to justify every decision that affects a citizen. So the defaults change: high-impact decisions keep an accountable human who decides while the AI only supports; explainability is a requirement because decisions get appealed; every consequential interaction is logged in a reconstructable way; and accessibility and multilingual quality are legal gates, not features. In practice I start public-sector clients on administrative work, like document processing, and make them earn their way up to anything decisional.

**Why they ask.** They want to know you will not carry startup assumptions into a government room. Naming legitimacy and appeals shows you get the real constraint.

---

## 2. How do you build auditability into a financial-services model?

**Model answer.** I design for the audit on day one, because you cannot backfill it. Concretely I build seven things: a model registry so I know exactly which version ran on which date; a decision log that stores, per decision, the inputs, output, and top contributing features; a stored human-readable explanation, the adverse-action reason, for every customer-affecting decision; formal change control so no model reaches production without documented sign-off; fairness evidence from disparate-impact testing at launch and on a periodic cadence; data lineage so every feature traces to its source; and tamper-evident retention for the legally required period. The test is simple: if a regulator picks a random declined applicant, I can produce all of that in minutes.

**Why they ask.** Anyone can say "we log things." They want to hear the specific machinery that survives a real examination, and the mindset that builds it before it is needed.

---

## 3. Where is the clinical/administrative line in healthcare AI, and why does it matter?

**Model answer.** Administrative use supports operations and paperwork and does not touch a care decision - summarizing notes, routing documents, scheduling. Clinical use influences diagnosis, treatment, or triage. The line matters because clinical AI is regulated as a medical device: it needs formal validation across the patient population, regulatory clearance, and genuine human oversight before it touches a patient. The dangerous part is drift - an administrative summarizer that nurses quietly start using to triage has silently become an unvalidated clinical tool. So my job is to name the line, put controls and monitoring on it, start clients on administrative use, and refuse to let a clinical use case ship as a side effect of an administrative one, even when the client loves the tool.

**Why they ask.** It is the single highest-stakes judgment in healthcare AI. They want to know you will stop a happy client to protect patients.

---

## 4. Why should a consultant specialize in only two sectors instead of serving everyone?

**Model answer.** Because credibility is sector-specific. Clients do not buy generic AI; they buy someone who understands their constraints, their regulators, and their language. Trying to serve every industry means I am shallow everywhere and trusted nowhere. Two sectors lets me build real depth - the readiness assessment, governance policy, roadmap, architecture, pilot, and executive deck that actually reflect that industry - and it lets me reuse and compound my learning. I pick two whose constraints differ enough to prove range, like public sector and financial services, so my portfolio shows two mindsets, not one template used twice.

**Why they ask.** They want to see commercial judgment. A consultant who claims every industry as a specialty is telling you they have none.

---

## 5. A client in a regulated sector wants to move fast and skip governance. How do you respond?

**Model answer.** I reframe governance as the thing that lets them move fast safely, not the thing that slows them down. I show them that in their sector the real delay is a failed audit, a challenged decision, or a patient-safety event - each of which stops the program cold. Then I offer a path that is both fast and safe: start with a low-risk administrative use case where governance is light, prove value quickly, and build the heavier controls in parallel before we touch anything high-risk. I do not agree to ship a high-risk use case without governance. If they insist, I decline that part of the work, because my name is on the outcome and a preventable failure in their sector is not a risk I will take.

**Why they ask.** They are testing whether you have a spine and whether you can sell safety as speed rather than as friction.

---

## 6. How would you adapt one RAG assistant to serve both a bank and a hospital?

**Model answer.** The core is the same - RAG over pgvector with citations, a model-provider abstraction, auth, logging, evaluation, monitoring - but the constraint overlays are completely different. For the bank I add a model registry, a reconstructable decision log, stored adverse-action explanations, and continuous fairness monitoring, and I scope it hard so it never gives financial advice. For the hospital I scope it strictly administrative, block clinical questions by design, put PHI controls and data-residency on every data path, and add monitoring for clinical-style usage so it cannot drift across the line. Same engine, two very different hardening and governance wrappers. I never ship the generic version into either room.

**Why they ask.** They want to see that specialization is real engineering-and-governance adaptation, not a cover page swap.

---

## 7. What is the biggest risk in education AI, and how do you handle cheating detection?

**Model answer.** The two biggest risks are student privacy, especially for minors, and unfair assessment. On cheating specifically, my strong advice is not to rely on AI-cheating detectors - they are unreliable and produce false accusations that harm honest students, which is a worse outcome than the cheating. Instead I help institutions redesign assessment to be integrity-resilient: in-class, oral, process-based, or applied work that AI cannot easily do for the student, and teaching responsible AI use rather than policing it with flawed tools. And for grading, a human always owns any consequential grade, with an appeal path, because automated grading can be silently unfair to non-standard answers and non-native speakers.

**Why they ask.** Many vendors oversell AI detectors. They want to know you understand the harm and have a better, defensible approach.

---

## 8. Your two-sector portfolios look too similar. What does that tell a reviewer?

**Model answer.** It tells them I pasted a sector name onto a generic template instead of actually specializing, which is the opposite of what Tier 16 is supposed to prove. A finance package and a public-sector package should read as two different mindsets: finance obsesses over auditability, model registries, and adverse-action reasons, while public sector obsesses over legitimacy, appeals, accessibility, and human decision-making on citizen outcomes. If a reviewer cannot tell them apart, I have not done the work. The fix is to drive every deliverable from that sector's specific constraints, not from a shared outline.

**Why they ask.** This is the honest self-check for the whole tier. They want to see you know the difference between real specialization and template theater.

---

Prof. Happy (SUTA Labs)
