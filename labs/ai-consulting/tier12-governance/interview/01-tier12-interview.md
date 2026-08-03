# Interview: Tier 12 - Responsible AI and Governance

**Tier 12 interview prep.** These are the questions a client executive, a board, a
regulator, or a hiring panel will actually ask to see whether you can govern AI, not
just build it. Governance is where consultants win engagements, because most
organizations can find someone to write code but few can prove their AI is validated,
fair, private, and accountable. Each entry has the question, a model answer in plain
language, and "why they ask" so you know what they are really probing.

The skill tested across all of these: can you turn frameworks and principles into
concrete controls, evidence, and decisions an executive can act on - without hype and
without hiding the risk?

---

## 1. Walk me through NIST AI RMF: Govern, Map, Measure, Manage.

**Model answer.** NIST AI RMF is a voluntary, vendor-neutral framework for managing AI
risk, built around four functions. **Govern** is the ring around the others - the
culture, policies, roles, accountability, and risk tolerance that make risk management
happen at all, including keeping an inventory of every AI system. **Map** establishes
context and identifies risks for each system: its purpose, who it affects, what could
go wrong. That is where you run impact assessments. **Measure** analyzes and tracks
those risks with real metrics - accuracy, fairness ratios, groundedness, safety
violations - so you have evidence, not opinion. **Manage** acts on the measured risks:
prioritize, mitigate, assign controls and owners, plan incident response, and monitor.
They are not one-time steps; they run continuously. A one-liner: Govern sets the rules,
Map finds the risks, Measure sizes them, Manage deals with them. For a generative
system I also apply NIST's Generative AI Profile, which adds risks like confabulation
and information integrity.

**Why they ask.** NIST AI RMF is the default risk language in the US. They want to hear
that you know the four functions cold, understand that Govern is cross-cutting, and can
connect each function to concrete work rather than reciting definitions.

---

## 2. What does ISO/IEC 42001 require of an organization?

**Model answer.** ISO/IEC 42001 is the first certifiable AI management-system standard -
an AIMS. Unlike NIST AI RMF, which you self-apply, an organization can be independently
audited and certified against 42001. It uses the standard ISO management-system shape,
so it slots in beside ISO 27001. It requires the organization to: understand its
context and set the scope of AI governance; get top-management leadership and a
documented AI policy; do planning that includes AI risk and impact assessments and
measurable objectives; provide support - competent people, awareness, and controlled
documentation; put operational controls across the AI lifecycle, including data
management and supplier relationships; run performance evaluation with internal audits
and management reviews; and drive continual improvement through corrective action. The
short version: it makes responsible AI a repeating, audited management cycle rather
than a one-off project.

**Why they ask.** Clients who want a badge to show partners and regulators pursue 42001.
They want to confirm you understand it is certifiable, know the clause themes, and can
map a client's existing documents to what an auditor will request.

---

## 3. NIST AI RMF or ISO/IEC 42001 - which should we use?

**Model answer.** They are complementary, not competing, and I usually recommend both.
Use NIST AI RMF to organize the risk thinking - it is flexible, rights-focused, and
free to adopt, and it gives you the Govern/Map/Measure/Manage structure to find and
size risks. Use ISO/IEC 42001 to formalize and, if the client wants it, certify the
management system - it gives you the auditable, repeatable machinery and a badge that
carries weight with partners and regulators. If a client already runs ISO 27001, 42001
drops into the same structure, which lowers the adoption cost. So: NIST to think, ISO to
prove.

**Why they ask.** It is a common real decision, and a naive answer picks one and
dismisses the other. They want to see you understand the difference between a framework
and a certifiable standard, and that you tailor the recommendation to the client.

---

## 4. How do you classify an AI use case as high-risk?

**Model answer.** I look at two dimensions - the severity of harm if it is wrong or
misused, and the scale of exposure - and combine them in a risk matrix. But there is a
decisive override: if the system makes or heavily influences a consequential decision
about a person - their money, health, freedom, employment, or access to a service - I
treat it as high-risk regardless of the grid. So a credit-scoring, hiring, benefits, or
clinical system is high-risk by default. High-risk then triggers heavy controls: a full
impact assessment, a human in the loop, an appeals path for affected people, legal
review, and close monitoring. When in doubt, I round up - it is cheaper to over-govern a
low-risk system than to under-govern a high-risk one.

**Why they ask.** Getting risk classification wrong is how organizations end up with an
ungoverned system making life-affecting decisions. They want to see you have a
consistent, defensible method and that you know the consequential-decision heuristic.

---

## 5. What goes in an AI vendor exit strategy?

**Model answer.** An exit strategy answers "how do we leave this vendor without breaking
our system or losing our data?" It covers: what data and artifacts we can export -
prompts, documents, embeddings, fine-tunes, and configuration - and in what format;
whether those artifacts are portable or locked to the vendor's model; a transition
period and the vendor's obligations during it; and, critically, an alternative we could
move to, which is why I keep a model-provider abstraction so we are not hard-wired to
one vendor. The most important point is that the exit path must be tested, not assumed -
an export feature you have never run is not an exit strategy. A vendor changing its
terms or deprecating a model is exactly when an untested exit bites, so I assess the
exit before signing and keep it warm.

**Why they ask.** Lock-in is one of the biggest, most underestimated AI risks. They
want to know you protect the client from being trapped, and that you treat "how do we
get out?" as a question to answer before signing, not after a crisis.

---

## 6. What is the difference between transparency and explainability?

**Model answer.** Transparency is systemic and up front - people are told an AI is being
used, and there is documentation describing the model, its data, and its limits. That is
what a model card and a data sheet provide; it is the label on the box. Explainability is
per decision - being able to give a human-understandable reason for one specific outcome,
like why a particular loan application was declined. That is the receipt for one purchase.
High-stakes decisions about people usually need both: transparency so people know AI is
involved, and explainability so an affected person can understand and challenge a
decision that affects them.

**Why they ask.** People conflate the two, and regulations increasingly demand each in
different ways. They want to confirm you can separate the concepts and know when each is
required.

---

## 7. A team says "we don't use race, so our model is fair." Are they right?

**Model answer.** No, and this is one of the most important points in responsible AI.
Dropping the protected attribute does not remove bias, because a **proxy variable** can
carry it back in - zip code standing in for race, or years of recorded experience
standing in for a group. If a feature is correlated with a protected trait, the model
can reproduce the disparity without ever seeing the trait. The only way to know is to
measure: I compute selection rates per group and a disparate-impact ratio, and flag it
if it falls below the four-fifths threshold of 0.80. If it does, I investigate the proxy
and the data. Fairness is something you measure and monitor, not something you assert by
leaving a column out.

**Why they ask.** This exact false-confidence statement is common and dangerous. They
want to see you know about proxy variables and that you would demand a measured fairness
metric rather than accept a claim.

---

## 8. What is in an AI impact assessment, and when do you run it?

**Model answer.** An impact assessment is a structured, written analysis of how a system
could affect people and the organization: the affected people, the intended benefits, the
possible harms, the data sources, bias, human oversight, security, privacy, complaints
and appeals, monitoring, and how it will be decommissioned. It feeds a risk
classification and a go/no-go decision. I run a lightweight version at use-case intake to
decide go/no-go and risk class, a full version before deployment with controls confirmed,
and I revisit it on any material change - a new data source, a new model version, or an
incident - and on a schedule for high-risk systems. It is a living, signed, dated
document, and it is usually the single most important evidence an auditor or regulator
asks for.

**Why they ask.** The impact assessment is the artifact that decides whether a system
should exist and how tightly to control it. They want to see you can produce and maintain
one, not just name it.

---

## 9. An employee pasted customer data into a public chatbot. How does governance prevent this?

**Model answer.** This is the most common real AI risk - a well-meaning employee, not a
hacker. Governance addresses it with layered controls. First, a plain, actionable AI
acceptable-use policy that clearly states confidential data must never go into
unapproved tools, with concrete examples. Second, a maintained list of approved tools
cleared for specific data classes, so there is a compliant option - the enabling control
is providing approved tools so people are not tempted by unapproved ones. Third,
awareness training focused on the confidential-data rule. Fourth, a clear front door to
ask "can I use X?" and to report incidents. And when it does happen, an incident-response
process to contain it, notify, find the root cause, and improve. Policy is the cheapest,
highest-leverage control here.

**Why they ask.** They want to see you treat governance as practical behaviour change,
not just documents, and that you know the biggest risk is internal and preventable.

---

## 10. How do you respond when an AI system produces a biased or harmful output in production?

**Model answer.** I treat it as a governance incident with two deliverables: contain the
harm, and document it. First, containment - disable or roll back the offending model
version immediately so it stops affecting people. Then diagnose the root cause; for bias
that is usually a proxy variable or a bad data or feature change. Remediate and retest
against the fairness metric to prove it recovered. Then file an incident report: what
happened, when, who was affected, severity, the immediate action, the root cause, the
remediation, who was notified - including any regulatory obligation - and the lessons
learned. The most important lesson-learned is prevention: gate model changes on the
fairness metric in CI so the same regression cannot ship again. The fix without the
paper trail and the prevention is only half the job.

**Why they ask.** They want to see you have a disciplined incident process, that you
contain before you investigate, and that you close the loop with prevention and
documentation rather than a quiet hot-fix.

---

## How to use this bank

- Practice each answer out loud until it is under 90 seconds and hype-free.
- For every framework answer (1, 2, 3), be ready to connect it to a concrete artifact
  from your toolkit - that is what separates you from someone who memorized definitions.
- Keep returning to the through-line: principle becomes policy, control, evidence, and
  owner. If you can always land an answer on "here is the control and here is the
  evidence," you sound like a governance consultant, not a student.

Prof. Happy (SUTA Labs)
