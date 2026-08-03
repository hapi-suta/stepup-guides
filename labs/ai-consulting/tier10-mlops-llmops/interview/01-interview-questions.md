# Interview: MLOps and LLMOps

**Tier 10 - MLOps and LLMOps (ai-consulting track).** These are the questions a hiring panel or a client executive will actually ask on this topic. For each: the question, a model answer you can say out loud, and why they ask it. Practise saying the answers in your own words - do not memorise them word for word. An interviewer can tell the difference between understanding and recitation.

The first four are the plan's required questions. The rest are the follow-ups that come up in real interviews for this tier.

---

## Q1. What do you monitor for an LLM app that you would not for a normal web app?

**Model answer.** A normal web app you watch for request volume, latency, error rate, and infrastructure health. An LLM app needs all of that plus a whole extra layer. You monitor token usage and model cost, because you pay per token and a loop can run up a real bill. You monitor which prompt version and which model version served each response, because when quality changes the first question is "did the prompt or the model change?" and you cannot answer it without versioning. You monitor output quality directly - groundedness for a RAG app, meaning whether the answer is actually supported by its sources, plus safety violations, refusals, and user feedback. For an agent you also watch tool-call accuracy. And you watch the provider itself, because an outage or a deprecated model breaks you even though your code is fine. The short version: cost, prompt and model versions, groundedness, safety, and vendor status - none of which a normal web app has.

**Why they ask.** This is the single best test of whether you actually understand LLMOps or just deployed an LLM once. Anyone can say "monitor latency." Naming cost, prompt/model versioning, groundedness, and vendor risk shows you have operated one in production and know where the pain is.

---

## Q2. Canary versus shadow deployment - explain the difference and when you use each.

**Model answer.** Both test a new version on real traffic, but they differ in who sees the output. A canary sends a small slice of real traffic - say 5% - to the new version and those users get its responses. You watch the canary's metrics; if it looks good you ramp to 100%, if it looks bad you cut it to 0%, which is an instant rollback affecting only a few users. A shadow sends real traffic to the new version in parallel but throws its output away - the user only ever sees the old version's answer. You compare the shadow's responses and metrics offline. So a canary exposes a few real users with quick reversibility, while a shadow exposes zero users at the cost of paying for the extra calls and not seeing real user reactions. Rule of thumb: shadow to check correctness on real inputs with zero user risk, canary to measure real user impact with limited, quickly-reversible exposure. For a high-risk change I shadow first, then canary, then full rollout.

**Why they ask.** These two get confused constantly. Getting the "who sees the output" distinction right, and giving a clear rule for when to use each, signals real release-engineering maturity rather than buzzword familiarity.

---

## Q3. How do you version prompts, and why?

**Model answer.** A prompt is code - it changes the app's behaviour - so I treat it like code. Prompt templates live in files under source control, never pasted into the application, each with a version identifier. Every response logs which prompt version produced it, so if quality shifts I can trace it to the exact edit. And no prompt change ships without passing a golden-set regression test wired into CI - if the change breaks known-good cases, the pipeline blocks the merge. The why is prompt drift: someone tweaks a prompt to fix one case and silently breaks ten others, and without versioning and a regression gate you find out from an angry customer instead of from CI. Versioning also gives you a clean rollback - if a new prompt underperforms, you revert to the previous version the same way you revert code.

**Why they ask.** Prompt versioning is where teams are sloppiest, and it causes real incidents. Answering it well - especially connecting it to a CI regression gate and to prompt drift - shows you would prevent a class of silent failures most people learn about the hard way.

---

## Q4. How do you detect and respond to model drift?

**Model answer.** First I name the kind of drift, because the response differs. Data drift is when the model's inputs stop looking like its training data - I detect that by comparing the live feature distribution against a saved training baseline with a statistical test like the Kolmogorov-Smirnov test, per feature, with a threshold that fires an alert. Concept drift is when the relationship between inputs and outputs changes - the inputs look normal but their meaning shifted - and that usually needs fresh labels to confirm because it shows up as falling accuracy. Performance drift is the bottom line, measured quality dropping on recent data, and if I have labels that is my strongest signal. For an LLM app there is also prompt drift, caught by the regression suite, and knowledge-base decay for RAG. The response is a decision, not a reflex: retrain on fresh data when the use case is still valid and relearning fixes it; retire when the world has changed so much the use case no longer holds; or do nothing when the drift is within tolerance. The maturity point is that I retrain because a signal told me to, and I can show the signal - not on a blind monthly schedule.

**Why they ask.** Drift is the reason "deploy and forget" fails, and it is the most expensive silent failure in production AI. They want to hear that you can distinguish the types, that you have a concrete detection method (not just "monitor it"), and that your response is a judgement call tied to business cost.

---

## Q5. Walk me through your CI/CD pipeline for a model, from a code change to production.

**Model answer.** A push kicks off CI. First the fast gates: unit tests on the plumbing - feature prep, token counting, request shaping - then integration tests that the pieces wire together. For an LLM app the prompt regression test runs against the golden set here, and a failure blocks the merge. If tests pass, the pipeline trains or builds the candidate, logs the run to experiment tracking with the data version, params, code commit, and metrics, and registers the model in staging. Then the validation gate: the candidate is compared against the current production model on the metric that matters, and it only advances if it beats or matches it. Deployment is decoupled - I promote in the registry, which the serving layer reads, and I roll it out gradually: shadow or canary first, watch the metrics, then full rollout. Rollback is a registry pointer flip to the last known-good version, and I have tested it. Infrastructure is provisioned as code so it is reproducible. The whole point is that "newer" never ships automatically - it ships because it passed the gates.

**Why they ask.** This is the tier's exit standard as a single question. They want to hear the full loop - test, track, register, validate, gradual rollout, tested rollback - and specifically that quality gates block bad changes automatically.

---

## Q6. A model that was accurate at launch is quietly getting worse. Nothing is erroring. How do you find out and what do you do?

**Model answer.** The "nothing is erroring" part is the tell - this is drift, which is silent by design because the model keeps returning HTTP 200 while getting less right. First I check whether I have fresh labels. If I do, I track performance on recent data - falling accuracy or F1 confirms performance drift directly. If I do not have labels yet, I run data-drift detection: compare the live input distribution against the training baseline with a KS test per feature; a feature whose distribution has shifted is my early warning. I also check for the LLM-specific causes if it is an LLM app - did the prompt change, did the provider update the model, did the knowledge base go stale. Once I know the cause, I decide: retrain on fresh labelled data if the use case holds, retire if it does not, and set a threshold alert so next time it pages me instead of me stumbling on it. The prevention is that this should never be discovered by a human noticing - drift monitoring with thresholds should have caught it.

**Why they ask.** It is the drift question posed as a real incident, and it tests whether you can operate without labels. Distinguishing "I have labels, track performance" from "no labels yet, detect input drift" is the practical answer that separates people who have done this from people who have read about it.

---

## Q7. How do you keep an LLM feature's cost under control?

**Model answer.** Cost is a control I build into the serving path, not a report I read the next morning. Layered: token counting on every request so I can measure spend live; a budget cap that refuses calls once the daily budget is reached, so a runaway loop is capped rather than unlimited; a per-client rate limit so one caller cannot dominate; caching so repeated prompts are free; and batching where the workload allows. On top of that a threshold alert that pages someone when spend crosses the budget. I prove the cap holds under load before launch - I run a simulated runaway against it and confirm it stops spending - because the time to discover you have no cost control is not when the bill arrives. For estimation I model expected requests times average tokens times price to give the client a monthly number with a range.

**Why they ask.** Cost blowouts are one of the most common LLM production incidents and a top client fear. They want to hear concrete controls in the serving path and that you validate them under load, plus that you can estimate cost for a business case - which is the consultant angle.

---

## Q8. What belongs in a model registry, and why does it make rollback safe?

**Model answer.** A registry is the single source of truth for which model is in production. Per model version it holds an identifier, the metrics it earned, a link to the artifact, the data version and code commit that produced it, and its stage - staging, production, or archived. It makes rollback safe because deployment reads "production" from the registry, so the model that is live is decoupled from the model files. Rolling back is flipping the pointer to the last known-good version - one operation, no rebuild, no scramble. A team that copies model files directly onto servers cannot do that; they have to reconstruct the old model under pressure. So the registry turns rollback from a hope into a one-command procedure, and it gives you the audit trail - who promoted what, when, trained on which data - that regulators and clients ask for.

**Why they ask.** The registry is the linchpin of operable ML, and rollback is the capability everyone claims and few have tested. Explaining how the registry makes rollback a pointer change - and mentioning the audit trail - shows you understand the architecture, not just the tool.

---

## Q9. Explain the difference between MLOps and LLMOps to a non-technical executive.

**Model answer.** MLOps is the discipline of running a machine-learning model reliably in production - like the operational care a database gets: you version it, monitor it, back it up, and can roll it back. LLMOps is that same discipline applied to applications built on large language models, plus a few extra concerns those bring. Three differences an executive should care about. First, cost: an LLM charges per use, so we actively cap and monitor spend the way you would a utility bill. Second, we often do not own the model - it runs at a vendor who can change or retire it - so we build in fallbacks and avoid locking to one provider. Third, the output is free text that can be confidently wrong, so we measure whether answers are actually supported by our own documents, not just whether the system is up. In plain terms: MLOps keeps the model working; LLMOps also keeps it affordable, safe, and independent of any one vendor.

**Why they ask.** For a consultant this is the most important version of the question - it tests whether you can translate the technical distinction into the terms a decision-maker cares about: cost, vendor risk, and trustworthiness. If you can only explain it to engineers, you cannot sell or govern it.

---

## Q10. How would you test a change to a customer-facing LLM assistant before it reaches users?

**Model answer.** I test in layers, cheapest and safest first. Unit tests on the plumbing and integration tests on the end-to-end flow. Then prompt regression against a golden set of representative questions with required facts and citations - if the change breaks a known-good case, CI blocks it. I red-team the change adversarially: prompt injection, attempts to extract the system prompt, requests for data the user should not see, because a customer-facing assistant is an attack surface. I load-test to see latency, error rate, and cost under volume. Then I move to production carefully: shadow the change against real traffic with the output discarded to check correctness on real inputs with zero user risk, then canary it to a small slice of real users with an instant rollback if metrics dip, then full rollout. And I keep human evaluation on a sample plus thumbs up/down feedback flowing, because some quality issues no automated check will catch. Every failure that slips through becomes a new golden-set case so it can never regress again.

**Why they ask.** It combines the whole testing concept - unit, integration, regression, red-team, load, shadow, canary, human eval - into one realistic scenario, and the "customer-facing" framing checks whether you add the security and gradual-rollout layers that a real launch demands.

Prof. Happy (SUTA Labs)
